@TestOn('vm')
library;

import 'package:hegel/src/property/config.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

StackTrace traceOf(List<String> frames) => Trace.parse(
  <String>[
    for (final (int index, String frame) in frames.indexed)
      '#$index      $frame',
  ].join('\n'),
);

void main() {
  group('the caller frame', () {
    test('is the first one outside this package', () {
      final frame = callerFrame(
        traceOf(<String>[
          'property (package:hegel/src/property/property.dart:52:7)',
          'main (file:///work/test/codec_test.dart:9:3)',
          'Declarer.declare (package:test_api/src/backend/declarer.dart:1:1)',
        ]),
      );

      expect(frame?.line, 9);
      expect(frame?.library, endsWith('codec_test.dart'));
    });

    test('is this file when asked from this file', () {
      // The synthetic traces above pin the filter; this pins that the filter
      // is looking at the shape of trace the runtime actually produces.
      expect(
        callerFrame(StackTrace.current)?.library,
        endsWith('test/property/config_test.dart'),
      );
    });

    test('is nothing when only this package ran', () {
      expect(
        callerFrame(
          traceOf(<String>[
            'property (package:hegel/src/property/property.dart:52:7)',
          ]),
        ),
        isNull,
      );
    });
  });

  group('a database key', () {
    test('names the file and the full test name', () {
      expect(
        databaseKeyFor(
          suite: 'test/codec_test.dart',
          testName: 'codec round trips',
        ),
        'test/codec_test.dart:codec round trips',
      );
    });

    test('separates two tests that share a name in different files', () {
      expect(
        databaseKeyFor(suite: 'test/a_test.dart', testName: 'round trips'),
        isNot(
          databaseKeyFor(suite: 'test/b_test.dart', testName: 'round trips'),
        ),
      );
    });
  });
}
