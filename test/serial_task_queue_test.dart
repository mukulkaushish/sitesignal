import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/core/async/serial_task_queue.dart';

void main() {
  test('runs scheduled work in submission order', () async {
    final queue = SerialTaskQueue();
    final firstMayFinish = Completer<void>();
    final events = <String>[];

    final first = queue.schedule(() async {
      events.add('first-start');
      await firstMayFinish.future;
      events.add('first-end');
    });
    final second = queue.schedule(() async {
      events.add('second');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['first-start']);
    firstMayFinish.complete();
    await Future.wait(<Future<void>>[first, second, queue.drain()]);
    expect(events, <String>['first-start', 'first-end', 'second']);
  });

  test('contains one failure without blocking later work', () async {
    final queue = SerialTaskQueue();
    Object? observedError;
    final failed = queue.schedule(
      () => Future<void>.error(StateError('failed')),
      propagateError: true,
      onError: (error, stackTrace) => observedError = error,
    );
    var secondRan = false;
    final second = queue.schedule(() async => secondRan = true);

    await expectLater(failed, throwsStateError);
    await Future.wait(<Future<void>>[second, queue.drain()]);
    expect(observedError, isA<StateError>());
    expect(secondRan, isTrue);
  });
}
