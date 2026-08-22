/// The runner: the engine's loop, the outcome of each case, and the report a
/// failure turns into.
library;

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:test_api/hooks.dart';
import 'package:test_api/scaffolding.dart';

import '../libhegel/errors.dart';
import '../libhegel/run.dart';
import '../libhegel/run_result.dart';
import '../libhegel/session.dart';
import '../libhegel/settings.dart';
import '../libhegel/test_case.dart' as engine;
import 'config.dart';
import 'reporting.dart';
import 'test_case.dart';

/// Raised when a run reached no verdict about the property.
///
/// Not the same thing as the property failing, and deliberately not a test
/// failure: a health check that fired, a counterexample that no longer
/// reproduces, an engine that could not make sense of what it was asked. The
/// property might hold or might not; the run did not find out. package:test
/// renders anything that is not a test failure as an error rather than a
/// failure, which is the severity that fits.
final class PropertyError implements Exception {
  /// Creates an error reported as [message].
  PropertyError(this.message);

  /// What went wrong, in the engine's own words wherever they exist.
  final String message;

  @override
  String toString() => 'PropertyError: $message';
}

/// Checks [body] against test cases the engine chooses.
///
/// Returns normally when the property held. When it did not, the engine
/// shrinks the failing case to the smallest one that still fails, [body] runs
/// once more on it, and that run's error is rethrown with its own stack --
/// so an `expect` mismatch is reported by package:test exactly as it would be
/// in a test that failed directly, and a debugger stops where it always did.
///
/// [settings] configures the run; whatever it leaves out, the engine decides,
/// and whatever the environment sets overrides both (see [resolveSettings]).
/// [databaseKey] scopes the counterexamples this property stores and replays,
/// unless the settings already name one.
///
/// [reproduce] takes a blob from an earlier failure and replays exactly that
/// case: no generation, no shrinking, one run of the body. It is how a
/// failure found on a machine with no example database -- a CI job -- is
/// brought back to one that has a debugger. [printBlob] forces the hint that
/// prints those blobs on or off; left out, it prints whenever the
/// counterexample might not have been kept anywhere.
///
/// [onDiagnostic] receives the engine's output, line by line, and the failure
/// report as a block. Left out, both go to package:test's on-failure buffer
/// when there is a test to attach them to, and to stderr when there is not.
///
/// This is the whole runner. `property()` adds package:test to it and nothing
/// else, which is what keeps the two honest: a harness that is not
/// package:test can drive properties through here.
Future<void> runProperty(
  FutureOr<void> Function(TestCase) body, {
  Settings settings = const Settings(),
  String? databaseKey,
  String? reproduce,
  bool? printBlob,
  void Function(String line)? onDiagnostic,
}) async {
  final diagnostic = onDiagnostic ?? _defaultDiagnostic();
  final session = Libhegel.instance;
  final resolved = resolveSettings(
    settings,
    environment: Platform.environment,
    databaseKey: databaseKey,
  );
  if (reproduce != null) {
    return _reproduce(reproduce, body, resolved, session, diagnostic);
  }
  final run = Run.start(resolved, session: session, onOutput: diagnostic);
  // The case that first failed, kept for the runs that store no
  // counterexample to replay: with nothing to re-run, what it captured is the
  // only account of the failure there will ever be.
  _Outcome? discovered;
  try {
    while (true) {
      final engineCase = run.nextTestCase();
      if (engineCase == null) break;
      try {
        final testCase = TestCase(EngineDrawContext(engineCase));
        final outcome = await _runCase(testCase, body, diagnostic);
        if (outcome.status == engine.TestCaseStatus.interesting) {
          discovered ??= outcome;
        }
        engineCase.markComplete(outcome.status, origin: outcome.origin);
      } finally {
        engineCase.dispose();
      }
    }

    final result = run.result();
    try {
      switch (result.status) {
        case RunStatus.passed:
          return;
        case RunStatus.error:
          throw PropertyError(
            result.error ?? 'the run ended without saying why',
          );
        case RunStatus.failed:
        case RunStatus.failedNondeterministic:
          await _report(
            result,
            resolved,
            session,
            body,
            diagnostic,
            discovered,
            printBlob,
          );
      }
    } finally {
      result.dispose();
    }
  } finally {
    run.dispose();
  }
}

/// How one test case ended, in the terms the engine asks for.
final class _Outcome {
  _Outcome.completed(this.testCase) : error = null, stack = null;

  _Outcome.threw(this.testCase, this.error, this.stack);

  /// The case the body ran against, holding what it drew and noted.
  final TestCase testCase;

  /// What ended the case, or null if the body simply finished.
  final Object? error;

  /// Where [error] came from.
  final StackTrace? stack;

  /// The catch ladder: what the engine is told this case was.
  ///
  /// The two control-flow signals are not failures. An assumption that did
  /// not hold makes the case invalid, so it does not count and the engine
  /// generates away from it; running out of choice budget makes it an
  /// overrun, which the engine reads as "this case was too big to finish"
  /// rather than as anything about the property. Everything else is the
  /// property failing.
  engine.TestCaseStatus get status => switch (error) {
    null => engine.TestCaseStatus.valid,
    AssumptionFailed() => engine.TestCaseStatus.invalid,
    StopTest() => engine.TestCaseStatus.overrun,
    _ => engine.TestCaseStatus.interesting,
  };

  /// What the engine groups this failure under, or null if it is not one.
  String? get origin => status == engine.TestCaseStatus.interesting
      ? originOf(error!, stack!)
      : null;
}

/// Runs [body] over [testCase] in a zone that owns its stray async errors.
///
/// A future the body started and did not await would otherwise fail into the
/// enclosing test: it arrives with no case to blame, after the runner has
/// moved on, and with the engine still waiting to be told how this case
/// ended. The zone catches the first one and makes it the case's outcome
/// instead, which is what the body would have seen had it awaited.
///
/// One that arrives after the case is over is reported rather than
/// attributed. It cannot become this case's verdict -- that has been given --
/// and it must not become the next one's.
Future<_Outcome> _runCase(
  TestCase testCase,
  FutureOr<void> Function(TestCase) body,
  void Function(String line) diagnostic,
) {
  final ended = Completer<_Outcome>();
  runZonedGuarded(
    () async {
      try {
        await body(testCase);
        if (!ended.isCompleted) ended.complete(_Outcome.completed(testCase));
      } on Object catch (error, stack) {
        if (!ended.isCompleted) {
          ended.complete(_Outcome.threw(testCase, error, stack));
        }
      }
    },
    (Object error, StackTrace stack) {
      if (ended.isCompleted) {
        diagnostic('leaked async work escaped its test case: $error');
        diagnostic('$stack');
        return;
      }
      ended.complete(_Outcome.threw(testCase, error, stack));
    },
  );
  return ended.future;
}

/// Replays the minimal counterexample and raises what it did.
///
/// The engine hands back a blob rather than values: the shrunk choice
/// sequence, which only becomes a failure again by running the body over it.
/// That replay is also what makes the report readable -- it is the run whose
/// draws and notes are the minimal ones -- so it happens even though the
/// engine already knows the property failed.
///
/// A replay that does not fail the same way is reported rather than passed
/// off as the failure: the engine's contract leaves it to the caller to
/// decide whether the blob reproduced, and quietly reporting a stale one
/// would attach the wrong error to the right bug.
Future<Never> _report(
  RunResult result,
  Settings settings,
  Libhegel session,
  FutureOr<void> Function(TestCase) body,
  void Function(String line) diagnostic,
  _Outcome? discovered,
  bool? printBlob,
) async {
  final failure = result.failure(0);
  try {
    final origin = failure.origin;
    final blob = failure.reproductionBlob;
    if (blob == null) {
      // Two runs store nothing to replay: one that produced a single test
      // case, which never shrinks, and one declared nondeterministic, which
      // has nothing to shrink toward. Both leave the discovering case as the
      // only account of the failure, which is what the engine's own
      // documentation says to report from.
      if (discovered == null) {
        throw PropertyError(
          'the property failed at $origin, and the run kept nothing that '
          'says how',
        );
      }
      _describe(discovered.testCase, settings, diagnostic);
      Error.throwWithStackTrace(discovered.error!, discovered.stack!);
    }

    final replayCase = engine.TestCase.fromBlob(
      settings,
      blob,
      session: session,
    );
    final _Outcome outcome;
    try {
      // Not marked complete: a case from a blob belongs to no run, so there
      // is nothing waiting to be told how it ended.
      outcome = await _runCase(
        TestCase(EngineDrawContext(replayCase)),
        body,
        diagnostic,
      );
    } finally {
      replayCase.dispose();
    }

    // Before raising, so that package:test has the counterexample in hand by
    // the time it prints the failure.
    _describe(
      outcome.testCase,
      settings,
      diagnostic,
      blob: blob,
      printBlob: printBlob,
    );
    raiseReplayed(origin: origin, error: outcome.error, stack: outcome.stack);
  } finally {
    failure.dispose();
  }
}

/// Reports what [testCase] drew and noted, and how to get it back.
///
/// Only ever the minimal case: the one the engine shrank to and the runner
/// replayed, or -- where nothing was stored to replay -- the one that
/// discovered the failure. Every other case the property tried is noise.
void _describe(
  TestCase testCase,
  Settings settings,
  void Function(String line) diagnostic, {
  String? blob,
  bool? printBlob,
}) => diagnostic(
  renderFailure(
    draws: testCase.draws,
    notes: testCase.notes,
    hints: reproductionHints(settings, blob: blob, printBlob: printBlob),
  ),
);

/// Replays exactly the case [blob] encodes, and reports what it did.
///
/// No run and no loop: the blob is already the minimal case, so the body runs
/// over it once and whatever it does is the answer. A case that no longer
/// fails is not an error -- it is what a fixed bug looks like from here --
/// but a blob the body no longer fits is, because then nothing was checked.
Future<void> _reproduce(
  String blob,
  FutureOr<void> Function(TestCase) body,
  Settings settings,
  Libhegel session,
  void Function(String line) diagnostic,
) async {
  final engine.TestCase replayCase;
  try {
    replayCase = engine.TestCase.fromBlob(settings, blob, session: session);
  } on HegelException catch (error) {
    throw PropertyError(
      'the blob given to reproduce could not be read: ${error.message}',
    );
  }
  final _Outcome outcome;
  try {
    outcome = await _runCase(
      TestCase(EngineDrawContext(replayCase)),
      body,
      diagnostic,
    );
  } finally {
    replayCase.dispose();
  }

  // Whatever happened: someone who asked for one case asked to see it.
  _describe(outcome.testCase, settings, diagnostic);
  switch (outcome.error) {
    case null:
      return;
    case StopTest():
      throw PropertyError(
        'the blob given to reproduce ran out of choices; the body drew more '
        'than it holds, so it was recorded from a different property or from '
        'an older version of this one',
      );
    case AssumptionFailed():
      throw PropertyError(
        'the blob given to reproduce was rejected as invalid; the body '
        'assumed something the recorded case does not satisfy',
      );
    case final Object error:
      Error.throwWithStackTrace(error, outcome.stack!);
  }
}

/// Raises whatever replaying the counterexample for [origin] amounts to.
///
/// The replay failing the same way is the ordinary case, and then [error] is
/// the property's own failure and is raised as it stands. The other three
/// endings all mean the same thing -- the stored case is no longer the
/// failure it was recorded as -- and differ only in what the body did
/// instead, which is the part worth saying: a body that did not fail, one
/// that rejected the case, and one that drew past what was stored are three
/// different mistakes.
///
/// Separated from the run so that the four endings can be checked directly.
/// Three of them need a body that changes its mind between the run and the
/// replay, and the engine catches a body that changes its mind *during* a
/// run, so there is no run that produces them on request.
@visibleForTesting
Never raiseReplayed({
  required String origin,
  required Object? error,
  required StackTrace? stack,
}) {
  switch (error) {
    case null:
      throw PropertyError(
        'the property failed at $origin, but replaying its counterexample '
        'did not fail again; a property that does not fail the same way '
        'twice usually depends on something it did not draw',
      );
    case StopTest():
      throw PropertyError(
        'the property failed at $origin, but replaying its counterexample '
        'ran out of choices; the body drew more than was stored, so the '
        'counterexample no longer matches its generators',
      );
    case AssumptionFailed():
      throw PropertyError(
        'the property failed at $origin, but replaying its counterexample '
        'rejected it as invalid; the body assumed differently on the replay',
      );
    case final Object failure:
      Error.throwWithStackTrace(failure, stack!);
  }
}

/// Where diagnostics go when the caller does not say.
///
/// Inside a test, package:test's own on-failure buffer: lines are kept and
/// shown if the test fails and dropped if it passes, which is what makes a
/// property that holds silent without the runner having to decide what was
/// interesting. Outside one -- a script, a soak run, a `dart run` -- there is
/// nothing to buffer against, so they go where the engine's own output would.
void Function(String line) _defaultDiagnostic() {
  try {
    TestHandle.current;
  } on OutsideTestException {
    return stderr.writeln;
  }
  return printOnFailure;
}
