// Everything that steps with Steps (Spinner, ProgressBar, ProgressList,
// TaskList, Skeleton) stands still under a TickerMode that is off or an
// Offstage: it changes nothing it shows and asks for no frame, and goes on
// from where it stood when the mode is on again.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

/// What row 0 shows, the text and the colors.
List<Object?> shown(TwkTester t, int width) => [
  t.lines.first,
  for (var x = 0; x < width; x++) t.cell(x, 0).fg,
];

void main() {
  final cases = <String, (Widget Function(TwkTester), int)>{
    'Spinner': ((_) => const Spinner(), 3),
    'ProgressBar': ((_) => const ProgressBar(), 10),
    'ProgressList': (
      (t) {
        final tracker = ProgressTracker(clock: t.clock.stopwatch)
          ..add('Index').start();
        addTearDown(tracker.dispose);
        return ProgressList(tracker: tracker);
      },
      20,
    ),
    'TaskList': (
      (_) => const TaskList(
        showElapsed: false,
        tasks: [TaskItem('Build', status: TaskItemStatus.running)],
      ),
      20,
    ),
    'TaskList with the time': (
      (_) => const TaskList(
        tasks: [TaskItem('Build', status: TaskItemStatus.running)],
      ),
      20,
    ),
    'Skeleton': (
      (_) => const Theme.terminal(
        child: Theme(
          data: ThemeData.dark,
          child: Align(
            alignment: Alignment.topLeft,
            child: Skeleton(width: 20),
          ),
        ),
      ),
      20,
    ),
  };

  for (final MapEntry(key: name, value: (build, width)) in cases.entries) {
    group(name, () {
      testTwk('under TickerMode(enabled: false) shows the same and asks for '
          'no frame; on again it moves', (t) async {
        Widget app({required bool enabled}) =>
            TickerMode(enabled: enabled, child: build(t));
        await t.pumpWidget(app(enabled: false), size: (20, 1));
        final before = shown(t, width);
        await t.pump(const Duration(seconds: 2));
        expect(shown(t, width), before);
        expect(t.clock.pendingTimers, 0);
        await t.pumpWidget(app(enabled: true));
        expect(t.clock.pendingTimers, 1);
        await t.pump(const Duration(seconds: 2));
        expect(shown(t, width), isNot(before));
      });

      testTwk('in an Offstage asks for no frame', (t) async {
        await t.pumpWidget(
          Offstage(child: build(t)),
          size: (20, 1),
        );
        await t.pump(const Duration(seconds: 2));
        expect(t.clock.pendingTimers, 0);
      });
    });
  }

  testTwk('a muted ProgressList keeps the mark of its spinner as the tracker '
      'repaints it', (t) async {
    final tracker = ProgressTracker(clock: t.clock.stopwatch);
    addTearDown(tracker.dispose);
    tracker.add('Index', total: 100).start();
    await t.pumpWidget(
      TickerMode(enabled: false, child: ProgressList(tracker: tracker)),
      size: (30, 8),
    );
    final mark = t.lines.first[0];
    for (var i = 1; i <= 5; i++) {
      await t.pump(ms * 90);
      tracker.add('Task $i');
      await t.pump(ms * 10);
      expect(t.lines.first[0], mark);
    }
  });

  testTwk('a muted Spinner keeps its frame and goes on from it', (t) async {
    Widget app({required bool enabled}) =>
        TickerMode(enabled: enabled, child: const Spinner());
    await t.pumpWidget(app(enabled: true), size: (3, 1));
    await t.pump(ms * 85);
    final frame = t.lines.first;
    expect(frame.trim(), '⠙');
    await t.pumpWidget(app(enabled: false));
    await t.pump(const Duration(seconds: 3));
    expect(t.lines.first, frame);
    await t.pumpWidget(app(enabled: true));
    // the frames pumpWidget lets pass are the next ones, not those the
    // 3 seconds would have come to
    expect(t.lines.first.trim(), isIn(['⠙', '⠹']));
    await t.pump(ms * 80);
    expect(t.lines.first.trim(), isIn(['⠹', '⠸']));
  });
}
