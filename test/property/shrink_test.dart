@TestOn('vm')
library;

import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/shrink_pin.dart';

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
}
