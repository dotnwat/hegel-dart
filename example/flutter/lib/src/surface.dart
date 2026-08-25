/// One case's worth of running interface, and the discipline that keeps it
/// from being the last case's.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device.dart';

/// How far to run the clock after an interaction.
typedef Advance = Future<void> Function(WidgetTester tester);

/// Pump until nothing is scheduled: the right answer for an app whose
/// animations end.
Future<void> settleFully(WidgetTester tester) => tester.pumpAndSettle();

/// Pump exactly one frame.
Future<void> oneFrame(WidgetTester tester) => tester.pump();

/// Pump [count] frames of sixteen milliseconds each.
///
/// For an app with an animation that never ends -- a spinner, a looping hero,
/// a pulsing dot -- where [settleFully] would run out its own budget and
/// report a timeout as though it were the bug.
Advance frames(int count) => (WidgetTester tester) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
};

/// More than one thing went wrong in one frame.
///
/// A single broken layout reports as itself; a frame that reported several
/// errors reports as this, with all of them in it. The distinction matters
/// because a `Row` that overflows horizontally and vertically at once is two
/// errors about one mistake, and a report that shows one of them and counts
/// the rest is a report that sends you to the wrong place.
final class UiFrameErrors implements Exception {
  /// The errors one frame reported.
  const UiFrameErrors(this.errors);

  /// What Flutter reported, in the order it reported them.
  final List<FlutterErrorDetails> errors;

  @override
  String toString() {
    final lines = errors
        .map((FlutterErrorDetails details) => details.exceptionAsString())
        .join('\n\n');
    return 'The interface reported ${errors.length} errors:\n\n$lines';
  }
}

/// Something that must be true of the interface, whatever state it is in.
///
/// The oracle half of a user-interface property. A check is written once and
/// held against every state the engine can drive the app into, which is the
/// difference between an accessibility audit of three screenshots and one of
/// every screen the app has.
final class UiCheck {
  /// A check called [name], which throws when it does not hold.
  const UiCheck(this.name, this.check);

  /// What this check is called, in the report.
  final String name;

  /// What has to be true. Throws if it is not.
  final FutureOr<void> Function(UiSurface ui) check;
}

/// A widget test's tester, with a case's worth of app pumped into it.
///
/// Everything a property does to the interface goes through one of these, for
/// two reasons that are easy to get wrong by hand.
///
/// The first is that Flutter *captures* errors rather than throwing them at
/// the code that caused them. A `RenderFlex` that overflows, an assertion in
/// a build method, an exception in a callback: all of them are reported to
/// the binding and held there. A property body that does not collect them
/// sees the case pass, and the failure surfaces later, outside the run, with
/// nothing shrunk. Every method here collects them, so a broken frame fails
/// the case that built it.
///
/// The second is that a case has to start from nothing. Pumping a new widget
/// into a tester reuses the render tree where it can, and Flutter reports a
/// given overflow once per render object and then keeps quiet -- so the same
/// screen at the same size overflows on the case that meets it first and
/// passes on every case after. That is a property whose result depends on
/// what ran before it, which the engine correctly reports as a flaky test.
/// [open] tears the previous tree down and puts the world back before it
/// pumps anything, which is what makes a case mean the same thing on the
/// first run and on the shrink.
final class UiSurface {
  UiSurface._(this.tester, this.device, this.advance);

  /// The tester underneath, for anything this class does not wrap.
  ///
  /// Reaching for it is fine and expected; what it does not do is collect
  /// captured errors, so follow anything that changes the tree with [drain].
  final WidgetTester tester;

  /// The configuration this case is running under.
  final DeviceProfile device;

  /// How far the clock is run after an interaction.
  final Advance advance;

  /// Pumps [app] into [tester] with nothing left of the last case.
  ///
  /// Resets the view and the platform overrides, tears down the previous
  /// tree, applies [device], pumps, and throws anything Flutter captured on
  /// the way in -- so a screen that cannot even build fails at the case that
  /// built it.
  static Future<UiSurface> open(
    WidgetTester tester,
    Widget app, {
    DeviceProfile device = const DeviceProfile(),
    Advance advance = settleFully,
  }) async {
    _installSink();
    _resetWorld(tester);
    // Down to nothing, and only then up again. A different widget type at the
    // root is what makes the framework discard the old element tree rather
    // than update it.
    await tester.pumpWidget(const SizedBox.shrink());
    // Whatever the last case left behind died with its tree; it is not this
    // case's failure.
    _sink?.clear();
    _applyDevice(tester, device);
    await tester.pumpWidget(app);
    await advance(tester);
    final surface = UiSurface._(tester, device, advance);
    surface.drain();
    return surface;
  }

  /// Puts the world back the way a fresh test found it.
  ///
  /// Call it from `addTearDown` in a test that configures a device by hand.
  /// [open] does it for every case, so a property does not need to.
  static void reset(WidgetTester tester) => _resetWorld(tester);

  static void _resetWorld(WidgetTester tester) {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
    debugDefaultTargetPlatformOverride = null;
    // Decoded images outlive the tree that asked for them, so a case that
    // renders differently the second time it is run is a case that shrinks
    // into nonsense.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  static void _applyDevice(WidgetTester tester, DeviceProfile device) {
    final ratio = device.devicePixelRatio;
    if (ratio != null) tester.view.devicePixelRatio = ratio;
    if (device.size case final size?) {
      // The view is told a physical size; the widgets are written in logical
      // ones. Multiplying here is what makes `size` mean what a Widget means
      // by it at any density.
      final effective = ratio ?? tester.view.devicePixelRatio;
      tester.view.physicalSize = size * effective;
    }
    if (device.textScale case final scale?) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
    }
    if (device.brightness case final brightness?) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
    }
    if (device.locale case final locale?) {
      tester.platformDispatcher.localeTestValue = locale;
      // Both, because a MaterialApp resolves against the list and the single
      // value is what everything else reads.
      tester.platformDispatcher.localesTestValue = <Locale>[locale];
    }
    if (device.platform case final platform?) {
      debugDefaultTargetPlatformOverride = platform;
    }
  }

  /// Throws whatever Flutter reported since this was last called.
  ///
  /// A single error is rethrown as it was raised, so an overflow reports as
  /// the overflow and an assertion as the assertion; several become one
  /// [UiFrameErrors] carrying all of them.
  void drain() {
    final error = takeError();
    if (error != null) throw error;
  }

  /// Whatever Flutter reported since this was last called, without throwing.
  ///
  /// For a property that is *about* the error -- one asserting a screen
  /// refuses bad input loudly -- rather than one that must not produce any.
  Object? takeError() {
    // The binding keeps its own copy of the first error of each frame, so
    // that an uncaught asynchronous one still finds a home there; clearing it
    // here is what keeps the two views of the world in step.
    tester.takeException();
    final sink = _sink;
    if (sink == null || sink.isEmpty) return null;
    final errors = List<FlutterErrorDetails>.of(sink);
    sink.clear();
    return errors.length == 1 ? errors.single.exception : UiFrameErrors(errors);
  }

  /// Taps [finder], runs the clock, and collects what that broke.
  Future<void> tap(Finder finder) async {
    await tester.tap(finder);
    await _settle();
  }

  /// Taps at [location] in the coordinate space of the whole view.
  Future<void> tapAt(Offset location) async {
    await tester.tapAt(location);
    await _settle();
  }

  /// Presses and holds [finder].
  Future<void> longPress(Finder finder) async {
    await tester.longPress(finder);
    await _settle();
  }

  /// Types [value] into [finder], replacing what was there.
  Future<void> enterText(Finder finder, String value) async {
    await tester.enterText(finder, value);
    await _settle();
  }

  /// Types [value] into whatever holds the keyboard focus.
  ///
  /// For a driver that found a text field through the semantics tree and has
  /// a node rather than a finder to name it by.
  Future<void> typeIntoFocused(String value) async {
    tester.testTextInput.enterText(value);
    await _settle();
  }

  /// Drags [finder] by [offset], for a scroll or a swipe.
  Future<void> drag(Finder finder, Offset offset) async {
    await tester.drag(finder, offset);
    await _settle();
  }

  /// Goes back the way the platform's back affordance would.
  Future<void> pageBack() async {
    await tester.pageBack();
    await _settle();
  }

  /// Runs the clock without doing anything, and collects what that broke.
  Future<void> settle() => _settle();

  /// Holds every check in [checks] against the interface as it stands.
  ///
  /// The first one that does not hold is the failure, named by its own name,
  /// so a report says which invariant broke rather than only that one did.
  Future<void> check(List<UiCheck> checks) async {
    for (final check in checks) {
      await check.check(this);
    }
  }

  Future<void> _settle() async {
    await advance(tester);
    drain();
  }
}

/// Where Flutter's reported errors are put while a test is running.
///
/// The binding has its own place for them, and `takeException` is the way to
/// read it -- but it holds exactly one. A second error arriving before the
/// first is taken replaces both with a summary that counts them and names
/// none, which is the wrong report for a frame that overflowed in two
/// directions at once. So the errors are collected here instead, all of them,
/// and handed over whole.
List<FlutterErrorDetails>? _sink;

/// Starts collecting, once per test.
///
/// The handler is put back when the test ends. Nothing is lost by collecting
/// here: the first error of every frame is passed to the binding as well, so
/// a frame that broke and was never drained still fails the test the way it
/// would have without any of this.
void _installSink() {
  if (_sink != null) return;
  final sink = <FlutterErrorDetails>[];
  _sink = sink;
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    // The first error of each frame goes to the binding as well as here.
    // The binding asserts that an uncaught asynchronous error arrives with
    // one already pending -- a handler that swallowed everything would turn
    // an ordinary thrown error into an assertion failure about handlers --
    // and passing only the first keeps it from dumping the rest to the
    // console, which is what it does when two are pending at once.
    if (sink.isEmpty) previous?.call(details);
    sink.add(details);
  };
  addTearDown(() {
    FlutterError.onError = previous;
    _sink = null;
  });
}
