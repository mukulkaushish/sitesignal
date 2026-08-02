import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:site_signal/core/platform/package_info_extensions.dart';

void main() {
  test('formats the installed version and build number', () {
    final info = PackageInfo(
      appName: 'SiteSignal',
      packageName: 'dev.sitesignal.app',
      version: '2.3.4',
      buildNumber: '17',
    );

    expect(info.displayVersion, '2.3.4 (17)');
  });

  test('does not duplicate an empty build number', () {
    final info = PackageInfo(
      appName: 'SiteSignal',
      packageName: 'dev.sitesignal.app',
      version: '2.3.4',
      buildNumber: '',
    );

    expect(info.displayVersion, '2.3.4');
  });
}
