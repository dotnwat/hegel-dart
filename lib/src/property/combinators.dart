part of 'generator.dart';

/// How many times [Generator.where] redraws before giving up on the case.
///
/// Three, which is what every Hegel frontend uses. The number is a
/// compromise the engine is on the other side of: retrying costs draws the
/// shrinker then has to work through, and giving up costs a case, but a
/// rejected case is also a signal -- the engine steers away from that part of
/// the space and complains if too much of the run goes that way. Retrying
/// harder would hide the very thing worth being told about.
const int _filterAttempts = 3;

/// One generator's values, put through a function.
final class _MappedGenerator<T, R> extends Generator<R> {
  const _MappedGenerator(this._source, this._transform);

  final Generator<T> _source;
  final R Function(T value) _transform;

  @override
  R generate(TestCase testCase) => testCase.span(
    SpanLabel.mapped,
    () => _transform(_source.generate(testCase)),
  );
}

/// One generator's values, kept only when a predicate accepts them.
final class _FilteredGenerator<T> extends Generator<T> {
  const _FilteredGenerator(this._source, this._predicate);

  final Generator<T> _source;
  final bool Function(T value) _predicate;

  @override
  T generate(TestCase testCase) {
    for (var attempt = 0; attempt < _filterAttempts; attempt++) {
      final (:kept, :value) = testCase.attempt(
        SpanLabel.filter,
        () => _source.generate(testCase),
        keep: _predicate,
      );
      if (kept) return value;
    }
    // The same signal the body's own precondition raises, because it means
    // the same thing: this case is not one the property is about. The engine
    // counts it as rejected rather than failed, and if enough cases end here
    // it says the filter is too narrow.
    throw const AssumptionFailed();
  }
}

/// One generator's values, each choosing the generator drawn from next.
final class _FlatMapGenerator<T, R> extends Generator<R> {
  const _FlatMapGenerator(this._source, this._choose);

  final Generator<T> _source;
  final Generator<R> Function(T value) _choose;

  @override
  R generate(TestCase testCase) => testCase.span(SpanLabel.flatMap, () {
    // Both draws inside the one span: what the second produced only makes
    // sense next to what the first chose, so the shrinker has to move them
    // together or not at all.
    final chosen = _choose(_source.generate(testCase));
    return chosen.generate(testCase);
  });
}
