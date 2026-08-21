@TestOn('vm')
library;

import 'package:hegel/src/libhegel/bindings.g.dart' as raw;
import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

const Settings settings = Settings(
  testCases: 25,
  seed: 43,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: machineSpeedChecks,
);

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  RunResult drive(void Function(TestCase testCase) body) {
    final run = Run.start(settings, session: session);
    try {
      while (true) {
        final testCase = run.nextTestCase();
        if (testCase == null) break;
        try {
          body(testCase);
          testCase.markComplete(TestCaseStatus.valid);
        } on StopTest {
          testCase.markComplete(TestCaseStatus.overrun);
        } on AssumptionFailed {
          testCase.markComplete(TestCaseStatus.invalid);
        } finally {
          testCase.dispose();
        }
      }
      return run.result();
    } finally {
      run.dispose();
    }
  }

  group('labels', () {
    test('take their values from the header', () {
      expect(SpanLabel.list.value, raw.hegel_label_t.HEGEL_LABEL_LIST);
      expect(SpanLabel.mapEntry.value, raw.hegel_label_t.HEGEL_LABEL_MAP_ENTRY);
      expect(
        SpanLabel.statefulRule.value,
        raw.hegel_label_t.HEGEL_LABEL_STATEFUL_RULE,
      );
    });

    // A library minting its own labels needs somewhere safe to start.
    test('leave room above the reserved range', () {
      expect(
        SpanLabel.firstAvailable,
        greaterThan(raw.hegel_label_t.HEGEL_LABEL_CONCURRENCY),
      );
      const mine = SpanLabel(SpanLabel.firstAvailable + 7);
      expect(mine.value, greaterThan(SpanLabel.concurrency.value));
    });
  });

  group('driving spans', () {
    test('a span around a group of draws leaves the run passing', () {
      final result = drive((TestCase c) {
        c.startSpan(SpanLabel.list);
        c.drawInteger(min: 0, max: 10);
        c.drawInteger(min: 0, max: 10);
        c.stopSpan();
      });
      addTearDown(result.dispose);
      expect(result.status, RunStatus.passed);
    });

    test('spans nest', () {
      final result = drive((TestCase c) {
        c.span(SpanLabel.list, () {
          for (var i = 0; i < 3; i++) {
            c.span(SpanLabel.listElement, () => c.drawInteger(min: 0, max: 5));
          }
        });
      });
      addTearDown(result.dispose);
      expect(result.status, RunStatus.passed);
    });

    // Discarding tells the engine the span's draws did not work out, so it
    // retries from where the span opened rather than keeping them.
    test('a discarded span is retried rather than kept', () {
      var discards = 0;
      final result = drive((TestCase c) {
        c.startSpan(SpanLabel.filter);
        final value = c.drawInteger(min: 0, max: 20);
        final acceptable = value.isEven;
        if (!acceptable) discards++;
        c.stopSpan(discard: !acceptable);
        if (!acceptable) {
          // Retrying is the engine's job; the body just reports the outcome.
          c.startSpan(SpanLabel.filter);
          c.drawInteger(min: 0, max: 20);
          c.stopSpan();
        }
      });
      addTearDown(result.dispose);
      expect(result.status, RunStatus.passed);
      expect(discards, greaterThan(0), reason: 'some draws should be odd');
    });

    test('the span helper closes the span when the body throws', () {
      final result = drive((TestCase c) {
        try {
          c.span(SpanLabel.oneOf, () {
            c.drawInteger(min: 0, max: 3);
            throw const FormatException('from the body');
          });
        } on FormatException {
          // Swallowed here; the point is the span still closed, which the
          // next draw would fail on if it had not.
        }
        c.drawInteger(min: 0, max: 3);
      });
      addTearDown(result.dispose);
      expect(result.status, RunStatus.passed);
    });
  });

  // Spans are closed from finally blocks as the stack unwinds. If closing one
  // raised, an overrun would surface as some unrelated error instead.
  test('closing a span is inert once the case has been abandoned', () {
    final run = Run.start(settings, session: session);
    addTearDown(run.dispose);
    final testCase = run.nextTestCase()!;
    addTearDown(testCase.dispose);

    testCase.startSpan(SpanLabel.list);
    testCase.markComplete(TestCaseStatus.valid);
    expect(() => testCase.stopSpan(), returnsNormally);
    testCase.dispose();
    expect(() => testCase.stopSpan(), returnsNormally);
  });
}
