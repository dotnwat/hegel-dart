/// Fails when coverage falls below the thresholds this package holds itself to.
///
///     dart run coverage:test_with_coverage --branch-coverage
///     dart run tool/check_coverage.dart
///
/// Generated files are excluded, and they say so themselves: a file whose
/// first line marks it generated is skipped. That way a new generated file is
/// excluded automatically and a hand-written one can never be quietly dropped
/// by editing a list here.
library;

import 'dart:io';

/// The floor for lines of hand-written code.
///
/// Not 100%, deliberately. Coverage is measured on one platform, and some
/// paths cannot be reached there: the rename-onto-existing fallback only
/// happens on Windows, and the unreadable-file paths need POSIX mode bits.
/// Merging coverage across the matrix would close that gap at a cost not worth
/// paying yet, so this is a floor that catches real regressions rather than a
/// number reachable only by pretending.
///
/// Set just under where the suite actually sits, so it ratchets: raise it when
/// coverage rises, never lower it to make a change fit.
const double lineFloor = 95;

/// The floor for branches, on the same reasoning.
const double branchFloor = 95;

const String _generatedMarker = 'GENERATED FILE';

void main() {
  final lcov = File('coverage/lcov.info');
  if (!lcov.existsSync()) {
    stderr.writeln(
      'no coverage/lcov.info; run `dart run coverage:test_with_coverage '
      '--branch-coverage` first',
    );
    exitCode = 1;
    return;
  }

  var lines = 0;
  var linesHit = 0;
  var branches = 0;
  var branchesHit = 0;
  final skipped = <String>[];
  final perFile = <({String path, int hit, int found})>[];

  for (final block in lcov.readAsStringSync().split('end_of_record')) {
    final path = RegExp(r'SF:(.*)').firstMatch(block)?.group(1);
    if (path == null) continue;

    final source = File(path);
    final firstLine = source.existsSync()
        ? (source.readAsLinesSync().firstOrNull ?? '')
        : '';
    if (firstLine.contains(_generatedMarker)) {
      skipped.add(path);
      continue;
    }

    int field(String name) => int.parse(
      RegExp('^$name:(\\d+)', multiLine: true).firstMatch(block)?.group(1) ??
          '0',
    );

    final found = field('LF');
    final hit = field('LH');
    lines += found;
    linesHit += hit;

    // The report carries per-branch records but no totals, so count them:
    // `BRDA:<line>,<block>,<branch>,<taken>`, where taken is a hit count, or
    // `-` when the block never ran at all.
    for (final record in RegExp(
      r'^BRDA:\d+,\d+,\d+,(.+)$',
      multiLine: true,
    ).allMatches(block)) {
      branches++;
      final taken = record.group(1)!;
      if (taken != '-' && taken != '0') branchesHit++;
    }

    perFile.add((path: path, hit: hit, found: found));
  }

  if (lines == 0) {
    stderr.writeln('no coverable lines found; is the report empty?');
    exitCode = 1;
    return;
  }

  perFile.sort((a, b) => (a.hit / a.found).compareTo(b.hit / b.found));
  for (final file in perFile) {
    final percent = file.hit / file.found * 100;
    stdout.writeln(
      '  ${percent.toStringAsFixed(1).padLeft(5)}%  '
      '${file.hit}/${file.found}  ${file.path.split('/lib/').last}',
    );
  }
  for (final path in skipped) {
    stdout.writeln('  generated, not measured: ${path.split('/lib/').last}');
  }

  final linePercent = linesHit / lines * 100;
  final branchPercent = branches == 0 ? 100.0 : branchesHit / branches * 100;
  stdout.writeln(
    '\nlines    ${linePercent.toStringAsFixed(1)}% '
    '($linesHit/$lines), floor $lineFloor%\n'
    'branches ${branchPercent.toStringAsFixed(1)}% '
    '($branchesHit/$branches), floor $branchFloor%',
  );

  if (linePercent < lineFloor || branchPercent < branchFloor) {
    stderr.writeln('\ncoverage is below the floor');
    exitCode = 1;
  }
}
