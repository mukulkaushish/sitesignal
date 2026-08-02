abstract final class IncidentNotificationKey {
  static const connectivity = 'network:connectivity';
  static const test = 'test-alert';

  static String site(String siteId) => 'site:$siteId';
}
