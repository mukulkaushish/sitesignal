import 'package:site_signal/features/updates/domain/entities/app_update.dart';

abstract interface class UpdateChecker {
  Future<AppUpdate?> checkForUpdate();

  void close();
}

final class DisabledUpdateChecker implements UpdateChecker {
  const DisabledUpdateChecker();

  @override
  Future<AppUpdate?> checkForUpdate() async => null;

  @override
  void close() {}
}
