import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:site_signal/core/theme/app_accent_color.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/repositories/monitor_repository.dart';
import 'package:site_signal/features/monitoring/domain/services/monitoring_policy.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _CheckRecordSqlColumns {
  const _CheckRecordSqlColumns({
    required this.checkedAt,
    required this.status,
    required this.responseTimeMs,
    required this.statusCode,
    required this.error,
    required this.failureDetail,
    required this.checkedUrl,
  });

  final String checkedAt;
  final String status;
  final String responseTimeMs;
  final String statusCode;
  final String error;
  final String failureDetail;
  final String checkedUrl;
}

abstract final class _CheckRecordSqlCodec {
  static const historyColumns = _CheckRecordSqlColumns(
    checkedAt: 'checked_at',
    status: 'status',
    responseTimeMs: 'response_time_ms',
    statusCode: 'status_code',
    error: 'error',
    failureDetail: 'failure_detail',
    checkedUrl: 'checked_url',
  );
  static const latestColumns = _CheckRecordSqlColumns(
    checkedAt: 'last_checked_at',
    status: 'last_check_status',
    responseTimeMs: 'last_response_time_ms',
    statusCode: 'last_status_code',
    error: 'last_error',
    failureDetail: 'last_failure_detail',
    checkedUrl: 'last_checked_url',
  );

  static CheckRecord? decode(
    Map<String, Object?> row,
    _CheckRecordSqlColumns columns, {
    DateTime? missingCheckedAtFallback,
  }) {
    final checkedAt =
        DateTime.tryParse(row[columns.checkedAt] as String? ?? '') ??
        missingCheckedAtFallback;
    if (checkedAt == null) {
      return null;
    }
    return CheckRecord(
      checkedAt: checkedAt,
      status: HealthStatus.fromName(row[columns.status] as String?),
      responseTimeMs: (row[columns.responseTimeMs] as num?)?.toInt(),
      statusCode: (row[columns.statusCode] as num?)?.toInt(),
      error: row[columns.error] as String?,
      failureDetail: row[columns.failureDetail] as String?,
      checkedUrl: row[columns.checkedUrl] as String? ?? '',
    );
  }

  static Map<String, Object?> encode(
    CheckRecord? record,
    _CheckRecordSqlColumns columns,
  ) {
    return <String, Object?>{
      columns.checkedAt: record?.checkedAt.toUtc().toIso8601String(),
      columns.status: record?.status.name,
      columns.responseTimeMs: record?.responseTimeMs,
      columns.statusCode: record?.statusCode,
      columns.error: record?.error,
      columns.failureDetail: record?.failureDetail,
      columns.checkedUrl: record?.checkedUrl,
    };
  }
}

/// SQLite-backed storage for monitor configuration, settings, and history.
///
/// Writes replace a complete controller snapshot inside one transaction. The
/// data set is intentionally bounded by [historyLimit], making this simple,
/// atomic approach predictable while leaving room for schema migrations.
class SqliteMonitorRepository implements MonitorRepository {
  SqliteMonitorRepository({
    this.factory,
    this.databasePath,
    this.legacyDatabasePath,
    this.historyLimit = defaultMonitorHistoryLimit,
  });

  static const _schemaVersion = 3;
  static const _databaseName = 'sitesignal.sqlite3';
  static const _legacyDatabaseName = 'sitotify.sqlite3';
  static const _pausedKey = 'monitoring_paused';
  static const _themePreferenceKey = 'theme_preference';
  static const _primaryColorKey = 'primary_color';
  static const _notificationSoundKey = 'notification_sound';

  final DatabaseFactory? factory;
  final String? databasePath;
  final String? legacyDatabasePath;
  final int historyLimit;

  Future<Database>? _databaseFuture;

  @override
  Future<PersistedMonitorState> load() async {
    final database = await _database;
    final monitorRows = await database.query(
      'monitors',
      orderBy: 'created_at DESC',
    );
    final monitorIds = monitorRows
        .map((row) => row['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final checksByMonitorId = <String, List<Map<String, Object?>>>{};
    if (monitorIds.isNotEmpty) {
      final allCheckRows = await database.query(
        'checks',
        where:
            'monitor_id IN (${List.filled(monitorIds.length, '?').join(', ')})',
        whereArgs: monitorIds,
        orderBy: 'monitor_id ASC, checked_at DESC',
      );
      for (final row in allCheckRows) {
        final monitorId = row['monitor_id'] as String? ?? '';
        (checksByMonitorId[monitorId] ??= <Map<String, Object?>>[]).add(row);
      }
    }
    final monitors = <SiteMonitor>[];

    for (final monitorRow in monitorRows) {
      final id = monitorRow['id'] as String? ?? '';
      final checkRows =
          (checksByMonitorId[id] ?? const <Map<String, Object?>>[]).take(
            historyLimit,
          );
      final recordedChecks = checkRows
          .map(
            (row) => _CheckRecordSqlCodec.decode(
              row,
              _CheckRecordSqlCodec.historyColumns,
              missingCheckedAtFallback: DateTime.fromMillisecondsSinceEpoch(
                0,
                isUtc: true,
              ),
            ),
          )
          .whereType<CheckRecord>()
          .toList(growable: false);
      final history = recordedChecks.mergeTransitions(
        const <CheckRecord>[],
        limit: historyLimit,
      );
      final lastCheck =
          _lastCheckFromMonitorRow(monitorRow) ??
          (recordedChecks.isEmpty ? null : recordedChecks.first);

      final baseUrl = monitorRow['base_url'] as String? ?? '';
      if (id.isEmpty || baseUrl.isEmpty) {
        continue;
      }
      monitors.add(
        SiteMonitor(
          id: id,
          name: monitorRow['name'] as String? ?? 'Untitled site',
          baseUrl: baseUrl,
          probeUrl: monitorRow['probe_url'] as String?,
          faviconUrl: monitorRow['favicon_url'] as String?,
          intervalSeconds: MonitoringPolicy.normalizeIntervalSeconds(
            (monitorRow['interval_seconds'] as num?)?.toInt() ??
                MonitoringPolicy.defaultIntervalSeconds,
          ),
          enabled: (monitorRow['enabled'] as num?)?.toInt() != 0,
          status: HealthStatus.fromName(monitorRow['status'] as String?),
          createdAt:
              DateTime.tryParse(monitorRow['created_at'] as String? ?? '') ??
              DateTime.now().toUtc(),
          history: List<CheckRecord>.unmodifiable(history),
          lastCheck: lastCheck,
        ),
      );
    }

    final settingRows = await database.query(
      'settings',
      columns: const <String>['key', 'value'],
    );
    final settings = <String, String>{
      for (final row in settingRows)
        if (row['key'] != null)
          row['key'].toString(): row['value']?.toString() ?? '',
    };
    final paused = settings[_pausedKey] == '1';
    final themePreference = AppThemePreference.fromName(
      settings[_themePreferenceKey],
    );
    final primaryColorValue = AppAccentColor.normalizeValue(
      int.tryParse(settings[_primaryColorKey] ?? '') ??
          AppAccentColor.defaultValue,
    );
    final notificationSoundPreference = NotificationSoundPreference.fromName(
      settings[_notificationSoundKey],
    );

    return PersistedMonitorState(
      sites: List<SiteMonitor>.unmodifiable(monitors),
      paused: paused,
      themePreference: themePreference,
      primaryColorValue: primaryColorValue,
      notificationSoundPreference: notificationSoundPreference,
    );
  }

  @override
  Future<void> save(PersistedMonitorState state) async {
    final database = await _database;
    await database.transaction((transaction) async {
      await transaction.delete('checks');
      await transaction.delete('monitors');

      for (final monitor in state.sites) {
        await transaction.insert('monitors', <String, Object?>{
          'id': monitor.id,
          'name': monitor.name,
          'base_url': monitor.baseUrl,
          'probe_url': monitor.probeUrl,
          'favicon_url': monitor.faviconUrl,
          'interval_seconds': monitor.intervalSeconds,
          'enabled': monitor.enabled ? 1 : 0,
          'status': monitor.status.name,
          'created_at': monitor.createdAt.toUtc().toIso8601String(),
          ..._CheckRecordSqlCodec.encode(
            monitor.lastCheck,
            _CheckRecordSqlCodec.latestColumns,
          ),
        });
        for (final record in monitor.history.mergeTransitions(
          const <CheckRecord>[],
          limit: historyLimit,
        )) {
          await transaction.insert('checks', <String, Object?>{
            'monitor_id': monitor.id,
            ..._CheckRecordSqlCodec.encode(
              record,
              _CheckRecordSqlCodec.historyColumns,
            ),
          });
        }
      }

      await _writePreferences(transaction, state.preferences);
    });
  }

  @override
  Future<void> savePreferences(PersistedMonitorPreferences preferences) async {
    final database = await _database;
    await database.transaction(
      (transaction) => _writePreferences(transaction, preferences),
    );
  }

  Future<void> _writePreferences(
    Transaction transaction,
    PersistedMonitorPreferences preferences,
  ) async {
    await transaction.insert('settings', <String, Object?>{
      'key': _pausedKey,
      'value': preferences.paused ? '1' : '0',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await transaction.insert('settings', <String, Object?>{
      'key': _themePreferenceKey,
      'value': preferences.themePreference.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await transaction.insert('settings', <String, Object?>{
      'key': _primaryColorKey,
      'value': AppAccentColor.normalizeValue(
        preferences.primaryColorValue,
      ).toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await transaction.insert('settings', <String, Object?>{
      'key': _notificationSoundKey,
      'value': preferences.notificationSoundPreference.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> close() async {
    final future = _databaseFuture;
    _databaseFuture = null;
    if (future != null) {
      final database = await future;
      await database.close();
    }
  }

  Future<Database> get _database {
    return _databaseFuture ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    sqfliteFfiInit();
    final resolvedPath = databasePath ?? await _defaultDatabasePath();
    final resolvedLegacyPath =
        legacyDatabasePath ??
        (databasePath == null
            ? path.join(path.dirname(resolvedPath), _legacyDatabaseName)
            : null);
    final activePath = await _copyLegacyDatabaseIfNeeded(
      destinationPath: resolvedPath,
      legacyPath: resolvedLegacyPath,
    );
    final resolvedFactory = factory ?? databaseFactoryFfi;
    return resolvedFactory.openDatabase(
      activePath,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          final batch = database.batch();
          batch.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          batch.execute('''
            CREATE TABLE monitors (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              base_url TEXT NOT NULL UNIQUE,
              probe_url TEXT,
              favicon_url TEXT,
              interval_seconds INTEGER NOT NULL,
              enabled INTEGER NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              last_checked_at TEXT,
              last_check_status TEXT,
              last_response_time_ms INTEGER,
              last_status_code INTEGER,
              last_error TEXT,
              last_failure_detail TEXT,
              last_checked_url TEXT
            )
          ''');
          batch.execute('''
            CREATE TABLE checks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              monitor_id TEXT NOT NULL,
              checked_at TEXT NOT NULL,
              status TEXT NOT NULL,
              response_time_ms INTEGER,
              status_code INTEGER,
              error TEXT,
              failure_detail TEXT,
              checked_url TEXT NOT NULL,
              FOREIGN KEY (monitor_id) REFERENCES monitors(id)
                ON DELETE CASCADE
            )
          ''');
          batch.execute('''
            CREATE INDEX checks_monitor_time
            ON checks(monitor_id, checked_at DESC)
          ''');
          await batch.commit(noResult: true);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            final batch = database.batch();
            batch.execute('ALTER TABLE monitors ADD COLUMN favicon_url TEXT');
            batch.execute(
              'ALTER TABLE monitors ADD COLUMN last_checked_at TEXT',
            );
            batch.execute(
              'ALTER TABLE monitors ADD COLUMN last_check_status TEXT',
            );
            batch.execute(
              'ALTER TABLE monitors ADD COLUMN last_response_time_ms INTEGER',
            );
            batch.execute(
              'ALTER TABLE monitors ADD COLUMN last_status_code INTEGER',
            );
            batch.execute('ALTER TABLE monitors ADD COLUMN last_error TEXT');
            batch.execute(
              'ALTER TABLE monitors ADD COLUMN last_checked_url TEXT',
            );
            await batch.commit(noResult: true);
          }
          if (oldVersion < 3) {
            final batch = database.batch();
            batch.execute(
              'ALTER TABLE monitors ADD COLUMN last_failure_detail TEXT',
            );
            batch.execute('ALTER TABLE checks ADD COLUMN failure_detail TEXT');
            await batch.commit(noResult: true);
          }
        },
      ),
    );
  }

  Future<String> _defaultDatabasePath() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final databaseDirectory = Directory(
      path.join(supportDirectory.path, 'database'),
    );
    await databaseDirectory.create(recursive: true);
    return path.join(databaseDirectory.path, _databaseName);
  }

  Future<String> _copyLegacyDatabaseIfNeeded({
    required String destinationPath,
    required String? legacyPath,
  }) async {
    final destination = File(destinationPath);
    if (await destination.exists() ||
        legacyPath == null ||
        !await File(legacyPath).exists()) {
      return destinationPath;
    }

    final copiedPaths = <String>[];
    try {
      copiedPaths.add(destinationPath);
      await File(legacyPath).copy(destinationPath);

      // A legacy process should be closed before an upgrade is launched. If it
      // left committed WAL pages behind, carrying the WAL beside the copied
      // database lets SQLite recover them normally on first open.
      final legacyWalPath = '$legacyPath-wal';
      if (await File(legacyWalPath).exists()) {
        final destinationWalPath = '$destinationPath-wal';
        copiedPaths.add(destinationWalPath);
        await File(legacyWalPath).copy(destinationWalPath);
      }
      return destinationPath;
    } on FileSystemException {
      for (final copiedPath in copiedPaths.reversed) {
        final copiedFile = File(copiedPath);
        if (await copiedFile.exists()) {
          await copiedFile.delete();
        }
      }

      // Keep the upgrade usable even on a read-only or nearly-full volume.
      // The next launch can retry the non-destructive copy.
      return legacyPath;
    }
  }

  CheckRecord? _lastCheckFromMonitorRow(Map<String, Object?> row) {
    return _CheckRecordSqlCodec.decode(row, _CheckRecordSqlCodec.latestColumns);
  }
}
