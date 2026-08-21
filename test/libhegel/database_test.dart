@TestOn('vm')
library;

import 'dart:io';

import 'package:hegel/src/libhegel/run_result.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

/// The value the shared property shrinks to at the default threshold.
///
/// Pinned rather than read back from the run so that a test comparing a later
/// run against it is comparing against a constant, not against whatever the
/// engine happened to do twice.
const int shrunkAtDefaultThreshold = 51;

Settings settingsFor({
  required int seed,
  required Database database,
  String? key = 'database-test',
  Set<Phase>? phases,
}) => Settings(
  testCases: 100,
  seed: seed,
  derandomize: true,
  database: database,
  databaseKey: key,
  phases: phases,
  verbosity: Verbosity.quiet,
  suppressHealthChecks: everyHealthCheck,
);

int entriesIn(Directory directory) => directory.existsSync()
    ? directory.listSync(recursive: true).whereType<File>().length
    : 0;

void main() {
  late Libhegel session;
  setUp(() => session = Libhegel.open());
  tearDown(() => session.dispose());

  Directory scratch() {
    final directory = Directory.systemTemp.createTempSync('hegel-database');
    addTearDown(() => directory.deleteSync(recursive: true));
    return directory;
  }

  Drive run({
    required int seed,
    required Database database,
    String? key = 'database-test',
    Set<Phase>? phases,
    int threshold = 50,
    Libhegel? on,
  }) {
    final drive = driveIntegerProperty(
      on ?? session,
      settings: settingsFor(
        seed: seed,
        database: database,
        key: key,
        phases: phases,
      ),
      threshold: threshold,
    );
    addTearDown(drive.result.dispose);
    return drive;
  }

  group('a discovered counterexample', () {
    test('is written to disk and replayed ahead of anything generated', () {
      final directory = scratch();

      final discovery = run(seed: 3, database: Database.at(directory.path));
      expect(discovery.result.status, RunStatus.failed);
      expect(discovery.draws.last, shrunkAtDefaultThreshold);
      expect(
        entriesIn(directory),
        greaterThan(0),
        reason: 'the failure should have been persisted',
      );

      // A different seed from the run that stored it, so replaying and
      // regenerating cannot be confused for one another.
      final replay = run(seed: 999, database: Database.at(directory.path));
      expect(replay.draws.first, shrunkAtDefaultThreshold);
      expect(
        replay.testCases,
        1,
        reason: 'the stored case should fail immediately, ending the run',
      );

      // The control is what makes the assertion above mean anything: on this
      // same seed, with nothing to replay, the engine opens somewhere else.
      final control = run(seed: 999, database: Database.disabled);
      expect(control.draws.first, isNot(shrunkAtDefaultThreshold));
      expect(control.testCases, greaterThan(1));
    });

    test('replays into a session that never saw the failure', () {
      final directory = scratch();
      final discovery = run(seed: 3, database: Database.at(directory.path));

      // Everything the engine learned in memory goes away here; only the
      // directory survives. A result may not outlive the session that
      // produced it, so it goes first -- the registered teardown then finds
      // it already disposed and does nothing.
      discovery.result.dispose();
      session.dispose();
      session = Libhegel.open();

      final replay = run(seed: 999, database: Database.at(directory.path));
      expect(replay.draws.first, shrunkAtDefaultThreshold);
      expect(replay.testCases, 1);
    });
  });

  group('the reuse phase', () {
    // Everything except reuse, so that adding it back is the only difference
    // between the two runs below.
    const Set<Phase> withoutReuse = <Phase>{
      Phase.explicit,
      Phase.generate,
      Phase.target,
      Phase.shrink,
    };

    test('is what turns a stored counterexample back into a test case', () {
      final directory = scratch();
      run(seed: 3, database: Database.at(directory.path));

      final skipped = run(
        seed: 999,
        database: Database.at(directory.path),
        phases: withoutReuse,
      );
      expect(
        skipped.draws.first,
        isNot(shrunkAtDefaultThreshold),
        reason: 'with reuse off there is nothing to replay from',
      );

      final replay = run(
        seed: 999,
        database: Database.at(directory.path),
        phases: <Phase>{...withoutReuse, Phase.reuse},
      );
      expect(replay.draws.first, shrunkAtDefaultThreshold);
      expect(replay.testCases, 1);
    });

    test('paired with shrink alone replays without generating anything', () {
      final directory = scratch();
      run(seed: 3, database: Database.at(directory.path));

      // The shape a "rerun just the known failures" mode would take.
      final replayOnly = run(
        seed: 999,
        database: Database.at(directory.path),
        phases: <Phase>{Phase.reuse, Phase.shrink},
      );
      expect(replayOnly.draws, <int>[shrunkAtDefaultThreshold]);
      expect(replayOnly.result.status, RunStatus.failed);
    });
  });

  group('a counterexample that no longer fails', () {
    test('is replayed once and then dropped from the database', () {
      final directory = scratch();
      run(seed: 3, database: Database.at(directory.path));
      expect(entriesIn(directory), greaterThan(0));

      // Standing in for the bug being fixed: nothing in range can exceed
      // this threshold, so the replayed case now passes.
      final fixed = run(
        seed: 7,
        database: Database.at(directory.path),
        threshold: 1000,
      );
      expect(
        fixed.draws.first,
        shrunkAtDefaultThreshold,
        reason: 'the stored case should still be tried first',
      );
      expect(fixed.result.status, RunStatus.passed);
      expect(
        entriesIn(directory),
        0,
        reason: 'an example that stopped failing should not be kept forever',
      );

      // Otherwise a fixed bug would go on costing a replay on every run.
      final later = run(
        seed: 11,
        database: Database.at(directory.path),
        threshold: 1000,
      );
      expect(later.draws.first, isNot(shrunkAtDefaultThreshold));
    });
  });

  group('the database key', () {
    test('scopes entries so one directory can hold several properties', () {
      final directory = scratch();
      run(seed: 3, database: Database.at(directory.path), key: 'alpha');

      final beta = run(
        seed: 999,
        database: Database.at(directory.path),
        key: 'beta',
      );
      expect(
        beta.draws.first,
        isNot(shrunkAtDefaultThreshold),
        reason: "beta must not see alpha's counterexample",
      );
      expect(beta.testCases, greaterThan(1));

      // Without this the test would also pass against a database that simply
      // stored nothing: alpha's entry is still there, in the same directory
      // beta just read from.
      final alpha = run(
        seed: 999,
        database: Database.at(directory.path),
        key: 'alpha',
      );
      expect(alpha.draws.first, shrunkAtDefaultThreshold);
      expect(alpha.testCases, 1);
    });

    test('may be empty, which is a key and not a request for no database', () {
      final directory = scratch();
      final discovery = run(
        seed: 3,
        database: Database.at(directory.path),
        key: '',
      );
      expect(entriesIn(directory), greaterThan(0));

      final replay = run(
        seed: 999,
        database: Database.at(directory.path),
        key: '',
      );
      expect(replay.draws.first, discovery.draws.last);
      expect(replay.testCases, 1);
    });
  });
}
