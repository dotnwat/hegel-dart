/// Result codes, the exception taxonomy, and the one funnel every fallible
/// libhegel call passes through.
library;

import 'bindings.g.dart' as raw;

/// A result code returned by a libhegel call.
///
/// [unknown] exists so that a code this binding does not recognise — from a
/// locally built or mismatched engine — produces an intelligible ABI-skew
/// diagnostic instead of a secondary lookup failure. The raw value is always
/// kept alongside it on [HegelException.rawCode].
enum HegelResultCode {
  /// The call succeeded.
  ok,

  /// The engine exhausted this test case's choice budget.
  stopTest,

  /// An assumption or precondition failed; the test case is invalid.
  assume,

  /// The randomness backend reported an error.
  backend,

  /// A handle argument was null where it must not be.
  invalidHandle,

  /// An argument other than a handle was invalid.
  invalidArg,

  /// The test case had already been completed.
  alreadyComplete,

  /// Something was read before it was ready.
  notComplete,

  /// An invariant inside libhegel was violated.
  internal,

  /// One handle was used from two threads at once.
  concurrentUse,

  /// A code this binding has no name for.
  unknown;

  /// The code [value] denotes, or [unknown] when it is unrecognised.
  static HegelResultCode fromNative(int value) => switch (value) {
    raw.hegel_result_t.HEGEL_OK => ok,
    raw.hegel_result_t.HEGEL_E_STOP_TEST => stopTest,
    raw.hegel_result_t.HEGEL_E_ASSUME => assume,
    raw.hegel_result_t.HEGEL_E_BACKEND => backend,
    raw.hegel_result_t.HEGEL_E_INVALID_HANDLE => invalidHandle,
    raw.hegel_result_t.HEGEL_E_INVALID_ARG => invalidArg,
    raw.hegel_result_t.HEGEL_E_ALREADY_COMPLETE => alreadyComplete,
    raw.hegel_result_t.HEGEL_E_NOT_COMPLETE => notComplete,
    raw.hegel_result_t.HEGEL_E_INTERNAL => internal,
    raw.hegel_result_t.HEGEL_E_CONCURRENT_USE => concurrentUse,
    _ => unknown,
  };
}

/// Signals that libhegel has run out of choice budget for this test case.
///
/// Control flow, not an error: the test body should unwind and the case be
/// reported as overrun. Carries no message or stack, because it is raised per
/// draw in hot loops.
final class StopTest implements Exception {
  /// Creates the signal.
  const StopTest();

  @override
  String toString() => 'StopTest: the engine ended this test case early';
}

/// Signals that an assumption did not hold, so this test case is invalid.
///
/// Control flow, not an error, exactly like [StopTest]. Draws that reject
/// themselves and a caller's own failed precondition raise the same type, so
/// engine-side and caller-side rejection unify in one catch.
final class AssumptionFailed implements Exception {
  /// Creates the signal.
  const AssumptionFailed();

  @override
  String toString() => 'AssumptionFailed: an assumption did not hold';
}

/// Raised when a libhegel call fails for a reason that is not control flow.
final class HegelException implements Exception {
  /// Creates an exception for [operation] failing with [rawCode].
  HegelException(this.operation, this.rawCode, this.message);

  /// The libhegel function that failed, for example `hegel_run_start`.
  final String operation;

  /// The result code exactly as the engine returned it.
  ///
  /// Kept verbatim so an unrecognised code is still reportable.
  final int rawCode;

  /// The engine's diagnostic, read before the next call could invalidate it.
  final String message;

  /// [rawCode] as a named code, or [HegelResultCode.unknown].
  HegelResultCode get code => HegelResultCode.fromNative(rawCode);

  @override
  String toString() {
    final named = code == HegelResultCode.unknown
        ? 'unknown code $rawCode'
        : '${code.name} ($rawCode)';
    return message.isEmpty
        ? 'HegelException: $operation failed with $named'
        : 'HegelException: $operation failed with $named: $message';
  }
}

/// Raises the exception [code] maps to. Only ever called for a failing code.
///
/// [StopTest] and [AssumptionFailed] are control flow and carry nothing;
/// everything else becomes a [HegelException] carrying the raw code and the
/// engine's own diagnostic.
Never throwForResult(int code, String operation, String message) {
  if (code == raw.hegel_result_t.HEGEL_E_STOP_TEST) throw const StopTest();
  if (code == raw.hegel_result_t.HEGEL_E_ASSUME) throw const AssumptionFailed();
  throw HegelException(operation, code, message);
}

/// Returns normally when [code] is success, and otherwise raises through
/// [throwForResult].
///
/// [describeError] supplies the engine's diagnostic and is consulted only on
/// the failure path: reading it costs a call into the engine, and its result
/// is invalidated by the next call on the same context.
void checkResult(int code, String operation, String Function() describeError) {
  if (code == raw.hegel_result_t.HEGEL_OK) return;
  throwForResult(code, operation, describeError());
}
