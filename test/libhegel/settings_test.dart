@TestOn('vm')
library;

import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/version.g.dart';
import 'package:test/test.dart';

import '../support/fake_bindings.dart';
import '../support/property_driver.dart';

/// Names of the setter calls a fake saw, in order.
List<String> settersCalledFor(Settings settings) {
  final fake = FakeBindings()
    ..onCall = (String name, Invocation invocation) {
      if (name == 'hegel_version') {
        writeVersion(invocation, libhegelVersion);
      }
    };
  final session = Libhegel.open(fake);
  try {
    settings.withNative(session, (_) => null);
  } finally {
    session.dispose();
  }
  return fake.calls
      .where((String name) => name.startsWith('hegel_settings_set_'))
      .toList();
}

void main() {
  group('phase and check sets', () {
    // Sets rather than a bit-flag type so that a const Settings can name them
    // directly; an extension type's operators are not const-evaluable.
    test('compose inside a const Settings', () {
      const settings = Settings(
        phases: <Phase>{Phase.generate, Phase.shrink},
        suppressHealthChecks: <HealthCheck>{HealthCheck.tooSlow},
      );
      expect(settings.phases, contains(Phase.generate));
      expect(settings.suppressHealthChecks, contains(HealthCheck.tooSlow));
    });

    test('fold to the bit masks the ABI takes', () {
      expect(maskOf(everyPhase), 31);
      expect(maskOf(<Phase>{Phase.explicit, Phase.reuse}), 3);
      expect(maskOf(everyHealthCheck), 15);
      expect(maskOf(const <Phase>{}), 0);
    });

    test('name every value the ABI defines', () {
      expect(Phase.values, hasLength(5));
      expect(everyPhase, Phase.values.toSet());
      expect(HealthCheck.values, hasLength(4));
      expect(everyHealthCheck, HealthCheck.values.toSet());
    });
  });

  // The engine applies environment-aware defaults of its own -- under CI it
  // disables the database and derandomizes -- so an unspecified option has to
  // mean "do not call the setter", not "call it with a default".
  group('omitted options', () {
    test('produce no setter calls at all', () {
      expect(settersCalledFor(const Settings()), isEmpty);
    });

    test('stay omitted when a neighbour is set', () {
      expect(settersCalledFor(const Settings(testCases: 10)), <String>[
        'hegel_settings_set_test_cases',
      ]);
    });

    // Passing false explicitly is a different intent from saying nothing, and
    // must reach the engine.
    test('are distinct from an explicit false', () {
      expect(settersCalledFor(const Settings(derandomize: false)), <String>[
        'hegel_settings_set_derandomize',
      ]);
    });
  });

  group('specified options', () {
    test('each call exactly one setter', () {
      expect(
        settersCalledFor(
          const Settings(
            testCases: 50,
            statefulStepCount: 20,
            mode: Mode.singleTestCase,
            backend: Backend.seeded,
            seed: 42,
            derandomize: true,
            database: Database.disabled,
            databaseKey: 'suite/case',
            phases: {Phase.generate},
            suppressHealthChecks: {HealthCheck.tooSlow},
            reportMultipleFailures: true,
            verbosity: Verbosity.quiet,
          ),
        ),
        <String>[
          'hegel_settings_set_test_cases',
          'hegel_settings_set_stateful_step_count',
          'hegel_settings_set_mode',
          'hegel_settings_set_backend',
          'hegel_settings_set_seed',
          'hegel_settings_set_derandomize',
          'hegel_settings_set_database',
          'hegel_settings_set_database_key',
          'hegel_settings_set_phases',
          'hegel_settings_set_suppress_health_check',
          'hegel_settings_set_report_multiple_failures',
          'hegel_settings_set_verbosity',
        ],
      );
    });

    test('every database choice reaches the same setter', () {
      for (final choice in <Database>[
        Database.standard,
        Database.disabled,
        const Database.at('/tmp/examples'),
      ]) {
        expect(
          settersCalledFor(Settings(database: choice, databaseKey: 'k')),
          <String>[
            'hegel_settings_set_database',
            'hegel_settings_set_database_key',
          ],
        );
      }
    });
  });

  group('values the engine cannot judge for itself', () {
    // uint64 on the wire: a negative int arrives as UINT64_MAX, which is a
    // perfectly valid budget as far as the engine is concerned.
    test('a negative test-case budget is refused here', () {
      expect(
        () => settersCalledFor(const Settings(testCases: -1)),
        throwsRangeError,
      );
      expect(
        () => settersCalledFor(const Settings(testCases: 0)),
        returnsNormally,
      );
    });

    // An empty path is the ABI's "no database" sentinel, so Database.at('')
    // would silently mean Database.disabled.
    test('an empty database path is refused rather than disabling', () {
      expect(
        () => settersCalledFor(const Settings(database: Database.at(''))),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'message',
            contains('Database.disabled'),
          ),
        ),
      );
      expect(
        () => settersCalledFor(const Settings(database: Database.disabled)),
        returnsNormally,
      );
    });

    // Verified against the engine: with no key it writes nothing at all --
    // not even the database directory -- and replays nothing, so the setting
    // reads as "persist my counterexamples" and delivers a run identical to
    // one with no database.
    test('an enabled database without a key is refused', () {
      for (final enabled in <Database>[
        Database.standard,
        const Database.at('/tmp/examples'),
      ]) {
        expect(
          () => settersCalledFor(Settings(database: enabled)),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.message.toString(),
              'message',
              contains('stores and replays nothing'),
            ),
          ),
          reason: '$enabled without a key does nothing',
        );
      }
      // Switching persistence off is not a request to persist, so it stands
      // on its own, and a key alone just names entries in the engine's own
      // default location.
      expect(
        () => settersCalledFor(const Settings(database: Database.disabled)),
        returnsNormally,
      );
      expect(
        () => settersCalledFor(const Settings(databaseKey: 'k')),
        returnsNormally,
      );
    });

    // The mirror image of the empty-path rule above, and the reason the two
    // cannot share one policy: an empty path means "no database", but an
    // empty key is just a key.
    test('an empty database key is a key, not a sentinel', () {
      expect(
        settersCalledFor(
          const Settings(database: Database.standard, databaseKey: ''),
        ),
        <String>[
          'hegel_settings_set_database',
          'hegel_settings_set_database_key',
        ],
      );
    });
  });

  group('a database at a path', () {
    test('is the same database as another at the same path', () {
      // Value semantics, like the two singletons: settings assembled at
      // runtime -- from an environment variable, say -- have to be
      // comparable with settings written down.
      expect(Database.at('/tmp/examples'), Database.at('/tmp/examples'));
      expect(
        Database.at('/tmp/examples').hashCode,
        Database.at('/tmp/examples').hashCode,
      );
      expect(Database.at('/tmp/a'), isNot(Database.at('/tmp/b')));
      expect(Database.at('/tmp/a'), isNot(Database.standard));
    });
  });

  group('a database key filled in from outside', () {
    // The layer above derives a key from the test's identity and fills it in,
    // which means copying every other field. A field added to Settings and
    // forgotten by that copy would simply stop being applied, so the check is
    // which setters the engine sees rather than a list of fields written out
    // again here.
    const Settings everything = Settings(
      testCases: 5,
      statefulStepCount: 3,
      mode: Mode.singleTestCase,
      backend: Backend.seeded,
      seed: 9,
      derandomize: true,
      database: Database.disabled,
      phases: <Phase>{Phase.generate},
      suppressHealthChecks: <HealthCheck>{HealthCheck.tooSlow},
      reportMultipleFailures: true,
      verbosity: Verbosity.quiet,
    );

    test('changes nothing else about the settings', () {
      final without = settersCalledFor(everything);
      final withKey = settersCalledFor(everything.withDatabaseKey('derived'));

      expect(withKey.toSet().difference(without.toSet()), <String>{
        'hegel_settings_set_database_key',
      });
      expect(withKey, hasLength(without.length + 1));
    });

    test('leaves a key the caller chose alone', () {
      // Sharing one key between properties is a deliberate thing to do, and
      // a derived key would silently undo it.
      const chosen = Settings(databaseKey: 'shared between properties');

      expect(chosen.withDatabaseKey('derived'), same(chosen));
    });
  });

  group('against the real engine', () {
    test('applies a full configuration and frees the handle', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      const settings = Settings(
        testCases: 5,
        seed: 7,
        derandomize: true,
        database: Database.disabled,
        databaseKey: 'settings-test',
        phases: {Phase.generate},
        suppressHealthChecks: machineSpeedChecks,
        verbosity: Verbosity.quiet,
      );
      expect(
        settings.withNative(session, (handle) => handle.address != 0),
        isTrue,
      );
    });

    test('rejects a stateful step count the engine will not take', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      expect(
        () =>
            const Settings(statefulStepCount: 0)
                .withNative(session, (_) => null),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects a database key with an interior NUL before the call', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      expect(
        () =>
            Settings(databaseKey: 'a${String.fromCharCode(0)}b')
                .withNative(session, (_) => null),
        throwsArgumentError,
      );
    });
  });
}
