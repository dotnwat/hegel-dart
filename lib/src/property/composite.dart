part of 'generator.dart';

/// The span a [composite] generator's draws are grouped under.
///
/// One number above everything the engine reserves, and the same number for
/// every composite. The engine reads a label as "these draws belong
/// together" and nothing more, so what a frontend mints only has to be
/// stable and out of the reserved way. A label per composite would need a
/// stable hash of a closure, which Dart has no way to take -- and Go, which
/// could, uses one constant anyway.
const SpanLabel _compositeLabel = SpanLabel(SpanLabel.firstAvailable);

/// Generates values [build] puts together out of draws of its own.
///
/// The door out of the catalog, and the only one: [Generator] is closed, so a
/// value the combinators cannot describe is written as a function instead of
/// as a subclass.
///
/// [build] is written exactly like a property body -- it gets the same
/// [TestCase] and draws from it the same way -- and everything it draws is
/// grouped as parts of the one value it returns, so a failure report names
/// the value rather than the pieces:
///
/// ```dart
/// final ranges = composite((tc) {
///   final low = tc.draw(integers(min: 0, max: 100));
///   final high = tc.draw(integers(min: low, max: 200));
///   return (low, high);
/// });
/// ```
///
/// A later draw may depend on an earlier one, as `high` does above, which is
/// what makes this worth reaching for. What [build] must not depend on is
/// anything the engine did not hand it: a clock, a counter, a random source
/// of its own. The engine replays a case by replaying its choices, and a
/// build that consults something else reads the same choices as a different
/// value -- so the counterexample in the report is not the one that failed.
///
/// [TestCase.assume] works inside, and rejects the whole case rather than
/// the value: a composite cannot redraw its way out of a rejection the way
/// [Generator.where] can, because it has already spent the draws.
Generator<T> composite<T>(T Function(TestCase testCase) build) =>
    _CompositeGenerator<T>(build);

/// A value put together by a function, out of draws it made itself.
final class _CompositeGenerator<T> extends Generator<T> {
  const _CompositeGenerator(this._build);

  final T Function(TestCase testCase) _build;

  @override
  T generate(TestCase testCase) =>
      testCase.span(_compositeLabel, () => _build(testCase));
}

/// A generator that stands in for one not written yet.
///
/// For recursive values, which Dart's initialisation rules otherwise make
/// impossible to write: a generator that mentions itself cannot be built in
/// one expression. This is the two-step version -- name it, then say what it
/// is:
///
/// ```dart
/// final trees = deferred<Tree>();
/// trees.define(
///   oneOf(<Generator<Tree>>[
///     integers(min: 0, max: 100).map(Leaf.new),
///     tuple2(trees, trees).map((pair) => Branch(pair.$1, pair.$2)),
///   ]),
/// );
/// ```
///
/// Recursion terminates because the engine runs out of room for it: a case
/// has a budget of choices, and as that budget goes the draws that decide
/// which branch to take are pushed toward their smallest value. So the
/// non-recursive branch has to be reachable at the smallest choice -- first
/// in a [oneOf], the null of an [optional] -- or the recursion has nothing to
/// bottom out into and every case overruns.
DeferredGenerator<T> deferred<T>() => DeferredGenerator<T>._();

/// The generator [deferred] returns, before and after it is defined.
///
/// Defined exactly once, and drawn from only after that. Both mistakes throw
/// where they are made rather than producing a strange run: a generator with
/// no definition has nothing to draw, and one defined twice means two
/// recipes are in play and no reader can tell which the failure came from.
final class DeferredGenerator<T> extends Generator<T> {
  DeferredGenerator._();

  Generator<T>? _defined;

  /// Says that this generator is [generator].
  ///
  /// Call it once, before the first draw.
  void define(Generator<T> generator) {
    if (_defined != null) {
      throw StateError(
        'this deferred generator is already defined; a second definition '
        'would leave two recipes in play and no way to tell which a '
        'counterexample came from',
      );
    }
    _defined = generator;
  }

  @override
  T generate(TestCase testCase) {
    final defined = _defined;
    if (defined == null) {
      throw StateError(
        'this deferred generator has not been defined yet; call define() on '
        'it before drawing from it or from anything built out of it',
      );
    }
    // No span of its own: this is a name for another generator rather than a
    // value composed out of parts, and a span here would tell the shrinker
    // there is a structure to take apart where there is none.
    return defined.generate(testCase);
  }
}
