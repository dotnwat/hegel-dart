/// Run configuration.
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.g.dart' as raw;
import 'marshal.dart';
import 'session.dart';

/// A value that occupies one bit of a mask the ABI takes.
abstract interface class MaskFlag {
  /// This value's bit.
  int get bit;
}

/// One phase of the property-test loop.
///
/// A set of these rather than a bit-flag type: `const Settings(phases: {...})`
/// has to work, and an extension type's operators cannot be evaluated at
/// compile time, so combining flags that way would force callers to give up
/// const or hand-compute bit values.
enum Phase implements MaskFlag {
  /// Replay hard-coded explicit examples.
  explicit(raw.hegel_phase_t.HEGEL_PHASE_EXPLICIT),

  /// Replay counterexamples persisted by previous runs.
  ///
  /// Does nothing unless both a [Settings.database] and a
  /// [Settings.databaseKey] are set. Paired with [shrink] and nothing else,
  /// a run replays what is stored and generates nothing new.
  reuse(raw.hegel_phase_t.HEGEL_PHASE_REUSE),

  /// Generate fresh test cases.
  generate(raw.hegel_phase_t.HEGEL_PHASE_GENERATE),

  /// Hill-climb toward observed targets.
  target(raw.hegel_phase_t.HEGEL_PHASE_TARGET),

  /// Shrink discovered failures.
  shrink(raw.hegel_phase_t.HEGEL_PHASE_SHRINK);

  const Phase(this.bit);

  @override
  final int bit;
}

/// Every phase, which is also what the engine does by default.
const Set<Phase> everyPhase = <Phase>{
  Phase.explicit,
  Phase.reuse,
  Phase.generate,
  Phase.target,
  Phase.shrink,
};

/// A health check the engine may abort a run over.
enum HealthCheck implements MaskFlag {
  /// Too many draws rejected by assumptions.
  filterTooMuch(raw.hegel_health_check_t.HEGEL_HC_FILTER_TOO_MUCH),

  /// Individual test cases taking too long.
  tooSlow(raw.hegel_health_check_t.HEGEL_HC_TOO_SLOW),

  /// Generated values too large.
  testCasesTooLarge(raw.hegel_health_check_t.HEGEL_HC_TEST_CASES_TOO_LARGE),

  /// A first test case that is already disproportionately large.
  largeInitialTestCase(
    raw.hegel_health_check_t.HEGEL_HC_LARGE_INITIAL_TEST_CASE,
  );

  const HealthCheck(this.bit);

  @override
  final int bit;
}

/// Every health check, for turning the lot off.
const Set<HealthCheck> everyHealthCheck = <HealthCheck>{
  HealthCheck.filterTooMuch,
  HealthCheck.tooSlow,
  HealthCheck.testCasesTooLarge,
  HealthCheck.largeInitialTestCase,
};

/// Folds [values] into the bit mask the ABI expects.
int maskOf(Iterable<MaskFlag> values) =>
    values.fold<int>(0, (int mask, MaskFlag value) => mask | value.bit);

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
/// Persistence is what makes a failure stick. Generation is random, so a bug
/// found on one run can simply not come up on the next; with a database the
/// engine writes the shrunk counterexample to disk and replays it ahead of
/// anything it generates, so the property keeps failing until the bug is
/// actually fixed. Once it stops failing, the entry is dropped rather than
/// replayed forever.
///
/// Nothing is stored or replayed without a [Settings.databaseKey], which
/// scopes entries so that several properties can share one directory.
/// Enabling a database without one is refused rather than silently doing
/// nothing.
///
/// A damaged or unwritable database is not an error: the engine treats it as
/// having nothing in it, and a run's outcome never depends on whether the
/// store worked.
///
/// A sealed type because the ABI encodes three different meanings in one
/// string parameter: a null pointer selects the default location, an empty
/// string disables persistence, and anything else is a path.
sealed class Database {
  const Database();

  /// The engine's own default location, `./.hegel/examples/`.
  ///
  /// Resolved against the working directory, so runs started from different
  /// directories do not share it.
  static const Database standard = _StandardDatabase();

  /// No persistence at all.
  static const Database disabled = _DisabledDatabase();

  /// Persist under [path], which is created if it does not exist.
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
///
/// The CI half of that is worth knowing before relying on it: the engine
/// looks for `CI`, `GITHUB_ACTIONS` and similar, so persistence that works
/// locally is off by default on a build machine. Anything that wants
/// counterexamples kept there has to ask for them explicitly.
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
  ///
  /// Requires [databaseKey]. Left null, the engine picks for itself, and
  /// what it picks depends on the environment: see the note on [Settings].
  final Database? database;

  /// Scopes stored and replayed examples.
  ///
  /// Required whenever [database] is enabled; see the refusal in `_apply`.
  /// The empty string is a perfectly ordinary key rather than a sentinel --
  /// unlike an empty [Database.at] path -- so it stores and replays like any
  /// other, and is not refused.
  final String? databaseKey;

  /// Which phases of the loop to run.
  final Set<Phase>? phases;

  /// Health checks to turn off.
  final Set<HealthCheck>? suppressHealthChecks;

  /// Keep generating after the first failure to find other distinct bugs.
  final bool? reportMultipleFailures;

  /// How much the engine says while it runs.
  final Verbosity? verbosity;

  /// This configuration with [key] as its [databaseKey], or unchanged if it
  /// already has one.
  ///
  /// The layer above derives a key from the test's own identity rather than
  /// asking for one, since a database with no key stores and replays nothing.
  /// A key the caller chose wins: sharing one between properties is a
  /// deliberate thing to do.
  ///
  /// Here rather than above because it copies every field: a setting added to
  /// the list above and forgotten here would be silently dropped.
  Settings withDatabaseKey(String key) => databaseKey != null
      ? this
      : Settings(
          testCases: testCases,
          statefulStepCount: statefulStepCount,
          mode: mode,
          backend: backend,
          seed: seed,
          derandomize: derandomize,
          database: database,
          databaseKey: key,
          phases: phases,
          suppressHealthChecks: suppressHealthChecks,
          reportMultipleFailures: reportMultipleFailures,
          verbosity: verbosity,
        );

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

    // Cross-field, so it cannot sit with either setter. Asking for
    // persistence without a key is not weaker persistence, it is none: with
    // no key the engine writes nothing -- not even the database directory --
    // and replays nothing, so the run is indistinguishable from one that
    // never configured a database. Verified against the engine for both
    // Database.standard and Database.at. Refused for the same reason as
    // Database.at(''): those are the two ways to ask for a database and
    // silently get no persistence at all.
    if (database case final chosen? when chosen is! _DisabledDatabase) {
      if (databaseKey == null) {
        throw ArgumentError.value(
          databaseKey,
          'databaseKey',
          'is required whenever the database is enabled, because without one '
              'the engine stores and replays nothing; pass a key that '
              'identifies this property, or use Database.disabled',
        );
      }
    }

    if (testCases case final value?) {
      // The ABI takes this as uint64, so a negative Dart int arrives as
      // UINT64_MAX and the engine has no way to see anything wrong. A typo
      // would quietly become an effectively unbounded run.
      if (value < 0) {
        throw RangeError.value(value, 'testCases', 'must not be negative');
      }
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
          // Not simply marshalled: an empty path is the ABI's sentinel for
          // "no database at all", so letting one through here would silently
          // turn Database.at into Database.disabled -- easy to hit when the
          // path comes from an unset configuration value.
          _PathDatabase(:final path) =>
            path.isEmpty
                ? throw ArgumentError.value(
                    path,
                    'database',
                    'is empty; use Database.disabled to turn persistence off',
                  )
                : toCString(arena, path, 'database'),
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
        bindings.hegel_settings_set_phases(context, handle, maskOf(value)),
        'hegel_settings_set_phases',
      );
    }
    if (suppressHealthChecks case final value?) {
      session.check(
        bindings.hegel_settings_set_suppress_health_check(
          context,
          handle,
          maskOf(value),
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
