import 'package:package_info_plus/package_info_plus.dart';

extension PackageInfoDisplay on PackageInfo {
  String get displayVersion {
    final normalizedVersion = version.trim();
    final normalizedBuild = buildNumber.trim();
    if (normalizedBuild.isEmpty || normalizedBuild == normalizedVersion) {
      return normalizedVersion;
    }
    return '$normalizedVersion ($normalizedBuild)';
  }
}
