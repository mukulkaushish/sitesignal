import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/data/mobile_background_monitor.dart';

void main() {
  test('coalesced reruns preserve force connectivity until consumed', () {
    final state = BackgroundCheckRerunState();

    state.request();
    state.request(forceConnectivity: true);
    state.request();

    expect(state.consume(), (requested: true, forceConnectivity: true));
    expect(state.consume(), (requested: false, forceConnectivity: false));
  });

  test('ordinary reruns remain non-forced', () {
    final state = BackgroundCheckRerunState()..request();

    expect(state.consume(), (requested: true, forceConnectivity: false));
  });
}
