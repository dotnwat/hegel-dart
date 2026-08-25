/// Property-based testing for Flutter user interfaces, powered by hegel.
///
/// A user-interface property is a claim about every state a user can drive
/// the app into, checked against states the engine generates. There are three
/// shapes of it here, and they differ in what they use for an oracle.
///
/// A **configuration sweep** generates the world rather than the actions:
/// screen size, text scale, locale, platform, and the content the screen is
/// asked to show. The oracle is Flutter itself, which reports an overflow or
/// a failed assertion for a frame it cannot render, and the accessibility
/// guidelines it already ships. Nothing has to be written down for this to
/// find something on an app that has never been tested this way.
///
/// A **model-based property** generates the actions and compares the screen
/// against a model of what it should be showing. This is [UiMachine], and the
/// counterexample is the shortest script of taps that drives the two apart.
///
/// A **monkey** generates the actions and knows nothing about them: it does
/// whatever the interface currently offers and only insists that the app go
/// on working. This is [MonkeyMachine], it needs no model at all, and what it
/// adds over an ordinary monkey test is that a forty-tap crash shrinks to the
/// three taps that had to happen.
///
/// All three run under `flutter test` on the host, so an app built for a
/// phone is tested the same way as one built for a desktop.
library;

import 'src/machine.dart';

export 'src/actions.dart'
    show ActionPolicy, UiAction, UiActionKind, discoverActions, perform;
export 'src/checks.dart'
    show
        accessibilityChecks,
        noFlutterErrors,
        tapTargetsAreLargeEnough,
        tapTargetsAreLargeEnoughForIos,
        tappablesAreLabelled,
        textContrastIsSufficient;
export 'src/device.dart';
export 'src/machine.dart' show MonkeyMachine, UiMachine;
export 'src/property.dart' show widgetProperty;
export 'src/surface.dart'
    show
        Advance,
        UiCheck,
        UiFrameErrors,
        UiSurface,
        frames,
        oneFrame,
        settleFully;
export 'src/text.dart' show hostileStrings, hostileText;
