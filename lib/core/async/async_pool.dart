/// Runs [operation] over [items] with a bounded number of in-flight futures.
///
/// Results retain input order even when individual operations finish out of
/// order. This keeps network fan-out predictable without a long-lived queue.
Future<List<R>> mapConcurrent<T, R>(
  Iterable<T> items,
  Future<R> Function(T item) operation, {
  required int maxConcurrent,
}) async {
  if (maxConcurrent < 1) {
    throw ArgumentError.value(
      maxConcurrent,
      'maxConcurrent',
      'Must be at least one.',
    );
  }
  final inputs = items.toList(growable: false);
  if (inputs.isEmpty) {
    return <R>[];
  }

  final results = List<Object?>.filled(inputs.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      final index = nextIndex;
      if (index >= inputs.length) {
        return;
      }
      nextIndex += 1;
      results[index] = await operation(inputs[index]);
    }
  }

  final workerCount = inputs.length < maxConcurrent
      ? inputs.length
      : maxConcurrent;
  await Future.wait(List<Future<void>>.generate(workerCount, (_) => worker()));
  return List<R>.generate(inputs.length, (index) => results[index] as R);
}
