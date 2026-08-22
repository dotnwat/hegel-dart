part of 'generator.dart';

/// A set of values a stateful test made, that the engine can choose among.
///
/// The mechanism behind "act on something an earlier step produced". A rule
/// that creates a resource -- a file, a session, a key -- puts it in a pool;
/// a rule that acts on one draws from the pool, and the engine decides which.
/// That decision is a draw like any other, so a failing case shrinks over it:
/// the counterexample that comes back acts on the *first* resource it made
/// rather than the seventh, if the first is enough to show the bug.
///
/// Two generators, because there are two kinds of resource. [reusable] leaves
/// what it drew in the pool, for something that can be acted on again;
/// [consumed] takes it out, for something that cannot -- a handle that gets
/// closed, a token that gets spent.
///
/// The pool holds the values, and the engine holds only identifiers for them,
/// which is what lets a value be anything at all.
///
/// ```dart
/// final class FileMachine extends StateMachine {
///   late final Pool<String> files;
///
///   @override
///   List<Rule> get rules => <Rule>[
///     Rule('create', (TestCase tc) {
///       files.add(tc, createFile());
///     }),
///     Rule(
///       'delete',
///       (TestCase tc) => deleteFile(tc.draw(files.consumed)),
///       // Drawing from an empty pool ends the case rather than the step, so
///       // the rule has to be kept off the table instead.
///       precondition: () => files.isNotEmpty,
///     ),
///   ];
/// }
/// ```
///
/// Its life is the test case it was made from: the engine handle behind it is
/// released when that case ends, whatever ends it, so there is nothing to
/// close. A pool made inside a rule of a concurrent machine belongs to that
/// worker's case and goes when its round is over, which is a shorter life
/// than the one a machine's own field gets -- another reason to build a pool
/// where the machine is built rather than where a rule runs.
final class Pool<T> {
  /// A pool over the family of [testCase], empty to begin with.
  Pool(TestCase testCase) : _pool = testCase.context.startPool() {
    testCase.onRelease(_pool.dispose);
  }

  final DrawPool _pool;

  /// What the engine's identifiers stand for, by identifier.
  ///
  /// A map rather than a list, because the engine records an identifier by
  /// value rather than by position: deleting an earlier addition while
  /// shrinking never renumbers the ones that survive it, which is exactly
  /// what a list would do.
  final Map<int, T> _values = <int, T>{};

  /// How many values are in the pool.
  int get length => _values.length;

  /// Whether the pool has nothing in it.
  ///
  /// The question a `precondition:` on a rule that draws from this pool
  /// should be asking: an empty pool ends the case rather than the step, so
  /// it has to be kept off the table rather than caught.
  bool get isEmpty => _values.isEmpty;

  /// Whether the pool has anything in it.
  bool get isNotEmpty => _values.isNotEmpty;

  /// Puts [value] in the pool, on a fresh identifier drawn from [testCase].
  void add(TestCase testCase, T value) {
    _values[_pool.add(testCase.context)] = value;
  }

  /// Draws a value the pool keeps.
  ///
  /// The engine chooses which, and a failing case shrinks toward the earliest
  /// one that still fails.
  Generator<T> get reusable => _PoolGenerator<T>(this, consume: false);

  /// Draws a value and takes it out of the pool.
  ///
  /// For a resource that cannot be acted on twice. Whatever comes back is no
  /// longer something a later step can draw.
  Generator<T> get consumed => _PoolGenerator<T>(this, consume: true);

  T _draw(TestCase testCase, {required bool consume}) {
    final identifier = _pool.draw(testCase.context, consume: consume);
    if (!_values.containsKey(identifier)) {
      // Not reachable through any run this package can produce: the engine
      // only ever chooses among the identifiers it was given. Reported rather
      // than left to a null that a nullable T would swallow, since a pool
      // that quietly handed back nothing would fail somewhere else entirely.
      throw StateError('the engine chose a variable this pool never added');
    }
    final value = _values[identifier] as T;
    if (consume) _values.remove(identifier);
    return value;
  }
}

/// One of a pool's values, chosen by the engine.
final class _PoolGenerator<T> extends Generator<T> {
  const _PoolGenerator(this._pool, {required this.consume});

  final Pool<T> _pool;

  /// Whether drawing takes the value out. Named without the underscore the
  /// rest of this library uses, so that it can be an initializing formal.
  final bool consume;

  @override
  T generate(TestCase testCase) => _pool._draw(testCase, consume: consume);
}
