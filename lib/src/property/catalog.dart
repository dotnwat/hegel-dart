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
/// open, since a closed end already excludes it.
///
/// Either may be turned *off* -- `allowNan: false` on an unbounded generator
/// is the usual one, for code that has no answer for NaN and no obligation to
/// have one. Turning either on past what the bounds allow is refused rather
/// than attempted, because the engine refuses it too: there is no way to draw
/// a NaN that respects a bound, or an infinity that respects two, so
/// `doubles(min: 0, max: 1, allowNan: true)` describes a generator with
/// nothing to generate.
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
  // compareTo rather than >, which reads -0.0 and 0.0 as equal. They are the
  // same number and not the same bound: the engine orders them apart, so
  // `min: 0.0, max: -0.0` is an inverted range that > would wave through and
  // the engine would meet as an internal error.
  if (min.compareTo(max) > 0) {
    throw ArgumentError.value(min, 'min', 'exceeds max ($max)');
  }
  if (min == max && (excludeMin || excludeMax)) {
    throw ArgumentError.value(
      min,
      'min',
      'is also max ($max), and excluding either leaves nothing to draw',
    );
  }
  final lowOpen = min == double.negativeInfinity;
  final highOpen = max == double.infinity;
  if (allowNan ?? false) {
    // Only fully unbounded, because a NaN is outside every bound: the engine
    // says "Cannot have allow_nan=true with min_value or max_value", and it
    // says it on every case rather than here.
    if (!lowOpen || !highOpen) {
      throw ArgumentError.value(
        allowNan,
        'allowNan',
        'needs both bounds open, since no NaN is inside a bound',
      );
    }
  }
  if ((allowInfinity ?? false) && !lowOpen && !highOpen) {
    throw ArgumentError.value(
      allowInfinity,
      'allowInfinity',
      'needs an open bound for an infinity to be inside',
    );
  }
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

/// A generator whose values the engine's string machinery makes.
///
/// One native generator per instance, built on the first draw and kept for
/// the life of the process. Building is expensive -- a regex to compile, a
/// Unicode table to walk -- and the ABI will only take it back once every
/// draw using it has finished, which is a moment an API of value-like
/// generators never reaches. So it is never taken back, and the leak tracker
/// is told so rather than left to report it. The cost is bounded by how many
/// string generators a program writes, which is a number of lines of source,
/// not a number of test cases.
///
/// One consequence of building on the first draw rather than at
/// construction: a specification the engine refuses -- an unknown codec, a
/// domain length with no room for a TLD -- is refused on that first draw,
/// inside a test case, rather than on the line that wrote it. The engine's
/// own message comes through, so what is wrong is legible; where it is wrong
/// is not, and that is the price of not opening a session to build a
/// generator nobody may draw from.
abstract base class _NativeStringGenerator extends Generator<String> {
  _NativeStringGenerator();

  engine.StringGenerator? _native;

  /// Whether this generator has found the native generator behind it.
  ///
  /// Both halves of the cache are worth a test: that nothing is built until a
  /// draw asks, and that nothing is built twice.
  @visibleForTesting
  bool get isNativeBuilt => _native != null;

  /// Everything this generator asks the engine for, encoded.
  ///
  /// Two generators with the same specification want the same native
  /// generator, whether or not they are the same object.
  String get specification;

  /// Builds the native generator this one draws through.
  engine.StringGenerator buildNative();

  engine.StringGenerator get _nativeGenerator =>
      _native ??= _nativeGenerators.putIfAbsent(specification, () {
        final made = buildNative();
        assert(exemptHandle(made));
        return made;
      });

  @override
  String generate(TestCase testCase) =>
      testCase.context.drawString(_nativeGenerator);
}

/// Every native string generator built so far, by what it was asked for.
///
/// Keyed by specification rather than held per generator object, because the
/// obvious way to write a property puts the generator inside the body:
///
/// ```dart
/// property('a name survives a round trip', (tc) {
///   final name = tc.draw(text(minLength: 1), name: 'name');
///   ...
/// });
/// ```
///
/// That builds a fresh `text(...)` for every test case, and per-object caching
/// would build -- and never free -- a native generator for every one of them.
/// A hundred cases, a hundred compiled alphabets. Keyed this way the same
/// property builds one, and the cost is what it was always meant to be:
/// bounded by the number of distinct string generators a program describes,
/// which is a property of the source rather than of how long a run goes on.
final Map<String, engine.StringGenerator> _nativeGenerators =
    <String, engine.StringGenerator>{};

/// How many native string generators have been built.
///
/// The cache is process-wide and its entries are never released, so what a
/// test can check is that a run added one of these rather than a hundred.
@visibleForTesting
int get nativeStringGeneratorCount => _nativeGenerators.length;

/// [parts] encoded so that no two different lists of parts encode alike.
///
/// Every free-form part here can hold any character at all -- a regex, an
/// alphabet, a Unicode category name -- so the parts are length-prefixed
/// rather than joined with a separator that one of them may contain. Two
/// generators sharing a cache entry they should not share would be a
/// generator quietly drawing from someone else's alphabet, which is the kind
/// of bug that shows up as a shrink that will not reproduce.
String _key(List<Object?> parts) {
  final out = StringBuffer();
  for (final part in parts) {
    switch (part) {
      case null:
        out.write('~');
      case final List<String> values:
        out
          ..write('[')
          ..write(_key(values))
          ..write(']');
      case _:
        final text = '$part';
        out
          ..write(text.length)
          ..write(':')
          ..write(text);
    }
  }
  return out.toString();
}

/// Generates strings over an alphabet.
///
/// The type [text] and [characters] return, named separately because
/// [fromRegex] takes one as the alphabet its padding is drawn from.
final class TextGenerator extends _NativeStringGenerator {
  TextGenerator._(this._spec);

  final _TextSpec _spec;

  @override
  String get specification => _key(<Object?>[
    'text',
    _spec.minLength,
    _spec.maxLength,
    _spec.codec,
    _spec.minCodepoint,
    _spec.maxCodepoint,
    _spec.categories,
    _spec.excludeCategories,
    _spec.includeCharacters,
    _spec.excludeCharacters,
  ]);

  @override
  engine.StringGenerator buildNative() => engine.StringGenerator.text(
    minSize: _spec.minLength,
    maxSize: _spec.maxLength,
    codec: _spec.codec,
    // The engine takes a range rather than a nullable one, and its widest
    // range is what "no restriction" means here.
    minCodepoint: _spec.minCodepoint ?? 0,
    maxCodepoint: _spec.maxCodepoint ?? 0xFFFFFFFF,
    categories: _spec.categories,
    excludeCategories: _spec.excludeCategories,
    includeCharacters: _spec.includeCharacters,
    excludeCharacters: _spec.excludeCharacters,
    session: Libhegel.instance,
  );
}

/// Everything [text] was asked for, kept until the first draw needs it.
typedef _TextSpec = ({
  int minLength,
  int? maxLength,
  String? codec,
  int? minCodepoint,
  int? maxCodepoint,
  List<String>? categories,
  List<String>? excludeCategories,
  String? includeCharacters,
  String? excludeCharacters,
});

/// Generates strings of [minLength] to [maxLength] characters.
///
/// The bounds count **characters**, not what `String.length` counts: a string
/// of five characters drawn from the whole of Unicode can have a `length` of
/// ten, because Dart measures a string in UTF-16 code units and an emoji is
/// two of them. `runes.length` is the number these bounds are about. A null
/// [maxLength] leaves the length to the engine, which keeps it small on its
/// own.
///
/// The alphabet is everything by default, and narrows by any combination of:
/// [codec] (`ascii`, `latin-1`, `utf-8`) for the starting range,
/// [minCodepoint] and [maxCodepoint] for a range of code points, [categories]
/// and [excludeCategories] for Unicode general categories (`Lu`, `Nd`, and so
/// on), and [includeCharacters] and [excludeCharacters] for named characters.
/// A null [categories] means no restriction; an empty one means an alphabet
/// with nothing in it, which is how a generator of exactly the characters in
/// [includeCharacters] is written.
///
/// Wide by default on purpose. A string generator restricted to ASCII finds
/// ASCII bugs; the family's position, and this library's, is that text is
/// Unicode and a program that says otherwise should have to say so.
TextGenerator text({
  int minLength = 0,
  int? maxLength,
  String? codec,
  int? minCodepoint,
  int? maxCodepoint,
  List<String>? categories,
  List<String>? excludeCategories,
  String? includeCharacters,
  String? excludeCharacters,
}) {
  _checkLengths(minLength, maxLength);
  return TextGenerator._((
    minLength: minLength,
    maxLength: maxLength,
    codec: codec,
    minCodepoint: minCodepoint,
    maxCodepoint: maxCodepoint,
    // Taken as they stand, like the list [sampledFrom] is given. A generator
    // that went on watching the caller's list would answer to a change made
    // after it was written -- and only until its first draw, after which the
    // native generator behind it is already built and the change is ignored.
    // A generator that means two things depending on when it is asked is one
    // whose counterexamples do not reproduce.
    categories: _copyOf(categories),
    excludeCategories: _copyOf(excludeCategories),
    includeCharacters: includeCharacters,
    excludeCharacters: excludeCharacters,
  ));
}

/// [values] as this library's own list, or null.
List<String>? _copyOf(List<String>? values) =>
    values == null ? null : List<String>.of(values);

/// Generates single characters, drawn the way [text] draws them.
///
/// One character, so one code point -- which is a Dart string of one or two
/// code units, since Dart has no character type and a `String` is what a
/// character is. Takes the same alphabet arguments as [text] and none of its
/// lengths.
TextGenerator characters({
  String? codec,
  int? minCodepoint,
  int? maxCodepoint,
  List<String>? categories,
  List<String>? excludeCategories,
  String? includeCharacters,
  String? excludeCharacters,
}) => TextGenerator._((
  minLength: 1,
  maxLength: 1,
  codec: codec,
  minCodepoint: minCodepoint,
  maxCodepoint: maxCodepoint,
  categories: _copyOf(categories),
  excludeCategories: _copyOf(excludeCategories),
  includeCharacters: includeCharacters,
  excludeCharacters: excludeCharacters,
));

/// Rejects lengths the engine would refuse, where they were written.
void _checkLengths(int minLength, int? maxLength) {
  if (minLength < 0) {
    throw RangeError.value(minLength, 'minLength', 'must not be negative');
  }
  if (maxLength != null && minLength > maxLength) {
    throw ArgumentError.value(
      minLength,
      'minLength',
      'exceeds maxLength ($maxLength)',
    );
  }
}

/// Generates strings matching [pattern], in Python `re` syntax.
///
/// Python's syntax rather than Dart's, because the engine is what matches it.
/// The two agree on everything ordinary and differ at the edges -- `\d` is
/// Unicode-aware in Python by default, and the named-group spelling is
/// `(?P<name>...)` -- so a pattern taken from Dart source is worth a glance
/// before it is trusted here.
///
/// With [fullMatch] the whole string matches the pattern. Without it the
/// match may be padded on either side, and [alphabet] says what that padding
/// is drawn from.
Generator<String> fromRegex(
  String pattern, {
  bool fullMatch = true,
  TextGenerator? alphabet,
}) => _RegexGenerator(pattern, fullMatch, alphabet);

/// Strings matching a pattern the engine compiles.
final class _RegexGenerator extends _NativeStringGenerator {
  _RegexGenerator(this._pattern, this._fullMatch, this._alphabet);

  final String _pattern;
  final bool _fullMatch;
  final TextGenerator? _alphabet;

  @override
  String get specification =>
      _key(<Object?>['regex', _pattern, _fullMatch, _alphabet?.specification]);

  @override
  engine.StringGenerator buildNative() => engine.StringGenerator.regex(
    _pattern,
    fullMatch: _fullMatch,
    // Built through the alphabet's own cache, so an alphabet shared between
    // several patterns is still built once.
    alphabet: _alphabet?._nativeGenerator,
    session: Libhegel.instance,
  );
}

/// Generates email addresses, per RFC 5321 and 5322.
///
/// A draw that would exceed the RFC's length cap rejects its own test case,
/// arriving as the same rejection [TestCase.assume] raises. That is rare
/// enough to ignore and regular enough not to be a surprise.
Generator<String> emails() => _NamedStringGenerator(<Object?>[
  'email',
], (Libhegel session) => engine.StringGenerator.email(session: session));

/// Generates http and https URLs, per RFC 3986.
Generator<String> urls() => _NamedStringGenerator(<Object?>[
  'url',
], (Libhegel session) => engine.StringGenerator.url(session: session));

/// Generates fully-qualified domain names of at most [maxLength] characters.
Generator<String> domains({int maxLength = 255}) {
  if (maxLength < 0) {
    throw RangeError.value(maxLength, 'maxLength', 'must not be negative');
  }
  return _NamedStringGenerator(
    <Object?>['domain', maxLength],
    (Libhegel session) =>
        engine.StringGenerator.domain(maxLength: maxLength, session: session),
  );
}

/// One of the engine's ready-made string shapes.
final class _NamedStringGenerator extends _NativeStringGenerator {
  _NamedStringGenerator(this._parts, this._build);

  /// What this shape is, and whatever narrows it.
  final List<Object?> _parts;

  final engine.StringGenerator Function(Libhegel session) _build;

  @override
  String get specification => _key(_parts);

  @override
  engine.StringGenerator buildNative() => _build(Libhegel.instance);
}

/// Generates byte strings of [minLength] to [maxLength] bytes.
///
/// Bytes rather than "binary", which is what the rest of the family calls
/// these: Dart's own vocabulary is `BytesBuilder`, `utf8.encode`, and a
/// `Uint8List` full of them. A null [maxLength] leaves the length to the
/// engine, which keeps it small on its own.
///
/// Values shrink toward the empty string, and toward zero bytes within it.
Generator<Uint8List> bytes({int minLength = 0, int? maxLength}) {
  _checkLengths(minLength, maxLength);
  return _BytesGenerator(minLength, maxLength);
}

/// The engine's byte draw, with its lengths fixed.
final class _BytesGenerator extends Generator<Uint8List> {
  const _BytesGenerator(this._minLength, this._maxLength);

  final int _minLength;
  final int? _maxLength;

  @override
  Uint8List generate(TestCase testCase) =>
      testCase.context.drawBytes(minLength: _minLength, maxLength: _maxLength);
}

/// Generates dates between [min] and [max] inclusive.
///
/// What comes back is a UTC [DateTime] at midnight, since a date is not a
/// moment and Dart has no type that says so. The bounds are read the same
/// way: the calendar date a [DateTime] displays, whatever zone it carries,
/// because a bound of "the first of March" means that date and not an instant
/// that lands on it somewhere.
///
/// The default range is the engine's, years 1 through 9999, which is also as
/// wide as a sensible [DateTime] goes. Values shrink toward 2000-01-01, or
/// toward the nearer bound when that is out of range.
Generator<DateTime> dates({DateTime? min, DateTime? max}) {
  final low = min == null ? _earliestDate : _dateOf(min);
  final high = max == null ? _latestDate : _dateOf(max);
  if (_dateValue(low) > _dateValue(high)) {
    throw ArgumentError.value(min, 'min', 'exceeds max ($max)');
  }
  return _DateGenerator(low, high);
}

const engine.HegelDate _earliestDate = (year: 1, month: 1, day: 1);
const engine.HegelDate _latestDate = (year: 9999, month: 12, day: 31);

engine.HegelDate _dateOf(DateTime value) =>
    (year: value.year, month: value.month, day: value.day);

/// A date as one number, so two of them can be compared.
int _dateValue(engine.HegelDate date) =>
    (date.year * 100 + date.month) * 100 + date.day;

/// The engine's date draw, rendered as a UTC midnight.
final class _DateGenerator extends Generator<DateTime> {
  const _DateGenerator(this._min, this._max);

  final engine.HegelDate _min;
  final engine.HegelDate _max;

  @override
  DateTime generate(TestCase testCase) {
    final drawn = testCase.context.drawDate(min: _min, max: _max);
    return DateTime.utc(drawn.year, drawn.month, drawn.day);
  }
}

/// Generates times of day between [min] and [max] inclusive.
///
/// A time of day as a [Duration] since midnight, which is what Dart has:
/// there is no time-of-day type in the core libraries, and Flutter's belongs
/// to Flutter. So the bounds are durations too, and a bound outside a day is
/// refused rather than wrapped.
///
/// Values shrink toward midnight.
Generator<Duration> times({Duration? min, Duration? max}) {
  final low = min ?? Duration.zero;
  final high = max ?? _endOfDay;
  _checkTimeOfDay(low, 'min');
  _checkTimeOfDay(high, 'max');
  if (low > high) {
    throw ArgumentError.value(min, 'min', 'exceeds max ($high)');
  }
  return _TimeGenerator(_timeOf(low), _timeOf(high));
}

const Duration _endOfDay = Duration(
  hours: 23,
  minutes: 59,
  seconds: 59,
  microseconds: 999999,
);

void _checkTimeOfDay(Duration value, String name) {
  if (value < Duration.zero || value > _endOfDay) {
    throw ArgumentError.value(value, name, 'is not a time of day');
  }
}

engine.HegelTime _timeOf(Duration value) => (
  hour: value.inHours,
  minute: value.inMinutes % 60,
  second: value.inSeconds % 60,
  microsecond: value.inMicroseconds % 1000000,
);

/// The engine's time draw, rendered as time since midnight.
final class _TimeGenerator extends Generator<Duration> {
  const _TimeGenerator(this._min, this._max);

  final engine.HegelTime _min;
  final engine.HegelTime _max;

  @override
  Duration generate(TestCase testCase) {
    final drawn = testCase.context.drawTime(min: _min, max: _max);
    return Duration(
      hours: drawn.hour,
      minutes: drawn.minute,
      seconds: drawn.second,
      microseconds: drawn.microsecond,
    );
  }
}

/// Generates dates and times between [min] and [max] inclusive.
///
/// UTC [DateTime]s, to microsecond precision, which both sides agree on. They
/// carry no zone in any meaningful sense -- the engine draws a naive date and
/// time, and UTC is how Dart says "no zone applied". A generator of instants
/// in a particular zone is this one mapped into it.
///
/// The bounds are read the same way [dates] reads them: as the wall clock a
/// [DateTime] displays, not as the instant it stands for. A local bound and a
/// UTC one that show the same numbers mean the same bound here, and two that
/// show different numbers are different bounds even where they name the same
/// instant. Anything else would put a generator's meaning at the mercy of the
/// machine's time zone, which is not a thing a counterexample should depend
/// on.
///
/// Values shrink toward 2000-01-01 midnight.
Generator<DateTime> dateTimes({DateTime? min, DateTime? max}) {
  final low = min == null
      ? (date: _earliestDate, time: _startOfDay)
      : _dateTimeOf(min);
  final high = max == null
      ? (date: _latestDate, time: _lastMicrosecond)
      : _dateTimeOf(max);
  // The encoded pair rather than the arguments, and whether or not both were
  // given. What the engine is handed is the wall clock, so that is what has
  // to be in order: comparing the instants instead lets a UTC minimum and a
  // local maximum pass here and invert there. And a single bound is still a
  // bound -- a minimum past year 9999 inverts the range against the default
  // maximum, with no second argument to compare it to.
  if (_dateTimeValue(low).compareTo(_dateTimeValue(high)) > 0) {
    throw ArgumentError.value(min, 'min', 'exceeds max ($max)');
  }
  return _DateTimeGenerator(low, high);
}

/// A date and time as one comparable string, zero-padded so that it orders.
String _dateTimeValue(engine.HegelDateTime value) =>
    '${_dateValue(value.date).toString().padLeft(9, '0')}'
    '${value.time.hour.toString().padLeft(2, '0')}'
    '${value.time.minute.toString().padLeft(2, '0')}'
    '${value.time.second.toString().padLeft(2, '0')}'
    '${value.time.microsecond.toString().padLeft(6, '0')}';

const engine.HegelTime _startOfDay = (
  hour: 0,
  minute: 0,
  second: 0,
  microsecond: 0,
);
const engine.HegelTime _lastMicrosecond = (
  hour: 23,
  minute: 59,
  second: 59,
  microsecond: 999999,
);

engine.HegelDateTime _dateTimeOf(DateTime value) => (
  date: _dateOf(value),
  time: (
    hour: value.hour,
    minute: value.minute,
    second: value.second,
    microsecond: value.millisecond * 1000 + value.microsecond,
  ),
);

/// The engine's date-and-time draw, rendered as a UTC [DateTime].
final class _DateTimeGenerator extends Generator<DateTime> {
  const _DateTimeGenerator(this._min, this._max);

  final engine.HegelDateTime _min;
  final engine.HegelDateTime _max;

  @override
  DateTime generate(TestCase testCase) {
    final drawn = testCase.context.drawDateTime(min: _min, max: _max);
    return DateTime.utc(
      drawn.date.year,
      drawn.date.month,
      drawn.date.day,
      drawn.time.hour,
      drawn.time.minute,
      drawn.time.second,
      0,
      drawn.time.microsecond,
    );
  }
}

/// Generates UUIDs in the canonical 8-4-4-4-12 form.
///
/// A string, because the SDK has no UUID type and the canonical text is what
/// gets stored, logged and compared. With [version] set, the version and
/// variant bits are what RFC 4122 says they are for that version; without it
/// all 128 bits are drawn, which is how a program that parses UUIDs it did
/// not make gets tested against ones it did not expect.
Generator<String> uuids({int? version}) {
  if (version != null && (version < 0 || version > 15)) {
    throw RangeError.value(version, 'version', 'must be in 0..15');
  }
  return _UuidGenerator(version);
}

/// The engine's UUID draw, formatted.
final class _UuidGenerator extends Generator<String> {
  const _UuidGenerator(this._version);

  final int? _version;

  @override
  String generate(TestCase testCase) =>
      _hyphenate(testCase.context.drawUuid(version: _version));

  /// The sixteen bytes as 8-4-4-4-12 hexadecimal.
  static String _hyphenate(Uint8List value) {
    final digits = StringBuffer();
    for (final (int index, int byte) in value.indexed) {
      if (index == 4 || index == 6 || index == 8 || index == 10) {
        digits.write('-');
      }
      digits.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return digits.toString();
  }
}

/// Generates IP addresses of [type], or of either kind when none is given.
///
/// Both kinds by default, because a program that has only ever seen IPv4 is
/// exactly the one worth pointing an IPv6 address at.
Generator<InternetAddress> ipAddresses({InternetAddressType? type}) =>
    switch (type) {
      InternetAddressType.IPv4 => const _AddressGenerator(4),
      InternetAddressType.IPv6 => const _AddressGenerator(6),
      // A Unix socket path is an InternetAddress in Dart's types and is not
      // an address the engine draws. Refused rather than quietly answered
      // with an internet address, which is not what was asked for.
      InternetAddressType.unix => throw ArgumentError.value(
        type,
        'type',
        'is a socket path rather than an address the engine can draw',
      ),
      // Null or `any`: the ONE_OF shape, so the choice shrinks toward the
      // simpler family the way any other choice between generators does.
      _ => oneOf(<Generator<InternetAddress>>[
        const _AddressGenerator(4),
        const _AddressGenerator(6),
      ]),
    };

/// The engine's address draw, of one family.
final class _AddressGenerator extends Generator<InternetAddress> {
  const _AddressGenerator(this._version);

  /// 4 or 6, which is the whole of what an address family is here.
  final int _version;

  @override
  InternetAddress generate(TestCase testCase) => InternetAddress.fromRawAddress(
    _version == 4 ? testCase.context.drawIpv4() : testCase.context.drawIpv6(),
  );
}

/// Generates lists of what [elements] generates.
///
/// The engine decides how long each list is, within [minLength] and
/// [maxLength]; a null [maxLength] leaves that to the engine, which keeps
/// lists short on its own rather than letting one run away. Length is not
/// drawn up front but decided element by element, which is what lets the
/// shrinker delete an element from the middle of a counterexample rather than
/// only from its end.
///
/// With [unique], no two elements of a list compare equal. Equality is Dart's
/// own, `==` and `hashCode`, so it means for a list of ints what it means for
/// a `Set<int>` -- and for a list of lists it means identity, since Dart's
/// `List` does not define structural equality. An element type that wants
/// structural uniqueness has to say so by implementing `==`.
///
/// Uniqueness is enforced by redrawing rather than by discarding: an element
/// equal to one already in the list is refused, and the engine produces
/// another in its place. A refused element does not count toward the length,
/// so `lists(booleans(), minLength: 3, unique: true)` cannot be satisfied and
/// spends the case trying -- ask for a length the element type can actually
/// fill.
///
/// Values shrink toward the shortest list the bounds allow, and each element
/// toward what its own generator shrinks to.
Generator<List<T>> lists<T>(
  Generator<T> elements, {
  int minLength = 0,
  int? maxLength,
  bool unique = false,
}) {
  _checkLengths(minLength, maxLength);
  return _ListGenerator<T>(elements, minLength, maxLength, unique);
}

/// A sequence of one generator's values, as long as the engine decides.
final class _ListGenerator<T> extends Generator<List<T>> {
  const _ListGenerator(
    this._elements,
    this._minLength,
    this._maxLength,
    this._unique,
  );

  final Generator<T> _elements;
  final int _minLength;
  final int? _maxLength;
  final bool _unique;

  @override
  List<T> generate(TestCase testCase) {
    final values = <T>[];
    final seen = _unique ? <T>{} : null;
    _collect(
      testCase,
      label: SpanLabel.list,
      elementLabel: SpanLabel.listElement,
      minLength: _minLength,
      maxLength: _maxLength,
      why: 'duplicate element',
      take: () {
        final value = _elements.generate(testCase);
        if (seen != null && !seen.add(value)) return false;
        values.add(value);
        return true;
      },
    );
    return values;
  }
}

/// Generates sets of what [elements] generates.
///
/// A [Set] rather than a list that happens not to repeat: what comes back has
/// the type that says so, and the property can use it as one. Uniqueness is
/// Dart's own `==` and `hashCode` -- the same equality the returned set will
/// go on using, which is the point of not inventing another one.
///
/// [minLength] and [maxLength] count distinct elements, since those are the
/// only ones a set holds. A repeat is refused and the engine produces another
/// element in its place, so `sets(booleans(), minLength: 3)` asks for
/// something no set of booleans can be and spends the case discovering it:
/// the bounds have to be ones the element type can fill.
///
/// Iteration order is the order the elements were generated in, [Set] being
/// insertion-ordered in Dart, so a counterexample reads the same way twice.
///
/// Values shrink toward the smallest set the bounds allow.
Generator<Set<T>> sets<T>(
  Generator<T> elements, {
  int minLength = 0,
  int? maxLength,
}) {
  _checkLengths(minLength, maxLength);
  return _SetGenerator<T>(elements, minLength, maxLength);
}

/// A set of one generator's values, as large as the engine decides.
final class _SetGenerator<T> extends Generator<Set<T>> {
  const _SetGenerator(this._elements, this._minLength, this._maxLength);

  final Generator<T> _elements;
  final int _minLength;
  final int? _maxLength;

  @override
  Set<T> generate(TestCase testCase) {
    final values = <T>{};
    _collect(
      testCase,
      label: SpanLabel.set,
      elementLabel: SpanLabel.setElement,
      minLength: _minLength,
      maxLength: _maxLength,
      why: 'duplicate element',
      // `add` answers whether the set took it, which is the same question the
      // collection is asking. There is no separate record of what has been
      // seen, because the set being built is one.
      take: () => values.add(_elements.generate(testCase)),
    );
    return values;
  }
}

/// Generates maps of what [keys] and [values] generate.
///
/// Each entry is one unit: its key and its value are drawn together and
/// shrink together, so a counterexample loses whole entries rather than
/// halves of them.
///
/// Keys are distinct by Dart's `==` and `hashCode`, the equality the returned
/// map will use. A repeated key is refused and the engine produces another
/// entry, so [minLength] and [maxLength] count entries the map actually kept
/// -- and, as with [sets], have to be bounds the key type can fill.
///
/// Iteration order is the order the entries were generated in, Dart's [Map]
/// being insertion-ordered.
///
/// Values shrink toward the smallest map the bounds allow.
Generator<Map<K, V>> maps<K, V>(
  Generator<K> keys,
  Generator<V> values, {
  int minLength = 0,
  int? maxLength,
}) {
  _checkLengths(minLength, maxLength);
  return _MapGenerator<K, V>(keys, values, minLength, maxLength);
}

/// A map of two generators' values, as large as the engine decides.
final class _MapGenerator<K, V> extends Generator<Map<K, V>> {
  const _MapGenerator(
    this._keys,
    this._values,
    this._minLength,
    this._maxLength,
  );

  final Generator<K> _keys;
  final Generator<V> _values;
  final int _minLength;
  final int? _maxLength;

  @override
  Map<K, V> generate(TestCase testCase) {
    final entries = <K, V>{};
    _collect(
      testCase,
      label: SpanLabel.map,
      elementLabel: SpanLabel.mapEntry,
      minLength: _minLength,
      maxLength: _maxLength,
      why: 'duplicate key',
      take: () {
        final key = _keys.generate(testCase);
        // The value is not drawn for a key the map already has. The entry is
        // going to be refused either way, and drawing it would spend choices
        // on a value nothing will ever hold -- choices the shrinker then has
        // to work through. What the entry's span holds therefore depends on
        // its key, which costs nothing: the same choices produce the same key
        // and so the same decision, which is all a replay needs.
        //
        // The one place this package's wire shape differs from the reference
        // interpreter the other frontends follow, which draws both halves and
        // discards the value. Worth knowing at an engine bump: if a map pin
        // in the shrink tests moves and no other pin does, this is the first
        // thing to look at.
        if (entries.containsKey(key)) return false;
        entries[key] = _values.generate(testCase);
        return true;
      },
    );
    return entries;
  }
}

/// Drives one engine-decided sequence, from inside the span it belongs to.
///
/// The shape every collection generator shares, in one place because the
/// three of them agreeing with the engine matters more than any of them
/// reading independently. The collection is started inside [label]'s span, so
/// the length decisions belong to the value the way its elements do; [take]
/// is called once per element the engine offers, inside a span of
/// [elementLabel], and answers whether the element was used. One that was not
/// is refused with [why] *after* its span has closed, the engine's protocol
/// being that a rejection names the last element produced -- and the engine
/// then offers another in its place, so a refusal costs nothing but a turn.
void _collect(
  TestCase testCase, {
  required SpanLabel label,
  required SpanLabel elementLabel,
  required int minLength,
  required int? maxLength,
  required String why,
  required bool Function() take,
}) {
  testCase.span(label, () {
    final collection = testCase.context.startCollection(
      minLength: minLength,
      maxLength: maxLength,
    );
    try {
      while (collection.more()) {
        if (!testCase.span(elementLabel, take)) collection.reject(why);
      }
    } finally {
      // Independent of the test case and the run, so it is released here
      // rather than left to whichever of them ends first.
      collection.dispose();
    }
  });
}
