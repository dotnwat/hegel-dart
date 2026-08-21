/// Best-effort reporting of handles that were never disposed.
///
/// Every handle the ABI hands out has exactly one matching free, and this
/// layer makes that the caller's job rather than the garbage collector's. The
/// tracking here exists to notice when someone forgets, not to clean up after
/// them: freeing from a finalizer would trade a leak for a free at an
/// unpredictable moment, which the ABI does not allow.
///
/// Active only when assertions are, so a release build pays nothing.
library;

import 'package:meta/meta.dart';

/// A handle that was collected without being disposed.
@immutable
final class LeakReport {
  /// Describes a leaked [kind] of handle created at [createdAt].
  const LeakReport(this.kind, this.createdAt);

  /// The wrapper class that was leaked, such as `Run`.
  final String kind;

  /// Where it was created, which is the only useful clue after the fact.
  final StackTrace createdAt;

  @override
  String toString() =>
      'hegel: a $kind was garbage collected without dispose(). The engine '
      'handle behind it was never released. Created at:\n$createdAt';
}

/// Where reports go. Replaceable so tests can read them.
///
/// Deliberately a plain function rather than a stream: a finalizer callback
/// must not throw, and must not depend on anything asynchronous still running.
@visibleForTesting
void Function(LeakReport report) reportLeak = _printLeak;

void _printLeak(LeakReport report) {
  // ignore: avoid_print
  print(report);
}

/// Restores the default reporter.
@visibleForTesting
void resetLeakReporting() => reportLeak = _printLeak;

/// Delivers a report without ever throwing into the collector.
///
/// A finalizer callback that throws would surface at an arbitrary point in an
/// unrelated part of the program, which is worse than the leak it is trying to
/// describe.
@visibleForTesting
void deliverLeakReport(LeakReport report) {
  try {
    reportLeak(report);
  } on Object {
    // Nothing useful to do here, and nowhere sensible to say it.
  }
}

final Finalizer<LeakReport> _finalizer = Finalizer<LeakReport>(
  deliverLeakReport,
);

/// Starts watching [owner], a wrapper around a handle of type [kind].
///
/// Returns true so it can be called from inside an assert, which is what keeps
/// it out of release builds along with the stack capture it needs.
@internal
bool trackHandle(Object owner, String kind) {
  _finalizer.attach(owner, LeakReport(kind, StackTrace.current), detach: owner);
  return true;
}

/// Stops watching [owner], which has been disposed properly.
@internal
bool releaseHandle(Object owner) {
  _finalizer.detach(owner);
  return true;
}
