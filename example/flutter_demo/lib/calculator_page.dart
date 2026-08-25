/// The calculator screen: a display, a keypad, and the wiring between them.
library;

import 'package:flutter/material.dart';

import 'arithmetic.dart';
import 'history.dart';
import 'keypad.dart';

/// Abacus.
class CalculatorPage extends StatefulWidget {
  /// The calculator.
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  /// The sum being typed.
  String _expression = '';

  /// What is under it: a preview while typing, the answer after `=`.
  String _answer = '';

  /// Whether the number below the expression is an answer rather than a
  /// preview. Pressing an operator now continues from it, the way a
  /// calculator does: `5+5=` and then `+` means `10+`.
  bool _showingAnswer = false;

  /// Everything worked out so far, oldest first.
  List<Calculation> _history = List<Calculation>.of(seededHistory);

  /// The one place the expression changes.
  ///
  /// The answer under it is whatever the expression comes to, so the two
  /// cannot drift apart -- which is the only thing anyone has to get right
  /// about a calculator display.
  void _setExpression(String next, {bool showingAnswer = false}) {
    setState(() {
      _expression = next;
      _answer = answerFor(next);
      _showingAnswer = showingAnswer;
    });
  }

  void _press(CalculatorKey key) {
    switch (key.kind) {
      case KeyKind.entry:
        _setExpression(_showingAnswer ? key.label : _expression + key.label);
      case KeyKind.operator:
        _setExpression(
          _showingAnswer ? _answer + key.label : _expression + key.label,
        );
      case KeyKind.backspace:
        _setExpression(
          _expression.isEmpty
              ? ''
              : _expression.substring(0, _expression.length - 1),
        );
      case KeyKind.clear:
        _setExpression('');
      case KeyKind.equals:
        _equals();
    }
  }

  void _equals() {
    if (_showingAnswer) return;
    final value = evaluate(_expression);
    if (value == null) return;
    final answer = formatAnswer(value);
    setState(() {
      _history = <Calculation>[..._history, Calculation(_expression, answer)];
      _answer = answer;
      _showingAnswer = true;
    });
  }

  Future<void> _openHistory() async {
    final recalled = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext context) => HistoryPage(
          history: _history,
          onClear: () => setState(() => _history = <Calculation>[]),
        ),
      ),
    );
    if (recalled == null || !mounted) return;
    // Put the recalled sum back on the display.
    setState(() => _expression = recalled);
  }

  void _resetDemo() {
    setState(() => _history = List<Calculation>.of(seededHistory));
    _setExpression('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Abacus'),
        actions: <Widget>[
          IconButton(
            key: const Key('open-history'),
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
          ),
          PopupMenuButton<String>(
            key: const Key('menu'),
            tooltip: 'More',
            onSelected: (String _) => _resetDemo(),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                key: Key('reset-demo'),
                value: 'reset',
                child: Text('Reset demo'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _expression,
                      key: const Key('expression'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (_showingAnswer)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              '=',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            _answer,
                            key: const Key('answer'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: _showingAnswer
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: _showingAnswer
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(flex: 4, child: Keypad(onPressed: _press)),
        ],
      ),
    );
  }
}
