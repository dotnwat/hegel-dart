@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:hegel/src/libhegel/bindings.g.dart' as raw;
import 'package:hegel/src/libhegel/errors.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/version.g.dart';
import 'package:test/test.dart';

import '../support/fake_bindings.dart';

/// A fake whose `hegel_version` reports [version].
FakeBindings fakeReporting(String version, {required List<Pointer<Utf8>> own}) {
  final text = version.toNativeUtf8();
  own.add(text);
  return FakeBindings()
    ..onCall = (String name, Invocation invocation) {
      if (name == 'hegel_version') {
        (invocation.positionalArguments.last as Pointer<Pointer<Char>>).value =
            text.cast<Char>();
      }
    };
}

void main() {
  final allocated = <Pointer<Utf8>>[];

  tearDown(() {
    for (final pointer in allocated) {
      calloc.free(pointer);
    }
    allocated.clear();
    Libhegel.resetForTesting();
  });

  group('versionsCompatible', () {
    // libhegel is pre-1.0: the ABI may change between minors but not patches.
    test('accepts a differing patch', () {
      expect(versionsCompatible('0.33.4', '0.33.0'), isTrue);
    });

    test('rejects a differing minor or major', () {
      expect(versionsCompatible('0.34.0', '0.33.0'), isFalse);
      expect(versionsCompatible('1.33.0', '0.33.0'), isFalse);
    });

    test('rejects a version it cannot parse', () {
      expect(versionsCompatible('nightly', '0.33.0'), isFalse);
      expect(versionsCompatible('', '0.33.0'), isFalse);
    });
  });

  group('against the real engine', () {
    test('reports the pinned version and holds a usable context', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      expect(session.engineVersion, libhegelVersion);
      expect(session.context, isNot(nullptr));
      expect(session.isDisposed, isFalse);
    });

    test('has no diagnostic after a successful call', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      expect(session.lastError(), isEmpty);
    });

    test('carries the engine diagnostic into the exception it raises', () {
      final session = Libhegel.open();
      addTearDown(session.dispose);
      // A null out-parameter is invalid, and the engine says so.
      final code = session.bindings.hegel_version(session.context, nullptr);
      expect(
        () => session.check(code, 'hegel_version'),
        throwsA(
          isA<HegelException>()
              .having(
                (HegelException e) => e.code,
                'code',
                HegelResultCode.invalidArg,
              )
              .having((HegelException e) => e.message, 'message', isNotEmpty),
        ),
      );
    });

    test('instance is cached per isolate', () {
      expect(identical(Libhegel.instance, Libhegel.instance), isTrue);
    });
  });

  group('lifecycle', () {
    test('dispose frees the context exactly once', () {
      final fake = fakeReporting(libhegelVersion, own: allocated);
      final session = Libhegel.open(fake)..dispose();
      session.dispose();
      expect(
        fake.calls.where((String c) => c == 'hegel_context_free'),
        hasLength(1),
      );
    });

    test('using a disposed session throws instead of touching the engine', () {
      final session = Libhegel.open(
        fakeReporting(libhegelVersion, own: allocated),
      )..dispose();
      expect(() => session.context, throwsStateError);
      expect(session.isDisposed, isTrue);
    });

    test('disposing the cached session clears it', () {
      final first = Libhegel.overrideForTesting(
        fakeReporting(libhegelVersion, own: allocated),
      )..dispose();
      expect(identical(Libhegel.instance, first), isFalse);
    });

    test('overriding disposes the session it replaces', () {
      final fake = fakeReporting(libhegelVersion, own: allocated);
      Libhegel.overrideForTesting(fake);
      Libhegel.overrideForTesting(
        fakeReporting(libhegelVersion, own: allocated),
      );
      expect(fake.calls, contains('hegel_context_free'));
    });
  });

  group('opening refuses', () {
    test('an engine whose ABI may differ, freeing the fresh context', () {
      final fake = fakeReporting('9.9.9', own: allocated);
      expect(
        () => Libhegel.open(fake),
        throwsA(
          isA<HegelException>().having(
            (HegelException e) => e.message,
            'message',
            allOf(
              contains('9.9.9'),
              contains(libhegelVersion),
              contains('libhegel_path'),
            ),
          ),
        ),
      );
      // A failed open must not leak the context it just allocated.
      expect(fake.calls, contains('hegel_context_free'));
    });

    test('an engine that reports no version at all', () {
      final fake = FakeBindings();
      expect(() => Libhegel.open(fake), throwsA(isA<HegelException>()));
      expect(fake.calls, contains('hegel_context_free'));
    });

    test('an engine whose version call fails', () {
      final fake = FakeBindings()
        ..results['hegel_version'] = raw.hegel_result_t.HEGEL_E_INTERNAL;
      expect(() => Libhegel.open(fake), throwsA(isA<HegelException>()));
      expect(fake.calls, contains('hegel_context_free'));
    });

    test('an engine that hands back no context', () {
      final fake = FakeBindings()..context = nullptr;
      expect(() => Libhegel.open(fake), throwsA(isA<HegelException>()));
    });
  });
}
