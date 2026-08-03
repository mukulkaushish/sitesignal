enum NotificationSoundPreference {
  siteSignal,
  brightChime,
  softPulse,
  beacon,
  system,
  silent;

  static NotificationSoundPreference fromName(String? value) {
    return NotificationSoundPreference.values.firstWhere(
      (preference) => preference.name == value,
      orElse: () => NotificationSoundPreference.siteSignal,
    );
  }
}

class NotificationSoundProfile {
  const NotificationSoundProfile({
    required this.label,
    required this.selectorDescription,
    required this.activeDescription,
    required this.androidChannelId,
    required this.androidChannelName,
    this.resourceName,
  });

  final String label;
  final String selectorDescription;
  final String activeDescription;
  final String androidChannelId;
  final String androidChannelName;
  final String? resourceName;

  String? get assetPath => switch (resourceName) {
    final resourceName? => 'assets/$resourceName.wav',
    null => null,
  };

  String? get fileName => switch (resourceName) {
    final resourceName? => '$resourceName.wav',
    null => null,
  };
}

extension NotificationSoundPreferenceCatalog on NotificationSoundPreference {
  NotificationSoundProfile get profile => switch (this) {
    NotificationSoundPreference.siteSignal => const NotificationSoundProfile(
      label: 'Classic bell',
      selectorDescription: 'The original two-note SiteSignal alert',
      activeDescription: 'The original SiteSignal bell plays for transitions.',
      androidChannelId: 'sitesignal_incidents_v4',
      androidChannelName: 'Site health · SiteSignal tone',
      resourceName: 'site_signal_alert',
    ),
    NotificationSoundPreference.brightChime => const NotificationSoundProfile(
      label: 'Bright chime',
      selectorDescription: 'A crisp, energetic three-note chime',
      activeDescription: 'A crisp three-note chime plays for transitions.',
      androidChannelId: 'sitesignal_incidents_bright_v4',
      androidChannelName: 'Site health · Bright chime',
      resourceName: 'site_signal_bright_chime',
    ),
    NotificationSoundPreference.softPulse => const NotificationSoundProfile(
      label: 'Soft pulse',
      selectorDescription: 'A gentler, low-key alert',
      activeDescription: 'A softer pulse plays for transitions.',
      androidChannelId: 'sitesignal_incidents_pulse_v4',
      androidChannelName: 'Site health · Soft pulse',
      resourceName: 'site_signal_soft_pulse',
    ),
    NotificationSoundPreference.beacon => const NotificationSoundProfile(
      label: 'Beacon',
      selectorDescription: 'A clear repeating signal',
      activeDescription: 'A clear beacon signal plays for transitions.',
      androidChannelId: 'sitesignal_incidents_beacon_v4',
      androidChannelName: 'Site health · Beacon',
      resourceName: 'site_signal_beacon',
    ),
    NotificationSoundPreference.system => const NotificationSoundProfile(
      label: 'System default',
      selectorDescription: 'Use your device notification sound',
      activeDescription: 'Your operating system chooses the alert tone.',
      androidChannelId: 'sitesignal_incidents_system_v4',
      androidChannelName: 'Site health · System sound',
    ),
    NotificationSoundPreference.silent => const NotificationSoundProfile(
      label: 'Silent',
      selectorDescription: 'Show alerts without playing sound',
      activeDescription: 'Outage and recovery alerts remain visible but quiet.',
      androidChannelId: 'sitesignal_incidents_silent_v4',
      androidChannelName: 'Site health · Silent',
    ),
  };

  bool get playsSound => this != NotificationSoundPreference.silent;
}
