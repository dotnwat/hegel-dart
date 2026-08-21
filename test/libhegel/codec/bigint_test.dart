@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:hegel/src/libhegel/codec/bigint.dart';
import 'package:test/test.dart';

BigInt big(String value) => BigInt.parse(value);

void main() {
  group('encoding', () {
    test('writes least significant byte first', () {
      expect(twosComplementBytes(big('1')), <int>[0x01]);
      expect(twosComplementBytes(big('258')), <int>[0x02, 0x01]);
    });

    test('represents zero as a single byte', () {
      expect(twosComplementBytes(BigInt.zero), <int>[0x00]);
    });

    // The sign byte is the whole subtlety of this format: 127 fits in a byte,
    // 128 does not, because a lone 0x80 reads as -128.
    test('adds a zero byte when the top bit would read as negative', () {
      expect(twosComplementBytes(big('127')), <int>[0x7F]);
      expect(twosComplementBytes(big('128')), <int>[0x80, 0x00]);
      expect(twosComplementBytes(big('255')), <int>[0xFF, 0x00]);
      expect(twosComplementBytes(big('256')), <int>[0x00, 0x01]);
    });

    test('adds an all-ones byte when a negative would read as positive', () {
      expect(twosComplementBytes(big('-1')), <int>[0xFF]);
      expect(twosComplementBytes(big('-128')), <int>[0x80]);
      expect(twosComplementBytes(big('-129')), <int>[0x7F, 0xFF]);
      expect(twosComplementBytes(big('-256')), <int>[0x00, 0xFF]);
    });

    test('never pads beyond the sign byte', () {
      for (final value in <String>['0', '1', '-1', '127', '-128', '32767']) {
        final encoded = twosComplementBytes(big(value));
        expect(
          encoded.length,
          twosComplementLength(big(value)),
          reason: 'for $value',
        );
        // Dropping the top byte would have to change the value.
        if (encoded.length > 1) {
          final shorter = encoded.sublist(0, encoded.length - 1);
          expect(
            bigIntFromTwosComplement(shorter),
            isNot(big(value)),
            reason: '$value should not fit in ${shorter.length} bytes',
          );
        }
      }
    });
  });

  group('decoding', () {
    test('reads the sign from the most significant byte', () {
      expect(bigIntFromTwosComplement(<int>[0x7F]), big('127'));
      expect(bigIntFromTwosComplement(<int>[0x80]), big('-128'));
      expect(bigIntFromTwosComplement(<int>[0xFF]), big('-1'));
    });

    // The engine sign-fills the caller's whole buffer, so a value must decode
    // the same however much room it was given.
    test('accepts a sign-filled buffer wider than the value needs', () {
      expect(bigIntFromTwosComplement(<int>[0x01, 0x00, 0x00, 0x00]), big('1'));
      expect(
        bigIntFromTwosComplement(<int>[0xFF, 0xFF, 0xFF, 0xFF]),
        big('-1'),
      );
      expect(
        bigIntFromTwosComplement(<int>[0x80, 0xFF, 0xFF, 0xFF]),
        big('-128'),
      );
    });

    test('refuses an empty buffer', () {
      expect(
        () => bigIntFromTwosComplement(const <int>[]),
        throwsArgumentError,
      );
    });
  });

  group('round trips', () {
    test('every value in a range that crosses byte and sign boundaries', () {
      for (var i = -600; i <= 600; i++) {
        final value = BigInt.from(i);
        expect(
          bigIntFromTwosComplement(twosComplementBytes(value)),
          value,
          reason: 'for $i',
        );
      }
    });

    test('the edges of the fixed-width integer types', () {
      final edges = <String>[
        '127',
        '-128',
        '128',
        '-129',
        '32767',
        '-32768',
        '32768',
        '-32769',
        '2147483647',
        '-2147483648',
        '9223372036854775807',
        '-9223372036854775808',
        '9223372036854775808',
        '-9223372036854775809',
        '18446744073709551615',
        '18446744073709551616',
      ];
      for (final text in edges) {
        final value = big(text);
        expect(
          bigIntFromTwosComplement(twosComplementBytes(value)),
          value,
          reason: 'for $text',
        );
      }
    });

    test('values far wider than any machine integer', () {
      final huge = big('2').pow(500) + big('12345');
      for (final value in <BigInt>[huge, -huge, huge + BigInt.one]) {
        expect(bigIntFromTwosComplement(twosComplementBytes(value)), value);
        expect(twosComplementBytes(value), isA<Uint8List>());
      }
    });

    test('through a sign-filled buffer, as the engine returns them', () {
      for (final text in <String>['0', '5', '-5', '300', '-300', '-1']) {
        final value = big(text);
        final minimal = twosComplementBytes(value);
        // Sign-fill to eight bytes the way the engine fills a caller's buffer.
        final filled = Uint8List(8)
          ..fillRange(0, 8, value.isNegative ? 0xFF : 0x00)
          ..setRange(0, minimal.length, minimal);
        expect(bigIntFromTwosComplement(filled), value, reason: 'for $text');
      }
    });
  });
}
