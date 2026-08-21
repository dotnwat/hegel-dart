@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:hegel/src/libhegel/marshal.dart';
import 'package:test/test.dart';

/// An unpaired high surrogate: valid in a Dart string, unencodable in UTF-8.
final String loneHigh = String.fromCharCode(0xD800);
final String loneLow = String.fromCharCode(0xDC00);

/// U+1F600, which is a *pair* of surrogates and perfectly legal.
const String astral = '\u{1F600}';

/// A string with an interior U+0000.
final String withNul = 'a${String.fromCharCode(0)}b';

void main() {
  group('checkScalarValues', () {
    test('accepts ordinary text and astral characters', () {
      expect(() => checkScalarValues('hello', 'x'), returnsNormally);
      expect(() => checkScalarValues(astral, 'x'), returnsNormally);
      expect(() => checkScalarValues('a${astral}b', 'x'), returnsNormally);
      expect(() => checkScalarValues('', 'x'), returnsNormally);
    });

    test('accepts U+0000, which is a scalar value like any other', () {
      expect(() => checkScalarValues(withNul, 'x'), returnsNormally);
    });

    // dart:convert would quietly turn either of these into U+FFFD, handing the
    // engine text the caller never wrote.
    test('rejects an unpaired high surrogate', () {
      expect(
        () => checkScalarValues(loneHigh, 'alphabet'),
        throwsArgumentError,
      );
      expect(
        () => checkScalarValues('a$loneHigh', 'alphabet'),
        throwsArgumentError,
      );
    });

    test('rejects an unpaired low surrogate', () {
      expect(() => checkScalarValues(loneLow, 'alphabet'), throwsArgumentError);
      expect(
        () => checkScalarValues('$loneLow$astral', 'alphabet'),
        throwsArgumentError,
      );
    });

    test('rejects a high surrogate followed by a non-surrogate', () {
      expect(
        () => checkScalarValues('${loneHigh}a', 'alphabet'),
        throwsArgumentError,
      );
    });

    test('names the argument and the offending index', () {
      expect(
        () => checkScalarValues('ab$loneHigh', 'categories'),
        throwsA(
          isA<ArgumentError>()
              .having((ArgumentError e) => e.name, 'name', 'categories')
              .having(
                (ArgumentError e) => e.message.toString(),
                'message',
                contains('index 2'),
              ),
        ),
      );
    });
  });

  group('checkNoInteriorNul', () {
    test('accepts text without U+0000', () {
      expect(() => checkNoInteriorNul('hello', 'x'), returnsNormally);
    });

    test('rejects an interior U+0000 that would truncate', () {
      expect(
        () => checkNoInteriorNul(withNul, 'database'),
        throwsArgumentError,
      );
    });
  });

  group('toCString', () {
    test('maps null to a null pointer, which means "not set"', () {
      using((Arena arena) {
        expect(toCString(arena, null, 'database'), nullptr);
      });
    });

    test('round-trips text, astral characters included', () {
      using((Arena arena) {
        final pointer = toCString(arena, 'hi $astral', 'x');
        expect(pointer.cast<Utf8>().toDartString(), 'hi $astral');
      });
    });

    test('rejects an interior NUL and an unpaired surrogate', () {
      using((Arena arena) {
        expect(() => toCString(arena, withNul, 'x'), throwsArgumentError);
        expect(() => toCString(arena, loneHigh, 'x'), throwsArgumentError);
      });
    });
  });

  group('toByteBuffer', () {
    test('maps null to a null pointer and zero length', () {
      using((Arena arena) {
        final buffer = toByteBuffer(arena, null, 'include');
        expect(buffer.data, nullptr);
        expect(buffer.length, 0);
      });
    });

    // Absent and empty mean different things to the engine, so an empty string
    // must still produce a pointer it can distinguish from null.
    test('gives an empty string a non-null pointer', () {
      using((Arena arena) {
        final buffer = toByteBuffer(arena, '', 'include');
        expect(buffer.data, isNot(nullptr));
        expect(buffer.length, 0);
      });
    });

    test('carries U+0000 through by length', () {
      using((Arena arena) {
        final buffer = toByteBuffer(arena, withNul, 'include');
        expect(buffer.length, 3);
        expect(buffer.data.asTypedList(3), <int>[0x61, 0x00, 0x62]);
      });
    });

    test('encodes astral characters as four bytes', () {
      using((Arena arena) {
        final buffer = toByteBuffer(arena, astral, 'include');
        expect(buffer.length, 4);
      });
    });

    test('rejects an unpaired surrogate', () {
      using((Arena arena) {
        expect(
          () => toByteBuffer(arena, loneHigh, 'include'),
          throwsArgumentError,
        );
      });
    });
  });

  group('toStringArray', () {
    test('maps null to a null pointer, meaning no restriction', () {
      using((Arena arena) {
        final array = toStringArray(arena, null, 'categories');
        expect(array.data, nullptr);
        expect(array.length, 0);
      });
    });

    // A non-null pointer of length zero means a deliberately empty alphabet.
    // Allocating nothing could yield null and silently change the meaning.
    test('gives an empty list a non-null pointer', () {
      using((Arena arena) {
        final array = toStringArray(arena, const <String>[], 'categories');
        expect(array.data, isNot(nullptr));
        expect(array.length, 0);
      });
    });

    test('writes each entry as a NUL-terminated string', () {
      using((Arena arena) {
        final array = toStringArray(arena, const <String>[
          'Lu',
          'Nd',
        ], 'categories');
        expect(array.length, 2);
        expect(array.data[0].cast<Utf8>().toDartString(), 'Lu');
        expect(array.data[1].cast<Utf8>().toDartString(), 'Nd');
      });
    });
  });

  group('reading back', () {
    test('decodes a length-delimited buffer including U+0000', () {
      using((Arena arena) {
        final buffer = toByteBuffer(arena, withNul, 'x');
        expect(
          utf8FromBuffer(buffer.data.cast<Char>(), buffer.length),
          withNul,
        );
      });
    });

    test('decodes an empty buffer without dereferencing it', () {
      expect(utf8FromBuffer(nullptr, 0), isEmpty);
    });

    test('refuses invalid UTF-8 rather than substituting', () {
      using((Arena arena) {
        final data = arena<Uint8>(2);
        data[0] = 0xFF;
        data[1] = 0xFE;
        expect(
          () => utf8FromBuffer(data.cast<Char>(), 2),
          throwsA(isA<FormatException>()),
        );
      });
    });

    test('maps a null C string to null', () {
      expect(utf8FromCString(nullptr), isNull);
    });

    test('copies bytes rather than aliasing the engine buffer', () {
      using((Arena arena) {
        final data = arena<Uint8>(3);
        data.asTypedList(3).setAll(0, <int>[1, 2, 3]);
        final copied = bytesFromBuffer(data, 3);
        data[0] = 99;
        // The engine frees its buffer as soon as the call returns, so the
        // copy has to be independent of it.
        expect(copied, <int>[1, 2, 3]);
      });
    });
  });

  group('sizeOrUnbounded', () {
    test('maps null to the unbounded bit pattern', () {
      expect(sizeOrUnbounded(null, 'maxSize'), noUpperBound);
      // Dart has no positive literal for UINT64_MAX; the ABI reads the bits.
      expect(noUpperBound, -1);
    });

    test('passes a real bound through', () {
      expect(sizeOrUnbounded(0, 'maxSize'), 0);
      expect(sizeOrUnbounded(64, 'maxSize'), 64);
    });

    test('rejects a negative bound', () {
      expect(() => sizeOrUnbounded(-1, 'maxSize'), throwsRangeError);
    });
  });
}
