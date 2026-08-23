/// Pins on what shrinking costs, not on where it lands.
///
/// The exact-value pins in shrink_test.dart would all stay green if a span
/// change made the shrinker take ten times as many probes to reach the same
/// minimum -- the report only shows where the search ended. So each test
/// here runs a canonical failing shape, counts how many times the body ran
/// after the failure was first found, and holds that count under a ceiling.
///
/// The ceilings are ratchets, not measurements: each sits a few multiples
/// above what the pinned seed actually costs today, noted per test, so that
/// engine-bump drift passes and an order-of-magnitude regression -- the kind
/// a misplaced span causes -- fails loudly. Seeded and derandomized, the
/// counts are exact on every machine; a bump that moves one is a review
/// question exactly the way a moved shrink pin is.
@TestOn('vm')
library;

import 'dart:async';

import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/shrink_pin.dart';

/// What one failing run cost, and where it ended.
final class _Measured {
  _Measured({required this.postDiscovery, required this.report});

  /// Body executions after the one that first failed: the shrink probes and
  /// the final replay, which is everything the search itself cost.
  final int postDiscovery;

  /// The block the run printed about the case it settled on.
  final String report;
}

/// Runs a failing property under [pinSettings] and counts what it cost.
///
/// [body] calls `found` on the executions that fail, which is what lets the
/// count start at the discovery rather than at the start of the run:
/// generation-phase variance is real but is not the shrinker's bill.
Future<_Measured> _measure(
  FutureOr<void> Function(TestCase testCase, void Function() found) body, {
  required int seed,
}) async {
  var calls = 0;
  var discovery = 0;
  final said = <String>[];
  try {
    await runProperty(
      (TestCase testCase) async {
        calls++;
        await body(testCase, () {
          if (discovery == 0) discovery = calls;
        });
      },
      settings: pinSettings(seed: seed),
      onDiagnostic: said.add,
    );
  } on Object {
    expect(discovery, isPositive, reason: 'the failure was never discovered');
    return _Measured(postDiscovery: calls - discovery, report: said.join('\n'));
  }
  fail('the property was meant to fail, so there is nothing to measure');
}

void main() {
  test('an integer walks to its boundary in bounded calls', () async {
    // 241 post-discovery calls at this seed today.
    final measured = await _measure(seed: 1, (
      TestCase testCase,
      void Function() found,
    ) {
      final value = testCase.draw(integers(), name: 'value');
      if (value >= 1000) {
        found();
        throw StateError('$value is past the boundary');
      }
    });

    expect(measured.report, contains('value = 1000'));
    expect(measured.postDiscovery, lessThan(600));
  });

  test('a list empties itself around its sum in bounded calls', () async {
    // 1059 post-discovery calls at this seed today.
    final measured = await _measure(seed: 2, (
      TestCase testCase,
      void Function() found,
    ) {
      final value = testCase.draw(lists(integers(min: 0)), name: 'value');
      if (value.fold<int>(0, (int sum, int element) => sum + element) >= 1000) {
        found();
        throw StateError('$value sums too high');
      }
    });

    expect(measured.report, contains('value = [1000]'));
    expect(measured.postDiscovery, lessThan(2500));
  });

  test('a nested list flattens in bounded calls', () async {
    // The shape that costs when spans go wrong: the failure is about the
    // total across the inner lists, so the shrinker has to move length
    // between collections rather than within one. 1062 post-discovery
    // calls at this seed today.
    final measured = await _measure(seed: 4, (
      TestCase testCase,
      void Function() found,
    ) {
      final value = testCase.draw(
        lists(lists(integers(min: -128, max: 127))),
        name: 'value',
      );
      if (value.fold<int>(
            0,
            (int sum, List<int> inner) => sum + inner.length,
          ) >=
          5) {
        found();
        throw StateError('$value holds too much');
      }
    });

    expect(measured.report, contains('value = [[0, 0, 0, 0, 0]]'));
    expect(measured.postDiscovery, lessThan(2500));
  });
}
