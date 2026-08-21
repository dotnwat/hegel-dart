@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:hegel/src/libhegel/version.g.dart';
import 'package:test/test.dart';

/// `hegel_result_t hegel_version(hegel_context_t *ctx, const char **out_version)`
///
/// Hand-written rather than generated: this test proves the whole acquisition
/// pipeline — build hook, digest verification, staging, code asset, `@Native`
/// resolution — before ffigen enters the picture. Passing a NULL context is
/// explicitly allowed by the ABI and only opts out of error messages.
@Native<Int32 Function(Pointer<Void>, Pointer<Pointer<Char>>)>(
  symbol: 'hegel_version',
  assetId: 'package:hegel/libhegel',
)
external int hegelVersion(
  Pointer<Void> context,
  Pointer<Pointer<Char>> outVersion,
);

void main() {
  test('the staged engine loads and reports the pinned version', () {
    final outVersion = calloc<Pointer<Char>>();
    try {
      final result = hegelVersion(nullptr, outVersion);

      expect(result, 0, reason: 'hegel_version should return HEGEL_OK');
      expect(outVersion.value, isNot(nullptr));
      // The engine the hook actually staged has to be the one that was
      // pinned and verified, not merely some engine that happened to load.
      expect(outVersion.value.cast<Utf8>().toDartString(), libhegelVersion);
    } finally {
      calloc.free(outVersion);
    }
  });
}
