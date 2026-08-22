@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/property/reporting.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

/// A stack trace made of [frames], in the format the VM prints.
StackTrace traceOf(List<String> frames) => Trace.parse(
  <String>[
    for (final (int index, String frame) in frames.indexed)
      '#$index      $frame',
  ].join('\n'),
);

/// A value whose `toString` throws, as a mock with a missing stub does.
final class Unrenderable {
  const Unrenderable();

  @override
  String toString() => throw StateError('cannot render');
}

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
      // Built from the directory's own URI rather than by pasting a path
      // together: on Windows the two use different separators.
      final file = Directory.current.uri.resolve('test/property/x.dart');
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

  group('a frame file', () {
    test('is separated the same way whatever platform named it', () {
      // Windows CI and a Linux laptop have to agree. They would not: the
      // frame renders a file URI with the host's own separator, and that
      // string ends up in both the origin the engine groups by and the key
      // the example database files counterexamples under.
      expect(
        fileOf(r'test\property\codec_test.dart'),
        'test/property/codec_test.dart',
      );
      expect(
        fileOf('test/property/codec_test.dart'),
        'test/property/codec_test.dart',
      );
      expect(fileOf('package:app/thing.dart'), 'package:app/thing.dart');
    });
  });

  group('a rendered value', () {
    test('quotes a string, so an empty one looks like something', () {
      expect(repr('hello'), "'hello'");
      expect(repr(''), "''");
      expect(repr('   '), "'   '");
    });

    test('makes whitespace and control characters visible', () {
      // The whole reason for not using toString: a counterexample that is a
      // newline and a counterexample that is a space print identically
      // otherwise, and telling them apart is the entire task.
      expect(repr('a\nb\tc\r'), r"'a\nb\tc\r'");
      expect(repr("it's"), r"'it\'s'");
      expect(repr(r'back\slash'), r"'back\\slash'");
      expect(repr('\u0000'), r"'\u{0}'");
      expect(repr('\u007f'), r"'\u{7f}'");
    });

    test('leaves printable text alone, whatever alphabet it is in', () {
      expect(repr('naïve 日本語 🎉'), "'naïve 日本語 🎉'");
    });

    test('escapes a stranded surrogate rather than printing nothing', () {
      expect(repr(String.fromCharCode(0xd800)), r"'\u{d800}'");
    });

    test('renders bytes as bytes', () {
      expect(repr(Uint8List.fromList(<int>[0, 255, 58])), 'bytes(00ff3a)');
      expect(repr(Uint8List(0)), 'bytes()');
    });

    test('goes through collections, so their contents are visible too', () {
      expect(repr(<int>[1, 2]), '[1, 2]');
      expect(repr(<String>['a', '']), "['a', '']");
      expect(repr(<String>{'a'}), "{'a'}");
      expect(repr(<String, int>{'k': 1}), "{'k': 1}");
      expect(
        repr(<List<String>>[
          <String>['a'],
        ]),
        "[['a']]",
      );
      expect(repr(<int>[]), '[]');
    });

    test('renders anything else the way it renders itself', () {
      expect(repr(null), 'null');
      expect(repr(42), '42');
      expect(repr(1.5), '1.5');
      expect(repr(double.nan), 'NaN');
      expect(repr(true), 'true');
      expect(repr((1, 'a')), '(1, a)');
    });

    test('says so rather than throwing when a value will not render', () {
      // The report is written before the property's failure is raised, so an
      // exception from here would replace the counterexample the reader was
      // about to be shown with one from the reporter.
      expect(repr(const Unrenderable()), '<unprintable Unrenderable>');
      expect(
        repr(<Object>[1, const Unrenderable()]),
        '[1, <unprintable Unrenderable>]',
      );
    });

    test('does not chase a value that contains itself', () {
      final looping = <Object>[];
      looping.add(looping);

      expect(repr(looping), '[...]');
    });

    test('renders a value that merely repeats, both times', () {
      // Identity, not equality: two equal lists are two values, and hiding
      // the second would hide a counterexample where both being equal is
      // the point.
      final twice = <String>['a'];

      expect(repr(<List<String>>[twice, twice]), "[['a'], ['a']]");
    });
  });

  group('a failure report', () {
    test('names each draw, falling back to its position', () {
      expect(
        renderFailure(
          draws: <Drawn>[
            (name: 'message', value: <int>[0, 128]),
            (name: null, value: 'x'),
          ],
          notes: <String>[],
          hints: <String>[],
        ),
        "message = [0, 128]\ndraw_2 = 'x'",
      );
    });

    test('keeps the notes and the hints in sections of their own', () {
      expect(
        renderFailure(
          draws: <Drawn>[(name: 'n', value: 1)],
          notes: <String>['before', 'after'],
          hints: <String>['Seed: 7.'],
        ),
        'n = 1\n\nbefore\nafter\n\nSeed: 7.',
      );
    });

    test('leaves out a section there is nothing to put in', () {
      expect(
        renderFailure(
          draws: <Drawn>[],
          notes: <String>[],
          hints: <String>['Seed: 7.'],
        ),
        'Seed: 7.',
      );
    });
  });

  group('a reproduction hint', () {
    test('says what the engine does when nobody chose', () {
      expect(reproductionHints(const Settings()).single, contains('under CI'));
    });

    test('says nothing was kept when the database is off', () {
      expect(
        reproductionHints(const Settings(database: Database.disabled)).single,
        contains('not kept'),
      );
    });

    test('names the default location when that is what was chosen', () {
      expect(
        reproductionHints(
          const Settings(database: Database.standard, databaseKey: 'k'),
        ).single,
        contains('.hegel/examples'),
      );
    });

    test('does not repeat a path back to whoever wrote it', () {
      expect(
        reproductionHints(
          const Settings(database: Database.at('/tmp/x'), databaseKey: 'k'),
        ).single,
        allOf(contains('example database'), isNot(contains('/tmp/x'))),
      );
    });

    test('prints the blob when nobody said to keep counterexamples', () {
      // The engine decides in that case, it decides against under CI, and CI
      // is where a blob is the only way to get a failure back.
      expect(
        reproductionHints(const Settings(), blob: 'AAEC'),
        contains(contains("reproduce: 'AAEC'")),
      );
      expect(
        reproductionHints(
          const Settings(database: Database.disabled),
          blob: 'AAEC',
        ),
        contains(contains("reproduce: 'AAEC'")),
      );
    });

    test('leaves it out when the counterexample is being kept', () {
      expect(
        reproductionHints(
          const Settings(database: Database.standard, databaseKey: 'k'),
          blob: 'AAEC',
        ),
        isNot(contains(contains('reproduce'))),
      );
    });

    test('does what it is told when it is told', () {
      expect(
        reproductionHints(
          const Settings(database: Database.standard, databaseKey: 'k'),
          blob: 'AAEC',
          printBlob: true,
        ),
        contains(contains('reproduce')),
      );
      expect(
        reproductionHints(const Settings(), blob: 'AAEC', printBlob: false),
        isNot(contains(contains('reproduce'))),
      );
    });

    test('has nothing to print when there is no blob', () {
      expect(
        reproductionHints(const Settings(), printBlob: true),
        isNot(contains(contains('reproduce'))),
      );
    });

    test('promises no replay when there was no run to keep one', () {
      // A single test case, a nondeterministic run, a bare replay from a
      // blob: nothing was stored, so pointing the reader at a database would
      // send them somewhere that has never heard of this failure.
      expect(
        reproductionHints(
          const Settings(database: Database.standard, databaseKey: 'k'),
          stored: false,
        ),
        isEmpty,
      );
      expect(
        reproductionHints(const Settings(seed: 3), stored: false),
        <String>['Seed: 3.'],
      );
    });

    test('gives the seed only when there was one to give', () {
      expect(reproductionHints(const Settings(seed: 7)), contains('Seed: 7.'));
      expect(
        reproductionHints(const Settings()),
        isNot(contains(startsWith('Seed'))),
      );
    });
  });
}
