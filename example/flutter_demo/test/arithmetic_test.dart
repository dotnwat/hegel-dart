/// Properties over the arithmetic, in plain Dart.
///
///     flutter test test/arithmetic_test.dart
///
/// This is hegel used the way it is normally used: a pure function, a claim
/// about every input, and no interface anywhere. It passes, and it is the
/// reason the demonstration can say that when the calculator shows the wrong
/// answer the mistake is not in the sums.
library;

import 'package:abacus/arithmetic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hegel/hegel.dart';

/// Whole numbers small enough to write out.
Generator<int> operands() => integers(min: 0, max: 99999);

void main() {
  property('a sum of two numbers is their sum', (TestCase testCase) {
    final left = testCase.draw(operands(), name: 'left');
    final right = testCase.draw(operands(), name: 'right');
    expect(evaluate('$left+$right'), left + right);
    expect(evaluate('$left$minusSign$right'), left - right);
    expect(evaluate('$left$timesSign$right'), left * right);
  });

  property('multiplication binds tighter than addition', (TestCase testCase) {
    final a = testCase.draw(operands(), name: 'a');
    final b = testCase.draw(operands(), name: 'b');
    final c = testCase.draw(operands(), name: 'c');
    expect(evaluate('$a+$b$timesSign$c'), a + b * c);
    expect(evaluate('$a$timesSign$b+$c'), a * b + c);
  });

  property('an answer can be read back', (TestCase testCase) {
    final value = testCase.draw(operands(), name: 'value');
    expect(evaluate(formatAnswer(value.toDouble())), value);
  });

  property('nothing the keypad can produce throws', (TestCase testCase) {
    // Every string the buttons can make, in any order, including the ones
    // that are not expressions at all. A calculator has half an expression on
    // screen most of the time; none of them may be an exception.
    final typed = testCase.draw(
      text(
        maxLength: 12,
        includeCharacters: '0123456789.$operators',
        categories: <String>[],
      ),
      name: 'typed',
    );
    expect(() => evaluate(typed), returnsNormally);
  });

  property('an expression ending in an operator is not one', (
    TestCase testCase,
  ) {
    final left = testCase.draw(operands(), name: 'left');
    final operator = testCase.draw(
      sampledFrom(operators.split('')),
      name: 'operator',
    );
    expect(evaluate('$left$operator'), isNull);
  });

  property('dividing by zero has no answer', (TestCase testCase) {
    final left = testCase.draw(operands(), name: 'left');
    expect(evaluate('$left${divideSign}0'), isNull);
  });
}
