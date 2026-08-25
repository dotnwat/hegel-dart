/// What the interface is offering right now, found rather than declared.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart' show MatrixUtils;
import 'package:flutter/semantics.dart';

import 'surface.dart';

/// What a discovered action does.
enum UiActionKind {
  /// Tap it.
  tap,

  /// Put the keyboard in it and type.
  type,
}

/// Something a user could do to the interface as it stands.
///
/// Discovered from the semantics tree, which is the closest thing Flutter has
/// to a list of what a person can actually do: it is what a screen reader
/// reads, it knows what is disabled, and it covers a custom widget that
/// declared itself a button as well as it covers an `ElevatedButton`.
final class UiAction {
  /// An action called [id], of kind [kind], covering [rect].
  const UiAction({
    required this.id,
    required this.kind,
    required this.label,
    required this.rect,
  });

  /// What this action is called, in the report and in a draw.
  ///
  /// Taken from the label a screen reader would read, and made unique within
  /// a step by a numeric suffix when two things share one. Two properties of
  /// this matter: it is stable, so the same tree yields the same names, and
  /// it is readable, so a counterexample says `tap Add` rather than
  /// `tap action 4`.
  final String id;

  /// Tapping or typing.
  final UiActionKind kind;

  /// The label the semantics tree carries, which may be empty.
  ///
  /// An empty one is a finding in itself: a tappable thing no screen reader
  /// can announce. [UiCheck] `tappablesAreLabelled` is the check that says so.
  final String label;

  /// Where it is, in the coordinate space of the whole view.
  final Rect rect;

  @override
  String toString() => '$id (${kind.name})';
}

/// What a driver is allowed to do, and how much of it.
final class ActionPolicy {
  /// A policy that allows everything on screen.
  const ActionPolicy({this.avoid = const <String>{}, this.limit});

  /// Ids never chosen.
  ///
  /// The way to keep a driver inside the part of the app under test: a
  /// walk that can tap "Sign out" spends most of its steps signed out.
  final Set<String> avoid;

  /// At most this many actions are offered per step, in traversal order.
  ///
  /// A screen with two hundred rows on it offers two hundred actions, and a
  /// driver that picks uniformly from them will spend its whole budget on
  /// rows. Capping is a bias, and a bias is better said out loud than left
  /// to the shape of the screen.
  final int? limit;
}

/// Everything a user could do to the interface [ui] is showing.
///
/// Returned in accessibility traversal order, which is a function of the
/// widget tree and nothing else. That matters more than it looks: the engine
/// replays a case by replaying its choices, so a driver that draws "the third
/// available action" only reproduces if the third available action is the
/// same thing the second time round. Discovery has to be deterministic, and
/// the surface has to be hermetic, or a shrunk script is a script for an app
/// in a state that no longer exists.
///
/// Anything disabled is left out, and so is anything whose centre is off the
/// view -- a row scrolled past the bottom of a list is not something a user
/// can tap without scrolling to it first.
List<UiAction> discoverActions(
  UiSurface ui, {
  ActionPolicy policy = const ActionPolicy(),
}) {
  final handle = ui.tester.ensureSemantics();
  try {
    final view = _viewRect(ui);
    final used = <String, int>{};
    final found = <UiAction>[];
    for (final node in ui.tester.semantics.simulatedAccessibilityTraversal()) {
      final data = node.getSemanticsData();
      final isTextField = data.flagsCollection.isTextField;
      final isTappable = data.hasAction(SemanticsAction.tap);
      if (!isTextField && !isTappable) continue;
      // Tristate, because "has no enabled state" and "is disabled" are
      // different things: a plain tappable row has no such state and is
      // perfectly tappable, where a greyed-out button says so.
      if (data.flagsCollection.isEnabled == Tristate.isFalse) continue;
      final rect = _globalRect(node, ui.tester.view.devicePixelRatio);
      if (!view.contains(rect.center)) continue;

      final label = _readable(data);
      final base = label.isEmpty ? 'unlabelled' : label;
      // A screen with three "Delete" buttons on it has three actions, and a
      // report has to be able to say which. The suffix counts occurrences in
      // traversal order, so it means the same thing on every replay.
      final seen = (used[base] ?? 0) + 1;
      used[base] = seen;
      found.add(
        UiAction(
          id: seen == 1 ? base : '$base #$seen',
          kind: isTextField ? UiActionKind.type : UiActionKind.tap,
          label: label,
          rect: rect,
        ),
      );
    }
    final allowed = found
        .where((UiAction action) => !policy.avoid.contains(action.id))
        .toList();
    final limit = policy.limit;
    return limit == null || allowed.length <= limit
        ? allowed
        : allowed.sublist(0, limit);
  } finally {
    handle.dispose();
  }
}

/// Does [action], and runs the clock afterwards.
///
/// Typing focuses the field by tapping it and then types through the
/// platform's own text input, which is what a keyboard does; [text] is what
/// to type and is ignored for a tap.
Future<void> perform(UiSurface ui, UiAction action, {String text = ''}) async {
  switch (action.kind) {
    case UiActionKind.tap:
      await ui.tapAt(action.rect.center);
    case UiActionKind.type:
      await ui.tapAt(action.rect.center);
      await ui.typeIntoFocused(text);
  }
}

/// The best name the semantics tree has for a node.
String _readable(SemanticsData data) {
  for (final candidate in <String>[
    data.label,
    data.tooltip,
    data.value,
    data.hint,
  ]) {
    final cleaned = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isNotEmpty) {
      return cleaned.length <= 40 ? cleaned : cleaned.substring(0, 40);
    }
  }
  return '';
}

/// [node] in logical pixels, in the coordinate space of the whole view.
///
/// A semantics node's rect is in its own space, and each ancestor's transform
/// takes it one level out; the guidelines Flutter ships compute it the same
/// way, and stop there because they are checking sizes rather than pointing
/// at anything.
Rect _globalRect(SemanticsNode node, double ratio) {
  var rect = node.rect;
  for (
    SemanticsNode? current = node;
    current != null;
    current = current.parent
  ) {
    final transform = current.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  // The walk ends in physical pixels, because the root node's transform is
  // the one that scales by the density. `tapAt` speaks logical pixels, and so
  // does everything else a test says about where things are.
  return Rect.fromLTRB(
    rect.left / ratio,
    rect.top / ratio,
    rect.right / ratio,
    rect.bottom / ratio,
  );
}

Rect _viewRect(UiSurface ui) {
  final view = ui.tester.view;
  return Rect.fromLTWH(
    0,
    0,
    view.physicalSize.width / view.devicePixelRatio,
    view.physicalSize.height / view.devicePixelRatio,
  );
}
