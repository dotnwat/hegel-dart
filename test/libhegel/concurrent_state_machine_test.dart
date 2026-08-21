@TestOn('vm')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:async/async.dart';

import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/pool.dart';
import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/state_machine.dart';
import 'package:hegel/src/libhegel/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

const List<String> rules = <String>['acquire', 'release'];

/// What a worker isolate needs to join a running machine.
///
/// Every field crosses isolates on its own: the handles travel as plain
/// addresses, and nothing here owns anything.
class WorkerSetup {
  WorkerSetup({
    required this.workerIndex,
    required this.concurrency,
    required this.caseAddress,
    required this.machineAddress,
    required this.poolAddress,
    required this.toCoordinator,
  });

  final int workerIndex;
  final int concurrency;
  final int caseAddress;
  final int machineAddress;
  final int poolAddress;
  final SendPort toCoordinator;
}

/// Pulls rules for one worker until the coordinator says to stop.
///
/// Each worker opens its own session, because a context may not be shared
/// between threads, and borrows the case clone and machine it was given.
Future<void> runWorker(WorkerSetup setup) async {
  final session = Libhegel.open();
  final workerCase = TestCase.adopt(session, HandleToken(setup.caseAddress));
  final machine = StateMachine.adopt(
    session,
    HandleToken(setup.machineAddress),
    setup.concurrency,
  );
  // A pool may legitimately be driven from several workers: the ABI
  // serializes operations on it rather than reporting contention.
  final pool = Pool.adopt(session, HandleToken(setup.poolAddress));

  final commands = ReceivePort();
  setup.toCoordinator.send(commands.sendPort);

  var produced = false;
  await for (final Object? command in commands) {
    if (command == 'stop') break;
    final applied = <int>[];
    try {
      while (true) {
        final rule = machine.nextRule(workerCase, setup.workerIndex);
        if (rule == null) break;
        applied.add(rule);
        // Rule 0 produces a value; rule 1 reads one back.
        //
        // The precondition is checked here rather than by letting the engine
        // reject an empty pool. An engine-side rejection raises
        // AssumptionFailed, which latches and ends the whole case -- correctly
        // so, since a failed assumption means the case is invalid. Reporting
        // the rule rejected is the mechanism for a precondition the caller can
        // see, and it only works if nothing has aborted the case first.
        if (rule == 0) {
          pool.add(workerCase);
          produced = true;
        } else if (produced) {
          // Never consumed, so once anything is in the pool a read is safe
          // whichever worker gets there first.
          pool.draw(workerCase);
        } else {
          machine.ruleRejected(workerCase, setup.workerIndex);
          applied.removeLast();
        }
      }
    } on Object catch (error) {
      setup.toCoordinator.send(<Object>['error', setup.workerIndex, '$error']);
      continue;
    }
    // Tagged with who ran them. Replies from separate isolates arrive in
    // whatever order they finish, so arrival order says nothing about which
    // worker produced a result.
    setup.toCoordinator.send(<Object>['applied', setup.workerIndex, applied]);
  }

  commands.close();
  session.dispose();
}

void main() {
  late Libhegel session;

  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  // The engine refuses the first concurrent machine on a run, flips the run to
  // nondeterministic at that case's end, and allows it from the next case on.
  test(
    'the first concurrent machine on a run is refused, then allowed',
    () async {
      final run = Run.start(
        const Settings(
          testCases: 4,
          seed: 61,
          derandomize: true,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
          statefulStepCount: 4,
          suppressHealthChecks: machineSpeedChecks,
        ),
        session: session,
      );
      addTearDown(run.dispose);

      var refusals = 0;
      var accepted = 0;
      final nondeterministicFlags = <bool>[];

      while (true) {
        final rootCase = run.nextTestCase();
        if (rootCase == null) break;
        nondeterministicFlags.add(rootCase.isNondeterministic);
        try {
          final machine = rootCase.newStateMachine(
            ruleNames: rules,
            minConcurrency: 2,
            maxConcurrency: 2,
          );
          accepted++;
          machine.dispose();
          rootCase.markComplete(TestCaseStatus.valid);
        } on AssumptionFailed {
          // The documented handshake: abandon the body and report the case
          // invalid; the engine flips the run at this case's end.
          refusals++;
          rootCase.markComplete(TestCaseStatus.invalid);
        } finally {
          rootCase.dispose();
        }
      }

      expect(refusals, 1, reason: 'only the first creation is refused');
      expect(accepted, greaterThan(0), reason: 'later cases are allowed');
      expect(nondeterministicFlags.first, isFalse);
      expect(
        nondeterministicFlags.skip(1),
        everyElement(isTrue),
        reason: 'every case after the flip is marked up front',
      );
    },
  );

  test('two worker isolates pull rules from their own clone streams', () async {
    final run = Run.start(
      const Settings(
        testCases: 3,
        seed: 67,
        derandomize: true,
        database: Database.disabled,
        verbosity: Verbosity.quiet,
        statefulStepCount: 6,
        suppressHealthChecks: machineSpeedChecks,
      ),
      session: session,
    );
    addTearDown(run.dispose);

    final appliedPerWorker = <int, List<int>>{0: <int>[], 1: <int>[]};
    var concurrentCases = 0;
    var rounds = 0;

    while (true) {
      final rootCase = run.nextTestCase();
      if (rootCase == null) break;

      final StateMachine machine;
      try {
        machine = rootCase.newStateMachine(
          ruleNames: rules,
          minConcurrency: 2,
          maxConcurrency: 2,
        );
      } on AssumptionFailed {
        rootCase
          ..markComplete(TestCaseStatus.invalid)
          ..dispose();
        continue;
      }

      concurrentCases++;
      expect(machine.concurrency, 2);

      // One clone per worker, made and owned here. A handle may be driven by
      // one thread at a time, so workers must not share the root.
      final clones = <TestCase>[
        for (var i = 0; i < machine.concurrency; i++) rootCase.clone(),
      ];
      final pool = rootCase.newPool();
      final fromWorkers = ReceivePort();
      final replies = StreamQueue<Object?>(fromWorkers);
      final isolates = <Isolate>[];
      final commandPorts = <SendPort>[];

      try {
        for (var i = 0; i < machine.concurrency; i++) {
          isolates.add(
            await Isolate.spawn(
              runWorker,
              WorkerSetup(
                workerIndex: i,
                concurrency: machine.concurrency,
                caseAddress: clones[i].token.address,
                machineAddress: machine.token.address,
                poolAddress: pool.token.address,
                toCoordinator: fromWorkers.sendPort,
              ),
            ),
          );
        }
        for (var i = 0; i < machine.concurrency; i++) {
          commandPorts.add(await replies.next as SendPort);
        }

        // Rounds are driven from the root handle; workers pull within a round
        // and the coordinator advances the group at each join point.
        while (machine.nextGroup(rootCase) != null) {
          rounds++;
          for (final port in commandPorts) {
            port.send('round');
          }
          for (var i = 0; i < commandPorts.length; i++) {
            final reply = (await replies.next)! as List<Object?>;
            expect(reply.first, 'applied', reason: 'a worker reported: $reply');
            // Credited to the worker that reported it, never to the position
            // the reply happened to arrive in.
            final reporter = reply[1]! as int;
            appliedPerWorker[reporter]!.addAll(
              (reply[2]! as List<Object?>).cast<int>(),
            );
          }
        }

        for (final port in commandPorts) {
          port.send('stop');
        }
        rootCase.markComplete(TestCaseStatus.valid);
      } finally {
        for (final isolate in isolates) {
          isolate.kill(priority: Isolate.beforeNextEvent);
        }
        await replies.cancel(immediate: true);
        // The coordinator owns every handle and frees them only once the
        // workers are done with them.
        for (final clone in clones) {
          clone.dispose();
        }
        pool.dispose();
        machine.dispose();
        rootCase.dispose();
      }
    }

    final result = run.result();
    addTearDown(result.dispose);

    expect(concurrentCases, greaterThan(0));
    expect(rounds, greaterThan(0), reason: 'the machine ran rounds');
    final total = appliedPerWorker.values
        .expand((List<int> applied) => applied)
        .toList();
    expect(total, isNotEmpty, reason: 'workers applied rules');
    expect(
      total,
      everyElement(allOf(greaterThanOrEqualTo(0), lessThan(rules.length))),
    );
    // Worker index 1 exists and is used, not just index 0. This is only
    // meaningful because replies are credited by reported index; keyed by
    // arrival order it would have passed whatever the workers did.
    expect(appliedPerWorker[0], isNotEmpty);
    expect(appliedPerWorker[1], isNotEmpty);
    expect(result.status, isNot(RunStatus.error));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'a failure on a nondeterministic run carries no reproduce blob',
    () async {
      final run = Run.start(
        const Settings(
          testCases: 6,
          seed: 71,
          derandomize: true,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
          statefulStepCount: 3,
          suppressHealthChecks: machineSpeedChecks,
        ),
        session: session,
      );
      addTearDown(run.dispose);

      while (true) {
        final rootCase = run.nextTestCase();
        if (rootCase == null) break;
        try {
          final machine = rootCase.newStateMachine(
            ruleNames: rules,
            minConcurrency: 2,
            maxConcurrency: 2,
          );
          machine.dispose();
          // Once the run is nondeterministic, report a failure from the
          // discovering case: there is no shrinking and no replay.
          rootCase.markComplete(
            TestCaseStatus.interesting,
            origin: 'concurrent: reported from the discovering case',
          );
        } on AssumptionFailed {
          rootCase.markComplete(TestCaseStatus.invalid);
        } finally {
          rootCase.dispose();
        }
      }

      final result = run.result();
      addTearDown(result.dispose);

      expect(result.status, RunStatus.failedNondeterministic);
      expect(result.failureCount, greaterThan(0));
      final failure = result.failure(0);
      addTearDown(failure.dispose);
      expect(failure.origin, contains('discovering case'));
      // No shrinking and no final replay happened, so there is nothing to
      // replay from; the caller reports what it captured while running.
      expect(failure.reproductionBlob, isNull);
    },
  );
}
