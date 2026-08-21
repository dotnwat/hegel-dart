/// Two's-complement little-endian conversion for arbitrary-precision integers.
///
/// The ABI exchanges big integers as signed two's-complement byte buffers,
/// least significant byte first. Bounds go in at their minimal width; drawn
/// values come back sign-filled to whatever width the caller offered.
library;

import 'dart:typed_data';

/// The fewest bytes that can hold [value] in two's complement.
///
/// One more bit than the magnitude needs, for the sign: 127 fits in a byte but
/// 128 does not, because a lone `0x80` reads as -128.
int twosComplementLength(BigInt value) {
  final bits = value.bitLength + 1;
  return bits <= 8 ? 1 : (bits + 7) ~/ 8;
}

/// Encodes [value] as minimal two's-complement little-endian bytes.
///
/// Minimal in the sense the ABI wants: never shorter than the value needs, and
/// never padded beyond the sign byte. A non-negative value whose top byte
/// would read as negative gains a `0x00`, and a negative value whose top byte
/// would read as non-negative gains a `0xff`; both fall out of the width rule
/// rather than being special-cased.
Uint8List twosComplementBytes(BigInt value) {
  final length = twosComplementLength(value);
  final unsigned = value.isNegative
      ? value + (BigInt.one << (8 * length))
      : value;

  final bytes = Uint8List(length);
  var remaining = unsigned;
  final mask = BigInt.from(0xFF);
  for (var i = 0; i < length; i++) {
    bytes[i] = (remaining & mask).toInt();
    remaining >>= 8;
  }
  return bytes;
}

/// Decodes two's-complement little-endian [bytes].
///
/// Any width is accepted, so a buffer the engine sign-filled to a wider size
/// than the value needed decodes to the same number as its minimal form.
BigInt bigIntFromTwosComplement(List<int> bytes) {
  if (bytes.isEmpty) {
    throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
  }

  var value = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i] & 0xFF);
  }
  // The top bit of the most significant byte is the sign.
  if (bytes[bytes.length - 1] & 0x80 != 0) {
    value -= BigInt.one << (8 * bytes.length);
  }
  return value;
}
