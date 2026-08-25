/// A property with no model in it: do whatever the interface offers, and
/// insist only that the app go on working.
///
///     flutter test test/monkey_test.dart
///
/// Nothing here says what the notes app is for. The actions are found in the
/// semantics tree -- the same tree a screen reader walks -- so the driver
/// knows what can be tapped and typed into without being told, and the oracle
/// is that every frame renders and every state is accessible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hegel/hegel.dart';
import 'package:hegel_flutter/hegel_flutter.dart';

import 'apps/notes_app.dart';

void main() {
  widgetProperty(
    'the guarded notes app survives being used',
    (TestCase testCase, WidgetTester tester) async {
      final ui = await UiSurface.open(
        tester,
        const NotesApp(guarded: true),
        advance: oneFrame,
      );
      await runStateful(
        testCase,
        MonkeyMachine(
          ui,
          // Every state the walk reaches has to render *and* be usable. These
          // are Flutter's own guidelines, and this is the difference between
          // auditing three screenshots and auditing every state the app has.
          checks: <UiCheck>[noFlutterErrors, ...accessibilityChecks],
        ),
      );
    },
    settings: const Settings(
      testCases: 20,
      statefulStepCount: 12,
      database: Database.disabled,
    ),
  );

  testWidgets('the monkey finds the unguarded index, in two taps', (
    WidgetTester tester,
  ) async {
    final report = <String>[];
    Object? failure;
    try {
      await runProperty(
        (TestCase testCase) async {
          final ui = await UiSurface.open(
            tester,
            const NotesApp(),
            advance: oneFrame,
          );
          await runStateful(testCase, MonkeyMachine(ui));
        },
        settings: const Settings(
          testCases: 60,
          statefulStepCount: 12,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
        ),
        onDiagnostic: report.add,
      );
    } on Object catch (error) {
      failure = error;
    }

    debugPrint(report.join('\n'));
    expect(failure, isNotNull, reason: 'the notes app has a bug in it');

    // Nothing told the driver that a note has to exist before it can be moved
    // up. It found that out, and the engine cut the walk down to the two taps
    // that had to happen.
    final steps = report
        .expand((String chunk) => chunk.split('\n'))
        .where((String line) => line.startsWith('Step '))
        .toList();
    expect(steps, hasLength(2));
    expect(report.join('\n'), contains('Move up'));
    expect(failure.toString(), contains('RangeError'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
