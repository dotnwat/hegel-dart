/// The package:test entry point.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';
import 'package:test_api/hooks.dart';

import '../libhegel/settings.dart';
import 'config.dart';
import 'runner.dart';
import 'test_case.dart';

/// Registers a property as a package:test test.
///
/// [body] receives a [TestCase] and draws from it; it may be synchronous or
/// asynchronous, and it may draw as many values as it likes, in whatever
/// order it likes. The property holds when the body completes, and fails when
/// it throws -- an `expect` mismatch like any other test, or any error at all:
///
/// ```dart
/// property('reversing twice is the identity', (tc) {
///   final items = tc.draw(lists(integers()));
///   expect(items.reversed.toList().reversed.toList(), items);
/// });
/// ```
///
/// It registers exactly one test, so everything package:test does with tests
/// it does with this one: `group()` nesting, `dart test -N` by name, tags,
/// skips, and the IDE's run button. The parameters it passes through mean the
/// same as they do on `test()`.
///
/// [settings] configures the run. What it leaves out the engine decides,
/// including whether to keep counterexamples on disk -- it turns that off
/// under CI by itself. The one thing this adds is the key those
/// counterexamples are filed under, derived from the test's own identity.
///
/// [reproduce] replaces the run with a single replay of the case that blob
/// encodes, which is how a failure from a machine with no example database --
/// a CI job -- is brought back to one with a debugger. [printBlob] forces the
/// hint that prints those blobs on or off.
///
/// Failures print through package:test's on-failure buffer, so a property
/// that holds says nothing at all.
@isTest
void property(
  Object? description,
  FutureOr<void> Function(TestCase) body, {
  Settings settings = const Settings(),
  String? reproduce,
  bool? printBlob,
  String? testOn,
  Timeout? timeout,
  Object? skip,
  Object? tags,
  Map<String, dynamic>? onPlatform,
  int? retry,
}) {
  // Read here rather than inside the test body: this is the frame that wrote
  // `property(`, and by the time the body runs the stack is package:test's.
  final caller = callerFrame(StackTrace.current);
  test(
    description,
    () => runProperty(
      body,
      settings: settings,
      databaseKey: databaseKeyFor(
        suite: caller?.library ?? '',
        testName: TestHandle.current.name,
      ),
      reproduce: reproduce,
      printBlob: printBlob,
    ),
    testOn: testOn,
    timeout: timeout,
    skip: skip,
    tags: tags,
    onPlatform: onPlatform,
    retry: retry,
    location: _locationOf(caller),
  );
}

/// [caller] as package:test's idea of a location.
///
/// A frame without a position is no use to an editor, so it is left out
/// rather than reported as the top of the file.
TestLocation? _locationOf(Frame? caller) {
  if (caller == null) return null;
  final line = caller.line;
  final column = caller.column;
  if (line == null || column == null) return null;
  return TestLocation(caller.uri, line, column);
}
