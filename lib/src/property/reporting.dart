/// What a failure is called, and how it reaches the reader.
library;

import 'dart:typed_data';

import 'package:stack_trace/stack_trace.dart';

import '../libhegel/settings.dart';
import 'test_case.dart';

/// Packages whose frames are never where a property went wrong.
///
/// Everything the assertion passed through on its way out: this package, the
/// test framework that raised it, and the trace library doing the looking.
const Set<String> _frameworkPackages = <String>{
  'hegel',
  'matcher',
  'stack_trace',
  'test',
  'test_api',
  'test_core',
};

/// A name for wherever [error] came from, stable across runs and machines.
///
/// The engine groups failures by this string and shrinks each group toward
/// its own minimal case, so what it says decides what counts as one bug: two
/// cases that name the same site are the same bug, and two sites in one body
/// are two bugs worth reporting separately. Stability is therefore the whole
/// requirement -- an origin containing a value, an address, or a case number
/// would make every case its own bug and shrinking would have nothing to
/// work on.
///
/// Derived from the first frame outside the framework, which for a failed
/// `expect` is the line the expect is on rather than anything inside
/// package:matcher. File paths come out relative to the working directory,
/// so two machines checking out the same repository agree.
String originOf(Object error, StackTrace stack) {
  for (final frame in Trace.from(stack).frames) {
    if (frame.isCore) continue;
    if (_frameworkPackages.contains(frame.package)) continue;
    final line = frame.line;
    return line == null
        ? '${error.runtimeType} at ${frame.library}'
        : '${error.runtimeType} at ${frame.library}:$line';
  }
  // Nothing but framework frames, which happens when an error is raised from
  // a callback the framework owns. The type alone still groups by kind, which
  // is better than grouping everything together.
  return '${error.runtimeType}';
}

/// [value] as a failure report should show it.
///
/// Not `toString`: a counterexample is read to work out what was special
/// about it, and `toString` hides exactly the things that usually are. The
/// empty string and a string of three spaces print identically; a tab and a
/// newline print as whitespace; a byte string prints as a list of decimal
/// numbers. Everything here exists to make one of those visible.
String repr(Object? value) => _repr(value, Set<Object>.identity());

String _repr(Object? value, Set<Object> enclosing) {
  if (value == null) return 'null';
  if (value is String) return _quoted(value);
  if (value is Uint8List) {
    final digits = StringBuffer();
    for (final byte in value) {
      digits.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    // Not a list of numbers: bytes are read as bytes, and the empty case has
    // to look like something rather than like nothing.
    return 'bytes($digits)';
  }
  if (value is Map<Object?, Object?>) {
    return _whileInside(
      value,
      enclosing,
      () =>
          '{${<String>[for (final MapEntry<Object?, Object?> entry in value.entries) '${_repr(entry.key, enclosing)}: ${_repr(entry.value, enclosing)}'].join(', ')}}',
    );
  }
  if (value is Set<Object?>) {
    return _whileInside(
      value,
      enclosing,
      () => '{${_elements(value, enclosing)}}',
    );
  }
  if (value is Iterable<Object?>) {
    return _whileInside(
      value,
      enclosing,
      () => '[${_elements(value, enclosing)}]',
    );
  }
  return '$value';
}

String _elements(Iterable<Object?> values, Set<Object> enclosing) =>
    values.map((Object? element) => _repr(element, enclosing)).join(', ');

/// Renders [value] with [render], unless it is already being rendered.
///
/// A value that contains itself is a thing a `map` can build, and the
/// reporter is the last place that should fall over. Identity rather than
/// equality: two equal lists are not the same list, and rendering the second
/// as an ellipsis would hide a genuine repetition.
String _whileInside(
  Object value,
  Set<Object> enclosing,
  String Function() render,
) {
  if (!enclosing.add(value)) return '...';
  try {
    return render();
  } finally {
    enclosing.remove(value);
  }
}

/// [value] in quotes, with everything invisible made visible.
String _quoted(String value) {
  final out = StringBuffer("'");
  for (final rune in value.runes) {
    switch (rune) {
      case 0x27:
        out.write(r"\'");
      case 0x5c:
        out.write(r'\\');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      default:
        // Control characters, and surrogates a map() could have stranded:
        // written through, they would come out as replacement characters or
        // as nothing at all, and a counterexample nobody can see is no use.
        if (rune < 0x20 ||
            (rune >= 0x7f && rune <= 0x9f) ||
            (rune >= 0xd800 && rune <= 0xdfff)) {
          out.write('\\u{${rune.toRadixString(16)}}');
        } else {
          out.writeCharCode(rune);
        }
    }
  }
  return (out..write("'")).toString();
}

/// The block a failing property prints under its error.
///
/// Everything about the counterexample that is not the error itself: what it
/// drew, what the body said about it, and how to get it back. Only ever the
/// minimal case -- the one the engine shrank to and the runner replayed -- so
/// what is printed is what someone has to reason about, rather than every
/// case the property tried.
String renderFailure({
  required List<Drawn> draws,
  required List<String> notes,
  required List<String> hints,
}) {
  final sections = <String>[
    if (draws.isNotEmpty)
      <String>[
        for (final (int index, Drawn drawn) in draws.indexed)
          '${drawn.name ?? 'draw_${index + 1}'} = ${repr(drawn.value)}',
      ].join('\n'),
    if (notes.isNotEmpty) notes.join('\n'),
    if (hints.isNotEmpty) hints.join('\n'),
  ];
  return sections.join('\n\n');
}

/// What to tell the reader about getting this failure back.
///
/// The engine decides for itself whether to keep counterexamples when the
/// settings do not say -- on locally, off under CI -- and there is no call
/// that asks it what it decided. So the line about a database nobody chose
/// says what the engine does rather than claiming to know what it did.
List<String> reproductionHints(
  Settings settings, {
  String? blob,
  bool? printBlob,
}) => <String>[
  switch (settings.database) {
    null =>
      'Kept in the example database and replayed first next time, unless the '
          'engine turned persistence off (it does under CI).',
    Database.disabled =>
      'The example database is off, so this counterexample was not kept.',
    Database.standard =>
      'Kept in .hegel/examples and replayed first next time.',
    // The path is the caller's own, so there is nothing to tell them about
    // it that they did not just write.
    _ => 'Kept in the example database and replayed first next time.',
  },
  if (blob != null && (printBlob ?? !_keepsCounterexamples(settings.database)))
    "To reproduce anywhere: property(..., reproduce: '$blob')",
  if (settings.seed case final seed?) 'Seed: $seed.',
];

/// Whether [database] is one that was asked to keep counterexamples.
///
/// The question the blob hint turns on. Printed by default whenever the
/// answer is no -- including when nobody chose, because then the engine
/// decided, it decides against under CI, and CI is exactly where a blob is
/// the only way to get a failure back. Somebody who did ask for a database
/// has the counterexample already and does not need a line of base64 under
/// every failure.
bool _keepsCounterexamples(Database? database) =>
    database != null && database != Database.disabled;
