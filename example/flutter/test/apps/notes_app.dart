/// A notes app with an unguarded index in it.
///
/// The kind of bug a monkey finds and a model does not need to know about:
/// the button that moves a note up is drawn on every row, including the
/// first, and moving the first row up reaches for the row above it.
library;

import 'package:flutter/material.dart';

/// A list of notes, optionally with the bounds check it needs.
class NotesApp extends StatefulWidget {
  /// A notes app. [guarded] adds the missing bounds check.
  const NotesApp({super.key, this.guarded = false});

  /// Whether moving the first note up is refused rather than attempted.
  final bool guarded;

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  final List<String> _notes = <String>[];
  final TextEditingController _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _add() => setState(() {
    final text = _draft.text.trim();
    _notes.add(text.isEmpty ? 'Note ${_notes.length + 1}' : text);
    _draft.clear();
  });

  void _moveUp(int index) => setState(() {
    // The whole bug: index zero has nothing above it, and the button that
    // calls this is drawn on row zero like every other row.
    if (widget.guarded && index == 0) return;
    final note = _notes[index];
    _notes[index] = _notes[index - 1];
    _notes[index - 1] = note;
  });

  void _remove(int index) => setState(() => _notes.removeAt(index));

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _draft,
                    decoration: const InputDecoration(
                      labelText: 'New note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _add, child: const Text('Add')),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _notes.length,
              itemBuilder: (BuildContext context, int index) => ListTile(
                title: Text(
                  _notes[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Move up',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () => _moveUp(index),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(index),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
