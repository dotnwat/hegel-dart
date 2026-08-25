/// A configuration sweep: generate the world rather than the actions, and let
/// Flutter's own error reporting be the oracle.
///
///     flutter test test/layout_test.dart
///
/// This is the shape that finds something on an app that has never been
/// property-tested, because nothing has to be written down first. The screen
/// is the one the team already has; the claim is only that it can be rendered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hegel/hegel.dart';
import 'package:hegel_flutter/hegel_flutter.dart';

import 'apps/profile_card.dart';

/// Every screen anyone ships, at every text scale a phone offers up to twice.
///
/// A property's bounds are a specification. This one says what the card is
/// promised to survive; a card that must also survive a three-times scale is
/// a different promise, and saying so is the point.
Generator<DeviceProfile> supportedDevices() =>
    deviceProfiles(size: screenSizes(), textScale: textScales(max: 2.0));

void main() {
  widgetProperty('a repaired profile card fits every supported screen', (
    TestCase testCase,
    WidgetTester tester,
  ) async {
    final device = testCase.draw(supportedDevices(), name: 'device');
    final name = testCase.draw(hostileText(), name: 'name');
    await UiSurface.open(
      tester,
      profileScreen(ProfileCard(name: name, role: 'Engineer', robust: true)),
      device: device,
    );
  }, settings: const Settings(testCases: 200, database: Database.disabled));

  testWidgets('the overflow is found, and shrinks to a configuration', (
    WidgetTester tester,
  ) async {
    final report = <String>[];
    Object? failure;
    try {
      await runProperty(
        (TestCase testCase) async {
          final device = testCase.draw(supportedDevices(), name: 'device');
          final name = testCase.draw(hostileText(), name: 'name');
          await UiSurface.open(
            tester,
            profileScreen(ProfileCard(name: name, role: 'Engineer')),
            device: device,
          );
        },
        settings: const Settings(
          testCases: 200,
          database: Database.disabled,
          verbosity: Verbosity.quiet,
          // A sweep this wide finds more than one way to overflow the same
          // card -- on the right at one configuration, at the bottom at
          // another -- and by default the engine reports every distinct
          // failure it found. That is the right default and the wrong one for
          // a demonstration, which should say the same thing every run.
          reportMultipleFailures: false,
        ),
        onDiagnostic: report.add,
      );
    } on Object catch (error) {
      failure = error;
    }

    debugPrint(report.join('\n'));
    expect(failure, isNotNull, reason: 'the card overflows somewhere');
    // The failure is Flutter's own, raised by the frame that could not be
    // laid out, and collected by the surface rather than left to surface
    // after the run.
    expect(failure.toString(), contains('overflowed'));
    // The counterexample names the configuration, which is the thing a
    // developer has to reproduce by hand.
    expect(report.join('\n'), contains('device ='));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
