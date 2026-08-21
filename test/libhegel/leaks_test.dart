@TestOn('vm')
library;

import 'dart:async';

import 'package:hegel/src/libhegel/leaks.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

const Settings settings = Settings(
  testCases: 3,
  seed: 83,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
);

void main() {
  final reports = <LeakReport>[];

  setUp(() {
    reports.clear();
    reportLeak = reports.add;
  });

  tearDown(resetLeakReporting);

  // The reporting path is tested directly rather than through the collector,
  // because a finalizer is never promised to run and a suite that depends on
  // one is a suite that fails at random.
  group('the report', () {
    test('names the handle and where it came from', () {
      final report = LeakReport('Run', StackTrace.current);
      expect(report.kind, 'Run');
      expect(report.toString(), contains('a Run was garbage collected'));
      expect(report.toString(), contains('dispose()'));
      expect(report.toString(), contains('Created at:'));
    });

    test('reaches the reporter', () {
      final report = LeakReport('TestCase', StackTrace.current);
      deliverLeakReport(report);
      expect(reports, <LeakReport>[report]);
    });

    // A finalizer callback that throws surfaces at an arbitrary point in an
    // unrelated part of the program, which is worse than the leak it was
    // describing.
    test('never throws into the collector', () {
      reportLeak = (LeakReport report) => throw StateError('reporter broke');
      expect(
        () => deliverLeakReport(LeakReport('Pool', StackTrace.current)),
        returnsNormally,
      );
    });

    test('goes back to printing when reset', () {
      resetLeakReporting();
      final printed = <String>[];
      // Captured rather than let loose on stdout, so this test does not look
      // like the very leak it is describing.
      runZoned(
        () => deliverLeakReport(LeakReport('Failure', StackTrace.current)),
        zoneSpecification: ZoneSpecification(
          print: (Zone _, ZoneDelegate _, Zone _, String line) =>
              printed.add(line),
        ),
      );
      expect(printed, hasLength(1));
      expect(printed.single, contains('a Failure was garbage collected'));
      expect(reports, isEmpty, reason: 'the collector was uninstalled');
    });
  });

  group('tracking', () {
    test('watches an owning handle and stops once it is disposed', () {
      final owner = Object();
      expect(trackHandle(owner, 'Run'), isTrue);
      expect(releaseHandle(owner), isTrue);
      // Detaching twice is what a double dispose does, and must be harmless.
      expect(releaseHandle(owner), isTrue);
    });

    test('a disposed wrapper is no longer watched', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      final run = Run.start(settings, session: session);
      final testCase = run.nextTestCase()!;
      testCase
        ..markComplete(TestCaseStatus.valid)
        ..dispose();
      run.dispose();
      // Nothing is reported for handles that were disposed properly, whatever
      // the collector decides to do with them later.
      expect(reports, isEmpty);
    });
  });

  // Delivery depends on the collector, which promises nothing. This checks
  // the wiring end to end when a collection happens and steps aside when one
  // does not, so it can never fail the suite.
  test('a dropped handle is reported if the collector gets to it', () async {
    final session = Libhegel.open();
    addTearDown(session.dispose);

    Run.start(settings, session: session);

    // Encourage a collection without depending on one.
    for (var attempt = 0; attempt < 20 && reports.isEmpty; attempt++) {
      final garbage = List<List<int>>.generate(
        200,
        (int i) => List<int>.filled(1000, i),
      );
      expect(garbage, isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    if (reports.isEmpty) {
      markTestSkipped('the collector did not run; delivery is never promised');
      return;
    }
    expect(reports.first.kind, 'Run');
    expect(reports.first.toString(), contains('never released'));
  });
}
