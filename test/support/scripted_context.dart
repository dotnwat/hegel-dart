/// Draw contexts that answer from a script instead of from the engine.
library;

import 'dart:typed_data';

import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/libhegel/string_generator.dart';
import 'package:hegel/src/libhegel/test_case.dart' as engine;
import 'package:hegel/src/property/test_case.dart';

/// A [DrawContext] with nothing scripted.
///
/// The seam grows a method per engine primitive the catalog reaches, and a
/// fake that spelled every one of them out would be mostly noise -- and would
/// stop compiling each time the catalog reached one more. So the default for
/// every draw is to refuse: a fake overrides the draws its test is about, and
/// a draw it did not expect says so instead of quietly answering zero.
abstract base class FakeDrawContext implements DrawContext {
  /// Records every call made, as text, so a test can pin the order as well as
  /// the count -- a span closed before its body ran would otherwise look
  /// right.
  final List<String> calls = <String>[];

  @override
  int drawInteger({required int min, required int max}) =>
      _unscripted('an integer');

  @override
  BigInt drawBigInteger({required BigInt min, required BigInt max}) =>
      _unscripted('a big integer');

  @override
  bool drawBoolean({required double probability}) => _unscripted('a boolean');

  @override
  double drawFloat({
    required double min,
    required double max,
    required bool allowNan,
    required bool allowInfinity,
    required bool excludeMin,
    required bool excludeMax,
  }) => _unscripted('a float');

  @override
  String drawString(StringGenerator generator) => _unscripted('a string');

  @override
  Uint8List drawBytes({required int minLength, int? maxLength}) =>
      _unscripted('bytes');

  @override
  engine.HegelDate drawDate({
    required engine.HegelDate min,
    required engine.HegelDate max,
  }) => _unscripted('a date');

  @override
  engine.HegelTime drawTime({
    required engine.HegelTime min,
    required engine.HegelTime max,
  }) => _unscripted('a time');

  @override
  engine.HegelDateTime drawDateTime({
    required engine.HegelDateTime min,
    required engine.HegelDateTime max,
  }) => _unscripted('a date and time');

  @override
  Uint8List drawUuid({int? version}) => _unscripted('a uuid');

  @override
  Uint8List drawIpv4() => _unscripted('an ipv4 address');

  @override
  Uint8List drawIpv6() => _unscripted('an ipv6 address');

  // A fake is not aborted: the latch belongs to a real case, and a test that
  // wants one says so by overriding this.
  @override
  bool get isAborted => false;

  @override
  DrawMachine startStateMachine({
    required List<String> ruleNames,
    required List<String> invariantNames,
  }) => _unscripted('a state machine');

  // Recorded rather than refused, like the spans: there is no value to
  // invent, so a fake that has none of these is still a fake that can be
  // asked for one.
  @override
  void target(double value, {required String label}) =>
      calls.add('target $value as $label');

  @override
  DrawCollection startCollection({required int minLength, int? maxLength}) =>
      _unscripted('a collection');

  @override
  void startSpan(SpanLabel label) => calls.add('start ${label.value}');

  @override
  void stopSpan({bool discard = false}) =>
      calls.add(discard ? 'discard' : 'stop');

  Never _unscripted(String what) =>
      throw UnsupportedError('this fake was asked for $what and has none');
}

/// A [DrawContext] that answers from a script and records what it was asked.
///
/// The engine cannot be asked to hand back a particular value at a particular
/// point, which is exactly what pinning the bookkeeping around a draw needs:
/// the third retry of a filter, the branch a choice landed on, the draw that
/// comes after a span was discarded.
final class ScriptedContext extends FakeDrawContext {
  /// Answers draws with the values given, each list in its own order.
  ScriptedContext(
    this.integers, {
    this.booleans = const <bool>[],
    this.floats = const <double>[],
    this.bigIntegers = const <BigInt>[],
    this.more = const <bool>[],
  });

  /// The values [drawInteger] returns, in order.
  final List<int> integers;

  /// The values [drawBoolean] returns, in order.
  final List<bool> booleans;

  /// The values [drawFloat] returns, in order.
  final List<double> floats;

  /// The values [drawBigInteger] returns, in order.
  final List<BigInt> bigIntegers;

  /// The answers [DrawCollection.more] returns, in order.
  ///
  /// One queue for every collection this context hands out, rather than one
  /// per collection: a test that starts two is testing how they interleave,
  /// and a flat script is how that order is written down.
  final List<bool> more;

  int _next = 0;
  int _nextBoolean = 0;
  int _nextFloat = 0;
  int _nextBigInteger = 0;
  int _nextMore = 0;

  @override
  DrawCollection startCollection({required int minLength, int? maxLength}) {
    calls.add('collection $minLength..${maxLength ?? '*'}');
    return _ScriptedCollection(this);
  }

  @override
  int drawInteger({required int min, required int max}) {
    calls.add('draw $min..$max');
    return integers[_next++];
  }

  @override
  BigInt drawBigInteger({required BigInt min, required BigInt max}) {
    calls.add('draw big $min..$max');
    return bigIntegers[_nextBigInteger++];
  }

  @override
  bool drawBoolean({required double probability}) {
    calls.add('draw boolean $probability');
    return booleans[_nextBoolean++];
  }

  // Recorded as the whole constraint rather than as a name, because what the
  // catalog resolves out of an unset allowNan is exactly the thing worth
  // pinning and the only place it is visible.
  @override
  double drawFloat({
    required double min,
    required double max,
    required bool allowNan,
    required bool allowInfinity,
    required bool excludeMin,
    required bool excludeMax,
  }) {
    calls.add(
      'draw float $min..$max nan=$allowNan inf=$allowInfinity '
      'exclude=$excludeMin/$excludeMax',
    );
    return floats[_nextFloat++];
  }
}

/// The collection a [ScriptedContext] hands out.
///
/// Answers [more] from the context's script and records the rest, so a test
/// can pin the protocol -- that the reject came after the element's span
/// closed, that the handle was released -- and not merely the list that came
/// out the other end.
final class _ScriptedCollection implements DrawCollection {
  _ScriptedCollection(this._context);

  final ScriptedContext _context;

  @override
  bool more() {
    final answer = _context.more[_context._nextMore++];
    _context.calls.add('more $answer');
    return answer;
  }

  @override
  void reject(String why) => _context.calls.add('reject $why');

  @override
  void dispose() => _context.calls.add('free');
}
