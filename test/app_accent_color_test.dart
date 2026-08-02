import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/core/theme/app_accent_color.dart';

void main() {
  test('every curated accent remains visible on light and dark surfaces', () {
    for (final preset in AppAccentColor.presets) {
      expect(
        AppAccentColor.readableOnBothSurfaces(preset.color),
        isTrue,
        reason: preset.name,
      );
    }
  });
}
