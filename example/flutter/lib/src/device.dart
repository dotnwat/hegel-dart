/// What a case runs on: the size, the density, the text scale, the platform.
library;

import 'dart:ui' show Brightness, Locale, Size;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:hegel/hegel.dart';

import 'surface.dart';

/// The world outside the widget under test.
///
/// Everything here is nullable and null means "leave it alone", so a profile
/// says only what a case wants to be different. [UiSurface.open] applies one
/// before it pumps and puts it back before the next case, which is what makes
/// a swept configuration a property rather than a leak.
final class DeviceProfile {
  /// A profile that changes nothing.
  const DeviceProfile({
    this.size,
    this.devicePixelRatio,
    this.textScale,
    this.brightness,
    this.platform,
    this.locale,
  });

  /// The screen, in logical pixels -- the units a `Widget` is written in.
  ///
  /// The physical size the view is told about is this times
  /// [devicePixelRatio], because that is the direction the framework does the
  /// arithmetic in and getting it backwards silently halves or doubles every
  /// layout.
  final Size? size;

  /// How many physical pixels there are to a logical one.
  final double? devicePixelRatio;

  /// The system text scale, as a multiplier of the app's own font sizes.
  final double? textScale;

  /// Light or dark, as the platform reports it.
  final Brightness? brightness;

  /// Which platform the framework should believe it is on.
  final TargetPlatform? platform;

  /// The system locale.
  final Locale? locale;

  /// This profile with [size] replaced, for narrowing a swept profile.
  DeviceProfile withSize(Size size) => DeviceProfile(
    size: size,
    devicePixelRatio: devicePixelRatio,
    textScale: textScale,
    brightness: brightness,
    platform: platform,
    locale: locale,
  );

  /// Short enough to read in a counterexample, and complete.
  ///
  /// This is what a failing draw prints, so it says everything the profile
  /// sets and nothing it does not: a report that says `360x640, text 2.0x` is
  /// one you can retype, and one that says `DeviceProfile` is not.
  @override
  String toString() {
    final parts = <String>[
      if (size case final value?)
        '${value.width.toStringAsFixed(0)}x${value.height.toStringAsFixed(0)}',
      if (devicePixelRatio case final value?) '@${value}x',
      if (textScale case final value?) 'text ${value}x',
      if (brightness case final value?) value.name,
      if (platform case final value?) value.name,
      if (locale case final value?) value.toLanguageTag(),
    ];
    return parts.isEmpty ? 'default device' : parts.join(', ');
  }
}

/// Screens of real devices, smallest first.
///
/// Shrinking walks a `sampledFrom` towards the front of its list, so the
/// order is not arbitrary: a counterexample that holds on every size reports
/// the smallest one, which is the one worth looking at.
const List<Size> commonScreenSizes = <Size>[
  Size(320, 568), // iPhone SE, and the smallest screen anyone still ships.
  Size(360, 640), // The commonest Android phone.
  Size(375, 812), // iPhone with a notch.
  Size(412, 915), // A large Android phone.
  Size(768, 1024), // iPad portrait.
  Size(1024, 768), // iPad landscape.
  Size(1280, 800), // A small desktop window.
  Size(1920, 1080), // A large one.
];

/// The text scales a system actually offers, smallest first.
///
/// Android goes to 2.0 in its settings and further with the accessibility
/// slider; iOS goes past 3.0 with larger accessibility sizes. A layout tested
/// at 1.0 alone is tested at the one setting nobody complains about.
const List<double> commonTextScales = <double>[
  1.0,
  0.85,
  1.15,
  1.3,
  1.5,
  2.0,
  3.0,
];

/// Locales worth sweeping, including two that are read right to left.
const List<Locale> commonLocales = <Locale>[
  Locale('en', 'US'),
  Locale('de', 'DE'), // Long compound words; the classic overflow.
  Locale('ja', 'JP'), // No spaces to break lines at.
  Locale('ar'), // Right to left.
  Locale('he'), // Right to left.
];

/// Real screens, and arbitrary ones.
///
/// Weighted towards the real ones, because a bug on a size somebody ships is
/// worth more than a bug at 837 by 1191 -- but not only the real ones,
/// because a resizable window is every size between them.
Generator<Size> screenSizes({
  double minWidth = 240,
  double maxWidth = 1920,
  double minHeight = 320,
  double maxHeight = 1200,
}) => oneOf(
  <Generator<Size>>[
    sampledFrom(
      commonScreenSizes
          .where(
            (Size size) =>
                size.width >= minWidth &&
                size.width <= maxWidth &&
                size.height >= minHeight &&
                size.height <= maxHeight,
          )
          .toList(),
    ),
    arbitraryScreenSizes(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    ),
  ],
  weights: <int>[3, 1],
);

/// Any screen in the given bounds, whether or not anyone ships one.
Generator<Size> arbitraryScreenSizes({
  double minWidth = 240,
  double maxWidth = 1920,
  double minHeight = 320,
  double maxHeight = 1200,
}) => composite(
  (TestCase testCase) => Size(
    testCase
        .draw(integers(min: minWidth.round(), max: maxWidth.round()))
        .toDouble(),
    testCase
        .draw(integers(min: minHeight.round(), max: maxHeight.round()))
        .toDouble(),
  ),
);

/// The text scales a system offers.
Generator<double> textScales({double max = 3.0}) => sampledFrom(
  commonTextScales.where((double scale) => scale <= max).toList(),
);

/// Pixel densities, coarsest first.
Generator<double> pixelRatios() => sampledFrom(<double>[1.0, 2.0, 3.0]);

/// The platforms the framework can be told it is on.
Generator<TargetPlatform> targetPlatforms() =>
    sampledFrom(TargetPlatform.values);

/// Light and dark.
Generator<Brightness> brightnesses() => sampledFrom(Brightness.values);

/// Locales worth sweeping.
Generator<Locale> locales() => sampledFrom(commonLocales);

/// Whole device configurations.
///
/// Each argument is a generator for that part of the profile, or null to
/// leave that part alone -- so `deviceProfiles(textScale: textScales())`
/// sweeps text scale over whatever screen the test view already has, and the
/// counterexample names one thing rather than six.
Generator<DeviceProfile> deviceProfiles({
  Generator<Size>? size,
  Generator<double>? devicePixelRatio,
  Generator<double>? textScale,
  Generator<Brightness>? brightness,
  Generator<TargetPlatform>? platform,
  Generator<Locale>? locale,
}) => composite(
  (TestCase testCase) => DeviceProfile(
    size: size == null ? null : testCase.draw(size),
    devicePixelRatio: devicePixelRatio == null
        ? null
        : testCase.draw(devicePixelRatio),
    textScale: textScale == null ? null : testCase.draw(textScale),
    brightness: brightness == null ? null : testCase.draw(brightness),
    platform: platform == null ? null : testCase.draw(platform),
    locale: locale == null ? null : testCase.draw(locale),
  ),
);
