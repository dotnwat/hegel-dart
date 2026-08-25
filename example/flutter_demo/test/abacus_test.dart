/// The app builds, adds up, and remembers.
///
/// Ordinary example-based widget tests: enough to know the demonstration app
/// works before any property is written about it.
library;

import 'package:abacus/calculator_page.dart';
import 'package:abacus/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> press(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('key-$id')));
  await tester.pumpAndSettle();
}

String shown(WidgetTester tester, String id) =>
    tester.widget<Text>(find.byKey(Key(id))).data ?? '';

void main() {
  testWidgets('it adds up', (WidgetTester tester) async {
    await tester.pumpWidget(const AbacusApp());
    await press(tester, '5');
    await press(tester, 'add');
    await press(tester, '5');
    expect(shown(tester, 'expression'), '5+5');
    expect(shown(tester, 'answer'), '10', reason: 'a live preview');
    await press(tester, 'equals');
    expect(shown(tester, 'answer'), '10');
  });

  testWidgets('an answer can be built on', (WidgetTester tester) async {
    await tester.pumpWidget(const AbacusApp());
    await press(tester, '5');
    await press(tester, 'add');
    await press(tester, '5');
    await press(tester, 'equals');
    await press(tester, 'multiply');
    expect(shown(tester, 'expression'), '10×', reason: 'chained from 10');
    await press(tester, '3');
    await press(tester, 'equals');
    expect(shown(tester, 'answer'), '30');
  });

  testWidgets('a calculation goes into the history', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AbacusApp());
    await press(tester, '7');
    await press(tester, 'add');
    await press(tester, '1');
    await press(tester, 'equals');
    await tester.tap(find.byKey(const Key('open-history')));
    await tester.pumpAndSettle();
    expect(find.text('7+1'), findsOneWidget);
    expect(find.text('= 8'), findsOneWidget);
  });

  testWidgets('the demo resets', (WidgetTester tester) async {
    await tester.pumpWidget(const AbacusApp());
    await press(tester, '9');
    expect(shown(tester, 'expression'), '9');
    await tester.tap(find.byKey(const Key('menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-demo')));
    await tester.pumpAndSettle();
    expect(shown(tester, 'expression'), '');
    expect(find.byType(CalculatorPage), findsOneWidget);
  });
}
