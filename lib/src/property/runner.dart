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
  final session = Libhegel.instance;
  final resolved = resolveSettings(
    settings,
    environment: Platform.environment,
    databaseKey: databaseKey,
  );
  // After resolution, because where the default sink sends a line depends on
  // how much the run was asked to say -- and the environment gets to change
  // that as much as the settings do.
  final diagnostic = onDiagnostic ?? defaultDiagnostic(resolved);
  if (reproduce != null) {
    return _reproduce(reproduce, body, resolved, session, diagnostic);
  }
  final run = Run.start(resolved, session: session, onOutput: diagnostic);
  // The case that first failed under each origin, kept for the runs that
  // store no counterexample to replay: with nothing to re-run, what it
  // captured is the only account of that failure there will ever be. Keyed by
  // origin because the engine reports one failure per origin, and the account
  // of one bug is no account at all of another.
  final discovered = <String, _Outcome>{};
  try {
    while (true) {
      final engineCase = run.nextTestCase();
      if (engineCase == null) break;
      try {
        final testCase = TestCase(EngineDrawContext(engineCase));
        final outcome = await _runCase(testCase, body);
        if (outcome.status == engine.TestCaseStatus.interesting) {
          discovered.putIfAbsent(outcome.origin!, () => outcome);
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
/// The first error wins, whichever way it arrives, because the case has to
/// end for the run to go on. Whatever comes second is registered rather than
/// dropped: a stray error and the property's own failure are both real, and
/// silently keeping one of them would report the wrong bug at the wrong
/// place -- the origin is derived from whichever error is kept, so the engine
/// would then shrink toward a site the property never failed at.
Future<_Outcome> _runCase(
  TestCase testCase,
  FutureOr<void> Function(TestCase) body,
) {
  final ended = Completer<_Outcome>();
  // The zone the run is happening in, kept because a late error has to be
  // reported *outside* the guard below. Reported from inside it, the report
  // is itself an uncaught error in the guarded zone, and comes back around
  // wrapped in a second explanation of the same thing.
  final host = Zone.current;
  runZonedGuarded(
    () async {
      try {
        await body(testCase);
        if (!ended.isCompleted) ended.complete(_Outcome.completed(testCase));
      } on Object catch (error, stack) {
        if (ended.isCompleted) {
          _registerLate(
            host,
            'the body failed after its case had ended',
            error,
            stack,
          );
        } else {
          ended.complete(_Outcome.threw(testCase, error, stack));
        }
      }
    },
    (Object error, StackTrace stack) {
      if (ended.isCompleted) {
        _registerLate(
          host,
          'leaked async work escaped its test case',
          error,
          stack,
        );
        return;
      }
      ended.complete(_Outcome.threw(testCase, error, stack));
    },
  );
  return ended.future;
}

/// Reports an error that arrived too late to be its case's verdict.
///
/// The case has one outcome and the engine has already been told it, so this
/// cannot become one -- and it must not become the next case's either. It
/// goes where package:test sends a stray error in any ordinary test:
/// attributed to the running test, loud enough to fail it, and never
/// silently buffered. Outside a test it reaches whatever zone the caller is
/// running in, which is the same promise by a different name.
///
/// The error's own stack is kept, since that is what says where the work
/// that escaped came from; the message says why it could not be the verdict.
/// Reported in [host] -- the zone the run itself is in -- so that it does not
/// arrive back at the guard it came from.
void _registerLate(Zone host, String what, Object error, StackTrace stack) =>
    host.run(() => registerException(PropertyError('$what: $error'), stack));

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
  Map<String, _Outcome> discovered,
  bool? printBlob,
) async {
  final origins = <String>[];
  final failures = <({Object error, StackTrace stack})>[];
  final count = result.failureCount;
  for (var index = 0; index < count; index++) {
    final failure = result.failure(index);
    try {
      final origin = failure.origin;
      origins.add(origin);
      // Named only when there is more than one, because a heading over the
      // only block there is says nothing the error above it did not.
      final heading = count > 1 ? origin : null;
      final blob = failure.reproductionBlob;
      if (blob == null) {
        // Two runs store nothing to replay: one that produced a single test
        // case, which never shrinks, and one declared nondeterministic, which
        // has nothing to shrink toward. Both leave the discovering case as the
        // only account of the failure, which is what the engine's own
        // documentation says to report from.
        final found = discovered[origin];
        if (found == null) {
          failures.add((
            error: PropertyError(
              'the property failed at $origin, and the run kept nothing that '
              'says how',
            ),
            stack: StackTrace.current,
          ));
          continue;
        }
        // Nothing was stored, so nothing will be replayed, and saying
        // otherwise would send the reader back to a database that has never
        // heard of this failure.
        _describe(
          found.testCase,
          settings,
          diagnostic,
          stored: false,
          heading: heading,
        );
        failures.add((error: found.error!, stack: found.stack!));
        continue;
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
        outcome = await _runCase(TestCase(EngineDrawContext(replayCase)), body);
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
        heading: heading,
      );
      failures.add(
        replayedFailure(
          origin: origin,
          error: outcome.error,
          stack: outcome.stack,
        ),
      );
    } finally {
      failure.dispose();
    }
  }

  if (failures.isEmpty) {
    // The engine said the property failed and then listed nothing that did.
    // Not reachable through any run this package can produce, and reported
    // rather than left to fall out of `first` on an empty list, because a
    // range error out of the reporter would say nothing about the property.
    throw PropertyError('the run reported a failure and then named none');
  }
  if (origins.length > 1) diagnostic(renderOrigins(origins));

  // Every failure after the first goes through package:test's own channel for
  // an error that is not the one being thrown. Registered before the throw
  // rather than after, there being no after: the throw is where this function
  // ends. The first is raised as it stands so that an `expect` mismatch is
  // rendered by package:test the way it renders every other one, and a
  // debugger stops where the assertion is.
  for (final extra in failures.skip(1)) {
    registerException(extra.error, extra.stack);
  }
  Error.throwWithStackTrace(failures.first.error, failures.first.stack);
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
  bool stored = true,
  String? heading,
}) => diagnostic(
  renderFailure(
    draws: testCase.draws,
    notes: testCase.notes,
    hints: reproductionHints(
      settings,
      blob: blob,
      printBlob: printBlob,
      stored: stored,
    ),
    heading: heading,
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
  } on ArgumentError catch (error) {
    // Refused while marshalling, before the engine sees it: an interior NUL
    // or a stranded surrogate, which is what a blob copied out of a
    // truncated or re-encoded log looks like. The same complaint as above
    // from the reader's point of view, so it is reported the same way.
    throw PropertyError(
      'the blob given to reproduce could not be read: ${error.message}',
    );
  }
  final _Outcome outcome;
  try {
    outcome = await _runCase(TestCase(EngineDrawContext(replayCase)), body);
  } finally {
    replayCase.dispose();
  }

  // There was no run, so there is no database line to give: nothing was
  // stored, and whoever passed a blob has the blob already. What is left is
  // what the case drew and what the body said about it -- which the default
  // sink still only shows if the replay failed, since a case that held is
  // not news.
  _describe(outcome.testCase, settings, diagnostic, stored: false);
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
  final replayed = replayedFailure(origin: origin, error: error, stack: stack);
  Error.throwWithStackTrace(replayed.error, replayed.stack);
}

/// [raiseReplayed], as a value rather than as a throw.
///
/// What a run with more than one distinct failure needs: only the first of
/// them is thrown, and the rest are handed to package:test as errors that
/// belong to this test without being the one that ended it. Deciding what a
/// replay amounted to and raising it are therefore two steps, and this is the
/// first -- the same decision either way, so the two cannot come apart.
///
/// The stack for a replay that failed is the failure's own. For the three
/// endings that produce a [PropertyError] there is no such stack, so it is
/// taken here, which is where the explanation is written.
({Object error, StackTrace stack}) replayedFailure({
  required String origin,
  required Object? error,
  required StackTrace? stack,
}) {
  switch (error) {
    case null:
      return (
        error: PropertyError(
          'the property failed at $origin, but replaying its counterexample '
          'did not fail again; a property that does not fail the same way '
          'twice usually depends on something it did not draw',
        ),
        stack: StackTrace.current,
      );
    case StopTest():
      return (
        error: PropertyError(
          'the property failed at $origin, but replaying its counterexample '
          'ran out of choices; the body drew more than was stored, so the '
          'counterexample no longer matches its generators',
        ),
        stack: StackTrace.current,
      );
    case AssumptionFailed():
      return (
        error: PropertyError(
          'the property failed at $origin, but replaying its counterexample '
          'rejected it as invalid; the body assumed differently on the replay',
        ),
        stack: StackTrace.current,
      );
    case final Object failure:
      return (error: failure, stack: stack!);
  }
}

/// Where diagnostics go when the caller does not say.
///
/// Inside a test, package:test's own on-failure buffer: lines are kept and
/// shown if the test fails and dropped if it passes, which is what makes a
/// property that holds silent without the runner having to decide what was
/// interesting. Outside one -- a script, a soak run, a `dart run` -- there is
/// nothing to buffer against, so they go where the engine's own output would.
///
/// Verbosity changes the answer. Someone who asked the engine for per-case
/// progress asked to watch a run happen, and a buffer shown only if the run
/// fails is the opposite of that: the run they were most likely watching is
/// the one that holds, and it would print nothing at all. So from
/// [Verbosity.verbose] up the lines go out as they arrive. The failure block
/// goes the same way, since it is the same sink; a verbose run is one where
/// being noisy is the point.
@visibleForTesting
void Function(String line) defaultDiagnostic(Settings settings) {
  try {
    TestHandle.current;
  } on OutsideTestException {
    return stderr.writeln;
  }
  return switch (settings.verbosity) {
    // Null is the engine deciding, and it decides on a summary line per run,
    // which is not somebody watching.
    Verbosity.verbose || Verbosity.debug => print,
    _ => printOnFailure,
  };
}
