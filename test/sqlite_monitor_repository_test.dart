import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:site_signal/core/theme/app_accent_color.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/data/sqlite_monitor_repository.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/repositories/monitor_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('persists monitors, probe selection, settings, and history', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'sitesignal-sqlite-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final databasePath = path.join(
      temporaryDirectory.path,
      'sitesignal.sqlite3',
    );

    final writer = SqliteMonitorRepository(databasePath: databasePath);
    await writer.save(
      PersistedMonitorState(
        paused: true,
        themePreference: AppThemePreference.dark,
        primaryColorValue: 0xFF2563EB,
        notificationSoundPreference: NotificationSoundPreference.system,
        sites: <SiteMonitor>[
          SiteMonitor(
            id: 'site-1',
            name: 'Example',
            baseUrl: 'https://example.com',
            probeUrl: 'https://example.com/health',
            faviconUrl: 'https://example.com/favicon.png',
            intervalSeconds: 60,
            enabled: true,
            status: HealthStatus.down,
            createdAt: DateTime.utc(2026, 7, 30),
            lastCheck: CheckRecord(
              checkedAt: DateTime.utc(2026, 7, 30, 12, 5),
              status: HealthStatus.down,
              responseTimeMs: 37,
              statusCode: 200,
              error: 'Page is stuck on “Loading…”',
              failureDetail: 'Stored failure context.',
              checkedUrl: 'https://example.com/health',
            ),
            history: <CheckRecord>[
              CheckRecord(
                checkedAt: DateTime.utc(2026, 7, 30, 12),
                status: HealthStatus.down,
                responseTimeMs: 48,
                statusCode: 200,
                error: 'Page is stuck on “Loading…”',
                failureDetail: 'Stored failure context.',
                checkedUrl: 'https://example.com/health',
              ),
              CheckRecord(
                checkedAt: DateTime.utc(2026, 7, 30, 11, 59),
                status: HealthStatus.down,
                responseTimeMs: 51,
                statusCode: 200,
                error: 'Page is stuck on “Loading…”',
                failureDetail: 'Stored failure context.',
                checkedUrl: 'https://example.com/health',
              ),
            ],
          ),
        ],
      ),
    );
    await writer.close();

    final reader = SqliteMonitorRepository(databasePath: databasePath);
    final restored = await reader.load();
    await reader.close();

    expect(restored.paused, isTrue);
    expect(restored.themePreference, AppThemePreference.dark);
    expect(restored.primaryColorValue, 0xFF2563EB);
    expect(
      restored.notificationSoundPreference,
      NotificationSoundPreference.system,
    );
    expect(restored.sites, hasLength(1));
    expect(restored.sites.single.baseUrl, 'https://example.com');
    expect(restored.sites.single.probeUrl, 'https://example.com/health');
    expect(restored.sites.single.faviconUrl, 'https://example.com/favicon.png');
    expect(restored.sites.single.history.single.statusCode, 200);
    expect(restored.sites.single.history, hasLength(1));
    expect(restored.sites.single.latestCheck?.responseTimeMs, 37);
    expect(
      restored.sites.single.latestCheck?.failureDetail,
      'Stored failure context.',
    );
    expect(
      restored.sites.single.history.single.failureDetail,
      'Stored failure context.',
    );
    expect(
      restored.sites.single.history.single.checkedUrl,
      'https://example.com/health',
    );
  });

  test('updates preferences without rewriting monitor rows', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'sitesignal-preferences-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final databasePath = path.join(
      temporaryDirectory.path,
      'sitesignal.sqlite3',
    );
    final repository = SqliteMonitorRepository(databasePath: databasePath);
    final site = SiteMonitor(
      id: 'site-1',
      name: 'Example',
      baseUrl: 'https://example.com',
      probeUrl: null,
      faviconUrl: null,
      intervalSeconds: 60,
      enabled: true,
      status: HealthStatus.unknown,
      createdAt: DateTime.utc(2026, 8, 2),
      history: const <CheckRecord>[],
    );
    await repository.save(
      PersistedMonitorState(sites: <SiteMonitor>[site], paused: false),
    );

    await repository.savePreferences(
      const PersistedMonitorPreferences(
        paused: true,
        themePreference: AppThemePreference.dark,
        primaryColorValue: 0xFF177E78,
        notificationSoundPreference: NotificationSoundPreference.beacon,
      ),
    );
    final restored = await repository.load();
    await repository.close();

    expect(restored.sites.single.id, site.id);
    expect(restored.paused, isTrue);
    expect(restored.themePreference, AppThemePreference.dark);
    expect(restored.primaryColorValue, 0xFF177E78);
    expect(
      restored.notificationSoundPreference,
      NotificationSoundPreference.beacon,
    );
  });

  test('migrates a version 1 database and preserves its latest check', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'sitesignal-sqlite-v1-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final databasePath = path.join(
      temporaryDirectory.path,
      'sitesignal.sqlite3',
    );

    sqfliteFfiInit();
    final legacyDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await database.execute('''
            CREATE TABLE monitors (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              base_url TEXT NOT NULL UNIQUE,
              probe_url TEXT,
              interval_seconds INTEGER NOT NULL,
              enabled INTEGER NOT NULL,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE checks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              monitor_id TEXT NOT NULL,
              checked_at TEXT NOT NULL,
              status TEXT NOT NULL,
              response_time_ms INTEGER,
              status_code INTEGER,
              error TEXT,
              checked_url TEXT NOT NULL
            )
          ''');
          await database.execute(
            'CREATE INDEX checks_monitor_time '
            'ON checks(monitor_id, checked_at DESC)',
          );
        },
      ),
    );
    await legacyDatabase.insert('monitors', <String, Object?>{
      'id': 'legacy',
      'name': 'Legacy',
      'base_url': 'https://example.com',
      'probe_url': null,
      'interval_seconds': 15,
      'enabled': 1,
      'status': 'up',
      'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    });
    for (final second in <int>[1, 2]) {
      await legacyDatabase.insert('checks', <String, Object?>{
        'monitor_id': 'legacy',
        'checked_at': DateTime.utc(2026, 1, 1, 0, 0, second).toIso8601String(),
        'status': 'up',
        'response_time_ms': 40 + second,
        'status_code': 200,
        'error': null,
        'checked_url': 'https://example.com',
      });
    }
    await legacyDatabase.close();

    final repository = SqliteMonitorRepository(databasePath: databasePath);
    final restored = await repository.load();
    await repository.close();

    expect(restored.sites, hasLength(1));
    expect(restored.sites.single.intervalSeconds, 15);
    expect(restored.sites.single.faviconUrl, isNull);
    expect(restored.sites.single.history, hasLength(1));
    expect(restored.sites.single.latestCheck?.responseTimeMs, 42);

    final migratedDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
    );
    expect(await migratedDatabase.getVersion(), 3);
    final columns = await migratedDatabase.rawQuery(
      'PRAGMA table_info(monitors)',
    );
    expect(columns.map((column) => column['name']), contains('favicon_url'));
    expect(
      columns.map((column) => column['name']),
      contains('last_checked_at'),
    );
    expect(
      columns.map((column) => column['name']),
      contains('last_failure_detail'),
    );
    final checkColumns = await migratedDatabase.rawQuery(
      'PRAGMA table_info(checks)',
    );
    expect(
      checkColumns.map((column) => column['name']),
      contains('failure_detail'),
    );
    expect(restored.primaryColorValue, AppAccentColor.defaultValue);
    expect(
      restored.notificationSoundPreference,
      NotificationSoundPreference.siteSignal,
    );
    await migratedDatabase.close();
  });

  test(
    'copies the legacy Sitotify database before opening SiteSignal',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'sitesignal-legacy-database-test-',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final legacyPath = path.join(temporaryDirectory.path, 'sitotify.sqlite3');
      final siteSignalPath = path.join(
        temporaryDirectory.path,
        'sitesignal.sqlite3',
      );

      final legacyRepository = SqliteMonitorRepository(
        databasePath: legacyPath,
      );
      await legacyRepository.save(
        PersistedMonitorState(
          paused: true,
          themePreference: AppThemePreference.dark,
          primaryColorValue: 0xFFE11D48,
          sites: <SiteMonitor>[
            SiteMonitor(
              id: 'preserved-site',
              name: 'Preserved site',
              baseUrl: 'https://example.com',
              probeUrl: null,
              faviconUrl: null,
              intervalSeconds: 15,
              enabled: true,
              status: HealthStatus.up,
              createdAt: DateTime.utc(2026, 7, 30),
              history: const <CheckRecord>[],
            ),
          ],
        ),
      );
      await legacyRepository.close();

      final siteSignalRepository = SqliteMonitorRepository(
        databasePath: siteSignalPath,
        legacyDatabasePath: legacyPath,
      );
      final restored = await siteSignalRepository.load();
      await siteSignalRepository.close();

      expect(await File(legacyPath).exists(), isTrue);
      expect(await File(siteSignalPath).exists(), isTrue);
      expect(restored.paused, isTrue);
      expect(restored.themePreference, AppThemePreference.dark);
      expect(restored.primaryColorValue, 0xFFE11D48);
      expect(restored.sites.single.id, 'preserved-site');
    },
  );
}
