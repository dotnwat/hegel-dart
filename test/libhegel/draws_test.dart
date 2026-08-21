@TestOn('vm')
library;

import 'dart:ffi';

import 'package:hegel/src/libhegel/bindings.g.dart' as raw;
import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:hegel/src/libhegel/version.g.dart';
import 'package:test/test.dart';

import '../support/fake_bindings.dart';

Settings settingsFor({int testCases = 50, int seed = 42}) => Settings(
  testCases: testCases,
  seed: seed,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: everyHealthCheck,
);

/// A test case backed by a fake, for the paths a real engine will not take
/// on demand.
({TestCase testCase, FakeBindings fake}) fakeCase() {
  final fake = FakeBindings()
    ..onCall = (String name, Invocation invocation) {
      if (name == 'hegel_version') writeVersion(invocation, libhegelVersion);
    };
  final session = Libhegel.open(fake);
  addTearDown(session.dispose);
  addTearDown(releaseVersionStrings);
  final testCase = TestCase(
    session,
    Pointer.fromAddress(0x2000),
    TestCaseFamily(),
  );
  // Disposed like any other handle, even over a fake: the leak detector
  // reports whatever is not, and a helper that leaks would report on every
  // test that used it.
  addTearDown(testCase.dispose);
  return (testCase: testCase, fake: fake);
}

void main() {
  group('a run that draws', () {
    // The echo.c example: draw an integer in range, assert it is in range.
    test('produces values inside the requested bounds', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      final run = Run.start(settingsFor(), session: session);
      addTearDown(run.dispose);

      var cases = 0;
      final drawn = <int>[];
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        cases++;
        try {
          final value = testCase.drawInteger(min: 0, max: 100);
          drawn.add(value);
          testCase.markComplete(
            value >= 0 && value <= 100
                ? TestCaseStatus.valid
                : TestCaseStatus.interesting,
            origin: value >= 0 && value <= 100 ? null : 'out of range',
          );
        } on StopTest {
          testCase.markComplete(TestCaseStatus.overrun);
        } finally {
          testCase.dispose();
        }
      }

      final result = run.result();
      addTearDown(result.dispose);
      expect(result.status, RunStatus.passed);
      // Now that the body draws, the budget actually binds.
      expect(cases, 50);
      expect(
        drawn,
        everyElement(allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(100))),
      );
      expect(drawn.toSet().length, greaterThan(1), reason: 'should vary');
    });

    test('is reproducible from a seed', () {
      List<int> sequence() {
        final session = Libhegel.open();
        final run = Run.start(settingsFor(testCases: 20), session: session);
        final values = <int>[];
        try {
          while (true) {
            final testCase = run.nextTestCase();
            if (testCase == null) break;
            try {
              values.add(testCase.drawInteger(min: -1000, max: 1000));
              testCase.markComplete(TestCaseStatus.valid);
            } finally {
              testCase.dispose();
            }
          }
        } finally {
          run.dispose();
          session.dispose();
        }
        return values;
      }

      expect(sequence(), sequence());
    });

    test('draws booleans and floats', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      final run = Run.start(settingsFor(testCases: 30), session: session);
      addTearDown(run.dispose);

      final booleans = <bool>{};
      final floats = <double>[];
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          booleans.add(testCase.drawBoolean());
          floats.add(testCase.drawFloat(min: -1.0, max: 1.0));
          testCase.markComplete(TestCaseStatus.valid);
        } finally {
          testCase.dispose();
        }
      }

      expect(booleans, containsAll(<bool>[true, false]));
      expect(
        floats,
        everyElement(allOf(greaterThanOrEqualTo(-1.0), lessThanOrEqualTo(1.0))),
      );
      expect(floats.any((double f) => f.isNaN), isFalse);
    });

    test('honours a forced boolean without consuming entropy', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      final run = Run.start(settingsFor(testCases: 3), session: session);
      addTearDown(run.dispose);

      final testCase = run.nextTestCase()!;
      addTearDown(testCase.dispose);
      expect(testCase.drawBoolean(forced: true), isTrue);
      expect(testCase.drawBoolean(forced: false), isFalse);
      expect(testCase.drawBoolean(probability: 1), isTrue);
      expect(testCase.drawBoolean(probability: 0), isFalse);
      testCase.markComplete(TestCaseStatus.valid);
    });
  });

  group('argument validation, before reaching the engine', () {
    late TestCase testCase;
    late FakeBindings fake;

    setUp(() {
      final built = fakeCase();
      testCase = built.testCase;
      fake = built.fake;
    });

    test('rejects inverted integer bounds', () {
      expect(() => testCase.drawInteger(min: 10, max: 1), throwsArgumentError);
      expect(fake.calls, isNot(contains('hegel_generate_integer')));
    });

    test('rejects a probability outside zero to one', () {
      expect(() => testCase.drawBoolean(probability: 1.5), throwsRangeError);
      expect(() => testCase.drawBoolean(probability: -0.1), throwsRangeError);
      expect(
        () => testCase.drawBoolean(probability: double.nan),
        throwsRangeError,
      );
    });

    test('rejects a float width the ABI does not define', () {
      expect(() => testCase.drawFloat(width: 16), throwsArgumentError);
    });

    test('rejects a non-positive smallest magnitude', () {
      expect(
        () => testCase.drawFloat(smallestNonzeroMagnitude: 0),
        throwsArgumentError,
      );
      expect(
        () => testCase.drawFloat(smallestNonzeroMagnitude: double.infinity),
        throwsArgumentError,
      );
    });
  });

  // The latch is what keeps unwinding safe: a draw in a finally block must not
  // reach an engine that has already given up on the case, and must not
  // change what kind of ending gets reported.
  // The guard-first contract says lifecycle misuse visible in Dart raises
  // StateError without a native call; a completed case is exactly that.
  group('a completed case', () {
    test('refuses further draws without calling the engine', () {
      final built = fakeCase();
      built.testCase.markComplete(TestCaseStatus.valid);
      built.fake.clearCalls();

      expect(
        () => built.testCase.drawInteger(min: 0, max: 1),
        throwsStateError,
      );
      expect(built.testCase.drawBoolean, throwsStateError);
      expect(built.testCase.drawFloat, throwsStateError);
      expect(built.fake.calls, isEmpty);
    });

    test('refuses to be cloned without calling the engine', () {
      final built = fakeCase();
      built.testCase.markComplete(TestCaseStatus.valid);
      built.fake.clearCalls();

      expect(built.testCase.clone, throwsStateError);
      expect(built.fake.calls, isEmpty);
    });

    // Reads a runner needs for reporting stay available after completion.
    test('still answers queries and disposes', () {
      final built = fakeCase();
      built.testCase.markComplete(TestCaseStatus.valid);
      expect(() => built.testCase.isNondeterministic, returnsNormally);
      expect(built.testCase.dispose, returnsNormally);
    });
  });

  group('the abort latch', () {
    test('re-raises StopTest without calling the engine again', () {
      final built = fakeCase();
      built.fake.results['hegel_generate_integer'] =
          raw.hegel_result_t.HEGEL_E_STOP_TEST;

      expect(
        () => built.testCase.drawInteger(min: 0, max: 1),
        throwsA(isA<StopTest>()),
      );
      final callsAfterFirst = built.fake.calls.length;

      expect(
        () => built.testCase.drawInteger(min: 0, max: 1),
        throwsA(isA<StopTest>()),
      );
      expect(built.fake.calls.length, callsAfterFirst);
    });

    test('re-raises AssumptionFailed as itself, not as StopTest', () {
      final built = fakeCase();
      built.fake.results['hegel_generate_boolean'] =
          raw.hegel_result_t.HEGEL_E_ASSUME;

      expect(built.testCase.drawBoolean, throwsA(isA<AssumptionFailed>()));
      // Re-raising StopTest here would turn an invalid case into an overrun
      // one, and the runner would report the wrong outcome.
      expect(
        () => built.testCase.drawInteger(min: 0, max: 1),
        throwsA(isA<AssumptionFailed>()),
      );
      expect(
        () => built.testCase.drawFloat(),
        throwsA(isA<AssumptionFailed>()),
      );
    });

    test('is shared with clones of the same case', () {
      final built = fakeCase();
      final family = built.testCase.family;
      built.fake.results['hegel_generate_integer'] =
          raw.hegel_result_t.HEGEL_E_STOP_TEST;

      expect(
        () => built.testCase.drawInteger(min: 0, max: 1),
        throwsA(isA<StopTest>()),
      );

      final clone = TestCase(
        built.testCase.session,
        Pointer.fromAddress(0x3000),
        family,
      );
      addTearDown(clone.dispose);
      expect(
        () => clone.drawBoolean(),
        throwsA(isA<StopTest>()),
        reason: 'a clone must not keep drawing from an abandoned case',
      );
    });

    test('still allows the case to be reported complete', () {
      final built = fakeCase();
      built.fake.results['hegel_generate_integer'] =
          raw.hegel_result_t.HEGEL_E_STOP_TEST;
      expect(
        () => built.testCase.drawInteger(min: 0, max: 1),
        throwsA(isA<StopTest>()),
      );
      // Reporting the outcome is how the abort gets communicated, so it must
      // survive the latch.
      expect(
        () => built.testCase.markComplete(TestCaseStatus.overrun),
        returnsNormally,
      );
    });

    // The latch exists so that a draw made while the stack unwinds cannot
    // change how the case is reported. An argument complaint from such a draw
    // would do exactly that, so the latch is consulted first.
    test('outranks a draw own argument validation', () {
      final built = fakeCase();
      built.fake.results['hegel_generate_boolean'] =
          raw.hegel_result_t.HEGEL_E_ASSUME;
      expect(built.testCase.drawBoolean, throwsA(isA<AssumptionFailed>()));

      expect(
        () => built.testCase.drawBoolean(probability: double.nan),
        throwsA(isA<AssumptionFailed>()),
      );
      expect(
        () => built.testCase.drawInteger(min: 10, max: 0),
        throwsA(isA<AssumptionFailed>()),
      );
      expect(
        () => built.testCase.drawFloat(width: 16),
        throwsA(isA<AssumptionFailed>()),
      );
    });

    test('leaves an unaborted case alone', () {
      final built = fakeCase();
      expect(built.testCase.family.abort, isNull);
      expect(() => built.testCase.drawInteger(min: 0, max: 1), returnsNormally);
    });
  });
}
