/// Turning a failing frame into something you can look at.
library;

import 'dart:io';
import 'dart:typed_data' show ByteData, Uint8List;
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter/services.dart' show FontLoader;

import 'surface.dart';

/// Writes what is on screen to [path] as a PNG.
///
/// A counterexample from an interface is a script of taps and a sentence
/// about what did not hold. Both are exact, and neither is a picture of the
/// screen that was wrong -- which is the thing you actually want to put in
/// front of somebody, and the thing a shrunk case is small enough to be worth
/// producing.
///
/// Call it from an invariant that is about to fail, or from a `catch` around
/// the property. Rendering needs real asynchrony, so this borrows the tester's
/// real clock for the moment it takes; that is allowed from a property body
/// and from an invariant, and not from inside a pump.
///
/// The directory is made if it is not there. A frame with nothing painted in
/// it writes nothing.
Future<void> saveFrame(UiSurface ui, String path) async {
  await ui.tester.runAsync(() async {
    final view = ui.tester.binding.renderViews.first;
    final layer = view.debugLayer;
    if (layer is! OffsetLayer) return;
    final image = await layer.toImage(view.paintBounds);
    try {
      final data = await image.toByteData(format: ImageByteFormat.png);
      if (data == null) return;
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// Registers the fonts Flutter ships, so that a captured frame is readable.
///
/// A widget test draws every glyph as a filled box. That is the right default
/// -- a layout that depends on which fonts a machine happens to have is a
/// layout that fails on somebody else's machine -- and it makes a picture of
/// a failing frame useless, because the thing you wanted to read is a row of
/// black rectangles.
///
/// Call it from `setUpAll` in a test that captures frames, and only there.
/// Real fonts have real metrics, so a layout property that runs with them is
/// answering a different question than one that runs without.
///
/// Finds the fonts beside the SDK that is running the test. Does nothing if
/// they are not there, so a machine that has moved them gets boxes rather
/// than a failure.
Future<void> loadRealFonts() async {
  final fonts = _materialFonts();
  if (fonts == null) return;
  await _register(fonts, 'Roboto', <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await _register(fonts, 'MaterialIcons', <String>[
    'MaterialIcons-Regular.otf',
  ]);
}

Future<void> _register(
  Directory fonts,
  String family,
  List<String> files,
) async {
  final loader = FontLoader(family);
  var found = false;
  for (final name in files) {
    final file = File('${fonts.path}/$name');
    if (!file.existsSync()) continue;
    found = true;
    loader.addFont(
      file.readAsBytes().then(
        (List<int> bytes) => ByteData.sublistView(Uint8List.fromList(bytes)),
      ),
    );
  }
  if (found) await loader.load();
}

/// Where the SDK keeps Roboto and the Material icons.
Directory? _materialFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (root != null) '$root/bin/cache/artifacts/material_fonts',
    // `flutter test` runs the Dart inside the SDK's own cache, so the fonts
    // are three directories up from it even when nothing said where the SDK
    // is.
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
        '/artifacts/material_fonts',
  ];
  for (final path in candidates) {
    final directory = Directory(path);
    if (directory.existsSync()) return directory;
  }
  return null;
}
