/// A counter with a bug that only a sequence can find.
///
/// The bug is in what `reset` forgets rather than in what it does, which is
/// why no single action reveals it and why a property over one value at a
/// time would never have looked: the decrement button is enabled by an
/// increment and disabled by nothing, so a counter that has been incremented
/// and then reset will happily go below zero.
library;

import 'package:flutter/material.dart';

/// A counter app, optionally with the bug fixed.
class CounterApp extends StatefulWidget {
  /// A counter. [fixed] repairs `reset`.
  const CounterApp({super.key, this.fixed = false});

  /// Whether `reset` clears the flag that gates decrement.
  final bool fixed;

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;
  bool _canDecrement = false;

  void _increment() => setState(() {
    _count++;
    _canDecrement = true;
  });

  void _decrement() => setState(() {
    if (_canDecrement) _count--;
  });

  void _reset() => setState(() {
    _count = 0;
    // The whole bug: without this the counter is reset but the permission to
    // decrement is not, and the next decrement takes it to minus one.
    if (widget.fixed) _canDecrement = false;
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Counter')),
      body: Center(
        child: Text(
          '$_count',
          key: const Key('display'),
          style: Theme.of(context).textTheme.displayMedium,
        ),
      ),
      persistentFooterButtons: <Widget>[
        TextButton(
          key: const Key('increment'),
          onPressed: _increment,
          child: const Text('Add one'),
        ),
        TextButton(
          key: const Key('decrement'),
          onPressed: _decrement,
          child: const Text('Take one'),
        ),
        TextButton(
          key: const Key('reset'),
          onPressed: _reset,
          child: const Text('Reset'),
        ),
      ],
    ),
  );
}
