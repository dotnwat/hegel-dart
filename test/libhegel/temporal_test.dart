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
  seed: 19,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: HealthChecks.all,
);

int daysIn(int year, int month) {
  const lengths = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month != 2) return lengths[month - 1];
  final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  return leap ? 29 : 28;
}

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  List<T> drawAll<T>(T Function(TestCase testCase) draw) {
    final run = Run.start(settings, session: session);
    final drawn = <T>[];
    try {
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          drawn.add(draw(testCase));
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
    return drawn;
  }

  group('dates', () {
    test('are real calendar dates', () {
      final drawn = drawAll((TestCase c) => c.drawDate());
      expect(drawn, isNotEmpty);
      for (final date in drawn) {
        expect(
          date.month,
          allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(12)),
        );
        expect(date.day, greaterThanOrEqualTo(1));
        // A day that does not exist in that month would mean the struct came
        // back misaligned, which is the real risk with by-value passing.
        expect(date.day, lessThanOrEqualTo(daysIn(date.year, date.month)));
      }
    });

    test('stay inside a narrow range', () {
      final drawn = drawAll(
        (TestCase c) => c.drawDate(
          min: (year: 2020, month: 6, day: 1),
          max: (year: 2020, month: 6, day: 30),
        ),
      );
      expect(drawn, isNotEmpty);
      for (final date in drawn) {
        expect(date.year, 2020);
        expect(date.month, 6);
        expect(date.day, allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(30)));
      }
    });

    test('handle a single permitted day', () {
      final drawn = drawAll(
        (TestCase c) => c.drawDate(
          min: (year: 1999, month: 12, day: 31),
          max: (year: 1999, month: 12, day: 31),
        ),
      );
      expect(drawn, everyElement((year: 1999, month: 12, day: 31)));
    });

    // Years outside what DateTime accepts are exactly why these are records.
    test('reach years beyond the range of DateTime', () {
      final drawn = drawAll(
        (TestCase c) => c.drawDate(
          min: (year: -999999, month: 1, day: 1),
          max: (year: -999000, month: 12, day: 31),
        ),
      );
      expect(drawn, isNotEmpty);
      expect(
        drawn.map((HegelDate d) => d.year),
        everyElement(lessThan(-998999)),
      );
    });
  });

  group('times', () {
    test('are real times of day', () {
      final drawn = drawAll((TestCase c) => c.drawTime());
      expect(drawn, isNotEmpty);
      for (final time in drawn) {
        expect(
          time.hour,
          allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(23)),
        );
        expect(
          time.minute,
          allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(59)),
        );
        expect(
          time.second,
          allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(59)),
        );
        expect(
          time.microsecond,
          allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(999999)),
        );
      }
    });

    test('stay inside a narrow range', () {
      final drawn = drawAll(
        (TestCase c) => c.drawTime(
          min: (hour: 12, minute: 0, second: 0, microsecond: 0),
          max: (hour: 12, minute: 0, second: 59, microsecond: 999999),
        ),
      );
      expect(drawn, isNotEmpty);
      for (final time in drawn) {
        expect(time.hour, 12);
        expect(time.minute, 0);
      }
    });
  });

  group('datetimes', () {
    test('combine a valid date and a valid time', () {
      final drawn = drawAll((TestCase c) => c.drawDateTime());
      expect(drawn, isNotEmpty);
      for (final value in drawn) {
        expect(
          value.date.day,
          lessThanOrEqualTo(daysIn(value.date.year, value.date.month)),
        );
        expect(value.time.hour, lessThanOrEqualTo(23));
        expect(value.time.microsecond, lessThanOrEqualTo(999999));
      }
    });

    // A nested struct passed by value is where field offsets are easiest to
    // get wrong; pinning both halves at once catches that.
    test('stay inside a narrow range on both halves', () {
      final drawn = drawAll(
        (TestCase c) => c.drawDateTime(
          min: (
            date: (year: 2001, month: 1, day: 1),
            time: (hour: 0, minute: 0, second: 0, microsecond: 0),
          ),
          max: (
            date: (year: 2001, month: 1, day: 2),
            time: (hour: 1, minute: 0, second: 0, microsecond: 0),
          ),
        ),
      );
      expect(drawn, isNotEmpty);
      for (final value in drawn) {
        expect(value.date.year, 2001);
        expect(value.date.month, 1);
        expect(value.date.day, anyOf(1, 2));
      }
    });
  });

  test('are reproducible from a seed', () {
    List<HegelDateTime> sequence() => drawAll((TestCase c) => c.drawDateTime());
    expect(sequence(), sequence());
  });

  test('an inverted range is refused by the engine', () {
    final run = Run.start(settings, session: session);
    addTearDown(run.dispose);
    final testCase = run.nextTestCase()!;
    addTearDown(testCase.dispose);
    expect(
      () => testCase.drawDate(
        min: (year: 2020, month: 1, day: 1),
        max: (year: 2019, month: 1, day: 1),
      ),
      throwsA(isA<HegelException>()),
    );
  });
}
