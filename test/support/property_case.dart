/// Drives the public test-case handle over a real run.
///
/// How a generator is exercised the way a property will exercise it, without
/// a property in the way: a whole run of the engine's own choosing, one public
/// handle per case, rather than a single hand-made draw. A generator that
/// holds on the first case and not the fiftieth is the failure mode worth
/// catching, and only a run catches it. What a property concludes about those
/// values is the runner's business, and tested there.
library;

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/test_case.dart' as engine;
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/test_case.dart';

import 'property_driver.dart';

/// Settings for a run whose only job is to hand out test cases.
///
/// Seeded and derandomized so that what the engine tries is the same on every
/// machine and every run: an assertion about what a generator produced is
/// only worth making if it is the same question each time it is asked.
Settings caseSettings({int testCases = 100, int seed = 42}) => Settings(
  testCases: testCases,
  seed: seed,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: machineSpeedChecks,
);

/// Runs [body] once per test case of a whole run, on a fresh public handle.
///
/// A case is reported valid unless a draw rejected it, which is what the
/// runner does with one: these runs are about what generators do, not about
/// what a property concludes, and a filter that did not land in three tries
/// is the generator working rather than the test failing.
void driveCases(
  Libhegel session,
  void Function(TestCase testCase) body, {
  int testCases = 100,
  int seed = 42,
}) {
  final run = Run.start(
    caseSettings(testCases: testCases, seed: seed),
    session: session,
  );
  try {
    while (true) {
      final engineCase = run.nextTestCase();
      if (engineCase == null) break;
      try {
        body(TestCase(EngineDrawContext(engineCase)));
        engineCase.markComplete(engine.TestCaseStatus.valid);
      } on AssumptionFailed {
        engineCase.markComplete(engine.TestCaseStatus.invalid);
      } finally {
        engineCase.dispose();
      }
    }
    run.result().dispose();
  } finally {
    run.dispose();
  }
}

/// Every value [generator] produced across a whole run, in order.
///
/// Cases the generator rejected produce nothing, so this can be shorter than
/// the number of cases asked for.
List<T> drawEveryCase<T>(
  Libhegel session,
  Generator<T> generator, {
  int testCases = 100,
  int seed = 42,
}) {
  final values = <T>[];
  driveCases(
    session,
    (TestCase testCase) => values.add(testCase.draw(generator)),
    testCases: testCases,
    seed: seed,
  );
  return values;
}
