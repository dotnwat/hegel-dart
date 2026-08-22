/// The handle a property body draws through, and the seam it draws from.
library;

import 'package:meta/meta.dart';

import '../libhegel/errors.dart';
import '../libhegel/span.dart';
import '../libhegel/test_case.dart' as engine;
import 'generator.dart';

/// One value the body drew, as the report will show it.
///
/// The name is the one the body gave the draw, or null when it gave none, in
/// which case the report falls back to the draw's position.
@internal
typedef Drawn = ({String? name, Object? value});

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

  /// Opens a span grouping the draws made until the matching [stopSpan].
  void startSpan(SpanLabel label);

  /// Closes the most recently opened span.
  void stopSpan();
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
  void startSpan(SpanLabel label) => testCase.startSpan(label);

  @override
  void stopSpan() => testCase.stopSpan();
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

  /// Records [message] for the failure report.
  ///
  /// Silent unless this case is the counterexample being reported, so a note
  /// on every case costs nothing on the cases that pass. Recorded as text
  /// when the call is made rather than held as an object, so what the report
  /// shows is what was true at the point the body said it.
  void note(Object? message) => _notes.add('$message');
}
