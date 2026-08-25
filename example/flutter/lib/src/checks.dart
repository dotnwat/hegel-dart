/// Invariants an interface has to satisfy whatever state it is in.
library;

import 'package:flutter_test/flutter_test.dart';

import 'surface.dart';

/// The frame built and painted without Flutter reporting anything.
///
/// The one check every user-interface property should hold, and the reason
/// the rest of this library is careful about draining: an overflow, a failed
/// assertion in a build method, an exception in a callback and a thrown error
/// in a gesture handler all arrive the same way, and all of them mean the
/// state the app just reached is a state it cannot render.
const UiCheck noFlutterErrors = UiCheck(
  'the interface built without errors',
  _drain,
);

void _drain(UiSurface ui) => ui.drain();

/// Every tappable thing is at least 48 by 48, as Android asks.
final UiCheck tapTargetsAreLargeEnough = UiCheck(
  'every tap target meets the Android minimum size',
  (UiSurface ui) => _guideline(ui, androidTapTargetGuideline),
);

/// Every tappable thing is at least 44 by 44, as iOS asks.
final UiCheck tapTargetsAreLargeEnoughForIos = UiCheck(
  'every tap target meets the iOS minimum size',
  (UiSurface ui) => _guideline(ui, iOSTapTargetGuideline),
);

/// Every tappable thing has something a screen reader can say about it.
final UiCheck tappablesAreLabelled = UiCheck(
  'every tap target has a label',
  (UiSurface ui) => _guideline(ui, labeledTapTargetGuideline),
);

/// Text stands out from what is behind it well enough to read.
final UiCheck textContrastIsSufficient = UiCheck(
  'text meets the contrast guideline',
  (UiSurface ui) => _guideline(ui, textContrastGuideline),
);

/// The accessibility guidelines Flutter ships, as one list.
///
/// These are the checks nobody runs over more than a handful of hand-written
/// states, which is exactly what makes them worth holding against generated
/// ones: they are already written, they already hold everywhere or should,
/// and the states that break them are the states nobody thought to screenshot.
final List<UiCheck> accessibilityChecks = <UiCheck>[
  tapTargetsAreLargeEnough,
  tappablesAreLabelled,
  textContrastIsSufficient,
];

/// Holds [guideline] against everything currently on screen.
///
/// The guidelines read the semantics tree, which only exists while something
/// is holding it open. `testWidgets` holds it open by default; this asks
/// again rather than assuming, because a caller that turned it off would
/// otherwise get an empty tree and a check that passes by finding nothing.
Future<void> _guideline(UiSurface ui, AccessibilityGuideline guideline) async {
  final handle = ui.tester.ensureSemantics();
  try {
    await expectLater(ui.tester, meetsGuideline(guideline));
  } finally {
    handle.dispose();
  }
}
