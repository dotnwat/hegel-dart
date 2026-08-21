@TestOn('vm')
library;

import 'package:hegel/src/libhegel/bindings.g.dart' as raw;
import 'package:hegel/src/libhegel/errors.dart';
import 'package:test/test.dart';

void main() {
  group('HegelResultCode.fromNative', () {
    test('names every code the ABI defines', () {
      expect(
        <int, HegelResultCode>{
          for (final code in <int>[
            raw.hegel_result_t.HEGEL_OK,
            raw.hegel_result_t.HEGEL_E_STOP_TEST,
            raw.hegel_result_t.HEGEL_E_ASSUME,
            raw.hegel_result_t.HEGEL_E_BACKEND,
            raw.hegel_result_t.HEGEL_E_INVALID_HANDLE,
            raw.hegel_result_t.HEGEL_E_INVALID_ARG,
            raw.hegel_result_t.HEGEL_E_ALREADY_COMPLETE,
            raw.hegel_result_t.HEGEL_E_NOT_COMPLETE,
            raw.hegel_result_t.HEGEL_E_INTERNAL,
            raw.hegel_result_t.HEGEL_E_CONCURRENT_USE,
          ])
            code: HegelResultCode.fromNative(code),
        },
        <int, HegelResultCode>{
          0: HegelResultCode.ok,
          -1: HegelResultCode.stopTest,
          -2: HegelResultCode.assume,
          -3: HegelResultCode.backend,
          -4: HegelResultCode.invalidHandle,
          -5: HegelResultCode.invalidArg,
          -6: HegelResultCode.alreadyComplete,
          -7: HegelResultCode.notComplete,
          -8: HegelResultCode.internal,
          -9: HegelResultCode.concurrentUse,
        },
      );
    });

    // An engine built from a newer source than this binding can return a code
    // with no name here; that has to stay reportable rather than crash the
    // lookup.
    test('falls back to unknown for a code it has no name for', () {
      expect(HegelResultCode.fromNative(-99), HegelResultCode.unknown);
      expect(HegelResultCode.fromNative(7), HegelResultCode.unknown);
    });

    test('covers every enum value except unknown', () {
      final named = HegelResultCode.values.toSet()
        ..remove(HegelResultCode.unknown);
      final mapped = <HegelResultCode>{
        for (var code = -9; code <= 0; code++) HegelResultCode.fromNative(code),
      };
      expect(mapped, named);
    });
  });

  group('throwForResult', () {
    test('raises StopTest for the budget-exhausted code', () {
      expect(
        () => throwForResult(
          raw.hegel_result_t.HEGEL_E_STOP_TEST,
          'hegel_generate_integer',
          'ignored',
        ),
        throwsA(isA<StopTest>()),
      );
    });

    test('raises AssumptionFailed for the rejection code', () {
      expect(
        () => throwForResult(
          raw.hegel_result_t.HEGEL_E_ASSUME,
          'hegel_pool_generate',
          'ignored',
        ),
        throwsA(isA<AssumptionFailed>()),
      );
    });

    // The two signals are control flow, so nothing should be tempted to catch
    // them as engine errors.
    test('keeps the signals outside HegelException', () {
      expect(const StopTest(), isNot(isA<HegelException>()));
      expect(const AssumptionFailed(), isNot(isA<HegelException>()));
    });

    test('raises HegelException carrying operation, code, and message', () {
      expect(
        () => throwForResult(
          raw.hegel_result_t.HEGEL_E_INVALID_ARG,
          'hegel_generate_integer',
          'min_value exceeds max_value',
        ),
        throwsA(
          isA<HegelException>()
              .having(
                (HegelException e) => e.operation,
                'operation',
                'hegel_generate_integer',
              )
              .having((HegelException e) => e.rawCode, 'rawCode', -5)
              .having(
                (HegelException e) => e.code,
                'code',
                HegelResultCode.invalidArg,
              )
              .having(
                (HegelException e) => e.message,
                'message',
                'min_value exceeds max_value',
              ),
        ),
      );
    });

    test('keeps an unrecognised code verbatim', () {
      expect(
        () => throwForResult(-4242, 'hegel_run_start', 'from the future'),
        throwsA(
          isA<HegelException>()
              .having((HegelException e) => e.rawCode, 'rawCode', -4242)
              .having(
                (HegelException e) => e.code,
                'code',
                HegelResultCode.unknown,
              ),
        ),
      );
    });
  });

  group('checkResult', () {
    test('returns without consulting the engine on success', () {
      var consulted = false;
      checkResult(raw.hegel_result_t.HEGEL_OK, 'hegel_version', () {
        consulted = true;
        return '';
      });
      // Reading the diagnostic costs a call into the engine, so the success
      // path must not pay for it.
      expect(consulted, isFalse);
    });

    test('consults the engine exactly once on failure', () {
      var reads = 0;
      expect(
        () => checkResult(raw.hegel_result_t.HEGEL_E_BACKEND, 'hegel_x', () {
          reads++;
          return 'backend exploded';
        }),
        throwsA(isA<HegelException>()),
      );
      expect(reads, 1);
    });

    // This test previously asserted reads == 1 under this very name: it
    // described the behaviour it wanted and then pinned the opposite, so the
    // wasted call it existed to prevent went unnoticed.
    test('does not consult the engine for control-flow signals', () {
      var reads = 0;
      String read() {
        reads++;
        return 'unused';
      }

      expect(
        () => checkResult(raw.hegel_result_t.HEGEL_E_STOP_TEST, 'draw', read),
        throwsA(isA<StopTest>()),
      );
      expect(
        () => checkResult(raw.hegel_result_t.HEGEL_E_ASSUME, 'draw', read),
        throwsA(isA<AssumptionFailed>()),
      );
      // Both signals are raised per draw in hot loops, carry no message, and
      // would discard a diagnostic anyway.
      expect(reads, 0);
    });

    test('classifies which codes are control flow', () {
      expect(isControlFlowResult(raw.hegel_result_t.HEGEL_E_STOP_TEST), isTrue);
      expect(isControlFlowResult(raw.hegel_result_t.HEGEL_E_ASSUME), isTrue);
      expect(isControlFlowResult(raw.hegel_result_t.HEGEL_E_BACKEND), isFalse);
      expect(isControlFlowResult(raw.hegel_result_t.HEGEL_OK), isFalse);
    });
  });

  group('toString', () {
    test('names the code and quotes the diagnostic', () {
      final exception = HegelException('hegel_run_start', -5, 'bad settings');
      expect(
        exception.toString(),
        'HegelException: hegel_run_start failed with invalidArg (-5): '
        'bad settings',
      );
    });

    test('omits an empty diagnostic', () {
      expect(
        HegelException('hegel_run_free', -8, '').toString(),
        'HegelException: hegel_run_free failed with internal (-8)',
      );
    });

    test('reports an unrecognised code as such', () {
      expect(
        HegelException('hegel_x', -77, 'huh').toString(),
        contains('unknown code -77'),
      );
    });

    test('describes the control-flow signals', () {
      expect(const StopTest().toString(), contains('ended this test case'));
      expect(
        const AssumptionFailed().toString(),
        contains('assumption did not hold'),
      );
    });
  });
}
