@TestOn('vm')
library;

import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/property/config.dart';
import 'package:hegel/src/property/reporting.dart';
import 'package:hegel/src/property/runner.dart';
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

    test('is this file, named the way the key needs it named', () {
      // Two things at once. The synthetic traces above pin the filter; this
      // pins that the filter is looking at the shape of trace the runtime
      // actually produces. And the path is relative rather than absolute,
      // which is what keeps a database key the same on two machines -- an
      // absolute one would make every checkout a different property, and
      // nothing would ever replay anywhere but where it was found.
      expect(
        fileOf(callerFrame(StackTrace.current)!.library),
        'test/property/config_test.dart',
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

  group('resolved settings', () {
    const Settings written = Settings(
      testCases: 7,
      seed: 3,
      database: Database.standard,
      databaseKey: null,
    );

    test('keep what the caller wrote when nothing overrides it', () {
      final resolved = resolveSettings(
        written,
        environment: <String, String>{},
        databaseKey: 'derived',
      );

      expect(resolved.testCases, 7);
      expect(resolved.seed, 3);
      expect(resolved.database, Database.standard);
      expect(resolved.databaseKey, 'derived');
    });

    test('leave a key the caller chose alone', () {
      final resolved = resolveSettings(
        const Settings(databaseKey: 'shared'),
        environment: <String, String>{},
        databaseKey: 'derived',
      );

      expect(resolved.databaseKey, 'shared');
    });

    test('let the environment win over what the caller wrote', () {
      // The point of setting one is to change a run on a machine whose source
      // you are not editing, so losing to the source would make them useless.
      final resolved = resolveSettings(
        written,
        environment: <String, String>{
          testCasesVariable: '3',
          databaseVariable: '/tmp/examples',
        },
        databaseKey: 'derived',
      );

      expect(resolved.testCases, 3);
      expect(resolved.database, const Database.at('/tmp/examples'));
      expect(resolved.seed, 3, reason: 'nothing else is touched');
    });

    test('read an empty database path as no database at all', () {
      final resolved = resolveSettings(
        written,
        environment: <String, String>{databaseVariable: ''},
        databaseKey: 'derived',
      );

      expect(resolved.database, Database.disabled);
    });

    test('refuse a case count that is not one', () {
      expect(
        () => resolveSettings(
          written,
          environment: <String, String>{testCasesVariable: 'lots'},
        ),
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            allOf(contains(testCasesVariable), contains('"lots"')),
          ),
        ),
      );
      expect(
        () => resolveSettings(
          written,
          environment: <String, String>{testCasesVariable: '-1'},
        ),
        throwsA(isA<PropertyError>()),
      );
    });
  });
}
