/// The settings a property has that nobody wrote down.
library;

import 'package:stack_trace/stack_trace.dart';

import '../libhegel/settings.dart';
import 'reporting.dart';
import 'runner.dart';

/// The frame where the caller reached into this package.
///
/// Two things need it, both at registration time: package:test is told where
/// the property was written, so an IDE's run button and the JSON reporter
/// point at the test rather than into this package, and the example database
/// is keyed partly by the file the property lives in.
///
/// Null when the stack is nothing but this package's own frames, which is
/// what a synthetic or trimmed trace looks like.
Frame? callerFrame(StackTrace stack) {
  for (final frame in Trace.from(stack).frames) {
    if (frame.package == 'hegel') continue;
    return frame;
  }
  return null;
}

/// What the example database files this property's counterexamples under.
///
/// A property has to be recognisable across runs and across machines for its
/// counterexample to be replayed at all, and Dart offers no macro to capture
/// where a call was written and no reflection to ask a closure its name. What
/// it does offer is the test's own identity: [suite] is the file the property
/// was registered in, relative to where the run started, and [testName] is
/// the full name package:test knows it by, group prefixes included. Together
/// they are what `t.Name()` is to hegel-go and `module_path!()` is to
/// hegel-rust. Pass [suite] through [fileOf], so that the key a Windows
/// developer writes is the key their CI reads.
///
/// Renaming a test therefore orphans its stored counterexample. That is the
/// same bargain every frontend makes, and the alternative -- asking each
/// property for a stable key -- makes the common case worse to buy something
/// nobody wanted.
String databaseKeyFor({required String suite, required String testName}) =>
    '$suite:$testName';

/// The variable that overrides how many test cases a run gets.
const String testCasesVariable = 'HEGEL_TEST_CASES';

/// The variable that overrides where counterexamples are kept.
///
/// A path, or the empty string for no database at all.
const String databaseVariable = 'HEGEL_DATABASE';

/// [settings] as the run will actually use them.
///
/// Three sources, in the order they win. [environment] comes first: the two
/// variables below are the ones hegel-rust honours, and the point of setting
/// one is to change a run on a machine you cannot edit the source on -- a CI
/// job that needs its counterexamples kept somewhere, a bisect that needs a
/// hundred times the cases. Then what the caller wrote. Then the engine,
/// which decides everything nobody else did.
///
/// [databaseKey] is the exception to the order: it fills in a key only when
/// the caller has none, since a key the caller chose is a deliberate choice
/// to share stored examples between properties.
Settings resolveSettings(
  Settings settings, {
  required Map<String, String> environment,
  String? databaseKey,
}) {
  final keyed = databaseKey == null
      ? settings
      : settings.withDatabaseKey(databaseKey);
  final testCases = environment[testCasesVariable];
  final database = environment[databaseVariable];
  return keyed.overriddenWith(
    testCases: testCases == null ? null : _casesFrom(testCases),
    database: database == null || !_canBeKeyed(keyed, database)
        ? null
        // Empty is the way to turn persistence off from the environment,
        // matching the engine's own reading of an empty database path.
        : database.isEmpty
        ? Database.disabled
        : Database.at(database),
  );
}

/// Whether pointing [settings] at [database] would mean anything.
///
/// A database with no key stores and replays nothing -- the engine wants to
/// know which property an example belongs to -- and the binding layer refuses
/// the combination outright rather than pretending. `property()` always
/// derives a key, so this only ever comes up for a run driven directly, which
/// has no test identity to derive one from. The variable is left unapplied
/// there rather than turning an ambient setting into a failed run: it was set
/// to keep counterexamples somewhere, not to stop a suite.
bool _canBeKeyed(Settings settings, String database) =>
    database.isEmpty || settings.databaseKey != null;

/// [value] as a test-case count.
///
/// Refused rather than ignored: a variable set to something that is not a
/// number was set on purpose, and silently running the default number of
/// cases would answer a question nobody asked.
///
/// Digits only, and at least one. `int.tryParse` would take `0x10` as
/// sixteen, `+5` and ` 5 ` as five, and zero as zero -- and zero is the
/// dangerous one, because a run with no cases checks nothing and reports
/// that the property held. A leftover variable on a CI job would turn a
/// whole suite green.
int _casesFrom(String value) {
  final count = RegExp(r'^[0-9]+$').hasMatch(value)
      ? int.tryParse(value, radix: 10)
      : null;
  if (count == null || count < 1) {
    throw PropertyError(
      '$testCasesVariable is set to "$value", which is not a number of test '
      'cases to run',
    );
  }
  return count;
}
