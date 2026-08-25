/// Tests of the surface itself, and of the Flutter behaviour it exists to
/// work around.
///
/// The first two are a pair, and they are the reason this library has a
/// lifecycle rather than a helper: Flutter reports a given render object's
/// overflow once and then keeps quiet about it, so a property that reuses the
/// tree between cases gets a different answer depending on which case met the
/// broken layout first. That is not a flaky engine; it is a flaky test, and
/// the engine is right to say so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hegel_flutter/hegel_flutter.dart';

/// A row too wide for the box it is in, at any width below 200.
Widget tooWide(double width) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: width,
      child: const Row(
        children: <Widget>[
          SizedBox(width: 100, child: Text('a')),
          SizedBox(width: 100, child: Text('b')),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('Flutter reports one render object\'s overflow only once', (
    WidgetTester tester,
  ) async {
    // The control, without the surface: pumping the same broken layout three
    // times reports it once, because the second and third pumps update the
    // render object the first one made rather than building a new one.
    final reported = <bool>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.pumpWidget(tooWide(150));
      reported.add(tester.takeException() != null);
    }
    expect(reported, <bool>[true, false, false]);
  });

  testWidgets('a surface reports it every time', (WidgetTester tester) async {
    final reported = <bool>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      Object? error;
      try {
        await UiSurface.open(tester, tooWide(150));
      } on Object catch (thrown) {
        error = thrown;
      }
      reported.add(error != null);
    }
    expect(reported, <bool>[true, true, true]);
  });

  testWidgets('a frame that breaks twice reports both', (
    WidgetTester tester,
  ) async {
    Object? error;
    try {
      // Two rows, each too wide for the box it is in: two render objects,
      // two errors, one frame. `takeException` alone would say only that
      // there were two of something.
      await UiSurface.open(
        tester,
        MaterialApp(
          home: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var row = 0; row < 2; row++)
                SizedBox(
                  width: 50,
                  child: Row(
                    children: const <Widget>[
                      SizedBox(width: 100, height: 20),
                      SizedBox(width: 100, height: 20),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    } on Object catch (thrown) {
      error = thrown;
    }
    expect(error, isA<UiFrameErrors>());
    expect((error! as UiFrameErrors).errors.length, greaterThan(1));
    expect(error.toString(), contains('overflowed'));
  });

  testWidgets('a device does not outlive the case that set it', (
    WidgetTester tester,
  ) async {
    await UiSurface.open(
      tester,
      const MaterialApp(home: Placeholder()),
      device: const DeviceProfile(
        size: Size(320, 568),
        devicePixelRatio: 1,
        textScale: 3,
      ),
    );
    expect(tester.view.physicalSize, const Size(320, 568));

    final ui = await UiSurface.open(
      tester,
      const MaterialApp(home: Placeholder()),
    );
    final media = MediaQuery.of(ui.tester.element(find.byType(Placeholder)));
    expect(tester.view.physicalSize, isNot(const Size(320, 568)));
    expect(media.textScaler.scale(10), 10);
  });

  testWidgets(
    'discovery finds what a user can reach, and not what they cannot',
    (WidgetTester tester) async {
      final ui = await UiSurface.open(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                TextButton(onPressed: () {}, child: const Text('Live')),
                const TextButton(onPressed: null, child: Text('Dead')),
                TextField(
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (String _) {},
                ),
              ],
            ),
          ),
        ),
      );
      final found = discoverActions(ui);
      expect(found.map((UiAction action) => action.id), <String>[
        'Live',
        'Name',
      ], reason: 'a disabled button is not something a user can do');
      expect(found.last.kind, UiActionKind.type);
      // The policy is what keeps a walk inside the part of the app under test.
      expect(
        discoverActions(
          ui,
          policy: const ActionPolicy(avoid: <String>{'Live'}),
        ).map((UiAction action) => action.id),
        <String>['Name'],
      );
    },
  );
}
