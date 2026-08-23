@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:hegel/src/libhegel/run.dart';
import 'package:hegel/src/libhegel/session.dart';
import 'package:hegel/src/libhegel/settings.dart';
import 'package:hegel/src/libhegel/span.dart';
import 'package:hegel/src/libhegel/string_generator.dart';
import 'package:hegel/src/libhegel/test_case.dart' as engine;
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/stateful.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/property_driver.dart';

/// A context that passes everything through and writes down the spans.
///
/// The audit has to watch a real run rather than read the source, because
/// what is being claimed is that a label is *opened* -- and a generator that
/// mentions one in a comment, or opens it only on a branch nothing reaches,
/// would satisfy a grep and satisfy nobody else.
final class _RecordingContext implements DrawContext {
  _RecordingContext(this._inner);

  final DrawContext _inner;

  /// Every label opened through this context, in no particular order.
  static final Set<int> opened = <int>{};

  @override
  void startSpan(SpanLabel label) {
    opened.add(label.value);
    _inner.startSpan(label);
  }

  @override
  void stopSpan({bool discard = false}) => _inner.stopSpan(discard: discard);

  @override
  int drawInteger({required int min, required int max}) =>
      _inner.drawInteger(min: min, max: max);

  @override
  BigInt drawBigInteger({required BigInt min, required BigInt max}) =>
      _inner.drawBigInteger(min: min, max: max);

  @override
  bool drawBoolean({required double probability}) =>
      _inner.drawBoolean(probability: probability);

  @override
  double drawFloat({
    required double min,
    required double max,
    required bool allowNan,
    required bool allowInfinity,
    required bool excludeMin,
    required bool excludeMax,
  }) => _inner.drawFloat(
    min: min,
    max: max,
    allowNan: allowNan,
    allowInfinity: allowInfinity,
    excludeMin: excludeMin,
    excludeMax: excludeMax,
  );

  @override
  String drawString(StringGenerator generator) => _inner.drawString(generator);

  @override
  Uint8List drawBytes({required int minLength, int? maxLength}) =>
      _inner.drawBytes(minLength: minLength, maxLength: maxLength);

  @override
  engine.HegelDate drawDate({
    required engine.HegelDate min,
    required engine.HegelDate max,
  }) => _inner.drawDate(min: min, max: max);

  @override
  engine.HegelTime drawTime({
    required engine.HegelTime min,
    required engine.HegelTime max,
  }) => _inner.drawTime(min: min, max: max);

  @override
  engine.HegelDateTime drawDateTime({
    required engine.HegelDateTime min,
    required engine.HegelDateTime max,
  }) => _inner.drawDateTime(min: min, max: max);

  @override
  Uint8List drawUuid({int? version}) => _inner.drawUuid(version: version);

  @override
  Uint8List drawIpv4() => _inner.drawIpv4();

  @override
  Uint8List drawIpv6() => _inner.drawIpv6();

  @override
  void target(double value, {required String label}) =>
      _inner.target(value, label: label);

  @override
  engine.TestCase? get engineCase => _inner.engineCase;

  @override
  bool get isAborted => _inner.isAborted;

  @override
  DrawCollection startCollection({required int minLength, int? maxLength}) =>
      _inner.startCollection(minLength: minLength, maxLength: maxLength);

  @override
  DrawPool startPool() => _inner.startPool();

  @override
  DrawMachine startStateMachine({
    required List<String> ruleNames,
    required List<int> ruleGroups,
    required List<String> invariantNames,
    required int minConcurrency,
    required int maxConcurrency,
  }) => _inner.startStateMachine(
    ruleNames: ruleNames,
    ruleGroups: ruleGroups,
    invariantNames: invariantNames,
    minConcurrency: minConcurrency,
    maxConcurrency: maxConcurrency,
  );

  @override
  ({DrawContext context, void Function() release}) cloneForWorker() {
    final clone = _inner.cloneForWorker();
    return (context: _RecordingContext(clone.context), release: clone.release);
  }
}

/// A machine whose only rule exists to open a stateful-rule span.
final class _Machine extends StateMachine {
  @override
  List<Rule> get rules => <Rule>[Rule('step', (TestCase tc) {})];
}

/// Draws through every compound generator the catalog offers.
///
/// Bounded so that every collection has at least one element: a list that
/// came out empty opens LIST and never opens LIST_ELEMENT, and an audit that
/// passed on an unlucky seed would be worth nothing.
Future<void> everything(TestCase testCase) async {
  testCase
    ..draw(lists(integers(min: 0, max: 9), minLength: 1, maxLength: 3))
    ..draw(sets(integers(min: 0, max: 9), minLength: 1, maxLength: 3))
    ..draw(
      maps(
        integers(min: 0, max: 9),
        integers(min: 0, max: 9),
        minLength: 1,
        maxLength: 3,
      ),
    )
    ..draw(tuple2(integers(min: 0, max: 9), integers(min: 0, max: 9)))
    ..draw(oneOf(<Generator<int>>[integers(min: 0, max: 9)]))
    ..draw(optional(integers(min: 0, max: 9)))
    ..draw(
      integers(min: 0, max: 9).flatMap((int n) => integers(min: n, max: 9)),
    )
    ..draw(integers(min: 0, max: 9).where((int n) => n >= 0))
    ..draw(integers(min: 0, max: 9).map((int n) => n))
    ..draw(sampledFrom(<String>['a', 'b']))
    ..draw(composite((TestCase inner) => inner.draw(integers(min: 0, max: 9))));
  await runStateful(testCase, _Machine());
}

void main() {
  test('every span label the catalog claims is opened by a real run', () async {
    final session = Libhegel.open();
    addTearDown(session.dispose);
    final run = Run.start(
      const Settings(
        testCases: 5,
        seed: 3,
        derandomize: true,
        database: Database.disabled,
        verbosity: Verbosity.quiet,
        suppressHealthChecks: machineSpeedChecks,
      ),
      session: session,
    );
    addTearDown(run.dispose);

    while (true) {
      final engineCase = run.nextTestCase();
      if (engineCase == null) break;
      try {
        await everything(
          TestCase(_RecordingContext(EngineDrawContext(engineCase))),
        );
        engineCase.markComplete(engine.TestCaseStatus.valid);
      } finally {
        engineCase.dispose();
      }
    }
    run.result().dispose();

    // The claim §6.4's table makes, checked against what the engine was
    // actually asked to group. Everything a compound generator builds is a
    // unit the shrinker can take apart, and a label that stopped being
    // opened would cost exactly that without failing any other test.
    const Map<String, SpanLabel> claimed = <String, SpanLabel>{
      'LIST': SpanLabel.list,
      'LIST_ELEMENT': SpanLabel.listElement,
      'SET': SpanLabel.set,
      'SET_ELEMENT': SpanLabel.setElement,
      'MAP': SpanLabel.map,
      'MAP_ENTRY': SpanLabel.mapEntry,
      'TUPLE': SpanLabel.tuple,
      'ONE_OF': SpanLabel.oneOf,
      'OPTIONAL': SpanLabel.optional,
      'FLAT_MAP': SpanLabel.flatMap,
      'FILTER': SpanLabel.filter,
      'MAPPED': SpanLabel.mapped,
      'SAMPLED_FROM': SpanLabel.sampledFrom,
      'STATEFUL_RULE': SpanLabel.statefulRule,
    };

    final missing = <String>[
      for (final MapEntry<String, SpanLabel> entry in claimed.entries)
        if (!_RecordingContext.opened.contains(entry.value.value)) entry.key,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'the catalog claims these spans and no run opened them: '
          '${missing.join(', ')}',
    );

    // The composite label is this package's own, minted above everything the
    // engine reserves, and is what makes a user-written generator a unit the
    // shrinker can delete whole rather than a run of loose draws.
    expect(
      _RecordingContext.opened,
      contains(SpanLabel.firstAvailable),
      reason: 'composite() mints its own label and has to open it',
    );
  });

  test('the two reserved labels with no generator stay that way', () {
    // A decision rather than a gap, recorded so that a later generator for
    // either is a deliberate addition. FIXED_DICT is what a named-field
    // record generator would open, and tuples already cover that ground
    // under TUPLE; ENUM_VARIANT is what a Dart `enum` generator would open,
    // and `sampledFrom` covers it under SAMPLED_FROM. Both are an index draw
    // either way, and neither shrinks better for having its own label.
    expect(
      _RecordingContext.opened,
      isNot(contains(SpanLabel.fixedDict.value)),
      reason: 'a fixed-dict generator would be news, not a silent addition',
    );
    expect(
      _RecordingContext.opened,
      isNot(contains(SpanLabel.enumVariant.value)),
      reason: 'an enum generator would be news, not a silent addition',
    );
  });
}
