import 'dart:async';

typedef SerialTaskErrorHandler =
    void Function(Object error, StackTrace stackTrace);

/// Runs independent task submissions in order while containing prior errors.
final class SerialTaskQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> schedule(
    Future<void> Function() operation, {
    SerialTaskErrorHandler? onError,
    bool propagateError = false,
  }) {
    final scheduled = _tail.then((_) => operation());
    _tail = scheduled.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        try {
          onError?.call(error, stackTrace);
        } on Object {
          // An observer must never poison the queue or block later tasks.
        }
      },
    );
    return propagateError ? scheduled : _tail;
  }

  Future<void> drain() => _tail;
}
