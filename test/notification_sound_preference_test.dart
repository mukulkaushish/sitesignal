import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';

void main() {
  test('sound catalog has unique labels and immutable Android channels', () {
    final profiles = NotificationSoundPreference.values
        .map((preference) => preference.profile)
        .toList(growable: false);

    expect(profiles.map((profile) => profile.label).toSet(), hasLength(6));
    expect(
      profiles.map((profile) => profile.androidChannelId).toSet(),
      hasLength(6),
    );
    expect(
      profiles.every((profile) => profile.androidChannelId.endsWith('_v4')),
      isTrue,
    );
    expect(
      profiles.every((profile) => profile.activeDescription.isNotEmpty),
      isTrue,
    );
  });

  test('every custom sound is bundled for Flutter and Android', () {
    final customProfiles = NotificationSoundPreference.values
        .map((preference) => preference.profile)
        .where((profile) => profile.resourceName != null)
        .toList(growable: false);

    expect(customProfiles, hasLength(4));
    for (final profile in customProfiles) {
      final assetPath = profile.assetPath;
      final fileName = profile.fileName;
      final resourceName = profile.resourceName;
      expect(assetPath, isNotNull);
      expect(fileName, isNotNull);
      expect(resourceName, isNotNull);
      if (assetPath == null || fileName == null || resourceName == null) {
        continue;
      }
      expect(resourceName, isNot(contains('.')));
      expect(fileName, '$resourceName.wav');
      expect(assetPath, 'assets/$fileName');
      expect(File(assetPath).existsSync(), isTrue, reason: assetPath);
      final androidPath = 'android/app/src/main/res/raw/$resourceName.wav';
      expect(File(androidPath).existsSync(), isTrue, reason: androidPath);
    }
  });
}
