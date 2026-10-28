// Progress lists on the fake clock: a tracker's tasks, their rate and time
// left as the clock moves, the clock a tracker is handed kept, run()
// finishing a task on its body's outcome, the finished hidden, the rows
// beyond maxVisible counted, the columns as the width allows, amounts in
// bytes, and the frames stepped by the spinner, not by advance().
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);
const s = Duration(seconds: 1);

/// The rows [t] shows, the spinner's frame as `*`.
List<String> rows(TwkTester t) => [
  for (final line in t.lines)
    line.replaceAll(RegExp('[${SpinnerFrames.dots.frames.join()}]'), '*'),
];

/// A tracker on a fake clock, and the clock.
(ProgressTracker, FakeClock) tracked() {
  final clock = FakeClock();
  final tracker = ProgressTracker(clock: clock.stopwatch);
  addTearDown(tracker.dispose);
  return (tracker, clock);
}

/// A tracker on the clock of the app [t] runs (`t.clock.stopwatch`, which
/// it hands the app), so that its fake clock moves the times.
ProgressTracker onApp(TwkTester t) {
  final tracker = ProgressTracker(clock: t.clock.stopwatch);
  addTearDown(tracker.dispose);
  return tracker;
}

void main() {
  group('ProgressTracker', () {
    test('rate over the window and the time left, by its clock', () async {
      final (tracker, clock) = tracked();
      final task = tracker.add('Download', total: 100);
      expect(task.status, TaskStatus.pending);
      expect(task.rate, isNull);
      expect(task.eta, isNull);
      expect(task.fraction, 0);
      task.start();
      expect(task.status, TaskStatus.running);
      expect(task.rate, isNull, reason: 'no time has passed');
      await clock.elapse(s);
      task.update(20);
      expect(task.rate, 20);
      expect(task.eta, const Duration(seconds: 4));
      expect(task.fraction, 0.2);
      expect(task.elapsed, s);
      // nothing more done: the rate falls as the clock moves
      await clock.elapse(s);
      expect(task.rate, 10);
      expect(task.eta, const Duration(seconds: 8));
      // ten a second for ten seconds: the window looks five back
      for (var i = 0; i < 10; i++) {
        await clock.elapse(s);
        task.advance(i < 5 ? 2 : 10);
      }
      expect(task.completed, 80);
      expect(task.rate, closeTo(10, 0.01));
      expect(task.eta, const Duration(seconds: 2));
      task.done();
      expect(task.completed, 100, reason: 'done counts all of the total');
      expect(task.rate, isNull);
      expect(task.eta, isNull);
      expect(task.elapsed, const Duration(seconds: 12));
      await clock.elapse(s);
      expect(task.elapsed, const Duration(seconds: 12));
      // finished, it takes no more
      task
        ..advance()
        ..fail('late');
      expect(task.status, TaskStatus.done);
      expect(task.completed, 100);
      expect(tracker.finished, isTrue);
    });

    test('advance and update set a pending task going; its listeners are '
        'told of what changes but each advance', () async {
      final (tracker, clock) = tracked();
      var told = 0;
      tracker.addListener(() => told++);
      final task = tracker.add('Index');
      expect(told, 1);
      expect(tracker.finished, isFalse);
      task.advance(3);
      expect(task.status, TaskStatus.running);
      expect(told, 2);
      for (var i = 0; i < 1000; i++) {
        task.advance();
      }
      task.update(5000);
      expect(task.completed, 5000);
      expect(told, 2);
      expect(task.fraction, isNull);
      expect(task.eta, isNull, reason: 'no total');
      task
        ..label = 'Indexing'
        ..total = 10000;
      expect(told, 4);
      task.label = 'Indexing';
      expect(told, 4, reason: 'the same label');
      await clock.elapse(s);
      expect(task.eta, isNotNull);
      task.skip();
      expect(told, 5);
      expect(task.status, TaskStatus.skipped);
      tracker.remove(task);
      expect(told, 6);
      expect(tracker.tasks, isEmpty);
      task.label = 'gone';
      expect(told, 6, reason: 'a task removed tells no one');
    });

    test("run() finishes the task done on the body's return and failed on "
        'its throw, which it throws again', () async {
      final (tracker, _) = tracked();
      final finished = <String>[];
      tracker.onTaskFinished.listen((t) => finished.add(t.summary));
      final got = await tracker.run('Build', (task) async {
        expect(task.status, TaskStatus.running);
        await Future<void>.delayed(Duration.zero);
        return 42;
      });
      expect(got, 42);
      expect(tracker.tasks.single.status, TaskStatus.done);
      final error = StateError('disk full');
      await expectLater(
        tracker.run('Deploy', (task) async {
          task.advance();
          await Future<void>.delayed(Duration.zero);
          throw error;
        }),
        throwsA(same(error)),
      );
      final failed = tracker.tasks.last;
      expect(failed.status, TaskStatus.failed);
      expect(failed.error, same(error));
      // a body that finishes the task keeps what it said
      await tracker.run('Lint', (task) => task.skip());
      expect(tracker.tasks.last.status, TaskStatus.skipped);
      await tracker.run('Test', (task) => task.done('Tested'));
      expect(tracker.tasks.last.label, 'Tested');
      expect(finished, [
        '✓ Build • 0.0 s',
        '✗ Deploy • 0.0 s • Bad state: disk full',
        '↓ Lint',
        '✓ Tested • 0.0 s',
      ]);
      expect(tracker.finished, isTrue);
    });

    test('a line per task finished, its amount in its unit', () async {
      final (tracker, clock) = tracked();
      final download = tracker.add(
        'assets.zip',
        total: 3400000,
        unit: ProgressUnit.bytes,
      )..advance(1200000);
      await clock.elapse(const Duration(milliseconds: 2100));
      download.done();
      expect(download.summary, '✓ assets.zip • 3.4/3.4 MB • 2.1 s');
      final files = tracker.add('files', total: 40)..update(12);
      await clock.elapse(const Duration(minutes: 1, seconds: 5));
      files.fail();
      expect(files.summary, '✗ files • 12/40 • 01:05');
      expect(tracker.add('wait').summary, '◦ wait');
    });
  });

  group('ProgressList', () {
    testTwk('a row a task: its mark, its label, its bar and how far it has '
        'got, the columns lined up', (t) async {
      final tracker = onApp(t);
      final download = tracker.add(
        'Downloading assets.zip',
        total: 2000000,
        unit: ProgressUnit.bytes,
      );
      final build = tracker.add('Building binary');
      tracker.add('Indexing database', total: 100);
      await t.pumpWidget(ProgressList(tracker: tracker), size: (64, 4));
      expect(rows(t), [
        '◦ Downloading assets.zip                                      0%',
        '◦ Building binary',
        '◦ Indexing database                                           0%',
        '',
      ]);
      download.start();
      build.start();
      await t.pump(s);
      download.update(1240000);
      await t.pump(s);
      build.done();
      await t.pump();
      expect(rows(t), [
        '* Downloading assets.zip ██████▉      62% • 620 kB/s • ETA 00:01',
        '✓ Building binary        ███████████ 100%                  2.0 s',
        '◦ Indexing database                    0%',
        '',
      ]);
      expect(t.clock.pendingTimers, greaterThan(0));
    });

    testTwk('the bar of a running task without a total sweeps; a list with '
        'nothing running leaves no timer', (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      final task = tracker.add('Index')..start();
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [ProgressColumn.label, ProgressColumn.bar],
        ),
        size: (18, 1),
      );
      expect(t.lines, ['Index ███']);
      await t.pump(ProgressBar.step);
      expect(t.lines, ['Index  ███']);
      task.done();
      await t.pump();
      expect(t.lines, ['Index ████████████']);
      await t.pump(s);
      expect(t.clock.pendingTimers, 0);
    });

    testTwk('in the line shape a bar is drawn as a LineGauge draws a heavy '
        'line: done to the half cell in its status color, the rest in the '
        "theme's border; a bar without a total sweeps along it", (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      final copy = tracker.add('Copy', total: 100)..start();
      tracker.add('Index').start();
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [ProgressColumn.label, ProgressColumn.bar],
          barShape: ProgressBarShape.line,
        ),
        size: (16, 2),
      );
      copy.update(45);
      // the rows are painted again at the spinner's next step
      await t.pump(SpinnerFrames.dots.interval);
      expect(t.lines, ['Copy  ━━━━╸━━━━━', 'Index ━━━━━━━━━━']);
      // a cell's color and attributes, and a row's from column 6
      (int, int) look(int x, int y) =>
          (t.vt.cell(x, y).fg, t.vt.cell(x, y).attrs);
      List<(int, int)> bar(int y) => [for (var x = 6; x < 16; x++) look(x, y)];
      final done = look(6, 0);
      final rest = look(15, 0);
      expect(done, isNot(rest));
      expect(bar(0), [...List.filled(5, done), ...List.filled(5, rest)]);
      // the sweep: a run of the line in the running color over the rest
      final sweep = bar(1);
      expect(sweep.where((c) => c != rest), hasLength(2));
      await t.pump(ProgressBar.step);
      expect(bar(1), isNot(sweep));
      expect(bar(1).where((c) => c != rest), hasLength(2));
      copy.done();
      await t.pump(SpinnerFrames.dots.interval);
      expect(bar(0).toSet(), hasLength(1));
      expect(bar(0).first, isNot(rest));
    });

    testTwk('the count of a task without a total is blank while it counted '
        'nothing, running or done, and shown once it counts', (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      final write = tracker.add('Write')..start();
      final scan = tracker.add('Scan')..start();
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [ProgressColumn.label, ProgressColumn.count],
        ),
        size: (12, 2),
      );
      scan.advance(12);
      write.done();
      await t.pump(SpinnerFrames.dots.interval);
      expect(t.lines, ['Write', 'Scan  12']);
    });

    testTwk('maxBarWidth caps the bar, the room past it left blank, the '
        'columns after it beside it', (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      tracker.add('Copy', total: 100)
        ..start()
        ..update(50);
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [
            ProgressColumn.label,
            ProgressColumn.bar,
            ProgressColumn.percent,
          ],
          maxBarWidth: 10,
        ),
        size: (40, 1),
      );
      await t.pump(SpinnerFrames.dots.interval);
      expect(t.lines, ['Copy █████      50%']);
    });

    testTwk('a million advance() calls a second cost a frame a step of the '
        'spinner', (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      final task = tracker.add('Count', total: 1000000)..start();
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [ProgressColumn.label, ProgressColumn.count],
        ),
        size: (22, 1),
      );
      await t.pump(SpinnerFrames.dots.interval);
      final frames = t.terminal.frames.length;
      // ten steps of the spinner, 12500 calls every 10 ms
      for (var tick = 0; tick < 80; tick++) {
        for (var i = 0; i < 12500; i++) {
          task.advance();
        }
        await t.pump(ms * 10);
      }
      expect(t.terminal.frames.length - frames, 10);
      expect(t.lines, ['Count 987500/1000000']);
      await t.pump(SpinnerFrames.dots.interval);
      expect(t.lines, ['Count 1000000/1000000']);
      // advance() alone asks for no frame
      final before = t.terminal.frames.length;
      task.advance(0);
      await t.pump(ms);
      expect(t.terminal.frames.length, before);
    });

    testTwk('rate and the time left move with the clock of the app', (
      t,
    ) async {
      final tracker = onApp(t);
      final task = tracker.add(
        'Upload',
        total: 10000000,
        unit: ProgressUnit.bytes,
      );
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [
            ProgressColumn.label,
            ProgressColumn.count,
            ProgressColumn.rate,
            ProgressColumn.eta,
            ProgressColumn.elapsed,
          ],
        ),
        size: (60, 1),
      );
      task.start();
      await t.pump(s);
      task.update(1200000);
      await t.pump(SpinnerFrames.dots.interval);
      expect(t.lines, [
        'Upload 1.2/10.0 MB • 1.2 MB/s • ETA 00:07 • 00:01',
      ]);
      await t.pump(const Duration(minutes: 1));
      task.done();
      await t.pump();
      // the rate and the time left are blank in every row: they take no room
      expect(t.lines, ['Upload 10.0/10.0 MB • 01:01']);
    });

    testTwk("a tracker handed the app's clock follows the fake clock from "
        'its first task: real time before its list builds is no time its '
        'tasks ran', (t) async {
      await t.pumpWidget(const _Download(), size: (24, 1));
      final state = t.state<_DownloadState>(find.byType(_Download));
      expect(state.tracker.clock, same(t.binding.twkApp.clock));
      final task = state.tracker.tasks.single;
      // set going at the app's time 0, 50 ms of real time before the list
      // built: a second on the app's clock is a second the task ran
      await t.pump(s - t.clock.elapsed);
      expect(task.elapsed, s);
      task.update(500);
      expect(task.rate, 500);
      await t.pump(s);
      expect(t.lines, ['Download 250/s']);
    });

    testTwk('a tracker handed no clock keeps its own stopwatch when a list '
        'shows it, and one handed a clock keeps that: nothing swaps it', (
      t,
    ) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      final own = tracker.clock;
      final task = tracker.add('Build')..start();
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [ProgressColumn.label, ProgressColumn.elapsed],
        ),
        size: (20, 1),
      );
      await t.pump(const Duration(seconds: 10));
      expect(tracker.clock, same(own));
      expect(tracker.clock, isNot(same(t.binding.twkApp.clock)));
      // the wall clock's time, not the 10 s the app's moved
      expect(task.elapsed, lessThan(const Duration(seconds: 5)));
      final given = Stopwatch();
      final kept = ProgressTracker(clock: given);
      addTearDown(kept.dispose);
      await t.pumpWidget(ProgressList(tracker: kept));
      expect(kept.clock, same(given));
    });

    testTwk('hideFinished leaves the tasks done and skipped out, not the '
        'failed', (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      final a = tracker.add('a')..start();
      final b = tracker.add('b')..start();
      final c = tracker.add('c')..start();
      tracker.add('d');
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          hideFinished: true,
          columns: const [ProgressColumn.mark, ProgressColumn.label],
        ),
        size: (8, 5),
      );
      expect(rows(t), ['* a', '* b', '* c', '◦ d', '']);
      a.done();
      b.fail();
      c.skip();
      await t.pump();
      expect(rows(t), ['✗ b', '◦ d', '', '', '']);
    });

    testTwk('maxVisible shows that many rows, the running first, and counts '
        'the others', (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      tracker.add('a').done();
      tracker.add('b');
      tracker.add('c').start();
      tracker.add('d').fail();
      tracker.add('e').start();
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          maxVisible: 2,
          columns: const [ProgressColumn.mark, ProgressColumn.label],
        ),
        size: (10, 4),
      );
      expect(rows(t), ['* c', '* e', '+3 more', '']);
      tracker.tasks[2].done();
      await t.pump();
      expect(rows(t), ['◦ b', '* e', '+3 more', '']);
      // then the failed before the done, the order kept
      tracker
        ..remove(tracker.tasks[1])
        ..tasks.last.done();
      await t.pump();
      expect(rows(t), ['✓ a', '✗ d', '+2 more', '']);
      tracker.remove(tracker.tasks.first);
      await t.pump();
      expect(rows(t), ['✓ c', '✗ d', '+1 more', '']);
    });

    testTwk('at narrow widths the labels are cut before the bar is under '
        '10, then the bar goes, then the columns from the last', (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      tracker.add('Downloading assets', total: 10).update(5);
      tracker.add('Build', total: 10).update(10);
      Future<List<String>> at(int width) async {
        await t.resize(width, 2);
        await t.pump();
        return rows(t);
      }

      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [
            ProgressColumn.mark,
            ProgressColumn.label,
            ProgressColumn.bar,
            ProgressColumn.percent,
            ProgressColumn.count,
          ],
        ),
        size: (48, 2),
      );
      expect(rows(t), [
        '* Downloading assets ███████         50% •  5/10',
        '* Build              ██████████████ 100% • 10/10',
      ]);
      // the bar at 10, the labels cut
      expect(await at(38), [
        '* Downloading… █████       50% •  5/10',
        '* Build        ██████████ 100% • 10/10',
      ]);
      // the labels at 8, the bar narrower
      expect(await at(29), [
        '* Downloa… ██▌    50% •  5/10',
        '* Build    █████ 100% • 10/10',
      ]);
      // no room for a bar
      expect(await at(23), [
        '* Downloa…  50% •  5/10',
        '* Build    100% • 10/10',
      ]);
      // then the last column goes, and the one before it
      expect(await at(15), ['* Downloa…  50%', '* Build    100%']);
      expect(await at(6), ['* Dow…', '* Bui…']);
    });

    testTwk('the percent is cut, and whole where the float of it times 100 '
        'is a hair short of it: 29 of 100 is 29%, not 28%', (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      final task = tracker.add('Copy', total: 100)..update(29);
      final other = tracker.add('Move', total: 1000)..update(996);
      await t.pumpWidget(
        ProgressList(
          tracker: tracker,
          columns: const [ProgressColumn.label, ProgressColumn.percent],
        ),
        size: (12, 2),
      );
      expect(t.lines, ['Copy 29%', 'Move 99%']);
      expect(t.binding.semantics.lines, [
        'list',
        'progressbar Copy: 29%',
        'progressbar Move: 99%',
      ]);
      task.done();
      other.done();
      await t.pump();
      expect(t.lines, ['Copy 100%', 'Move 100%']);
    });

    testTwk('a screen reader reads a list of progress bars with their '
        'labels', (t) async {
      final tracker = ProgressTracker();
      addTearDown(tracker.dispose);
      tracker.add('Download', total: 4).update(1);
      tracker.add('Build').done();
      await t.pumpWidget(ProgressList(tracker: tracker), size: (40, 3));
      expect(t.binding.semantics.lines, [
        'list',
        'progressbar Download: 25%',
        'progressbar Build, done',
      ]);
    });
  });
}

/// A download set going as the State is made, its tracker made with it on
/// the app's clock, as a program's State makes one: real time passes
/// before its list builds.
final class _Download extends StatefulWidget {
  const _Download();

  @override
  State<_Download> createState() => _DownloadState();
}

final class _DownloadState extends State<_Download> {
  /// On the app's clock, which a test's fake clock moves: first read in
  /// [initState].
  late final tracker = ProgressTracker(
    clock: AppBinding.of(context).twkApp.clock,
  );

  @override
  void initState() {
    super.initState();
    tracker.add('Download', total: 1000).start();
    // what the first build may take in a cold isolate, and more: real time
    // on purpose, which the test shows is no time on the app's fake clock
    // ignore: twk_lints/wall_time_in_tests
    sleep(const Duration(milliseconds: 50));
  }

  @override
  void dispose() {
    tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProgressList(
    tracker: tracker,
    columns: const [ProgressColumn.label, ProgressColumn.rate],
  );
}
