// driverTest against a real twk app in a real pseudo-terminal: the matchers
// of testTwk on its screen, its finders asked of the app, driven time, the
// profiles, and the checks that end a test.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart' show Text;
import 'package:twk_test/driver.dart';
import 'package:twk_test/src/driver.dart' show runDriverTest;
import 'package:twk_test/twk_test.dart';

const app = 'test/driver/app.dart';

void main() {
  driverTest('start: the first frame is on the screen', (d) async {
    final a = await d.start(app, size: (40, 8));
    expect(a.screen, containsLine('Count: 0'));
    expect(a.screen, hasTextAt(0, 1, 'Saved: 0'));
    expect(a.screen, isNot(containsLine('Count: 1')));
    expect(a.screen.lines, hasLength(8));
  });

  driverTest('inline: the normal screen, its lines and its exit', (d) async {
    final a = await d.start(app, arguments: ['--inline'], inline: true);
    expect(a.screen, containsLine('Count: 0'));
    await a.press('up');
    expect(a.screen, containsLine('Count: 1'));
    final step = await a.press('q');
    expect(step.exit!.code, 0);
  });

  driverTest('press: the frame that took the key in', (d) async {
    final a = await d.start(app);
    final step = await a.press('up up');
    expect(step.screen, contains('Count: 2'));
    expect(a.screen, containsLine('Count: 2'));
    expect(a.text, contains('Count: 2'));
  });

  driverTest('tap: a button the finder names, checked like a click', (d) async {
    final a = await d.start(app);
    await a.tap(find.text('Save'));
    expect(a.screen, containsLine('Saved: 1'));
    // two Texts: strict, as findOne is
    await expectLater(
      a.tap(find.byType(Text)),
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          contains('matches'),
        ),
      ),
    );
  });

  driverTest('find: the widgets of the app, asked of it', (d) async {
    final a = await d.start(app);
    expect(await a.find(find.byType(Text)), hasLength(greaterThan(2)));
    final one = await a.findOne(find.text('Count: 0'));
    expect(one.text, 'Count: 0');
    expect(await a.rect(find.text('Saved: 0')), (
      x: 0,
      y: 1,
      width: 8,
      height: 1,
    ));
    expect(
      a.screen,
      containsLine('Saved: 0', withinRect: await a.rect(find.text('Saved: 0'))),
    );
    expect(await a.tree(), contains('Column'));
  });

  driverTest('within a finder is refused on a screen of a process', (d) async {
    final a = await d.start(app);
    expect(
      () => expect(
        a.screen,
        containsLine('Saved: 0', within: find.text('Saved: 0')),
      ),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          contains('withinRect'),
        ),
      ),
    );
  });

  driverTest('waitFor: driven time moves to the timer, in no real time', (
    d,
  ) async {
    final a = await d.start(app);
    await a.press('d');
    expect(a.screen, isNot(containsLine('Done')));
    final step = await a.waitFor((s) => s.contains('Done'));
    expect(step.screen, contains('Done'));
    expect(a.screen, containsLine('Done'));
    expect((await a.clock.status()).time, greaterThanOrEqualTo(2000000));
  });

  driverTest('waitFor: "not within" the budget, and "never" when quiet', (
    d,
  ) async {
    final a = await d.start(app);
    await a.press('d');
    await expectLater(
      a.waitFor(
        (s) => s.contains('Done'),
        budget: const Duration(seconds: 1),
      ),
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          contains('within 1 s of app time'),
        ),
      ),
    );
    await a.waitFor((s) => s.contains('Done'));
    await expectLater(
      a.waitFor((s) => s.contains('Never shown'), near: 'Saved: 0'),
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          allOf(startsWith('never:'), contains('Closest line: "Saved: 0"')),
        ),
      ),
    );
  });

  driverTest('waitForFinder: the tree at each frame, to the count', (d) async {
    final a = await d.start(app);
    await a.press('d');
    expect(await a.find(find.text('Done')), isEmpty);
    final found = await a.waitForFinder(find.text('Done'));
    expect(found.single.text, 'Done');
    // already so: returns at once
    await a.waitForFinder(find.text('Done'), count: findsWidgets);
    await a.waitForFinder(find.text('Nothing'), count: findsNothing);
  });

  driverTest('waitForFinder: the budget, and never', (d) async {
    final a = await d.start(app);
    await a.press('d');
    await expectLater(
      a.waitForFinder(
        find.text('Done'),
        budget: const Duration(seconds: 1),
      ),
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          contains('within 1 s of app time'),
        ),
      ),
    );
    await a.waitForFinder(find.text('Done'));
    await expectLater(
      a.waitForFinder(find.text('Missing')),
      throwsA(
        isA<DriverError>().having(
          (e) => e.message,
          'message',
          startsWith('never:'),
        ),
      ),
    );
  });

  driverTest("press q: the exit is the step's, the terminal given back", (
    d,
  ) async {
    final a = await d.start(app);
    final step = await a.press('q');
    expect(step.exit!.code, 0);
    expect(a.ended, isTrue);
    expect(await a.exitCode, 0);
  });

  driverTest(
    'profiles: the app takes the colors the terminal gives it',
    (d) async {
      final a = await d.start(app);
      final cell = a.screen.vt.cell(0, 2);
      expect(cell.text, 'R');
      // 16 colors: a palette index (0x2000000 | n); truecolor: 24-bit
      final mode = switch (cell.fg >> 24) {
        1 => 'rgb',
        2 => 'palette',
        _ => 'none',
      };
      final expected = switch (d.profile) {
        'truecolor' => 'rgb',
        '16 colors' => 'palette',
        _ => 'none',
      };
      expect(mode, expected);
      expect(a.screen, styleAt(0, 2, isNotNull));
    },
    profiles: ['truecolor', '16 colors', 'no color'],
  );

  group('the checks that end a test', () {
    test('a sequence no terminal takes fails it, with the report', () async {
      late DriverApp a;
      await expectLater(
        runDriverTest((d) async {
          a = await d.start(app);
          await a.press('x');
        }),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('app 1:'), contains('ESC')),
          ),
        ),
      );
      expect(a.ended, isTrue);
    });

    test('a failed body is reported with the app left as it was', () async {
      late DriverApp a;
      await expectLater(
        runDriverTest((d) async {
          a = await d.start(app);
          await a.press('up');
          throw StateError('the test says no');
        }),
        throwsA(isA<StateError>()),
      );
      expect(a.ended, isTrue);
      final report = await a.describeState();
      expect(report, contains('Count: 1'));
    });

    test('the report: screen, earlier frames, tree', () async {
      await runDriverTest((d) async {
        final a = await d.start(app);
        await a.press('up');
        await a.press('up');
        final report = await a.describeState(title: 'app 1');
        expect(report, contains('app 1: running'));
        expect(report, contains('screen 80×24:'));
        expect(report, contains('Count: 2'));
        expect(report, contains('earlier, at frame'));
        expect(report, contains('Count: 1'));
        expect(report, contains('widget tree:'));
        expect(report, contains('Column #'));
        // the trace is named, and has the steps so far
        final trace = a.session.trace!;
        expect(report, contains(trace.castPath));
        expect(report, contains(trace.tracePath));
        expect(File(trace.castPath).readAsStringSync(), contains('"m"'));
      });
    });

    test('the report names the last log records of the app', () async {
      await runDriverTest((d) async {
        final a = await d.start(app);
        await a.press('up l');
        await a.press('l');
        final report = await a.describeState();
        expect(report, contains('last log records:'));
        expect(report, contains('warning logged at 1'));
        expect(
          File(a.session.trace!.tracePath).readAsStringSync(),
          contains('warning logged at 1'),
        );
      });
    });

    test('the app that ended leaves its log in the exit', () async {
      await runDriverTest((d) async {
        final a = await d.start(app);
        await a.press('l');
        final step = await a.press('q');
        expect(step.exit!.log, [contains('warning logged at 0')]);
      });
    });

    test('a passing test deletes its trace, a failing one keeps it', () async {
      late DriverApp kept;
      await expectLater(
        runDriverTest((d) async {
          kept = await d.start(app);
          await kept.press('up');
          throw StateError('no');
        }),
        throwsA(isA<StateError>()),
      );
      expect(File(kept.session.trace!.tracePath).existsSync(), isTrue);
      kept.session.trace!.delete();
      late DriverApp gone;
      await runDriverTest((d) async {
        gone = await d.start(app);
        await gone.press('up');
      });
      expect(File(gone.session.trace!.tracePath).existsSync(), isFalse);
    });

    test('an unknown profile is named', () {
      expect(
        () => profileEnvironment('8 colors'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
