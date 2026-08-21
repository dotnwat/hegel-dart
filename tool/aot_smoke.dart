/// AOT bundling smoke target.
///
/// Built with `dart build cli` and run in CI: it proves the libhegel code
/// asset survives ahead-of-time compilation and is still resolvable from the
/// bundle, which plain `dart test` (JIT) cannot show. Exits non-zero unless
/// the engine it loads reports exactly the pinned version.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:hegel/src/libhegel/bindings.g.dart' as libhegel;
import 'package:hegel/src/libhegel/version.g.dart';

void main() {
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
