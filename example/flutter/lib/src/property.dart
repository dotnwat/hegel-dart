/// Registering a property that owns a widget tester.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hegel/hegel.dart';
import 'package:meta/meta.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:test_api/hooks.dart';

import 'surface.dart';

/// Registers a property as a Flutter widget test.
///
/// What `property()` is to `test()`, this is to `testWidgets()`: one test,
/// registered the ordinary way, whose body the engine runs once per case with
/// a [TestCase] to draw from and a [WidgetTester] to drive.
///
/// ```dart
/// widgetProperty('the profile card fits on any phone', (testCase, tester) async {
///   final device = testCase.draw(
///     deviceProfiles(size: screenSizes(), textScale: textScales()),
///     name: 'device',
///   );
///   await UiSurface.open(tester, ProfileCard(name: 'Ada'), device: device);
/// });
/// ```
///
/// The tester is the same one for every case, which is what makes
/// [UiSurface.open] the way to start one: it tears the last case's tree down
/// and puts the platform overrides back, so that a case means the same thing
/// whether it is the first the engine tries or the fiftieth it shrinks to.
///
/// Everything `testWidgets` does with a test it does with this one. A failure
/// prints the shrunk draws and a reproduce blob the way any hegel failure
/// does, and the counterexample is kept in the example database under a key
/// derived from this test's own name.
@isTest
void widgetProperty(
  String description,
  FutureOr<void> Function(TestCase testCase, WidgetTester tester) body, {
  Settings settings = const Settings(),
  String? reproduce,
  bool? printBlob,
  bool? skip,
  Timeout? timeout,
  Object? tags,
  int? retry,
  bool semanticsEnabled = true,
}) {
  // Read here rather than in the body: this is the frame that wrote
  // `widgetProperty(`, and by the time a case runs the stack is the runner's.
  final caller = _callerFrame(StackTrace.current);
  testWidgets(
    description,
    (WidgetTester tester) => runProperty(
      (TestCase testCase) => body(testCase, tester),
      settings: settings,
      databaseKey: '${_suiteOf(caller)}:${TestHandle.current.name}',
      reproduce: reproduce,
      printBlob: printBlob,
    ),
    skip: skip,
    timeout: timeout,
    tags: tags,
    retry: retry,
    semanticsEnabled: semanticsEnabled,
  );
}

/// The frame where the caller reached into this package.
Frame? _callerFrame(StackTrace stack) {
  for (final frame in Trace.from(stack).frames) {
    if (frame.package == 'hegel_flutter') continue;
    return frame;
  }
  return null;
}

/// What the example database files this property's counterexamples under.
///
/// The same shape hegel's own `property()` uses -- the suite, a colon, and
/// the full name package:test knows the test by -- spelled out again here
/// because the helper that builds it is internal to that package. A public
/// seam for it is the one thing this library wants from hegel that hegel does
/// not already offer; until there is one, a rename of this format there and
/// not here would only mean the two packages file their examples differently,
/// which costs nothing because they never share a key.
String _suiteOf(Frame? caller) {
  if (caller == null) return '';
  final path = caller.uri.path;
  final marker = path.lastIndexOf('/test/');
  return marker == -1 ? path : path.substring(marker + 1);
}
