/// Drives a property test through the libhegel bindings directly.
///
/// A port of the engine's own `echo.c`: draw an integer in range, check it is
/// in range, and report the run. It uses the internal bindings layer, since
/// the property-testing API those will support does not exist yet -- so this
/// shows what the bindings make possible, not what using hegel will look like.
///
///     dart run example/echo.dart
library;

import 'dart:io';

import 'package:hegel/src/libhegel/libhegel.dart';

void main() {
  final session = Libhegel.instance;
  stdout.writeln('libhegel ${session.engineVersion}');

  final run = Run.start(
    const Settings(
      testCases: 50,
      seed: 42,
      derandomize: true,
      database: Database.disabled,
      verbosity: Verbosity.quiet,
    ),
    onOutput: stderr.writeln,
  );

  var valid = 0;
  try {
    while (true) {
      final testCase = run.nextTestCase();
      if (testCase == null) break;
      try {
        final value = testCase.drawInteger(min: 0, max: 100);
        if (value < 0 || value > 100) {
          // The engine groups failures by origin, so it has to be stable.
          testCase.markComplete(
            TestCaseStatus.interesting,
            origin: 'echo: out of range',
          );
        } else {
          valid++;
          testCase.markComplete(TestCaseStatus.valid);
        }
      } on StopTest {
        // The engine ran out of budget mid-case: inconclusive, not a failure.
        testCase.markComplete(TestCaseStatus.overrun);
      } finally {
        // Every handle is freed exactly once, by whoever asked for it.
        testCase.dispose();
      }
    }

    final result = run.result();
    try {
      stdout.writeln('ran $valid valid test cases, ${result.status.name}');
      for (var i = 0; i < result.failureCount; i++) {
        final failure = result.failure(i);
        try {
          stdout.writeln('  failure: ${failure.origin}');
          stdout.writeln('  replay with: ${failure.reproductionBlob}');
        } finally {
          failure.dispose();
        }
      }
      if (result.status == RunStatus.error) {
        stderr.writeln('run error: ${result.error}');
      }
      exitCode = result.status == RunStatus.passed ? 0 : 1;
    } finally {
      result.dispose();
    }
  } finally {
    run.dispose();
  }
}
