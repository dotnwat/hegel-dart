@TestOn('vm')
library;

import 'package:hegel/hegel.dart';
import 'package:test/test.dart';

/// Runs [body] to completion at [verbosity] and returns the diagnostic lines.
Future<List<String>> statisticsOf(
  Future<void> Function(TestCase) body, {
  Verbosity verbosity = Verbosity.verbose,
}) async {
  final lines = <String>[];
  await runProperty(
    body,
    settings: Settings(
      testCases: 40,
      seed: 20260824,
      derandomize: true,
      verbosity: verbosity,
      database: Database.disabled,
    ),
    onDiagnostic: lines.add,
  );
  return lines;
}

void main() {
  group('collect', () {
    test(
      'tallies one observation per call, per valid case, by label',
      () async {
        final lines = await statisticsOf((testCase) async {
          final n = testCase.draw(integers(min: 0, max: 9));
          testCase.collect(n.isEven ? 'even' : 'odd', label: 'parity');
          testCase.collect(n < 5, label: 'small');
        });

        expect(lines, contains('Statistics:'));
        expect(
          lines,
          contains(matches(RegExp(r'^  parity \(\d+ observed\):$'))),
        );
        expect(
          lines,
          contains(matches(RegExp(r'^  small \(\d+ observed\):$'))),
        );
        expect(
          lines,
          contains(matches(RegExp(r'^    \d+% \(\d+\) (even|odd)$'))),
        );
      },
    );

    test('discards what a rejected case observed on its way out', () async {
      final lines = await statisticsOf((testCase) async {
        final keep = testCase.draw(booleans());
        if (!keep) {
          testCase.collect('dropped', label: 'kept');
          testCase.assume(false);
        }
        testCase.collect('kept', label: 'kept');
      });

      expect(lines.join('\n'), isNot(contains('dropped')));
      expect(lines.join('\n'), contains('kept'));
    });

    test('discards what a declined stateful rule observed', () async {
      final lines = await statisticsOf((testCase) async {
        await runStateful(testCase, _CollectingMachine());
      });

      expect(lines.join('\n'), isNot(contains('declined-step')));
      expect(lines.join('\n'), contains('ran'));
    });

    test('stays silent below verbose', () async {
      final lines = await statisticsOf((testCase) async {
        testCase.collect('anything');
      }, verbosity: Verbosity.normal);

      expect(lines.join('\n'), isNot(contains('Statistics:')));
    });

    test('stays silent when nothing was collected', () async {
      final lines = await statisticsOf((testCase) async {
        testCase.draw(integers(min: 0, max: 9));
      });

      expect(lines.join('\n'), isNot(contains('Statistics:')));
    });
  });
}

final class _CollectingMachine extends StateMachine {
  @override
  List<Rule> get rules => [
    Rule('runs', (testCase) {
      testCase.collect('ran', label: 'steps');
    }),
    Rule('declines', (testCase) {
      testCase.collect('declined-step', label: 'steps');
      testCase.assume(false);
    }),
  ];
}
