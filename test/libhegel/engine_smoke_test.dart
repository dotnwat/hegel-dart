@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:hegel/src/libhegel/bindings.g.dart' as libhegel;
import 'package:hegel/src/libhegel/version.g.dart';
import 'package:test/test.dart';

void main() {
  // Proves the whole chain in one call: the build hook resolved and verified
  // an engine, staged it, published it as a code asset, and the generated
  // @Native declaration bound to that asset and reached the real library.
  test('the staged engine loads and reports the pinned version', () {
    final outVersion = calloc<Pointer<Char>>();
    try {
      // A NULL context is explicitly allowed by the ABI; it only opts out of
      // error messages.
      final result = libhegel.hegel_version(nullptr, outVersion);

      expect(result, libhegel.hegel_result_t.HEGEL_OK);
      expect(outVersion.value, isNot(nullptr));
      // The engine the hook actually staged has to be the one that was pinned
      // and verified, not merely some engine that happened to load.
      expect(outVersion.value.cast<Utf8>().toDartString(), libhegelVersion);
    } finally {
      calloc.free(outVersion);
    }
  });
}
