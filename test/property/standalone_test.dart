@Tags(<String>['e2e'])
@TestOn('vm')
// Skipped on Windows for the same reason test/property/e2e_test.dart is: a
// nested Dart process re-copies the engine into `.dart_tool/lib/`, and Windows
// will not let it delete a DLL the outer `dart test` already has loaded. The
// promise this file checks is not one that varies by platform -- there is no
// package:test zone on any of them -- so what is lost here is a repetition.
@OnPlatform(<String, Object>{
  'windows': Skip('a nested Dart run cannot re-copy the engine DLL'),
})
library;

import 'dart:io';

import 'package:test/test.dart';

/// A script that drives `runProperty` with no package:test around it.
const String standalonePath = 'test/fixture/standalone_fixture.dart';

/// Runs the script and hands back everything it wrote, from both streams.
Future<({int exitCode, String output})> runStandalone() async {
  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'run',
    standalonePath,
  ]);
  return (
    exitCode: result.exitCode,
    output: '${result.stdout}${result.stderr}',
  );
}

void main() {
  group('a property that fails in more than one way, outside a test', () {
    test('hands the first failure to whoever awaited the run', () async {
      final run = await runStandalone();

      // The contract every caller has, whatever harness they are: the future
      // completes with the property's own error, and an ordinary catch gets
      // it.
      expect(run.output, contains('CAUGHT Bad state: an odd value'));
    });

    test('lets nothing escape past the caller', () async {
      final run = await runStandalone();

      // The regression this file exists for. package:test's channel for an
      // extra error is `Zone.current.handleUncaughtError`, which outside a
      // test hands the error to nobody and kills the process -- on a
      // property that failed in the ordinary way and was about to be
      // reported properly.
      expect(run.exitCode, 0, reason: run.output);
      expect(run.output, isNot(contains('Unhandled exception')));
      expect(
        run.output,
        contains('AFTER'),
        reason: 'the script has to reach its own end',
      );
    });

    test('reports the other failure with its counterexample', () async {
      final run = await runStandalone();

      // Not raised anywhere, so the block has to carry it: the error text
      // above the draws that produced it, rather than a counterexample with
      // no failure attached to it.
      expect(run.output, contains('Bad state: an even value went large: 100'));
      expect(run.output, contains('value = 100'));
      expect(run.output, contains('The property failed in 2 distinct ways'));
    });
  });
}
