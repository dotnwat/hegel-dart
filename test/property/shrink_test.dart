@TestOn('vm')
library;

import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/shrink_pin.dart';
import '../support/tree.dart';

void main() {
  group('a mapped generator', () {
    test('shrinks to the smallest value the transform can make', () async {
      // Multiples of three above fifty start at 51, so the shrinker has to
      // walk the source down to 17 and no further. A counterexample of 54
      // would mean it stopped early; one of 52 would mean the transform was
      // not what produced the reported value.
      final report = await shrunkReport((TestCase testCase) {
        final value = testCase.draw(
          integers(min: 0, max: 1000).map((int n) => n * 3),
          name: 'value',
        );
        if (value > 50) throw StateError('$value is too big');
      });

      expect(report, contains('value = 51'));
    });
  });

  group('a filtered generator', () {
    test('shrinks to the smallest value that gets past the filter', () async {
      final report = await shrunkReport((TestCase testCase) {
        final value = testCase.draw(
          integers(min: 0, max: 1000).where((int n) => n.isEven),
          name: 'value',
        );
        if (value > 50) throw StateError('$value is too big');
      });

      // 51 is the smallest failing integer and 52 the smallest failing even
      // one. Reporting 51 would mean a filtered value reached the property,
      // which is the filter failing at the one thing it does.
      expect(report, contains('value = 52'));
    });
  });

  group('a flat-mapped generator', () {
    test('shrinks both draws, and keeps them consistent', () async {
      // The second draw's range depends on the first, so a shrinker that
      // moved one without the other would report a value outside the range
      // the report's own first draw allows. The minimum is 4: the smallest
      // failing value, reachable only once the first draw has shrunk to 0.
      final report = await shrunkReport((TestCase testCase) {
        final value = testCase.draw(
          integers(
            min: 0,
            max: 5,
          ).flatMap((int n) => integers(min: n, max: 20)),
          name: 'value',
        );
        if (value > 3) throw StateError('$value is too big');
      });

      expect(report, contains('value = 4'));
    });
  });

  group('a sampled generator', () {
    test('shrinks toward the front of the list', () async {
      final report = await shrunkReport((TestCase testCase) {
        final value = testCase.draw(
          sampledFrom(<String>['ant', 'bee', 'cow']),
          name: 'value',
        );
        throw StateError('$value is not the one');
      });

      expect(report, contains("value = 'ant'"));
    });
  });

  group('a one-of generator', () {
    test('shrinks into its first failing option', () async {
      // Both options can fail, and both shrink to the same number, so the
      // tag is the whole assertion: the reported case took the first
      // option, which is where the index shrinks to.
      final report = await shrunkReport((TestCase testCase) {
        final value = testCase.draw(
          oneOf(<Generator<String>>[
            integers(min: 0, max: 1000).map((int n) => 'a$n'),
            integers(min: 0, max: 1000).map((int n) => 'b$n'),
          ]),
          name: 'value',
        );
        if (int.parse(value.substring(1)) > 50) {
          throw StateError('$value is too big');
        }
      });

      expect(report, contains("value = 'a51'"));
    });

    test('stays in the option that fails, and shrinks that one', () async {
      // Only the second option reaches past ten, so shrinking the choice
      // toward the first would lose the failure. It has to shrink what is
      // inside the branch instead, which is what the span is for.
      final report = await shrunkReport((TestCase testCase) {
        final value = testCase.draw(
          oneOf(<Generator<int>>[
            integers(min: 0, max: 10),
            integers(min: 0, max: 1000),
          ]),
          name: 'value',
        );
        if (value > 50) throw StateError('$value is too big');
      });

      expect(report, contains('value = 51'));
    });
  });

  group('an optional generator', () {
    test('shrinks to null when null fails too', () async {
      final report = await shrunkReport((TestCase testCase) {
        final value = testCase.draw(
          optional(integers(min: 0, max: 1000)),
          name: 'value',
        );
        if (value == null || value > 50) throw StateError('$value is no good');
      });

      expect(report, contains('value = null'));
    });

    test('keeps the value when null does not fail', () async {
      final report = await shrunkReport((TestCase testCase) {
        final value = testCase.draw(
          optional(integers(min: 0, max: 1000)),
          name: 'value',
        );
        if (value != null && value > 50) throw StateError('$value is too big');
      });

      expect(report, contains('value = 51'));
    });
  });

  group('a tuple generator', () {
    test('shrinks each part as far as that part can go', () async {
      // Eleven and twenty-one: each part walked down to its own smallest
      // failing value, which is a different number for each. A shrinker
      // that could only take the pair as a whole would stop somewhere
      // larger, and one that shrank the parts independently of the failure
      // would report the pair that no longer fails.
      final report = await shrunkReport((TestCase testCase) {
        final (first, second) = testCase.draw(
          tuple2(integers(min: 0, max: 1000), integers(min: 0, max: 1000)),
          name: 'pair',
        );
        if (first > 10 && second > 20) throw StateError('both are too big');
      });

      expect(report, contains('pair = (11, 21)'));
    });

    test('shrinks the parts a failure does not need out of the way', () async {
      final report = await shrunkReport((TestCase testCase) {
        final (first, second, third) = testCase.draw(
          tuple3(
            integers(min: 0, max: 100),
            integers(min: 0, max: 100),
            integers(min: 0, max: 100),
          ),
          name: 'triple',
        );
        if (first + second + third > 30) throw StateError('too big');
      });

      expect(report, contains('triple = (0, 0, 31)'));
    });
  });

  group('a composite generator', () {
    test('shrinks the parts it built the value out of', () async {
      // The second draw's range starts at the first, so a low of zero is
      // what lets the high shrink as far as six -- the smallest pair more
      // than five apart. Reporting anything wider would mean the parts were
      // being shrunk one at a time against a failure that needs both.
      final report = await shrunkReport((TestCase testCase) {
        final (low, high) = testCase.draw(
          composite((TestCase inner) {
            final low = inner.draw(integers(min: 0, max: 100));
            final high = inner.draw(integers(min: low, max: 200));
            return (low, high);
          }),
          name: 'range',
        );
        if (high - low > 5) throw StateError('$low..$high is too wide');
      });

      expect(report, contains('range = (0, 6)'));
    });
  });

  group('a recursive generator', () {
    test('shrinks to the smallest tree that still fails', () async {
      // The pin that most needs its spans. A tree is drawn from dozens of
      // choices, and shrinking one means deleting whole subtrees; without
      // the spans that say which choices are a subtree the engine has to
      // pick at them one at a time, and this stops finishing at all.
      final report = await shrunkReport((TestCase testCase) {
        final tree = testCase.draw(trees(), name: 'tree');
        if (tree.leaves >= 2) throw StateError('$tree has too many leaves');
      });

      expect(report, contains('tree = Branch(Leaf(0), Leaf(0))'));
    });
  });
}
