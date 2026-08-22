/// What a failure is called, and how it reaches the reader.
library;

import 'package:stack_trace/stack_trace.dart';

/// Packages whose frames are never where a property went wrong.
///
/// Everything the assertion passed through on its way out: this package, the
/// test framework that raised it, and the trace library doing the looking.
const Set<String> _frameworkPackages = <String>{
  'hegel',
  'matcher',
  'stack_trace',
  'test',
  'test_api',
  'test_core',
};

/// A name for wherever [error] came from, stable across runs and machines.
///
/// The engine groups failures by this string and shrinks each group toward
/// its own minimal case, so what it says decides what counts as one bug: two
/// cases that name the same site are the same bug, and two sites in one body
/// are two bugs worth reporting separately. Stability is therefore the whole
/// requirement -- an origin containing a value, an address, or a case number
/// would make every case its own bug and shrinking would have nothing to
/// work on.
///
/// Derived from the first frame outside the framework, which for a failed
/// `expect` is the line the expect is on rather than anything inside
/// package:matcher. File paths come out relative to the working directory,
/// so two machines checking out the same repository agree.
String originOf(Object error, StackTrace stack) {
  for (final frame in Trace.from(stack).frames) {
    if (frame.isCore) continue;
    if (_frameworkPackages.contains(frame.package)) continue;
    final line = frame.line;
    return line == null
        ? '${error.runtimeType} at ${frame.library}'
        : '${error.runtimeType} at ${frame.library}:$line';
  }
  // Nothing but framework frames, which happens when an error is raised from
  // a callback the framework owns. The type alone still groups by kind, which
  // is better than grouping everything together.
  return '${error.runtimeType}';
}
