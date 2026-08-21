@TestOn('vm')
library;

import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/string_generator.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

/// Values the ABI would reinterpret rather than reject.
///
/// dart:ffi narrows silently, so a negative int handed to an unsigned
/// parameter arrives as a huge positive one and a value wider than a byte
/// field arrives truncated. The engine then validates a number the caller
/// never wrote -- or, worse, tries to honour it.
void main() {
  late Libhegel session;
  late Run run;
  late TestCase testCase;

  setUp(() {
    session = Libhegel.open();
    run = Run.start(
      const Settings(
        testCases: 5,
        seed: 41,
        derandomize: true,
        database: Database.disabled,
        verbosity: Verbosity.quiet,
      ),
      session: session,
    );
    testCase = run.nextTestCase()!;
  });

  tearDown(() {
    testCase.dispose();
    run.dispose();
    session.dispose();
  });

  group('string generator sizes', () {
    // Left unchecked this aborted the process: minSize -1 reached the ABI as
    // UINT64_MAX, and the first draw panicked inside the engine's allocator
    // with a capacity overflow, killing the whole test runner rather than
    // failing one test.
    test('a negative minimum is refused rather than wrapping', () {
      expect(
        () => StringGenerator.text(minSize: -1, session: session),
        throwsRangeError,
      );
    });

    test('a minimum above the maximum is refused', () {
      expect(
        () => StringGenerator.text(minSize: 5, maxSize: 2, session: session),
        throwsArgumentError,
      );
    });

    test('a codepoint outside the unsigned field is refused', () {
      expect(
        () => StringGenerator.text(minCodepoint: -1, session: session),
        throwsRangeError,
      );
      expect(
        () =>
            StringGenerator.text(maxCodepoint: 0x1_0000_0000, session: session),
        throwsRangeError,
      );
    });

    test('a negative domain length is refused', () {
      expect(
        () => StringGenerator.domain(maxLength: -1, session: session),
        throwsRangeError,
      );
    });

    test('the legitimate extremes still work', () {
      final generator = StringGenerator.text(
        minSize: 0,
        maxCodepoint: 0xFFFFFFFF,
        codec: 'ascii',
        session: session,
      );
      addTearDown(generator.dispose);
      expect(testCase.drawString(generator), isA<String>());
    });
  });

  group('temporal fields', () {
    // Month and day are single bytes: 257 would arrive as 1, so the engine
    // would happily validate a bound nobody asked for.
    test('a month outside a byte is refused rather than truncated', () {
      expect(
        () => testCase.drawDate(
          min: (year: 2020, month: 257, day: 1),
          max: (year: 2020, month: 257, day: 1),
        ),
        throwsRangeError,
      );
    });

    test('an hour outside a byte is refused rather than truncated', () {
      expect(
        () => testCase.drawTime(
          min: (hour: 256, minute: 0, second: 0, microsecond: 0),
          max: (hour: 256, minute: 0, second: 0, microsecond: 0),
        ),
        throwsRangeError,
      );
    });

    test('a microsecond outside its field is refused', () {
      expect(
        () => testCase.drawTime(
          max: (hour: 23, minute: 59, second: 59, microsecond: 4294967296),
        ),
        throwsRangeError,
      );
    });

    test('ordinary out-of-range values are refused too', () {
      expect(
        () => testCase.drawDate(min: (year: 2020, month: 13, day: 1)),
        throwsRangeError,
      );
      expect(
        () => testCase.drawDate(min: (year: 2020, month: 1, day: 0)),
        throwsRangeError,
      );
      expect(
        () => testCase.drawTime(
          min: (hour: 24, minute: 0, second: 0, microsecond: 0),
        ),
        throwsRangeError,
      );
    });

    test('a year beyond the engine range is refused', () {
      expect(
        () => testCase.drawDate(min: (year: -1000000, month: 1, day: 1)),
        throwsRangeError,
      );
    });

    test('both halves of a datetime are checked', () {
      expect(
        () => testCase.drawDateTime(
          min: (
            date: (year: 2020, month: 1, day: 1),
            time: (hour: 99, minute: 0, second: 0, microsecond: 0),
          ),
        ),
        throwsRangeError,
      );
      expect(
        () => testCase.drawDateTime(
          max: (
            date: (year: 2020, month: 99, day: 1),
            time: (hour: 1, minute: 0, second: 0, microsecond: 0),
          ),
        ),
        throwsRangeError,
      );
    });

    test('the legitimate extremes still work', () {
      expect(
        () => testCase.drawDateTime(
          min: (
            date: (year: -999999, month: 1, day: 1),
            time: (hour: 0, minute: 0, second: 0, microsecond: 0),
          ),
          max: (
            date: (year: 999999, month: 12, day: 31),
            time: (hour: 23, minute: 59, second: 59, microsecond: 999999),
          ),
        ),
        returnsNormally,
      );
    });
  });
}
