@TestOn('vm')
library;

import 'dart:io';

import 'package:hegel/src/property/reporting.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

/// A stack trace made of [frames], in the format the VM prints.
StackTrace traceOf(List<String> frames) => Trace.parse(
  <String>[
    for (final (int index, String frame) in frames.indexed)
      '#$index      $frame',
  ].join('\n'),
);

void main() {
  group('an origin', () {
    test('names the first frame that is not the framework', () {
      final origin = originOf(
        StateError('boom'),
        traceOf(<String>[
          'Expect.fail (package:matcher/src/expect/expect.dart:149:31)',
          'expect (package:test_api/src/expect/expect.dart:52:3)',
          'main.<anonymous closure> (package:app/widget.dart:31:5)',
        ]),
      );

      expect(origin, 'StateError at package:app/widget.dart:31');
    });

    test('walks past the runtime as well as the framework', () {
      final origin = originOf(
        ArgumentError('nope'),
        traceOf(<String>[
          '_AsyncAwaitCompleter.completeError (dart:async/runtime.dart:45:2)',
          'Zone.run (dart:async/zone.dart:1661:54)',
          'check (package:app/check.dart:8:11)',
        ]),
      );

      expect(origin, 'ArgumentError at package:app/check.dart:8');
    });

    test('reports a file path relative to where the run started', () {
      // Absolute paths differ between machines, and an origin that differs
      // between machines is a different bug on each of them -- including to
      // the example database, which is checked out alongside the code.
      final file = Uri.file('${Directory.current.path}/test/property/x.dart');
      final origin = originOf(
        StateError('boom'),
        traceOf(<String>['main ($file:12:9)']),
      );

      expect(origin, 'StateError at test/property/x.dart:12');
    });

    test('is the same for two failures raised from the same place', () {
      final trace = traceOf(<String>['main (package:app/a.dart:4:1)']);

      expect(
        originOf(StateError('first'), trace),
        originOf(StateError('second, larger'), trace),
        reason: 'the engine groups by this, and one bug is one group',
      );
    });

    test('separates two places in one body', () {
      expect(
        originOf(
          StateError('x'),
          traceOf(<String>['main (package:app/a.dart:4:1)']),
        ),
        isNot(
          originOf(
            StateError('x'),
            traceOf(<String>['main (package:app/a.dart:9:1)']),
          ),
        ),
      );
    });

    test('falls back to the kind of error when only framework frames ran', () {
      final origin = originOf(
        FormatException('bad'),
        traceOf(<String>[
          'Invoker.<anonymous closure> (package:test_api/src/invoker.dart:2:1)',
          'runProperty (package:hegel/src/property/runner.dart:9:1)',
        ]),
      );

      expect(origin, 'FormatException');
    });

    test('leaves out a line number it does not have', () {
      // Built by hand: a frame with no position is what a trace from a
      // compiled or minified stack looks like, and no format this parses
      // produces one on demand.
      final trace = Trace(<Frame>[
        Frame(Uri.parse('package:app/a.dart'), null, null, 'main'),
      ]);

      expect(
        originOf(StateError('boom'), trace),
        'StateError at package:app/a.dart',
      );
    });
  });
}
