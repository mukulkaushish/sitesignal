import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/monitor_ui.dart';

void main() {
  test('relative times use concise human-readable units', () {
    final now = DateTime.utc(2026, 8, 2, 12);

    expect(formatRelativeTime(now, now: now), 'Just now');
    expect(
      formatRelativeTime(now.subtract(const Duration(seconds: 12)), now: now),
      '12 sec ago',
    );
    expect(
      formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
      '5 min ago',
    );
    expect(
      formatRelativeTime(now.subtract(const Duration(days: 2)), now: now),
      '2 days ago',
    );
  });

  test('timestamps use friendly calendar labels and 12-hour time', () {
    final now = DateTime(2026, 8, 2, 20);

    expect(
      formatTimestamp(DateTime(2026, 8, 2, 18, 5), now: now),
      'Today, 6:05 PM',
    );
    expect(
      formatTimestamp(DateTime(2026, 8, 1, 8, 7), now: now),
      'Yesterday, 8:07 AM',
    );
    expect(
      formatTimestamp(DateTime(2026, 7, 10, 0, 4), now: now),
      'Jul 10, 12:04 AM',
    );
    expect(
      formatTimestamp(DateTime(2025, 12, 31, 12), now: now),
      'Dec 31, 2025, 12:00 PM',
    );
  });
}
