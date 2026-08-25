/// The buttons.
library;

import 'package:flutter/material.dart';

import 'arithmetic.dart';

/// What a key does when it is pressed.
enum KeyKind {
  /// Adds a digit or a decimal point to the expression.
  entry,

  /// Adds an operator to the expression.
  operator,

  /// Works the expression out.
  equals,

  /// Takes the last character off.
  backspace,

  /// Starts again.
  clear,
}

/// One button on the keypad.
@immutable
final class CalculatorKey {
  /// A key labelled [label], identified by [id], of kind [kind].
  const CalculatorKey(
    this.id,
    this.label,
    this.kind, {
    this.flex = 1,
    this.icon,
  });

  /// What the widget key and the semantics label are built from.
  final String id;

  /// What is written on it.
  final String label;

  /// What pressing it does.
  final KeyKind kind;

  /// How much of its row it takes.
  final int flex;

  /// Drawn instead of [label], for a key whose meaning is a picture.
  final IconData? icon;
}

/// The keypad, row by row, in the order it is drawn.
const List<List<CalculatorKey>> keypadRows = <List<CalculatorKey>>[
  <CalculatorKey>[
    CalculatorKey('clear', 'C', KeyKind.clear, flex: 2),
    CalculatorKey(
      'backspace',
      '⌫',
      KeyKind.backspace,
      icon: Icons.backspace_outlined,
    ),
    CalculatorKey('divide', divideSign, KeyKind.operator),
  ],
  <CalculatorKey>[
    CalculatorKey('7', '7', KeyKind.entry),
    CalculatorKey('8', '8', KeyKind.entry),
    CalculatorKey('9', '9', KeyKind.entry),
    CalculatorKey('multiply', timesSign, KeyKind.operator),
  ],
  <CalculatorKey>[
    CalculatorKey('4', '4', KeyKind.entry),
    CalculatorKey('5', '5', KeyKind.entry),
    CalculatorKey('6', '6', KeyKind.entry),
    CalculatorKey('subtract', minusSign, KeyKind.operator),
  ],
  <CalculatorKey>[
    CalculatorKey('1', '1', KeyKind.entry),
    CalculatorKey('2', '2', KeyKind.entry),
    CalculatorKey('3', '3', KeyKind.entry),
    CalculatorKey('add', '+', KeyKind.operator),
  ],
  <CalculatorKey>[
    CalculatorKey('0', '0', KeyKind.entry, flex: 2),
    CalculatorKey('dot', '.', KeyKind.entry),
    CalculatorKey('equals', '=', KeyKind.equals),
  ],
];

/// Every key on the pad, in the order they are drawn.
List<CalculatorKey> get everyKey =>
    keypadRows.expand((List<CalculatorKey> row) => row).toList();

/// The keypad.
class Keypad extends StatelessWidget {
  /// A keypad that reports presses to [onPressed].
  const Keypad({super.key, required this.onPressed});

  /// Called with the key that was pressed.
  final void Function(CalculatorKey key) onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      children: <Widget>[
        for (final row in keypadRows)
          Expanded(
            child: Row(
              children: <Widget>[
                for (final key in row)
                  Expanded(
                    flex: key.flex,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _KeyButton(
                        entry: key,
                        onPressed: () => onPressed(key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.entry, required this.onPressed});

  final CalculatorKey entry;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (entry.kind) {
      KeyKind.equals => (scheme.primary, scheme.onPrimary),
      KeyKind.operator => (scheme.primaryContainer, scheme.onPrimaryContainer),
      KeyKind.clear || KeyKind.backspace => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      KeyKind.entry => (scheme.surfaceContainerHighest, scheme.onSurface),
    };
    return Semantics(
      button: true,
      label: _spokenName(entry),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('key-${entry.id}'),
          onTap: onPressed,
          child: Center(
            child: ExcludeSemantics(
              child: entry.icon == null
                  ? Text(
                      entry.label,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w500,
                          ),
                    )
                  : Icon(entry.icon, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a screen reader says for [key].
///
/// The glyphs on an operator key are not words, and a reader that announces
/// "multiplication sign" where a person would say "timesSign" is one nobody
/// listens to twice.
String _spokenName(CalculatorKey key) => switch (key.id) {
  'clear' => 'Clear',
  'backspace' => 'Backspace',
  'divide' => 'Divide',
  'multiply' => 'Multiply',
  'subtract' => 'Minus',
  'add' => 'Plus',
  'equals' => 'Equals',
  'dot' => 'Decimal point',
  _ => key.label,
};
