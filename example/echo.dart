/// Property-based testing with hegel, in a script you can run.
///
///     dart run example/echo.dart
///
/// Properties are normally written with `property()`, which registers an
/// ordinary `package:test` test -- that is what the README shows and what you
/// want in a suite. This file uses `runProperty`, the same runner without
/// package:test around it, so that it runs under `dart run` and can show you
/// what a failure looks like without failing anything.
library;

import 'dart:io';

import 'package:hegel/hegel.dart';

/// A short, quiet run, and no database: an example that remembered a
/// counterexample would behave differently the second time you ran it.
const Settings settings = Settings(
  testCases: 200,
  database: Database.disabled,
  verbosity: Verbosity.quiet,
);

Future<void> main() async {
  stdout.writeln('hegel: a property that holds');
  await runProperty((TestCase testCase) {
    // Draw a list of small integers, sort a copy, and check the copy is a
    // rearrangement of the original rather than something shorter.
    final numbers = testCase.draw(
      lists(integers(min: 0, max: 100)),
      name: 'numbers',
    );
    final sorted = numbers.toList()..sort();
    if (sorted.length != numbers.length) {
      throw StateError('sorting lost something: $numbers became $sorted');
    }
  }, settings: settings);
  stdout.writeln('  held over ${settings.testCases} cases\n');

  stdout.writeln('hegel: a property that does not');
  try {
    await runProperty(
      (TestCase testCase) {
        // Nearly true: join a list of words with a comma, split it again, get
        // the list back. The engine will find where "nearly" lives.
        final words = testCase.draw(
          lists(text(maxLength: 4, maxCodepoint: 0x7a)),
          name: 'words',
        );
        final roundTripped = words.join(',').split(',');
        if (roundTripped.length != words.length) {
          // Counted rather than printed: a list holding one empty string
          // prints as `[]`, which is also what the empty list prints as, and
          // an example whose message is ambiguous teaches the wrong lesson.
          throw StateError(
            'joining ${words.length} words and splitting gave back '
            '${roundTripped.length}',
          );
        }
      },
      settings: settings,
      // Where the counterexample goes. Inside a test this defaults to
      // package:test's on-failure buffer, so a property that holds is silent.
      onDiagnostic: (String line) => stdout.writeln('  $line'),
    );
  } on Object catch (error) {
    stdout.writeln('  $error');
  }
}
