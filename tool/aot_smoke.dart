/// AOT bundling smoke target.
///
/// Built with `dart build cli` and run in CI: it proves the libhegel code
/// asset survives ahead-of-time compilation and is still resolvable from the
/// bundle, which plain `dart test` (JIT) cannot show. Exits non-zero unless
/// the engine it loads reports exactly the pinned version, and unless a
/// property runs through the public API and reaches a verdict.
///
/// Both halves, because they fail differently. Resolving `hegel_version`
/// proves the asset is there; it says nothing about whether a run can be
/// started, cases pulled, values drawn, and a failure shrunk through a
/// binary the SDK compiled and bundled. A workload runner built on
/// `runProperty` would depend on exactly that, and would find out here
/// rather than in the field.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:hegel/hegel.dart';
import 'package:hegel/src/libhegel/bindings.g.dart' as libhegel;
import 'package:hegel/src/libhegel/version.g.dart';

/// A run with nothing ambient about it: no database to read or write, and a
/// fixed seed, since a smoke test that varied would be a smoke test that
/// sometimes passed.
const Settings smokeSettings = Settings(
  testCases: 50,
  seed: 7,
  derandomize: true,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
);

Future<void> main() async {
  _checkVersion();
  if (exitCode != 0) return;
  await _checkProperty();
}

/// Fails unless a property holds, one fails, and the failure shrinks.
///
/// The whole layer in one pass: generation, the catch ladder, shrinking, and
/// the report. A bundle where the engine loads but the run loop cannot
/// advance passes the version check and fails here.
Future<void> _checkProperty() async {
  await runProperty((TestCase testCase) {
    testCase.draw(lists(integers(min: 0, max: 100), maxLength: 4));
  }, settings: smokeSettings);

  final said = <String>[];
  try {
    await runProperty(
      (TestCase testCase) {
        final value = testCase.draw(integers(min: 0, max: 1000), name: 'value');
        if (value > 10) throw StateError('$value is too big');
      },
      settings: smokeSettings,
      onDiagnostic: said.add,
    );
  } on StateError {
    // The counterexample the engine shrank to, raised as the body's own
    // error. Eleven is the smallest failing value, so anything else means
    // shrinking did not survive the bundle.
    final report = said.join('\n');
    if (!report.contains('value = 11')) {
      stderr.writeln('expected a shrunk counterexample, got:\n$report');
      exitCode = 1;
      return;
    }
    stdout.writeln('property ran, failed, and shrank to 11');
    return;
  }
  stderr.writeln('the failing property did not fail');
  exitCode = 1;
}

void _checkVersion() {
  final outVersion = calloc<Pointer<Char>>();
  try {
    final result = libhegel.hegel_version(nullptr, outVersion);
    if (result != libhegel.hegel_result_t.HEGEL_OK) {
      stderr.writeln('hegel_version returned $result');
      exitCode = 1;
      return;
    }

    final reported = outVersion.value.cast<Utf8>().toDartString();
    stdout.writeln('libhegel $reported');
    if (reported != libhegelVersion) {
      stderr.writeln('expected the pinned $libhegelVersion, got $reported');
      exitCode = 1;
    }
  } finally {
    calloc.free(outVersion);
  }
}
