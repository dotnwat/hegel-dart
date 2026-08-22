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
