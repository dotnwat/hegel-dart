@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:hegel/src/libhegel/bindings.dart';
import 'package:hegel/src/libhegel/bindings.g.dart' as raw;
import 'package:hegel/src/libhegel/version.g.dart';
import 'package:test/test.dart';

import '../support/fake_bindings.dart';

void main() {
  group('NativeBindings', () {
    // The one check that proves the whole bound surface links against the
    // pinned engine. @Native resolution is lazy, so without this an engine
    // missing a symbol would only surface at the first call needing it.
    test('resolves every symbol in the ABI', () {
      expect(const NativeBindings().verifySymbols, returnsNormally);
    });

    test('forwards a call through to the engine', () {
      const bindings = NativeBindings();
      final outVersion = calloc<Pointer<Char>>();
      try {
        expect(
          bindings.hegel_version(nullptr, outVersion),
          raw.hegel_result_t.HEGEL_OK,
        );
        expect(outVersion.value.cast<Utf8>().toDartString(), libhegelVersion);
      } finally {
        calloc.free(outVersion);
      }
    });

    test('reports an engine error through its result code', () {
      const bindings = NativeBindings();
      final context = bindings.hegel_context_new();
      expect(context, isNot(nullptr));
      try {
        // A null out-parameter is invalid for every call that takes one.
        expect(
          bindings.hegel_version(context, nullptr),
          raw.hegel_result_t.HEGEL_E_INVALID_ARG,
        );
        expect(
          bindings
              .hegel_context_last_error(context)
              .cast<Utf8>()
              .toDartString(),
          isNotEmpty,
        );
      } finally {
        bindings.hegel_context_free(context);
      }
    });
  });

  group('FakeBindings', () {
    test('succeeds by default and records the calls it answered', () {
      final fake = FakeBindings();
      expect(
        fake.hegel_settings_set_test_cases(nullptr, nullptr, 100),
        raw.hegel_result_t.HEGEL_OK,
      );
      expect(
        fake.hegel_run_free(nullptr, nullptr),
        raw.hegel_result_t.HEGEL_OK,
      );
      expect(fake.calls, <String>[
        'hegel_settings_set_test_cases',
        'hegel_run_free',
      ]);
    });

    // These are the codes the fake exists for: a real engine will not produce
    // them to order.
    test('answers with a scripted result code', () {
      final fake = FakeBindings()
        ..results['hegel_next_test_case'] =
            raw.hegel_result_t.HEGEL_E_CONCURRENT_USE
        ..results['hegel_run_result'] = raw.hegel_result_t.HEGEL_E_INTERNAL;

      expect(
        fake.hegel_next_test_case(nullptr, nullptr, nullptr),
        raw.hegel_result_t.HEGEL_E_CONCURRENT_USE,
      );
      expect(
        fake.hegel_run_result(nullptr, nullptr, nullptr),
        raw.hegel_result_t.HEGEL_E_INTERNAL,
      );
    });

    test('hands back a non-null context so construction succeeds', () {
      expect(FakeBindings().hegel_context_new(), isNot(nullptr));
    });

    test('lets a test fill in an out-parameter', () {
      final out = calloc<Int64>();
      try {
        final fake = FakeBindings()
          ..onCall = (String name, Invocation invocation) {
            if (name == 'hegel_generate_integer') {
              (invocation.positionalArguments.last as Pointer<Int64>).value =
                  42;
            }
          };
        expect(
          fake.hegel_generate_integer(nullptr, nullptr, 0, 100, out),
          raw.hegel_result_t.HEGEL_OK,
        );
        expect(out.value, 42);
      } finally {
        calloc.free(out);
      }
    });
  });
}
