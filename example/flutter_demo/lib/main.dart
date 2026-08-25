/// Abacus: a calculator with a bug in it.
///
///     flutter run -d linux
///
/// A toy, but not a widget on its own: two screens, a keypad, a history that
/// can be recalled from, and arithmetic of its own that is tested where
/// arithmetic should be tested. The bug it has is not in any of that. It is
/// in the wiring between the screens, which is the part no test of a pure
/// function can reach.
library;

import 'package:flutter/material.dart';

import 'calculator_page.dart';

void main() => runApp(const AbacusApp());

/// The colour the app is built out of.
const Color _seed = Color(0xFF4C6EF5);

/// Worked out once rather than on every build.
///
/// Deriving a Material palette from a seed colour is real arithmetic, and
/// `colorSchemeSeed:` does it every time the app is built. That is invisible
/// in an app, which is built once, and it is a fifth of the cost of a case in
/// a property that builds one per case.
final ThemeData _light = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _seed),
  useMaterial3: true,
);

final ThemeData _dark = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
);

/// The app.
class AbacusApp extends StatelessWidget {
  /// Abacus.
  const AbacusApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Abacus',
    debugShowCheckedModeBanner: false,
    theme: _light,
    darkTheme: _dark,
    home: const CalculatorPage(),
  );
}
