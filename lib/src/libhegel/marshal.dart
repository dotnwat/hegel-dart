/// Moving values across the C boundary.
///
/// Two rules run through everything here. Text is strict UTF-8 in both
/// directions, because the engine validates its inputs and its own strings are
/// Rust strings. And an absent value is never the same as an empty one: the
/// ABI reads a null pointer as "no constraint" and a non-null pointer with
/// length zero as "deliberately empty".
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The bit pattern the ABI reads as `UINT64_MAX`, meaning no upper bound.
///
/// Dart's int is signed 64-bit, so there is no positive literal for it. Kept
/// internal deliberately: the public API takes a nullable bound and marshals
/// null to this, rather than exposing a constant that reads as -1.
const int noUpperBound = -1;

/// Rejects [value] unless every code unit belongs to a Unicode scalar value.
///
/// Dart strings are UTF-16 and can hold an unpaired surrogate, which UTF-8
/// cannot represent. `utf8.encode` silently substitutes U+FFFD for one, which
/// would hand the engine different text than the caller wrote, so an unpaired
/// surrogate is refused rather than quietly rewritten.
void checkScalarValues(String value, String name) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit < 0xD800 || unit > 0xDFFF) continue;

    final isHighHalf = unit < 0xDC00;
    final next = i + 1 < value.length ? value.codeUnitAt(i + 1) : 0;
    final isPair = isHighHalf && next >= 0xDC00 && next <= 0xDFFF;
    if (!isPair) {
      throw ArgumentError.value(
        value,
        name,
        'contains an unpaired surrogate at index $i, which cannot be encoded '
        'as UTF-8',
      );
    }
    i++;
  }
}

/// Rejects [value] if it contains U+0000.
///
/// Only for destinations the ABI reads as NUL-terminated C strings, where an
/// interior NUL would silently truncate. Length-delimited buffers accept it.
void checkNoInteriorNul(String value, String name) {
  if (value.codeUnits.contains(0)) {
    throw ArgumentError.value(
      value,
      name,
      'contains U+0000, which would truncate a NUL-terminated string',
    );
  }
}

/// Encodes [value] as a NUL-terminated UTF-8 string in [arena].
///
/// A null [value] becomes a null pointer, which the ABI reads as "not set"
/// wherever it accepts one.
ffi.Pointer<ffi.Char> toCString(Arena arena, String? value, String name) {
  if (value == null) return ffi.nullptr;
  checkScalarValues(value, name);
  checkNoInteriorNul(value, name);
  return value.toNativeUtf8(allocator: arena).cast<ffi.Char>();
}

/// A pointer and length pair handed to the ABI.
typedef NativeBuffer = ({ffi.Pointer<ffi.Uint8> data, int length});

/// Encodes [value] as a length-delimited UTF-8 buffer in [arena].
///
/// U+0000 is allowed: the engine reads these by length, and the character sets
/// they describe may legitimately include it. A present but empty string still
/// yields a non-null pointer, so the engine can tell it from absent.
NativeBuffer toByteBuffer(Arena arena, String? value, String name) {
  if (value == null) return (data: ffi.nullptr, length: 0);
  checkScalarValues(value, name);
  final bytes = utf8.encode(value);
  final data = arena<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
  if (bytes.isNotEmpty) data.asTypedList(bytes.length).setAll(0, bytes);
  return (data: data, length: bytes.length);
}

/// An array of C strings, with its length.
typedef NativeStringArray = ({
  ffi.Pointer<ffi.Pointer<ffi.Char>> data,
  int length,
});

/// Encodes [values] as an array of NUL-terminated strings in [arena].
///
/// This is where absent and empty diverge most sharply: for a text generator's
/// categories, a null array means "no restriction" while a non-null array of
/// length zero means "an empty alphabet". Allocating zero elements can yield a
/// null pointer, which would silently flip one into the other, so an empty
/// list still allocates.
NativeStringArray toStringArray(
  Arena arena,
  List<String>? values,
  String name,
) {
  if (values == null) return (data: ffi.nullptr, length: 0);
  final data = arena<ffi.Pointer<ffi.Char>>(values.isEmpty ? 1 : values.length);
  for (var i = 0; i < values.length; i++) {
    data[i] = toCString(arena, values[i], name);
  }
  return (data: data, length: values.length);
}

/// Reads [length] bytes at [data] as UTF-8.
///
/// Strict: the engine's strings are Rust strings, so anything else means
/// something is wrong and should say so rather than produce U+FFFD.
String utf8FromBuffer(ffi.Pointer<ffi.Char> data, int length) {
  if (length == 0) return '';
  return utf8.decode(data.cast<ffi.Uint8>().asTypedList(length));
}

/// Reads a NUL-terminated string at [data], or null if [data] is null.
String? utf8FromCString(ffi.Pointer<ffi.Char> data) =>
    data == ffi.nullptr ? null : data.cast<Utf8>().toDartString();

/// Copies [length] bytes at [data] into a Dart list.
///
/// Always a copy: engine-allocated buffers are freed as soon as the call that
/// produced them returns.
Uint8List bytesFromBuffer(ffi.Pointer<ffi.Uint8> data, int length) =>
    Uint8List.fromList(data.asTypedList(length));

/// Rejects [value] if the ABI would reinterpret it rather than reject it.
///
/// dart:ffi narrows silently: a negative int handed to a `uint64_t` parameter
/// arrives as a huge positive one, and a value wider than a `uint8_t` field
/// arrives truncated. Either way the engine sees a number the caller never
/// wrote and has no way to tell it apart from a deliberate one, so the check
/// has to happen here.
void checkFitsUnsigned(int value, String name, {int? bits}) {
  if (value < 0) {
    throw RangeError.value(value, name, 'must not be negative');
  }
  if (bits != null && value > (1 << bits) - 1) {
    throw RangeError.range(value, 0, (1 << bits) - 1, name);
  }
}

/// Rejects [value] unless it lies between [min] and [max] inclusive.
void checkInRange(int value, String name, int min, int max) {
  if (value < min || value > max) {
    throw RangeError.range(value, min, max, name);
  }
}

/// Marshals a nullable upper bound, where null means unbounded.
int sizeOrUnbounded(int? size, String name) {
  if (size == null) return noUpperBound;
  if (size < 0) {
    throw RangeError.value(size, name, 'must not be negative');
  }
  return size;
}
