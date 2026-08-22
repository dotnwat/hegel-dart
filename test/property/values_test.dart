@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:test/test.dart';

import '../support/property_case.dart';

/// A session for the group below, closed when its last test ends.
Libhegel openSession() {
  final session = Libhegel.open();
  addTearDown(session.dispose);
  return session;
}

void main() {
  group('bytes', () {
    test('draws inside the requested length bounds', () {
      final values = drawEveryCase(
        openSession(),
        bytes(minLength: 2, maxLength: 8),
      );

      expect(values, isNotEmpty);
      expect(
        values.map((Uint8List value) => value.length),
        everyElement(inInclusiveRange(2, 8)),
      );
      expect(
        values.map((Uint8List value) => value.length).toSet().length,
        greaterThan(1),
      );
    });

    test('leaves the length to the engine when none was given', () {
      final values = drawEveryCase(openSession(), bytes());

      expect(values, isNotEmpty);
      expect(values, contains(isEmpty));
      expect(
        values.map((Uint8List value) => value.length),
        everyElement(lessThan(1000)),
      );
    });

    test('refuses lengths that are not lengths, where they were written', () {
      expect(() => bytes(minLength: -1), throwsRangeError);
      expect(() => bytes(minLength: 5, maxLength: 2), throwsArgumentError);
    });
  });

  group('dates', () {
    test('draws inside the requested bounds, at UTC midnight', () {
      final values = drawEveryCase(
        openSession(),
        dates(min: DateTime.utc(2020, 3, 1), max: DateTime.utc(2020, 3, 31)),
      );

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(
          isA<DateTime>()
              .having((DateTime d) => d.isUtc, 'isUtc', isTrue)
              .having((DateTime d) => d.year, 'year', 2020)
              .having((DateTime d) => d.month, 'month', 3)
              .having((DateTime d) => d.day, 'day', inInclusiveRange(1, 31))
              .having(
                (DateTime d) => d.hour + d.minute + d.second,
                'time of day',
                0,
              ),
        ),
      );
    });

    test('reads a bound as the calendar date it shows', () {
      // A local DateTime and a UTC one for the same calendar date mean the
      // same date here, because a date is not a moment.
      final values = drawEveryCase(
        openSession(),
        dates(min: DateTime(2021, 6, 15), max: DateTime(2021, 6, 15)),
      );

      expect(values, everyElement(DateTime.utc(2021, 6, 15)));
    });

    test('spans the engine default range when unbounded', () {
      final values = drawEveryCase(openSession(), dates());

      expect(values, isNotEmpty);
      expect(
        values.map((DateTime d) => d.year),
        everyElement(inInclusiveRange(1, 9999)),
      );
      expect(values.map((DateTime d) => d.year).toSet().length, greaterThan(1));
    });

    test('refuses an inverted range where it was written', () {
      expect(
        () => dates(min: DateTime.utc(2020, 2, 2), max: DateTime.utc(2020)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('exceeds max'),
          ),
        ),
      );
    });
  });

  group('times', () {
    test('draws inside the requested bounds', () {
      final values = drawEveryCase(
        openSession(),
        times(
          min: const Duration(hours: 9),
          max: const Duration(hours: 17, minutes: 30),
        ),
      );

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(
          predicate<Duration>(
            (Duration d) =>
                d >= const Duration(hours: 9) &&
                d <= const Duration(hours: 17, minutes: 30),
            'within business hours',
          ),
        ),
      );
    });

    test('stays inside a day when unbounded', () {
      final values = drawEveryCase(openSession(), times());

      expect(values, isNotEmpty);
      expect(values, everyElement(greaterThanOrEqualTo(Duration.zero)));
      expect(values, everyElement(lessThan(const Duration(days: 1))));
    });

    test('refuses a bound that is not a time of day', () {
      expect(
        () => times(min: const Duration(hours: 25)),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            contains('is not a time of day'),
          ),
        ),
      );
      expect(
        () => times(min: const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      expect(
        () => times(
          min: const Duration(hours: 12),
          max: const Duration(hours: 6),
        ),
        throwsArgumentError,
      );
    });
  });

  group('dateTimes', () {
    test('draws inside the requested bounds, in UTC', () {
      final low = DateTime.utc(2020, 5, 4, 10);
      final high = DateTime.utc(2020, 5, 4, 11);
      final values = drawEveryCase(
        openSession(),
        dateTimes(min: low, max: high),
      );

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(
          isA<DateTime>().having((DateTime d) => d.isUtc, 'isUtc', isTrue),
        ),
      );
      expect(
        values,
        everyElement(
          predicate<DateTime>(
            (DateTime d) => !d.isBefore(low) && !d.isAfter(high),
            'inside the bounds',
          ),
        ),
      );
    });

    test('carries microseconds, which both sides count in', () {
      final values = drawEveryCase(
        openSession(),
        dateTimes(
          min: DateTime.utc(2020, 1, 1, 0, 0, 0, 0, 0),
          max: DateTime.utc(2020, 1, 1, 0, 0, 0, 0, 999),
        ),
      );

      expect(values, isNotEmpty);
      expect(
        values.map((DateTime d) => d.microsecondsSinceEpoch),
        everyElement(
          inInclusiveRange(
            DateTime.utc(2020).microsecondsSinceEpoch,
            DateTime.utc(2020).microsecondsSinceEpoch + 999,
          ),
        ),
      );
      expect(
        values.map((DateTime d) => d.microsecond).toSet().length,
        greaterThan(1),
        reason: 'a generator that lost the microseconds would draw one value',
      );
    });

    test('refuses an inverted range where it was written', () {
      expect(
        () => dateTimes(
          min: DateTime.utc(2020, 1, 2),
          max: DateTime.utc(2020, 1, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('uuids', () {
    test('comes out in the canonical form', () {
      final values = drawEveryCase(openSession(), uuids(), testCases: 30);

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(
          matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')),
        ),
      );
    });

    test('sets the version nibble when a version is asked for', () {
      final values = drawEveryCase(
        openSession(),
        uuids(version: 4),
        testCases: 30,
      );

      expect(values, isNotEmpty);
      // The thirteenth hexadecimal digit is the version, and the
      // seventeenth's high bits are the RFC 4122 variant.
      expect(values.map((String v) => v[14]).toSet(), <String>{'4'});
      expect(
        values.map((String v) => v[19]),
        everyElement(anyOf('8', '9', 'a', 'b')),
      );
    });

    test('draws every bit when no version is asked for', () {
      final values = drawEveryCase(openSession(), uuids(), testCases: 60);

      expect(
        values.map((String v) => v[14]).toSet().length,
        greaterThan(1),
        reason: 'an unversioned uuid is 128 drawn bits, version field and all',
      );
    });

    test('refuses a version that is not one', () {
      expect(() => uuids(version: 16), throwsRangeError);
      expect(() => uuids(version: -1), throwsRangeError);
    });
  });

  group('ipAddresses', () {
    test('draws both families when none was asked for', () {
      final values = drawEveryCase(openSession(), ipAddresses(), testCases: 40);

      expect(values, isNotEmpty);
      expect(
        values.map((InternetAddress a) => a.type).toSet(),
        <InternetAddressType>{
          InternetAddressType.IPv4,
          InternetAddressType.IPv6,
        },
      );
    });

    test('draws only the family it was asked for', () {
      final v4 = drawEveryCase(
        openSession(),
        ipAddresses(type: InternetAddressType.IPv4),
        testCases: 20,
      );
      final v6 = drawEveryCase(
        openSession(),
        ipAddresses(type: InternetAddressType.IPv6),
        testCases: 20,
      );

      expect(
        v4.map((InternetAddress a) => a.type),
        everyElement(InternetAddressType.IPv4),
      );
      expect(
        v4.map((InternetAddress a) => a.rawAddress.length),
        everyElement(4),
      );
      expect(
        v6.map((InternetAddress a) => a.type),
        everyElement(InternetAddressType.IPv6),
      );
      expect(
        v6.map((InternetAddress a) => a.rawAddress.length),
        everyElement(16),
      );
    });

    test('produces addresses that render as addresses', () {
      final values = drawEveryCase(
        openSession(),
        ipAddresses(type: InternetAddressType.IPv4),
        testCases: 20,
      );

      expect(
        values.map((InternetAddress a) => a.address),
        everyElement(matches(RegExp(r'^\d{1,3}(\.\d{1,3}){3}$'))),
      );
    });
  });
}
