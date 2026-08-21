/// Drives a one-draw integer property against the real engine.
///
/// The database, phase and shrinking tests all need the same thing: run a
/// property to completion, and afterwards say what the engine drew and how
/// many test cases it handed out. Replay is only observable from the outside
/// as "the first value of this run is one an earlier run ended on", so the
/// order of [Drive.draws] is the whole point rather than a debugging aid.
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart';

/// The health checks that measure the machine rather than the code.
///
/// TooSlow fires on thirty seconds of wall clock, so on a loaded or slow CI
/// runner it reports the runner rather than a defect in what is being tested.
/// The other three are deterministic given the choice sequence, so they are
/// left live throughout the suite: if the engine ever has something to say
/// about one of these tests, it should be able to say it.
///
/// The suite used to suppress all four everywhere. Removing that changed
/// nothing -- every test still passed -- so the blanket was never
/// load-bearing, only in the way.
const Set<HealthCheck> machineSpeedChecks = <HealthCheck>{HealthCheck.tooSlow};

/// What one call to [driveIntegerProperty] observed.
final class Drive {
  /// Records a finished run.
  Drive({required this.result, required this.draws, required this.testCases});

  /// The finished run. The caller owns it and must dispose it.
  final RunResult result;

  /// Every value drawn, in the order the engine asked for it.
  ///
  /// The last entry is wherever the shrinker's search stopped, which is only
  /// sometimes the value it settled on. Read the counterexample itself from
  /// the failure's reproduction blob.
  final List<int> draws;

  /// How many test cases the engine handed out.
  ///
  /// A replay-only run hands out exactly one, which is how a test tells
  /// "replayed the stored counterexample" apart from "generated its way back
  /// to the same value".
  final int testCases;
}

/// Runs a property that draws one integer in [min]..[max] per test case and
/// fails whenever that value exceeds [threshold].
///
/// Raising [threshold] above [max] models the bug being fixed, which is what
/// the database's cleanup path needs in order to be exercised.
Drive driveIntegerProperty(
  Libhegel session, {
  required Settings settings,
  int threshold = 50,
  int min = 0,
  int max = 1000,
  String origin = 'value above threshold',
}) => driveProperty(
  session,
  settings: settings,
  body: (TestCase testCase, List<int> draws) {
    final value = testCase.drawInteger(min: min, max: max);
    draws.add(value);
    if (value > threshold) {
      testCase.markComplete(TestCaseStatus.interesting, origin: origin);
    } else {
      testCase.markComplete(TestCaseStatus.valid);
    }
  },
);

/// Runs [body] over every test case the engine hands out, and reports what
/// happened.
///
/// [body] is expected to complete its test case. Running out of choice budget
/// is the driver's business rather than the caller's, so a [StopTest] escaping
/// [body] is caught and marked as an overrun -- which is also how a caller
/// deliberately drives the engine into overrunning, by drawing until it
/// refuses.
Drive driveProperty(
  Libhegel session, {
  required Settings settings,
  required void Function(TestCase testCase, List<int> draws) body,
}) {
  final draws = <int>[];
  var testCases = 0;
  final run = Run.start(settings, session: session);
  try {
    while (true) {
      final testCase = run.nextTestCase();
      if (testCase == null) break;
      testCases++;
      try {
        body(testCase, draws);
      } on StopTest {
        testCase.markComplete(TestCaseStatus.overrun);
      } finally {
        testCase.dispose();
      }
    }
    return Drive(result: run.result(), draws: draws, testCases: testCases);
  } finally {
    run.dispose();
  }
}
