// Task lists on the fake clock: the mark of each status in its color, the
// sub-tasks indented, the time a task has run, and a change to one task,
// a step of its spinner or a second of its time repainting its row alone.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../layout/view.dart' show View;
import 'shot.dart';

const ms = Duration(milliseconds: 1);

/// Pumps until the clock reads [at].
Future<void> until(TwkTester t, Duration at) => t.pump(at - t.clock.elapsed);

/// The rows [t] shows, the spinner's frame as `*`.
List<String> rows(TwkTester t) => [
  for (final line in t.lines)
    line.replaceAll(RegExp('[${SpinnerFrames.dots.frames.join()}]'), '*'),
];

/// A list of one task, [label] at [status].
TaskList one(String label, TaskStatus status) =>
    TaskList(tasks: [TaskItem(label, status: status)]);

void main() {
  testTwk('shows the mark of each status in its color, the label after '
      'it, and the sub-tasks of a task indented below it', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: TaskList(
          showElapsed: false,
          tasks: [
            TaskItem('Fetch', status: TaskStatus.done),
            TaskItem(
              'Build',
              status: TaskStatus.running,
              children: [
                TaskItem('lib/a.dart', status: TaskStatus.done),
                TaskItem(
                  'lib/b.dart',
                  status: TaskStatus.running,
                  children: [TaskItem('parse', status: TaskStatus.failed)],
                ),
                TaskItem('lib/c.dart'),
              ],
            ),
            TaskItem('Lint', status: TaskStatus.failed),
            TaskItem('Deploy', status: TaskStatus.skipped),
            TaskItem('Test'),
          ],
        ),
      ),
      size: (16, 10),
    );
    expect(t.lines, [
      '✓ Fetch',
      '⠋ Build',
      '  ✓ lib/a.dart',
      '  ⠋ lib/b.dart',
      '    ✗ parse',
      '  ◦ lib/c.dart',
      '✗ Lint',
      '↓ Deploy',
      '◦ Test',
      '',
    ]);
    const theme = ThemeData.terminal(Brightness.dark);
    expect(t, styleAt(0, 0, hasFg(theme.success.fg!)));
    expect(t, styleAt(0, 1, hasFg(theme.primary.fg!)));
    expect(t, styleAt(4, 4, hasFg(theme.error.fg!)));
    expect(t, styleAt(0, 8, hasFg(const Color.indexed(245))));
    // a skipped task's label is muted too, the others' not
    expect(t, styleAt(2, 7, hasFg(const Color.indexed(245))));
    expect(t, isNot(styleAt(2, 8, hasFg(const Color.indexed(245)))));
  });

  testTwk('times a task on the clock of the app: as a clock in whole '
      'seconds while it runs, to the tenth once it is done, and no timer is '
      'left', (t) async {
    await t.pumpWidget(
      Theme.terminal(child: one('Build', TaskStatus.running)),
      size: (16, 1),
    );
    expect(rows(t), ['* Build 00:00']);
    await until(t, ms * 999);
    expect(rows(t), ['* Build 00:00']);
    await until(t, ms * 1000);
    expect(rows(t), ['* Build 00:01']);
    await until(t, ms * 3250);
    expect(rows(t), ['* Build 00:03']);
    await t.pumpWidget(Theme.terminal(child: one('Build', TaskStatus.done)));
    expect(t.lines, ['✓ Build 3.2 s']);
    await t.pump(const Duration(seconds: 5));
    expect(t.lines, ['✓ Build 3.2 s']);
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('a task set running counts from that frame, keeps its time when '
      'it fails, and shows none pending or skipped', (t) async {
    await t.pumpWidget(
      Theme.terminal(child: one('Build', TaskStatus.pending)),
      size: (16, 1),
    );
    expect(t.lines, ['◦ Build']);
    expect(t.clock.pendingTimers, 0);
    await until(t, ms * 500);
    await t.pumpWidget(Theme.terminal(child: one('Build', TaskStatus.running)));
    await until(t, ms * 1499);
    expect(rows(t), ['* Build 00:00']);
    await until(t, ms * 1500);
    expect(rows(t), ['* Build 00:01']);
    await until(t, ms * 2750);
    await t.pumpWidget(Theme.terminal(child: one('Build', TaskStatus.failed)));
    expect(t.lines, ['✗ Build 2.2 s']);
    await t.pumpWidget(Theme.terminal(child: one('Build', TaskStatus.running)));
    expect(rows(t), ['* Build 00:00']);
    await t.pumpWidget(Theme.terminal(child: one('Build', TaskStatus.skipped)));
    expect(t.lines, ['↓ Build']);
    await t.pumpWidget(Theme.terminal(child: one('Build', TaskStatus.done)));
    expect(t.lines, ['✓ Build']);
  });

  testTwk('a time the task is given is shown as given, running or done, '
      'and the row times it no more; without it, it times it again', (
    t,
  ) async {
    TaskList given(TaskStatus status, Duration? elapsed) => TaskList(
      tasks: [TaskItem('Build', status: status, elapsed: elapsed)],
    );
    await t.pumpWidget(
      Theme.terminal(
        child: given(TaskStatus.running, const Duration(milliseconds: 2600)),
      ),
      size: (16, 1),
    );
    expect(rows(t), ['* Build 00:02']);
    // the clock moves on, the time given does not
    await until(t, ms * 3000);
    expect(rows(t), ['* Build 00:02']);
    expect(t.clock.pendingTimers, 1, reason: "the spinner's alone");
    // a task shown done at once shows the time it is given
    await t.pumpWidget(
      Theme.terminal(child: given(TaskStatus.done, ms * 1400)),
    );
    expect(t.lines, ['✓ Build 1.4 s']);
    await t.pumpWidget(
      Theme.terminal(child: given(TaskStatus.failed, ms * 61500)),
    );
    expect(t.lines, ['✗ Build 01:01']);
    await t.pumpWidget(
      Theme.terminal(child: given(TaskStatus.skipped, ms * 1400)),
    );
    expect(t.lines, ['↓ Build']);
    await t.pumpWidget(
      Theme.terminal(child: given(TaskStatus.pending, ms * 1400)),
    );
    expect(t.lines, ['◦ Build']);
    expect(t.clock.pendingTimers, 0);
    // its time no longer given, it times it from the frame it was set
    // running in
    await t.pumpWidget(
      Theme.terminal(child: given(TaskStatus.running, ms * 9000)),
    );
    expect(rows(t), ['* Build 00:09']);
    await t.pumpWidget(Theme.terminal(child: given(TaskStatus.running, null)));
    expect(rows(t), ['* Build 00:00']);
    await t.pump(const Duration(seconds: 1));
    expect(rows(t), ['* Build 00:01']);
    await t.pumpWidget(
      Theme.terminal(
        child: TaskList(
          showElapsed: false,
          tasks: [TaskItem('Build', status: TaskStatus.done, elapsed: ms * 5)],
        ),
      ),
    );
    expect(t.lines, ['✓ Build']);
  });

  testTwk('a task running in a row not painted, scrolled out of view, '
      'shows the time it has run once it is', (t) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Widget list(TaskStatus second) => SizedBox(
      height: 1,
      child: SingleChildScrollView(
        controller: scroll,
        child: TaskList(
          tasks: [
            const TaskItem('Fetch', status: TaskStatus.done),
            TaskItem('Build', status: second),
          ],
        ),
      ),
    );
    await t.pumpWidget(
      Theme.terminal(child: list(TaskStatus.running)),
      size: (16, 1),
    );
    final from = t.clock.elapsed;
    await until(t, from + ms * 2500);
    scroll.jumpTo(1);
    await t.pump();
    expect(rows(t), ['* Build 00:02']);
  });

  testTwk('minutes and seconds, then hours, minutes and seconds', (t) async {
    await t.pumpWidget(
      Theme.terminal(child: one('Build', TaskStatus.running)),
      size: (16, 1),
    );
    await until(t, const Duration(minutes: 1, seconds: 5));
    expect(rows(t), ['* Build 01:05']);
    await until(t, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(rows(t), ['* Build 1:02:03']);
    await t.pumpWidget(Theme.terminal(child: one('Build', TaskStatus.done)));
    expect(t.lines, ['✓ Build 1:02:03']);
  });

  testTwk('a change to one task repaints its row alone', (t) async {
    final count = PaintCount();
    Widget list(TaskStatus second) => Column(
      children: [
        TaskList(
          tasks: [
            const TaskItem('Fetch', status: TaskStatus.done),
            TaskItem('Build', status: second),
            const TaskItem('Test'),
          ],
        ),
        Counted(count),
      ],
    );
    await t.pumpWidget(
      Theme.terminal(child: list(TaskStatus.pending)),
      size: (12, 4),
    );
    final painted = count.paints;
    for (final status in [
      TaskStatus.running,
      TaskStatus.done,
      TaskStatus.failed,
      TaskStatus.skipped,
    ]) {
      await t.pumpWidget(Theme.terminal(child: list(status)));
      expect(t.binding.twkApp.stats.lastRepaints, 1, reason: '$status');
    }
    expect(t.lines, ['✓ Fetch', '↓ Build', '◦ Test', '']);
    expect(count.paints, painted);
  });

  testTwk('a step of the spinner and a second of the time repaint the row '
      'of the running task alone, a time that grows lays it out alone', (
    t,
  ) async {
    final count = PaintCount();
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          children: [
            const TaskList(
              tasks: [
                TaskItem('Fetch', status: TaskStatus.done),
                TaskItem('Build', status: TaskStatus.running),
              ],
            ),
            Counted(count),
          ],
        ),
      ),
      size: (16, 3),
    );
    final painted = count.paints;
    await until(t, ms * 80);
    expect(t.lines[1], '⠙ Build 00:00');
    expect(t.binding.twkApp.stats.lastRepaints, 1);
    await until(t, ms * 1000);
    expect(rows(t)[1], '* Build 00:01');
    expect(t.binding.twkApp.stats.lastRepaints, 1);
    await until(t, ms * 10000);
    expect(rows(t), ['✓ Fetch', '* Build 00:10', '']);
    expect(t.binding.twkApp.stats.lastRepaints, 1);
    // the clock takes two columns more at the hour
    await until(t, const Duration(hours: 1));
    expect(rows(t), ['✓ Fetch', '* Build 1:00:00', '']);
    expect(t.binding.twkApp.stats.lastRepaints, 1);
    expect(count.paints, painted);
  });

  testTwk('a row stays with its task as tasks come and go around it, and '
      'its time goes on', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: TaskList(
          tasks: [TaskItem('Build', status: TaskStatus.running)],
        ),
      ),
      size: (16, 3),
    );
    await until(t, ms * 1500);
    await t.pumpWidget(
      const Theme.terminal(
        child: TaskList(
          tasks: [
            TaskItem('Fetch', status: TaskStatus.done),
            TaskItem('Build', status: TaskStatus.running),
          ],
        ),
      ),
    );
    expect(rows(t), ['✓ Fetch', '* Build 00:01', '']);
    // a task of another id is another task
    await t.pumpWidget(
      const Theme.terminal(
        child: TaskList(
          tasks: [
            TaskItem('Fetch', status: TaskStatus.done),
            TaskItem('Build', id: 2, status: TaskStatus.running),
          ],
        ),
      ),
    );
    expect(rows(t), ['✓ Fetch', '* Build 00:00', '']);
    // the same label under another task: another task
    await t.pumpWidget(
      const Theme.terminal(
        child: TaskList(
          tasks: [
            TaskItem(
              'a',
              children: [TaskItem('x', status: TaskStatus.running)],
            ),
          ],
        ),
      ),
    );
    await until(t, ms * 3500);
    await t.pumpWidget(
      const Theme.terminal(
        child: TaskList(
          tasks: [
            TaskItem(
              'b',
              children: [TaskItem('x', status: TaskStatus.running)],
            ),
            TaskItem('a'),
          ],
        ),
      ),
    );
    expect(rows(t), ['◦ b', '  * x 00:00', '◦ a']);
  });

  testTwk('a label too long is cut off with an ellipsis before the time', (
    t,
  ) async {
    await t.pumpWidget(
      Theme.terminal(child: one('Compile everything', TaskStatus.running)),
      size: (15, 1),
    );
    expect(rows(t), ['* Compil… 00:00']);
    await t.pumpWidget(
      Theme.terminal(child: one('Compile everything', TaskStatus.pending)),
    );
    expect(t.lines, ['◦ Compile ever…']);
  });

  testTwk('the spinner of its choice, and the mark as wide as its widest '
      'frame', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: TaskList(
          spinner: SpinnerFrames(['a', 'bbb'], interval: Duration(seconds: 1)),
          showElapsed: false,
          tasks: [
            TaskItem('Build', status: TaskStatus.running),
            TaskItem('Test', status: TaskStatus.done),
          ],
        ),
      ),
      size: (12, 2),
    );
    expect(t.lines, ['a   Build', '✓   Test']);
    await until(t, const Duration(seconds: 1));
    expect(t.lines, ['bbb Build', '✓   Test']);
  });

  test('outside an app the spinner shows its first frame and no time', () {
    final v = View(10, 1)..pump(one('Build', TaskStatus.running));
    expect(v.rows(), ['⠋ Build']);
  });
}
