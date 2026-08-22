part of 'generator.dart';

/// The widest range a Dart int covers, which is what a missing bound means.
///
/// Written in hexadecimal because the decimal form of the minimum is not a
/// Dart integer literal: the lexer reads the digits before the sign, and they
/// are one past the maximum.
const int _minInt = -0x8000000000000000;
const int _maxInt = 0x7fffffffffffffff;

/// Generates integers between [min] and [max] inclusive.
///
/// A bound left out is as wide as the type goes, following the convention the
/// sibling frontends share: an unconstrained integer is any integer, not a
/// small one. Values shrink toward zero, and toward whichever bound is nearer
/// zero when zero is out of range.
Generator<int> integers({int? min, int? max}) {
  final low = min ?? _minInt;
  final high = max ?? _maxInt;
  // Refused here rather than at the first draw: an inverted range is a
  // mistake in the test, and the useful place to report it is where it was
  // written, not on whichever case happens to reach it.
  if (low > high) {
    throw ArgumentError.value(min, 'min', 'exceeds max ($high)');
  }
  return _IntegerGenerator(low, high);
}

/// The engine's integer draw, with its bounds fixed.
final class _IntegerGenerator extends Generator<int> {
  const _IntegerGenerator(this._min, this._max);

  final int _min;
  final int _max;

  @override
  int generate(TestCase testCase) =>
      testCase.context.drawInteger(min: _min, max: _max);
}

/// Generates [value] and nothing else.
///
/// Draws nothing, so it costs no choices and there is nothing to shrink: a
/// constant among generated values, which is how a fixed part of a compound
/// value is written.
Generator<T> just<T>(T value) => _JustGenerator<T>(value);

/// The generator of a value that was never drawn.
final class _JustGenerator<T> extends Generator<T> {
  const _JustGenerator(this._value);

  final T _value;

  @override
  T generate(TestCase testCase) => _value;
}

/// Generates values picked from [values].
///
/// The list is taken as it stands, so changing it afterwards does not change
/// the generator. Values shrink toward the front of the list, which is worth
/// knowing when writing one: put the ordinary case first and the exotic ones
/// after it, and a counterexample will say which of them it needed.
Generator<T> sampledFrom<T>(List<T> values) {
  if (values.isEmpty) {
    throw ArgumentError.value(
      values,
      'values',
      'is empty, and a generator has to be able to produce something',
    );
  }
  return _SampledGenerator<T>(List<T>.of(values));
}

/// One of a fixed list of values, chosen by a drawn index.
final class _SampledGenerator<T> extends Generator<T> {
  const _SampledGenerator(this._values);

  final List<T> _values;

  @override
  T generate(TestCase testCase) => testCase.span(SpanLabel.sampledFrom, () {
    final index = testCase.context.drawInteger(min: 0, max: _values.length - 1);
    return _values[index];
  });
}

/// Generates values from whichever of [options] each case picks.
///
/// The options are weighted equally. A counterexample shrinks toward the
/// first of them, so an `oneOf` reads best with its simplest option first:
/// the report then tells you whether the bug needed the complicated case or
/// merely tolerated it.
Generator<T> oneOf<T>(List<Generator<T>> options) {
  if (options.isEmpty) {
    throw ArgumentError.value(
      options,
      'options',
      'is empty, and a generator has to be able to produce something',
    );
  }
  return _OneOfGenerator<T>(List<Generator<T>>.of(options));
}

/// One of several generators, chosen by a drawn index.
final class _OneOfGenerator<T> extends Generator<T> {
  const _OneOfGenerator(this._options);

  final List<Generator<T>> _options;

  @override
  T generate(TestCase testCase) => testCase.span(SpanLabel.oneOf, () {
    final index = testCase.context.drawInteger(
      min: 0,
      max: _options.length - 1,
    );
    // Inside the span the index was drawn in, so the shrinker can move the
    // choice and what it produced together: a branch simplified toward the
    // first one takes its draws with it.
    return _options[index].generate(testCase);
  });
}

/// Generates values from [value], or null.
///
/// The one place Dart's own types say exactly what the family means by
/// optional: what comes back is a `T?`, not a wrapper. Shrinks toward null,
/// so a property that fails on both a value and on null reports null.
Generator<T?> optional<T>(Generator<T> value) => _OptionalGenerator<T>(value);

/// A value or its absence, chosen by a drawn index.
final class _OptionalGenerator<T> extends Generator<T?> {
  const _OptionalGenerator(this._value);

  final Generator<T> _value;

  @override
  T? generate(TestCase testCase) => testCase.span(SpanLabel.optional, () {
    // Null is index zero because that is the direction indices shrink in,
    // and null is the simpler of the two answers.
    if (testCase.context.drawInteger(min: 0, max: 1) == 0) return null;
    return _value.generate(testCase);
  });
}

/// Generates pairs of what [first] and [second] generate.
///
/// A record rather than a class, so the parts keep their types and are read
/// out positionally: `final (name, age) = tc.draw(tuple2(names, ages));`.
/// Past four parts, `composite` reads better than a longer ladder of these.
Generator<(A, B)> tuple2<A, B>(Generator<A> first, Generator<B> second) =>
    _Tuple2Generator<A, B>(first, second);

/// Generates triples of what [first], [second] and [third] generate.
Generator<(A, B, C)> tuple3<A, B, C>(
  Generator<A> first,
  Generator<B> second,
  Generator<C> third,
) => _Tuple3Generator<A, B, C>(first, second, third);

/// Generates quadruples of what [first] to [fourth] generate.
Generator<(A, B, C, D)> tuple4<A, B, C, D>(
  Generator<A> first,
  Generator<B> second,
  Generator<C> third,
  Generator<D> fourth,
) => _Tuple4Generator<A, B, C, D>(first, second, third, fourth);

/// Two generators drawn in order, as one value.
///
/// The parts are drawn into locals rather than straight into the record, so
/// that the order they are drawn in is the order they are written in and
/// stays that way. Every draw is a position in the choice sequence, and a
/// case only replays if those positions mean the same thing twice.
final class _Tuple2Generator<A, B> extends Generator<(A, B)> {
  const _Tuple2Generator(this._first, this._second);

  final Generator<A> _first;
  final Generator<B> _second;

  @override
  (A, B) generate(TestCase testCase) => testCase.span(SpanLabel.tuple, () {
    final first = _first.generate(testCase);
    final second = _second.generate(testCase);
    return (first, second);
  });
}

/// Three generators drawn in order, as one value.
final class _Tuple3Generator<A, B, C> extends Generator<(A, B, C)> {
  const _Tuple3Generator(this._first, this._second, this._third);

  final Generator<A> _first;
  final Generator<B> _second;
  final Generator<C> _third;

  @override
  (A, B, C) generate(TestCase testCase) => testCase.span(SpanLabel.tuple, () {
    final first = _first.generate(testCase);
    final second = _second.generate(testCase);
    final third = _third.generate(testCase);
    return (first, second, third);
  });
}

/// Four generators drawn in order, as one value.
final class _Tuple4Generator<A, B, C, D> extends Generator<(A, B, C, D)> {
  const _Tuple4Generator(this._first, this._second, this._third, this._fourth);

  final Generator<A> _first;
  final Generator<B> _second;
  final Generator<C> _third;
  final Generator<D> _fourth;

  @override
  (A, B, C, D) generate(TestCase testCase) =>
      testCase.span(SpanLabel.tuple, () {
        final first = _first.generate(testCase);
        final second = _second.generate(testCase);
        final third = _third.generate(testCase);
        final fourth = _fourth.generate(testCase);
        return (first, second, third, fourth);
      });
}

/// Generates true with probability [probability], false otherwise.
///
/// Shrinks toward false. A weighted boolean rather than a separate weighted
/// variant, because the engine takes the probability on the draw and a
/// generator that hid it would only be a generator with one number missing.
Generator<bool> booleans({double probability = 0.5}) {
  if (probability.isNaN || probability < 0 || probability > 1) {
    throw RangeError.value(probability, 'probability', 'must be in 0..1');
  }
  return _BooleanGenerator(probability);
}

/// The engine's boolean draw, with its probability fixed.
final class _BooleanGenerator extends Generator<bool> {
  const _BooleanGenerator(this._probability);

  final double _probability;

  @override
  bool generate(TestCase testCase) =>
      testCase.context.drawBoolean(probability: _probability);
}

/// Generates doubles between [min] and [max].
///
/// The bounds are inclusive unless [excludeMin] or [excludeMax] says
/// otherwise, and default to the infinities, which is this library's way of
/// saying unbounded.
///
/// [allowNan] and [allowInfinity] left out follow Hypothesis, whose rule is
/// that a bound you did not give cannot be violated: NaN comes up only when
/// both ends are open, since NaN compares false against every bound and would
/// otherwise walk through one; an infinity comes up only on an end that is
/// open, since a closed end already excludes it. Set either explicitly to
/// override that -- `allowNan: false` on an unbounded generator is the usual
/// one, for code that has no answer for NaN and no obligation to.
///
/// Values shrink toward zero, and simple values -- integers, then halves --
/// are preferred over ones with long mantissas, so a counterexample tends to
/// read as a number rather than as noise.
Generator<double> doubles({
  double min = double.negativeInfinity,
  double max = double.infinity,
  bool? allowNan,
  bool? allowInfinity,
  bool excludeMin = false,
  bool excludeMax = false,
}) {
  // NaN is refused as a bound before the comparison below, which it would
  // pass: every comparison against NaN is false, so an inverted range with a
  // NaN in it would look like a range in order.
  if (min.isNaN) throw ArgumentError.value(min, 'min', 'is not a number');
  if (max.isNaN) throw ArgumentError.value(max, 'max', 'is not a number');
  if (min > max) {
    throw ArgumentError.value(min, 'min', 'exceeds max ($max)');
  }
  final lowOpen = min == double.negativeInfinity;
  final highOpen = max == double.infinity;
  return _DoubleGenerator(
    min: min,
    max: max,
    allowNan: allowNan ?? (lowOpen && highOpen),
    allowInfinity: allowInfinity ?? (lowOpen || highOpen),
    excludeMin: excludeMin,
    excludeMax: excludeMax,
  );
}

/// The engine's float draw at double width, with its constraints fixed.
final class _DoubleGenerator extends Generator<double> {
  const _DoubleGenerator({
    required this.min,
    required this.max,
    required this.allowNan,
    required this.allowInfinity,
    required this.excludeMin,
    required this.excludeMax,
  });

  final double min;
  final double max;
  final bool allowNan;
  final bool allowInfinity;
  final bool excludeMin;
  final bool excludeMax;

  @override
  double generate(TestCase testCase) => testCase.context.drawFloat(
    min: min,
    max: max,
    allowNan: allowNan,
    allowInfinity: allowInfinity,
    excludeMin: excludeMin,
    excludeMax: excludeMax,
  );
}

/// How wide an unbounded [bigIntegers] reaches.
///
/// Two to the 127th, so an unbounded big integer is wider than any fixed-width
/// integer a program is likely to hold and still a finite range the engine can
/// distribute over. The sibling frontends land in the same place: an
/// unbounded big integer means "wide enough that the width is not the thing
/// under test", not "arbitrarily large".
final BigInt _bigBound = BigInt.one << 127;

/// Generates integers of any width between [min] and [max] inclusive.
///
/// For values past what a Dart int holds. Within that range [integers] says
/// the same thing more cheaply, and the engine takes the cheaper path anyway
/// when both bounds fit.
///
/// A bound left out is ±2^127. Values shrink toward zero, as [integers] does.
Generator<BigInt> bigIntegers({BigInt? min, BigInt? max}) {
  final low = min ?? -_bigBound;
  final high = max ?? _bigBound;
  if (low > high) {
    throw ArgumentError.value(min, 'min', 'exceeds max ($high)');
  }
  return _BigIntegerGenerator(low, high);
}

/// The engine's wide-integer draw, with its bounds fixed.
final class _BigIntegerGenerator extends Generator<BigInt> {
  const _BigIntegerGenerator(this._min, this._max);

  final BigInt _min;
  final BigInt _max;

  @override
  BigInt generate(TestCase testCase) =>
      testCase.context.drawBigInteger(min: _min, max: _max);
}

/// Generates durations between [min] and [max] inclusive.
///
/// Drawn as a whole number of microseconds, which is what a Dart [Duration]
/// is. A bound left out is as wide as that representation goes in that
/// direction, so an unconstrained duration is any duration -- including a
/// negative one, which [Duration] allows and which a program that subtracts
/// two timestamps will eventually see. `min: Duration.zero` is how to say
/// otherwise.
///
/// Values shrink toward zero.
Generator<Duration> durations({Duration? min, Duration? max}) {
  final low = min ?? const Duration(microseconds: _minInt);
  final high = max ?? const Duration(microseconds: _maxInt);
  if (low > high) {
    throw ArgumentError.value(min, 'min', 'exceeds max ($high)');
  }
  return _DurationGenerator(low.inMicroseconds, high.inMicroseconds);
}

/// A span of time, drawn as the microseconds it is made of.
final class _DurationGenerator extends Generator<Duration> {
  const _DurationGenerator(this._min, this._max);

  final int _min;
  final int _max;

  @override
  Duration generate(TestCase testCase) => Duration(
    microseconds: testCase.context.drawInteger(min: _min, max: _max),
  );
}
