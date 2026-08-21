/// Run configuration.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'marshal.dart';
import 'session.dart';

/// Which phases of the property-test loop to run.
///
/// An extension type rather than an enum because these combine: the ABI takes
/// a bitwise OR of them.
extension type const Phases(int bits) {
  /// Replay hard-coded explicit examples.
  static const Phases explicit = Phases(raw.hegel_phase_t.HEGEL_PHASE_EXPLICIT);

  /// Replay counterexamples persisted by previous runs.
  static const Phases reuse = Phases(raw.hegel_phase_t.HEGEL_PHASE_REUSE);

  /// Generate fresh test cases.
  static const Phases generate = Phases(raw.hegel_phase_t.HEGEL_PHASE_GENERATE);

  /// Hill-climb toward observed targets.
  static const Phases target = Phases(raw.hegel_phase_t.HEGEL_PHASE_TARGET);

  /// Shrink discovered failures.
  static const Phases shrink = Phases(raw.hegel_phase_t.HEGEL_PHASE_SHRINK);

  /// Every phase, which is the engine's own default.
  static const Phases all = Phases(raw.hegel_phase_t.HEGEL_PHASE_ALL);

  /// Both sets of phases.
  Phases operator |(Phases other) => Phases(bits | other.bits);

  /// Whether every phase in [other] is included here.
  bool includes(Phases other) => bits & other.bits == other.bits;
}

/// Health checks the engine may abort a run over.
///
/// Passed to [Settings.suppressHealthChecks] to turn them off, so a value here
/// names what will *not* fire.
extension type const HealthChecks(int bits) {
  /// Too many draws rejected by assumptions.
  static const HealthChecks filterTooMuch = HealthChecks(
    raw.hegel_health_check_t.HEGEL_HC_FILTER_TOO_MUCH,
  );

  /// Individual test cases taking too long.
  static const HealthChecks tooSlow = HealthChecks(
    raw.hegel_health_check_t.HEGEL_HC_TOO_SLOW,
  );

  /// Generated values too large.
  static const HealthChecks testCasesTooLarge = HealthChecks(
    raw.hegel_health_check_t.HEGEL_HC_TEST_CASES_TOO_LARGE,
  );

  /// A first test case that is already disproportionately large.
  static const HealthChecks largeInitialTestCase = HealthChecks(
    raw.hegel_health_check_t.HEGEL_HC_LARGE_INITIAL_TEST_CASE,
  );

  /// Every check.
  static const HealthChecks all = HealthChecks(1 | 2 | 4 | 8);

  /// No checks, the engine's own default.
  static const HealthChecks none = HealthChecks(0);

  /// Both sets of checks.
  HealthChecks operator |(HealthChecks other) =>
      HealthChecks(bits | other.bits);

  /// Whether every check in [other] is included here.
  bool includes(HealthChecks other) => bits & other.bits == other.bits;
}

/// Whether to run the full loop or a single test case.
enum Mode {
  /// Generate, shrink, and replay until the budget is spent. The default.
  testRun(raw.hegel_mode_t.HEGEL_MODE_TEST_RUN),

  /// Produce exactly one test case, with no shrinking.
  singleTestCase(raw.hegel_mode_t.HEGEL_MODE_SINGLE_TEST_CASE);

  const Mode(this.native);

  /// The value the ABI expects.
  final int native;
}

/// Where the engine's randomness comes from.
enum Backend {
  /// Chosen by the engine. The default.
  auto(raw.hegel_backend_t.HEGEL_BACKEND_AUTO),

  /// A seeded PRNG, so runs are reproducible from the seed.
  seeded(raw.hegel_backend_t.HEGEL_BACKEND_DEFAULT),

  /// Fresh entropy per draw, intended for running under Antithesis.
  urandom(raw.hegel_backend_t.HEGEL_BACKEND_URANDOM);

  const Backend(this.native);

  /// The value the ABI expects.
  final int native;
}

/// How much the engine says while it runs.
enum Verbosity {
  /// The final result only.
  quiet(raw.hegel_verbosity_t.HEGEL_VERBOSITY_QUIET),

  /// A summary line per run. The default.
  normal(raw.hegel_verbosity_t.HEGEL_VERBOSITY_NORMAL),

  /// Per-case progress and drawn values.
  verbose(raw.hegel_verbosity_t.HEGEL_VERBOSITY_VERBOSE),

  /// As verbose, plus the shrinker's trace.
  debug(raw.hegel_verbosity_t.HEGEL_VERBOSITY_DEBUG);

  const Verbosity(this.native);

  /// The value the ABI expects.
  final int native;
}

/// Where discovered counterexamples are persisted.
///
/// A sealed type because the ABI encodes three different meanings in one
/// string parameter: a null pointer selects the default location, an empty
/// string disables persistence, and anything else is a path.
sealed class Database {
  const Database();

  /// The engine's own default location, `./.hegel/examples/`.
  static const Database standard = _StandardDatabase();

  /// No persistence at all.
  static const Database disabled = _DisabledDatabase();

  /// Persist under [path].
  const factory Database.at(String path) = _PathDatabase;
}

final class _StandardDatabase extends Database {
  const _StandardDatabase();
}

final class _DisabledDatabase extends Database {
  const _DisabledDatabase();
}

final class _PathDatabase extends Database {
  const _PathDatabase(this.path);

  final String path;
}

/// Configuration for one run.
///
/// Every option is nullable, and an option left null is never sent to the
/// engine at all. That matters: `hegel_settings_new` applies its own
/// environment-aware defaults — under CI it disables the database and turns on
/// derandomization — and calling a setter with a "default" value would
/// silently overrule them.
final class Settings {
  /// Creates settings, leaving anything unspecified to the engine.
  const Settings({
    this.testCases,
    this.statefulStepCount,
    this.mode,
    this.backend,
    this.seed,
    this.derandomize,
    this.database,
    this.databaseKey,
    this.phases,
    this.suppressHealthChecks,
    this.reportMultipleFailures,
    this.verbosity,
  });

  /// How many valid test cases to run before declaring the property held.
  final int? testCases;

  /// Target number of steps per stateful test case.
  final int? statefulStepCount;

  /// Full loop or a single test case.
  final Mode? mode;

  /// Where randomness comes from.
  final Backend? backend;

  /// The seed to generate from. Null lets the engine pick one.
  final int? seed;

  /// Derive the seed from the database key rather than fresh randomness.
  final bool? derandomize;

  /// Where counterexamples are persisted.
  final Database? database;

  /// Scopes stored and replayed examples.
  final String? databaseKey;

  /// Which phases of the loop to run.
  final Phases? phases;

  /// Health checks to turn off.
  final HealthChecks? suppressHealthChecks;

  /// Keep generating after the first failure to find other distinct bugs.
  final bool? reportMultipleFailures;

  /// How much the engine says while it runs.
  final Verbosity? verbosity;

  /// Builds an engine-side settings handle, applies this configuration, and
  /// hands it to [use]. The handle is freed before returning.
  ///
  /// Settings are copied by `hegel_run_start`, so the handle never needs to
  /// outlive the call that consumes it.
  @internal
  T withNative<T>(
    Libhegel session,
    T Function(ffi.Pointer<raw.hegel_settings_t> settings) use,
  ) {
    final out = calloc<ffi.Pointer<raw.hegel_settings_t>>();
    ffi.Pointer<raw.hegel_settings_t> handle = ffi.nullptr;
    try {
      session.check(
        session.bindings.hegel_settings_new(session.context, out),
        'hegel_settings_new',
      );
      handle = out.value;
      _apply(session, handle);
      return use(handle);
    } finally {
      if (handle != ffi.nullptr) {
        session.bindings.hegel_settings_free(session.context, handle);
      }
      calloc.free(out);
    }
  }

  void _apply(Libhegel session, ffi.Pointer<raw.hegel_settings_t> handle) {
    final bindings = session.bindings;
    final context = session.context;

    if (testCases case final value?) {
      session.check(
        bindings.hegel_settings_set_test_cases(context, handle, value),
        'hegel_settings_set_test_cases',
      );
    }
    if (statefulStepCount case final value?) {
      session.check(
        bindings.hegel_settings_set_stateful_step_count(context, handle, value),
        'hegel_settings_set_stateful_step_count',
      );
    }
    if (mode case final value?) {
      session.check(
        bindings.hegel_settings_set_mode(context, handle, value.native),
        'hegel_settings_set_mode',
      );
    }
    if (backend case final value?) {
      session.check(
        bindings.hegel_settings_set_backend(context, handle, value.native),
        'hegel_settings_set_backend',
      );
    }
    if (seed case final value?) {
      session.check(
        bindings.hegel_settings_set_seed(context, handle, value, true),
        'hegel_settings_set_seed',
      );
    }
    if (derandomize case final value?) {
      session.check(
        bindings.hegel_settings_set_derandomize(context, handle, value),
        'hegel_settings_set_derandomize',
      );
    }
    if (database case final value?) {
      using((Arena arena) {
        final path = switch (value) {
          _StandardDatabase() => ffi.nullptr,
          _DisabledDatabase() => toCString(arena, '', 'database'),
          _PathDatabase(:final path) => toCString(arena, path, 'database'),
        };
        session.check(
          bindings.hegel_settings_set_database(context, handle, path),
          'hegel_settings_set_database',
        );
      });
    }
    if (databaseKey case final value?) {
      using((Arena arena) {
        session.check(
          bindings.hegel_settings_set_database_key(
            context,
            handle,
            toCString(arena, value, 'databaseKey'),
          ),
          'hegel_settings_set_database_key',
        );
      });
    }
    if (phases case final value?) {
      session.check(
        bindings.hegel_settings_set_phases(context, handle, value.bits),
        'hegel_settings_set_phases',
      );
    }
    if (suppressHealthChecks case final value?) {
      session.check(
        bindings.hegel_settings_set_suppress_health_check(
          context,
          handle,
          value.bits,
        ),
        'hegel_settings_set_suppress_health_check',
      );
    }
    if (reportMultipleFailures case final value?) {
      session.check(
        bindings.hegel_settings_set_report_multiple_failures(
          context,
          handle,
          value,
        ),
        'hegel_settings_set_report_multiple_failures',
      );
    }
    if (verbosity case final value?) {
      session.check(
        bindings.hegel_settings_set_verbosity(context, handle, value.native),
        'hegel_settings_set_verbosity',
      );
    }
  }
}
