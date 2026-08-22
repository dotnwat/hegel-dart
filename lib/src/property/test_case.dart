/// The handle a property body draws through, and the seam it draws from.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../libhegel/collection.dart' as engine;
import '../libhegel/errors.dart';
import '../libhegel/settings.dart';
import '../libhegel/span.dart';
import '../libhegel/string_generator.dart';
import '../libhegel/test_case.dart' as engine;
import 'generator.dart';

/// One value the body drew, as the report will show it.
///
/// The name is the one the body gave the draw, or null when it gave none, in
/// which case the report falls back to the draw's position.
@internal
typedef Drawn = ({String? name, Object? value});

/// A sequence whose length the engine decides, as a generator sees it.
///
/// The engine end of every variable-length value: [more] asks whether another
/// element is wanted, [reject] says the one just produced cannot be used, and
/// [dispose] gives the handle back. Which test case the decisions are drawn
/// from is the seam's business rather than the generator's, so unlike the
/// binding layer's [engine.Collection] none of these take one.
@internal
abstract interface class DrawCollection {
  /// Whether the engine wants another element.
  bool more();

  /// Reports that the element just produced cannot be used.
  ///
  /// [why] is for the engine's future diagnostics; it does not act on it yet.
  void reject(String why);

  /// Releases the collection. Idempotent.
  void dispose();
}

/// The engine, as a generator needs to see it.
///
/// A [TestCase] holds one of these rather than an engine handle, so that a
/// combinator can be driven by a scripted choice sequence. That is not a
/// convenience: the interesting cases for a combinator are the ones where the
/// engine hands back a specific value at a specific point -- a duplicate
/// element, a filtered draw, the third retry -- and asking the real engine for
/// those means asking it to be something other than random.
///
/// It grows a method per engine primitive the catalog reaches, and no more:
/// what is not here is what no generator has needed yet.
@internal
abstract interface class DrawContext {
  /// Draws an integer between [min] and [max] inclusive.
  int drawInteger({required int min, required int max});

  /// Draws an integer of any width between [min] and [max] inclusive.
  BigInt drawBigInteger({required BigInt min, required BigInt max});

  /// Draws true with probability [probability].
  bool drawBoolean({required double probability});

  /// Draws a 64-bit float within the bounds and exclusions given.
  double drawFloat({
    required double min,
    required double max,
    required bool allowNan,
    required bool allowInfinity,
    required bool excludeMin,
    required bool excludeMax,
  });

  /// Draws a string described by [generator].
  String drawString(StringGenerator generator);

  /// Draws a byte string of [minLength] to [maxLength] bytes.
  Uint8List drawBytes({required int minLength, int? maxLength});

  /// Draws a calendar date between [min] and [max] inclusive.
  engine.HegelDate drawDate({
    required engine.HegelDate min,
    required engine.HegelDate max,
  });

  /// Draws a time of day between [min] and [max] inclusive.
  engine.HegelTime drawTime({
    required engine.HegelTime min,
    required engine.HegelTime max,
  });

  /// Draws a date and time between [min] and [max] inclusive.
  engine.HegelDateTime drawDateTime({
    required engine.HegelDateTime min,
    required engine.HegelDateTime max,
  });

  /// Draws the sixteen bytes of a UUID, of [version] where one is asked for.
  Uint8List drawUuid({int? version});

  /// Draws the four bytes of an IPv4 address.
  Uint8List drawIpv4();

  /// Draws the sixteen bytes of an IPv6 address.
  Uint8List drawIpv6();

  /// Records [value] under [label] as something to steer toward.
  void target(double value, {required String label});

  /// Starts a sequence of [minLength] to [maxLength] elements.
  ///
  /// A null [maxLength] leaves the length unbounded, which is the engine
  /// keeping it small on its own rather than the length running away.
  DrawCollection startCollection({required int minLength, int? maxLength});

  /// Opens a span grouping the draws made until the matching [stopSpan].
  void startSpan(SpanLabel label);

  /// Closes the most recently opened span.
  ///
  /// With [discard] the span is closed as rejected, and the engine retries
  /// from where it opened rather than keeping the draws inside it.
  void stopSpan({bool discard = false});
}

/// A [DrawContext] backed by a real engine test case.
@internal
final class EngineDrawContext implements DrawContext {
  /// Draws from [testCase].
  EngineDrawContext(this.testCase);

  /// The binding-layer case every draw goes to.
  final engine.TestCase testCase;

  @override
  int drawInteger({required int min, required int max}) =>
      testCase.drawInteger(min: min, max: max);

  @override
  BigInt drawBigInteger({required BigInt min, required BigInt max}) =>
      testCase.drawBigInteger(min: min, max: max);

  @override
  bool drawBoolean({required double probability}) =>
      testCase.drawBoolean(probability: probability);

  @override
  double drawFloat({
    required double min,
    required double max,
    required bool allowNan,
    required bool allowInfinity,
    required bool excludeMin,
    required bool excludeMax,
  }) => testCase.drawFloat(
    min: min,
    max: max,
    allowNan: allowNan,
    allowInfinity: allowInfinity,
    excludeMin: excludeMin,
    excludeMax: excludeMax,
  );

  @override
  String drawString(StringGenerator generator) =>
      testCase.drawString(generator);

  @override
  Uint8List drawBytes({required int minLength, int? maxLength}) =>
      testCase.drawBytes(minLength: minLength, maxLength: maxLength);

  @override
  engine.HegelDate drawDate({
    required engine.HegelDate min,
    required engine.HegelDate max,
  }) => testCase.drawDate(min: min, max: max);

  @override
  engine.HegelTime drawTime({
    required engine.HegelTime min,
    required engine.HegelTime max,
  }) => testCase.drawTime(min: min, max: max);

  @override
  engine.HegelDateTime drawDateTime({
    required engine.HegelDateTime min,
    required engine.HegelDateTime max,
  }) => testCase.drawDateTime(min: min, max: max);

  @override
  Uint8List drawUuid({int? version}) => testCase.drawUuid(version: version);

  @override
  Uint8List drawIpv4() => testCase.drawIpv4();

  @override
  Uint8List drawIpv6() => testCase.drawIpv6();

  @override
  void target(double value, {required String label}) =>
      testCase.target(value, label: label);

  @override
  DrawCollection startCollection({required int minLength, int? maxLength}) =>
      _EngineCollection(
        testCase,
        testCase.startCollection(minSize: minLength, maxSize: maxLength),
      );

  @override
  void startSpan(SpanLabel label) => testCase.startSpan(label);

  @override
  void stopSpan({bool discard = false}) => testCase.stopSpan(discard: discard);
}

/// A [DrawCollection] backed by a real engine collection.
///
/// Holds the test case the collection was started on and drives it from that
/// one throughout. The handle is shared by a whole test-case family, so which
/// member asks decides where the continue-or-stop choice is recorded, and a
/// sequence whose decisions came from two different members would record its
/// length in two places.
final class _EngineCollection implements DrawCollection {
  _EngineCollection(this._testCase, this._collection);

  final engine.TestCase _testCase;
  final engine.Collection _collection;

  @override
  bool more() => _collection.more(_testCase);

  @override
  void reject(String why) => _collection.reject(_testCase, why: why);

  @override
  void dispose() => _collection.dispose();
}

/// One test case, as a property body sees it.
///
/// The body receives one of these and draws every value it needs from it. A
/// case is single-use: the runner makes a fresh one per test case, and the
/// engine decides what the draws come back as -- generated, replayed from the
/// example database, or shrunk.
final class TestCase {
  /// Draws through [context].
  @internal
  TestCase(this._context);

  final DrawContext _context;

  /// How many values are currently being composed out of draws.
  ///
  /// A draw belongs to the report only when nothing else is building a value
  /// out of it: the elements of a list are the list, not five more drawn
  /// values, and the report says so by naming the list alone. Every compound
  /// generator opens a span around its parts, so counting open spans is the
  /// same question as "is anything composing this draw", asked in the one
  /// place the answer is already known.
  int _depth = 0;

  final List<Drawn> _draws = <Drawn>[];
  final List<String> _notes = <String>[];

  /// The seam generators draw from.
  @internal
  DrawContext get context => _context;

  /// The values this case drew, in the order it drew them.
  ///
  /// Composed parts are not in here; see [_depth].
  @internal
  List<Drawn> get draws => _draws;

  /// What the body recorded with [note], in order.
  @internal
  List<String> get notes => _notes;

  /// Draws a value from [generator].
  ///
  /// What comes back is the engine's choice, not a random value: on a replay
  /// or while shrinking, the same call returns whatever the stored choice
  /// sequence says. A property that branches on a drawn value therefore
  /// replays exactly as it ran.
  ///
  /// [name] labels the value in the failure report. Worth giving: a report
  /// that says `message = [0, 128]` is read at a glance, and one that says
  /// `draw_2 = [0, 128]` has to be counted out against the body. Dart has no
  /// macro that could take the name from the variable being assigned, which
  /// is how the Rust frontend does it, so the name is asked for instead.
  T draw<T>(Generator<T> generator, {String? name}) {
    final value = generator.generate(this);
    if (_depth == 0) _draws.add((name: name, value: value));
    return value;
  }

  /// Runs [body] as one value composed under a span labelled [label].
  ///
  /// Two things at once, because they are the same thing: the engine is told
  /// which draws belong together, so the shrinker can simplify or delete the
  /// value whole, and the report is told that the draws inside are parts
  /// rather than values of their own.
  ///
  /// The span closes however [body] ends. A generator that gave up partway
  /// through -- an assumption that did not hold, a case the engine ended --
  /// still leaves the engine's span stack where it found it.
  @internal
  T span<T>(SpanLabel label, T Function() body) {
    _context.startSpan(label);
    _depth++;
    try {
      return body();
    } finally {
      _depth--;
      _context.stopSpan();
    }
  }

  /// Runs [body] as one attempt at a value composed under [label].
  ///
  /// [span], with the engine told whether the attempt was worth keeping.
  /// [keep] decides, and a span it rejects is closed as discarded: the engine
  /// then retries from where the span opened instead of carrying the rejected
  /// draws around for the rest of the case. That is the difference between a
  /// filter that shrinks and one whose every abandoned attempt stays in the
  /// choice sequence forever.
  ///
  /// Returns whether the value was kept alongside the value itself, rather
  /// than returning null for a rejected attempt: a generator of nullable
  /// values has null among the things it can legitimately keep.
  @internal
  ({bool kept, T value}) attempt<T>(
    SpanLabel label,
    T Function() body, {
    required bool Function(T value) keep,
  }) {
    _context.startSpan(label);
    _depth++;
    var kept = false;
    try {
      final value = body();
      kept = keep(value);
      return (kept: kept, value: value);
    } finally {
      _depth--;
      // An attempt that threw kept nothing, and is not retried either: the
      // signal that ended it is on its way out past whoever would retry. So
      // discarding here is about the span rather than about the case, which
      // by then is over.
      _context.stopSpan(discard: !kept);
    }
  }

  /// Abandons this test case unless [condition] holds.
  ///
  /// The case becomes invalid rather than failing: it does not count toward
  /// the number of cases the property is asked for, and the engine steers
  /// away from generating more like it. Rejecting a large share of cases is
  /// itself worth knowing about, which is what the engine's FilterTooMuch
  /// health check is for.
  void assume(bool condition) {
    if (!condition) throw const AssumptionFailed();
  }

  /// Records [value] as an observation the engine should steer toward.
  ///
  /// Higher is more interesting. The engine hill-climbs: cases that scored
  /// well are the ones it builds the next cases out of, so a property can say
  /// what "closer to the interesting part of the space" means when the
  /// interesting part is somewhere random generation rarely reaches. The
  /// length of a parsed list, the depth of a tree, the difference between two
  /// balances that should agree -- anything that is a number and that a bug
  /// would make large.
  ///
  /// [label] names the objective and defaults to one, which is what a
  /// property with a single thing to maximise wants. Each label may be
  /// recorded once per case; recording two is two objectives, not two
  /// observations of one.
  ///
  /// Steering happens during [Phase.target], which the engine runs unless
  /// [Settings.phases] leaves it out. Left out, this is a no-op rather than
  /// an error: a property that reports an observation is still a correct
  /// property when nobody is steering by it, and a `phases:` set written to
  /// isolate one part of the loop should not have to be rewritten to keep
  /// compiling.
  ///
  /// [value] has to be finite. There is no ordering that puts NaN anywhere,
  /// and an infinity is a score nothing can beat, so both would make the
  /// hill-climb meaningless rather than merely unhelpful.
  void target(double value, {String label = 'target'}) =>
      _context.target(value, label: label);

  /// Records [message] for the failure report.
  ///
  /// Silent unless this case is the counterexample being reported, so a note
  /// on every case costs nothing on the cases that pass. Recorded as text
  /// when the call is made rather than held as an object, so what the report
  /// shows is what was true at the point the body said it.
  void note(Object? message) => _notes.add('$message');
}
