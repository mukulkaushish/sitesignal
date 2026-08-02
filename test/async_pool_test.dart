import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/core/async/async_pool.dart';

void main() {
  test('bounds concurrency and preserves input order', () async {
    var active = 0;
    var peak = 0;

    final values = await mapConcurrent<int, int>(<int>[4, 3, 2, 1, 0], (
      value,
    ) async {
      active += 1;
      if (active > peak) {
        peak = active;
      }
      await Future<void>.delayed(Duration(milliseconds: value));
      active -= 1;
      return value * 2;
    }, maxConcurrent: 2);

    expect(peak, 2);
    expect(values, <int>[8, 6, 4, 2, 0]);
  });

  test('rejects a non-positive concurrency limit', () {
    expect(
      () => mapConcurrent<int, int>(
        const <int>[1],
        (value) async => value,
        maxConcurrent: 0,
      ),
      throwsArgumentError,
    );
  });
}
