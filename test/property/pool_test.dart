@TestOn('vm')
library;

import 'package:hegel/src/libhegel/leaks.dart';
import 'package:hegel/src/property/generator.dart';
import 'package:hegel/src/property/runner.dart';
import 'package:hegel/src/property/stateful.dart';
import 'package:hegel/src/property/test_case.dart';
import 'package:test/test.dart';

import '../support/shrink_pin.dart';

/// A resource that can be opened once and closed once.
///
/// The lifecycle a pool exists to model: a thing an earlier step made, that a
/// later step acts on, and that stops being available once it has been used
/// up.
final class _Handle {
  _Handle(this.id);

  final int id;
  bool closed = false;

  void close() {
    if (closed) throw StateError('handle $id was closed twice');
    closed = true;
  }
}

/// Opens handles, uses them, and closes them for good.
final class _HandleMachine extends StateMachine {
  _HandleMachine(this.testCase) : pool = Pool<_Handle>(testCase);

  final TestCase testCase;
  final Pool<_Handle> pool;

  /// Every handle ever opened, so a test can ask what became of them.
  final List<_Handle> opened = <_Handle>[];

  /// Which rules actually ran, in order.
  final List<String> log = <String>[];

  @override
  List<Rule> get rules => <Rule>[
    Rule('open', (TestCase tc) {
      final handle = _Handle(opened.length);
      opened.add(handle);
      pool.add(tc, handle);
      log.add('open ${handle.id}');
    }),
    Rule(
      'use',
      (TestCase tc) {
        final handle = tc.draw(pool.reusable);
        expect(handle.closed, isFalse);
        log.add('use ${handle.id}');
      },
      // An empty pool ends the case rather than the step, so the rule has to
      // be kept off the table rather than caught.
      precondition: () => pool.isNotEmpty,
    ),
    Rule('close', (TestCase tc) {
      final handle = tc.draw(pool.consumed);
      handle.close();
      log.add('close ${handle.id}');
    }, precondition: () => pool.isNotEmpty),
  ];
}

/// A machine built out of the rules a test hands it.
final class _Machine extends StateMachine {
  _Machine(this.rules);

  @override
  final List<Rule> rules;
}

void main() {
  group('a pool', () {
    test('models a resource that is made, used, and used up', () async {
      final machines = <_HandleMachine>[];

      await runProperty((TestCase testCase) async {
        final machine = _HandleMachine(testCase);
        machines.add(machine);
        await runStateful(testCase, machine);
      }, settings: pinSettings(testCases: 30));

      // Something has to have happened, or the assertions below hold of a
      // run that did nothing.
      final busy = machines.where((_HandleMachine m) => m.log.length > 3);
      expect(busy, isNotEmpty);
      for (final _HandleMachine machine in machines) {
        // A closed handle is out of the pool, so nothing can reach it again:
        // no double close, and no use after one. The rules assert both from
        // the inside, so a run that finished at all has already shown it --
        // what is left to check is that the pool tracked the count.
        expect(
          machine.pool.length,
          machine.opened.where((_Handle h) => !h.closed).length,
        );
      }
    });

    test('holds nothing to begin with', () async {
      await runProperty((TestCase testCase) {
        final pool = Pool<int>(testCase);
        expect(pool.length, 0);
        expect(pool.isEmpty, isTrue);
        expect(pool.isNotEmpty, isFalse);
      }, settings: pinSettings(testCases: 3));
    });

    test('counts what was added and what was drawn away', () async {
      await runProperty((TestCase testCase) {
        final pool = Pool<String>(testCase)
          ..add(testCase, 'a')
          ..add(testCase, 'b');
        expect(pool.length, 2);

        // Reusable leaves it where it was.
        expect(testCase.draw(pool.reusable), anyOf('a', 'b'));
        expect(pool.length, 2);

        // Consumed takes it out.
        final taken = testCase.draw(pool.consumed);
        expect(pool.length, 1);
        expect(testCase.draw(pool.reusable), isNot(taken));
      }, settings: pinSettings(testCases: 5));
    });

    test('ends the case rather than the step when it is empty', () async {
      // The guidance path, and the reason [Pool.isEmpty] exists. An
      // assumption the engine raised is latched against the whole case, so a
      // rule cannot catch it and carry on: the step that drew is the last
      // thing that happens, however many steps the engine had left to give.
      final scripts = <List<String>>[];

      final run = runProperty((TestCase testCase) async {
        final log = <String>[];
        scripts.add(log);
        final pool = Pool<int>(testCase);
        await runStateful(
          testCase,
          _Machine(<Rule>[
            // No precondition, which is the mistake this documents.
            Rule('use', (TestCase tc) {
              log.add('use');
              tc.draw(pool.reusable);
              log.add('unreachable');
            }),
          ]),
        );
        log.add('finished');
      }, settings: pinSettings(testCases: 20));

      // And the property does not quietly pass either. Every case ends
      // invalid, which is the engine's own signal that a test is filtering
      // out everything -- so what a property written this way gets is a run
      // that reached no verdict and says why.
      await expectLater(
        run,
        throwsA(
          isA<PropertyError>().having(
            (PropertyError error) => error.message,
            'message',
            contains('FilterTooMuch'),
          ),
        ),
      );

      expect(scripts, isNotEmpty);
      for (final List<String> log in scripts) {
        // One step entered, nothing after it, and the body never returned.
        expect(log, <String>['use']);
      }
    });

    test('releases its engine handle when the case ends', () async {
      // A pool outlives every draw taken from it, so nothing in a property
      // body is in a position to release it. The case is, and does -- which
      // the leak tracker is what notices.
      final leaks = <String>[];
      reportLeak = (LeakReport report) => leaks.add(report.kind);
      addTearDown(resetLeakReporting);

      await runProperty((TestCase testCase) {
        Pool<int>(testCase).add(testCase, 1);
      }, settings: pinSettings(testCases: 20));

      // Every pool the run made is gone; a leak report would name one that
      // was collected without being disposed.
      await _collect();
      expect(leaks, isEmpty);
    });
  });

  group('a pool inside a machine', () {
    test('shrinks toward the resource that was made first', () async {
      final report = await shrunkReport((TestCase testCase) async {
        final pool = Pool<int>(testCase);
        // Three to choose from, so choosing is a draw the shrinker can move.
        for (var made = 0; made < 3; made++) {
          pool.add(testCase, made);
        }
        final chosen = testCase.draw(pool.reusable, name: 'chosen');
        throw StateError('acted on $chosen');
      });

      // The engine records an identifier by value rather than by position,
      // and shrinks toward the earliest, so the counterexample acts on the
      // first thing the case made rather than on whichever it happened to
      // pick.
      expect(report, contains('chosen = 0'));
    });
  });
}

/// Gives the collector a chance to notice what nobody is holding.
Future<void> _collect() async {
  for (var turn = 0; turn < 5; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}
