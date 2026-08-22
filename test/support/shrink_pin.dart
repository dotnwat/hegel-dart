/// Runs a property that must fail, and hands back what its report said.
///
/// A generator with a missing or misplaced span still draws values in range
/// and still finds bugs; what it loses is the shrinker's ability to take a
/// value apart, and the only place that loss shows is the counterexample
/// finally reported. So these tests assert exact values -- `[0, 0]`, `52` --
/// rather than "something small", which is the assertion a degraded shrink
/// would still pass.
///
/// A value that is a single draw shrinks to its minimum either way; the
/// engine does not need a span to walk one integer down. What these pins say
/// about such a value is that the shrunk case is genuinely the smallest one
/// the generator can produce that still fails -- that a filter, say, did not
/// report a value it was meant to have filtered out. The pins that bite on
/// span placement are the ones over values with parts.
///
/// Pinned values belong to an engine version. A bump that changes one is not
/// automatically a regression, but it is always a review question, and the
/// diff on this file is the evidence.
library;

import 'dart:async';

import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import 'property_driver.dart';

/// Settings for a run whose counterexample is going to be pinned.
///
/// Seeded, derandomized, and with no database, so that the run is the same
/// one on every machine and is not quietly replaying an earlier answer.
Settings pinSettings({int testCases = 100, int seed = 5}) => Settings(
  testCases: testCases,
  seed: seed,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: machineSpeedChecks,
);

/// The block [body] printed about the case it finally failed on.
///
/// The failure itself is dropped: a pin is about which case the engine
/// settled on, and the report is where the shrunk case is written down.
Future<String> shrunkReport(
  FutureOr<void> Function(TestCase) body, {
  int testCases = 100,
  int seed = 5,
}) async {
  final said = <String>[];
  try {
    await runProperty(
      body,
      settings: pinSettings(testCases: testCases, seed: seed),
      onDiagnostic: said.add,
    );
  } on Object {
    return said.single;
  }
  fail('the property was meant to fail, so there is no shrunk case to pin');
}
