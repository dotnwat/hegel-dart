/// A model-based property over an interface: rules tap, an invariant compares
/// the screen against a model, and a counterexample is a script of taps.
///
///     flutter test test/counter_ui_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hegel/hegel.dart';
import 'package:hegel_flutter/hegel_flutter.dart';

import 'apps/counter_app.dart';

/// The counter on screen, a model of what it should be showing, and the taps
/// between them.
///
/// The rules are the three buttons. Each one taps and then says what that
/// should have done to the model, which is the whole of the specification:
/// resetting sets the count to zero *and* takes back the permission to
/// decrement, whatever the app does.
final class CounterMachine extends UiMachine {
  /// A machine driving [ui].
  CounterMachine(super.ui);

  /// What the display should be showing.
  int count = 0;

  /// Whether taking one away should do anything.
  bool canDecrement = false;

  @override
  List<Rule> get rules => <Rule>[
    Rule('add one', (TestCase testCase) async {
      await ui.tap(find.byKey(const Key('increment')));
      count++;
      canDecrement = true;
    }),
    Rule('take one', (TestCase testCase) async {
      await ui.tap(find.byKey(const Key('decrement')));
      if (canDecrement) count--;
    }),
    Rule('reset', (TestCase testCase) async {
      await ui.tap(find.byKey(const Key('reset')));
      count = 0;
      canDecrement = false;
    }),
  ];

  @override
  List<Invariant> get invariants => <Invariant>[
    // The interface checks the machine already brings -- here, that every
    // frame rendered -- and then the one this machine is about.
    ...super.invariants,
    Invariant('the display matches the model', (TestCase testCase) {
      final shown = ui.tester
          .widget<Text>(find.byKey(const Key('display')))
          .data;
      if (shown != '$count') {
        throw StateError('the display shows $shown, the model says $count');
      }
    }),
  ];
}

void main() {
  // The property as it would be written in a suite: registered like any
  // widget test, failing like any widget test. The fixed counter holds.
  widgetProperty('a repaired counter matches its model', (
    TestCase testCase,
    WidgetTester tester,
  ) async {
    final ui = await UiSurface.open(tester, const CounterApp(fixed: true));
    await runStateful(testCase, CounterMachine(ui));
  }, settings: const Settings(testCases: 30, database: Database.disabled));

  // And the same property against the counter with the bug in it, run
  // through the runner directly so that the failure can be shown rather than
  // raised. This is what `example/echo.dart` does in the pure Dart package,
  // and for the same reason: a demonstration should not fail the suite that
  // demonstrates it.
  testWidgets('the bug is found, and shrinks to three taps', (
    WidgetTester tester,
  ) async {
    final report = <String>[];
    Object? failure;
    try {
      await runProperty(
        (TestCase testCase) async {
          final ui = await UiSurface.open(
            tester,
            const CounterApp(),
            advance: oneFrame,
          );
          await runStateful(testCase, CounterMachine(ui));
        },
        settings: const Settings(
          testCases: 100,
          // A three-tap bug does not need a fifty-tap walk to be found in,
          // and every step of every case is a real frame. This is the knob
          // that decides what a user-interface property costs.
          statefulStepCount: 15,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
        ),
        onDiagnostic: report.add,
      );
    } on Object catch (error) {
      failure = error;
    }

    // A demonstration prints what it found; the engine's report is one
    // string with the whole script in it.
    debugPrint(report.join('\n'));
    expect(failure, isNotNull, reason: 'the counter has a bug in it');

    // A random walk of hundreds of taps, shrunk to the three that had to
    // happen: the increment that grants permission to decrement, the reset
    // that should have taken it back, and the decrement that goes below zero.
    final steps = report
        .expand((String chunk) => chunk.split('\n'))
        .where((String line) => line.startsWith('Step '))
        .toList();
    expect(steps, <String>[
      'Step 1: add one',
      'Step 2: reset',
      'Step 3: take one',
    ]);
    expect(failure.toString(), contains('the display shows -1'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
