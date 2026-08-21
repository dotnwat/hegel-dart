@TestOn('vm')
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

const Settings settings = Settings(
  testCases: 40,
  seed: 11,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: HealthChecks.all,
);

BigInt big(String value) => BigInt.parse(value);

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  /// Draws once per case with [draw] and returns everything drawn.
  List<BigInt> drawAll(BigInt Function(TestCase testCase) draw) {
    final run = Run.start(settings, session: session);
    final values = <BigInt>[];
    try {
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          values.add(draw(testCase));
          testCase.markComplete(TestCaseStatus.valid);
        } on StopTest {
          testCase.markComplete(TestCaseStatus.overrun);
        } finally {
          testCase.dispose();
        }
      }
    } finally {
      run.dispose();
    }
    return values;
  }

  group('within the machine-integer range', () {
    test('stays inside the bounds', () {
      final values = drawAll(
        (TestCase c) => c.drawBigInteger(min: big('-1000'), max: big('1000')),
      );
      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(
          allOf(
            greaterThanOrEqualTo(big('-1000')),
            lessThanOrEqualTo(big('1000')),
          ),
        ),
      );
      expect(values.toSet().length, greaterThan(1));
    });

    test('handles equal bounds without consuming a choice', () {
      final values = drawAll(
        (TestCase c) => c.drawBigInteger(min: big('7'), max: big('7')),
      );
      expect(values, everyElement(big('7')));
    });
  });

  // Past int64 the exchange switches to two's-complement buffers, which is the
  // path the codec exists for.
  group('beyond the machine-integer range', () {
    test('draws inside bounds wider than int64', () {
      final min = big('-170141183460469231731687303715884105728');
      final max = big('170141183460469231731687303715884105727');
      final values = drawAll(
        (TestCase c) => c.drawBigInteger(min: min, max: max),
      );
      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(allOf(greaterThanOrEqualTo(min), lessThanOrEqualTo(max))),
      );
    });

    test('draws inside a range entirely above int64', () {
      final min = big('9223372036854775808');
      final max = min + big('1000000');
      final values = drawAll(
        (TestCase c) => c.drawBigInteger(min: min, max: max),
      );
      expect(
        values,
        everyElement(allOf(greaterThanOrEqualTo(min), lessThanOrEqualTo(max))),
      );
    });

    test('draws inside a range entirely below int64', () {
      final max = big('-9223372036854775809');
      final min = max - big('1000000');
      final values = drawAll(
        (TestCase c) => c.drawBigInteger(min: min, max: max),
      );
      expect(
        values,
        everyElement(allOf(greaterThanOrEqualTo(min), lessThanOrEqualTo(max))),
      );
    });

    test('handles bounds of different widths', () {
      // A one-byte minimum against a very wide maximum: the out buffer has to
      // be sized from the wider of the two.
      final values = drawAll(
        (TestCase c) => c.drawBigInteger(min: big('0'), max: big('2').pow(200)),
      );
      expect(
        values,
        everyElement(
          allOf(
            greaterThanOrEqualTo(BigInt.zero),
            lessThanOrEqualTo(big('2').pow(200)),
          ),
        ),
      );
    });

    test('is reproducible from a seed', () {
      List<BigInt> sequence() => drawAll(
        (TestCase c) =>
            c.drawBigInteger(min: -big('2').pow(100), max: big('2').pow(100)),
      );
      expect(sequence(), sequence());
    });
  });

  group('validation', () {
    test('rejects inverted bounds', () {
      final run = Run.start(settings, session: session);
      addTearDown(run.dispose);
      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);
      expect(
        () => testCase.drawBigInteger(min: big('10'), max: big('1')),
        throwsArgumentError,
      );
      testCase.markComplete(TestCaseStatus.valid);
    });
  });
}
