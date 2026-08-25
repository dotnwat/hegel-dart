/// Text chosen to break layouts.
library;

import 'package:hegel/hegel.dart';

/// Strings that have broken a real screen.
///
/// Not a sample of what users type: a sample of what users type that nobody
/// tested. A word too long to break, a script with no spaces in it, a family
/// emoji that is one character and eleven code units, a combining mark that
/// makes a glyph taller than its line, and an override that reverses the run
/// it is in.
const List<String> hostileStrings = <String>[
  '',
  ' ',
  '\n',
  '\t',
  'Donaudampfschifffahrtsgesellschaftskapitaen',
  'https://example.com/a/very/long/path/that/will/not/wrap/anywhere/at/all',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '\u{1F469}‍\u{1F469}‍\u{1F467}‍\u{1F466}', // One family.
  'é́́́́', // A stack of combining accents.
  'مرحبا بالعالم',
  'שלום עולם',
  '日本語のテキストです',
  '\u202Eeht si siht\u202C', // A right-to-left override.
  '​​​', // Zero-width spaces: present, and invisible.
  '0',
  '-1',
  '999999999999999999999999',
];

/// Text that is trying to break the layout it lands in.
///
/// Weighted towards the known-bad strings, because they are the ones that
/// find something, with room left for arbitrary Unicode and for something
/// long enough to overflow anything it is put in.
///
/// Shrinking walks towards the front of a sampled list and towards shorter
/// strings, so a counterexample tends to arrive as the mildest string that
/// still breaks the screen -- often the empty one, which is usually the
/// honest answer about a label nobody guarded.
Generator<String> hostileText({int maxLength = 32, int longLength = 200}) =>
    oneOf(
      <Generator<String>>[
        sampledFrom(hostileStrings),
        text(maxLength: maxLength),
        text(minLength: longLength ~/ 2, maxLength: longLength),
      ],
      weights: <int>[6, 3, 2],
    );
