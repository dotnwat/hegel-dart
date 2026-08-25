/// What the calculator has worked out already.
library;

import 'package:flutter/material.dart';

/// One sum and its answer.
@immutable
final class Calculation {
  /// A calculation of [expression] giving [answer].
  const Calculation(this.expression, this.answer);

  /// The sum, as it was typed.
  final String expression;

  /// What it came to, formatted.
  final String answer;
}

/// What the app opens with, so that there is something to recall on a fresh
/// start the way there would be on a real one.
const List<Calculation> seededHistory = <Calculation>[
  Calculation('12×3', '36'),
  Calculation('100−7', '93'),
  Calculation('8÷2', '4'),
];

/// The list of past calculations, newest first.
///
/// Popping with an expression puts it back on the calculator; popping with
/// nothing leaves the calculator alone.
class HistoryPage extends StatelessWidget {
  /// A page over [history], oldest first as it is stored.
  const HistoryPage({super.key, required this.history, required this.onClear});

  /// Every calculation so far, in the order they were made.
  final List<Calculation> history;

  /// Called when the list is emptied.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final newestFirst = history.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: <Widget>[
          IconButton(
            key: const Key('clear-history'),
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_outline),
            onPressed: newestFirst.isEmpty
                ? null
                : () {
                    onClear();
                    Navigator.of(context).pop();
                  },
          ),
        ],
      ),
      body: newestFirst.isEmpty
          ? const Center(child: Text('Nothing worked out yet.'))
          : ListView.separated(
              itemCount: newestFirst.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final calculation = newestFirst[index];
                return ListTile(
                  key: Key('history-$index'),
                  title: Text(calculation.expression),
                  subtitle: Text('= ${calculation.answer}'),
                  trailing: const Icon(Icons.north_west),
                  onTap: () =>
                      Navigator.of(context).pop(calculation.expression),
                );
              },
            ),
    );
  }
}
