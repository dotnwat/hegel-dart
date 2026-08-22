/// The settings a property has that nobody wrote down.
library;

import 'package:stack_trace/stack_trace.dart';

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
/// hegel-rust.
///
/// Renaming a test therefore orphans its stored counterexample. That is the
/// same bargain every frontend makes, and the alternative -- asking each
/// property for a stable key -- makes the common case worse to buy something
/// nobody wanted.
String databaseKeyFor({required String suite, required String testName}) =>
    '$suite:$testName';
