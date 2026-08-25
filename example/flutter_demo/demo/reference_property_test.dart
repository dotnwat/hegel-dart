/// The property that finds the bug, kept where `flutter test` will not run it.
///
///     flutter test demo/reference_property_test.dart
///
/// This is the reference: it is known to find the bug and to shrink it, and it
/// is here so that the demonstration has something to fall back on if the live
/// run goes sideways. Copy it into test/ to make it part of the suite.
///
/// The claim is one sentence, and it needs no model of the calculator: the
/// number under the expression is the answer to the expression. Abacus already
/// has a correct evaluator with properties of its own over it, so the oracle
/// is the app's own arithmetic and the property is that the interface agrees
/// with it.
library;

import 'package:abacus/arithmetic.dart';
import 'package:abacus/history.dart';
import 'package:abacus/keypad.dart';
import 'package:abacus/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hegel/hegel.dart';
import 'package:hegel_flutter/hegel_flutter.dart';

/// Where a picture of the failing frame is left.
const String counterexampleImage = 'build/counterexample.png';

/// Abacus, driven through its own buttons.
final class AbacusMachine extends UiMachine {
  /// A machine driving [ui].
  AbacusMachine(super.ui);

  bool get _onHistory => find.byType(HistoryPage).evaluate().isNotEmpty;

  List<String> get _rows => find
      .byType(ListTile)
      .evaluate()
      .map((Element element) => element.widget)
      .whereType<ListTile>()
      .map((ListTile tile) => (tile.title! as Text).data ?? '')
      .toList();

  @override
  List<Rule> get rules => <Rule>[
    Rule('press a key', (TestCase testCase) async {
      final key = testCase.draw(
        sampledFrom(everyKey.map((CalculatorKey key) => key.id).toList()),
        name: 'key',
      );
      await ui.tap(find.byKey(Key('key-$key')));
    }, precondition: () => !_onHistory),
    Rule('open the history', (TestCase testCase) async {
      await ui.tap(find.byKey(const Key('open-history')));
    }, precondition: () => !_onHistory),
    Rule('recall a calculation', (TestCase testCase) async {
      final rows = _rows;
      final wanted = testCase.draw(sampledFrom(rows), name: 'recall');
      await ui.tap(find.byKey(Key('history-${rows.indexOf(wanted)}')));
    }, precondition: () => _onHistory && _rows.isNotEmpty),
    Rule('go back', (TestCase testCase) async {
      await ui.pageBack();
    }, precondition: () => _onHistory),
  ];

  @override
  List<Invariant> get invariants => <Invariant>[
    ...super.invariants,
    Invariant('the number shown is the answer to the sum shown', (
      TestCase testCase,
    ) async {
      final expressionText = find.byKey(const Key('expression'));
      // The history is a screen of its own, and has no display on it.
      if (expressionText.evaluate().isEmpty) return;
      final expression = ui.tester.widget<Text>(expressionText).data ?? '';
      final shown =
          ui.tester.widget<Text>(find.byKey(const Key('answer'))).data ?? '';
      final expected = answerFor(expression);
      if (shown == expected) return;
      await saveFrame(ui, counterexampleImage);
      throw StateError(
        'the display reads "$expression" with "$shown" under it, but '
        '"$expression" ${expected.isEmpty ? 'is not a sum' : 'is $expected'}',
      );
    }),
  ];
}

void main() {
  // Real fonts, so the picture of the failing frame has words in it rather
  // than the black boxes a widget test draws by default.
  setUpAll(loadRealFonts);

  testWidgets('the number shown is the answer to the sum shown', (
    WidgetTester tester,
  ) async {
    await runProperty(
      (TestCase testCase) async {
        final ui = await UiSurface.open(tester, const AbacusApp());
        await runStateful(testCase, AbacusMachine(ui));
      },
      settings: const Settings(
        // Enough to find a two-step counterexample many times over, and
        // small enough that the whole run is a demonstration rather than a
        // wait. Every step is a real frame, and shrinking replays the case.
        testCases: 60,
        statefulStepCount: 8,
        database: Database.disabled,
      ),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
