@TestOn('vm')
library;

import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/version.g.dart';
import 'package:test/test.dart';

import '../support/fake_bindings.dart';

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
  group('flag sets', () {
    test('combine and test for membership', () {
      final selected = Phases.generate | Phases.shrink;
      expect(selected.includes(Phases.generate), isTrue);
      expect(selected.includes(Phases.shrink), isTrue);
      expect(selected.includes(Phases.reuse), isFalse);
      expect(Phases.all.includes(selected), isTrue);
    });

    test('match the ABI bit values', () {
      expect(Phases.all.bits, 31);
      expect((Phases.explicit | Phases.reuse).bits, 3);
      expect(HealthChecks.all.bits, 15);
      expect(HealthChecks.none.bits, 0);
    });

    test('health checks combine the same way', () {
      final suppressed = HealthChecks.tooSlow | HealthChecks.filterTooMuch;
      expect(suppressed.includes(HealthChecks.tooSlow), isTrue);
      expect(suppressed.includes(HealthChecks.testCasesTooLarge), isFalse);
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
            phases: Phases.generate,
            suppressHealthChecks: HealthChecks.tooSlow,
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
        expect(settersCalledFor(Settings(database: choice)), <String>[
          'hegel_settings_set_database',
        ]);
      }
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
        phases: Phases.generate,
        suppressHealthChecks: HealthChecks.all,
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
