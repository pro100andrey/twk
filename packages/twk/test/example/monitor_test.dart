// The process monitor of example/monitor.dart on made-up processes: the
// gauges and sparklines, a sample a second, the table sorted by a click
// or a key, the selection kept through the samples, the tree and its
// folds, the selection carried between the two; and ProcSource reading a
// directory laid out as /proc.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/monitor.dart';

/// The monitor on made-up processes, on a terminal of 80 × 24.
Future<void> start(TwkTester t) => t.pumpWidget(
  Monitor(source: SyntheticSource()),
  size: (80, 24),
  backgroundRgb: 0x16181d,
);

/// The pids the table shows, top down.
List<int> pids(TwkTester t) => [
  for (final line in t.lines.sublist(8, 22))
    int.parse(line.substring(1, 9).trim()),
];

/// The row of the screen that shows the process [pid] in the table.
int tableRow(TwkTester t, int pid) => t.lines.indexWhere(
  (l) => l.length > 9 && l.substring(1, 9).trim() == '$pid',
);

/// The row of the screen that shows the process [pid] in the tree.
int treeRow(TwkTester t, int pid) => t.lines.indexWhere(
  (l) => l.length > 65 && l.substring(57, 65).trim() == '$pid',
);

/// Whether row [y] is the one selected.
Matcher selected(int y) => styleAt(30, y, hasBg(theme.selection.bg!));

/// The theme the app takes on the tests' terminal, a dark one: twk's own.
const ThemeData theme = ThemeData.dark;

void main() {
  testTwk('the CPU busy and the memory used as gauges under sparklines; the '
      'processes sorted by the CPU they use, the most first', (t) async {
    await start(t);
    expect(
      t,
      matchesScreen('''
╭ cpu ──────────── load 0.97 1.10 0.90 ╮╭ mem ────────────────── 3.7G of 16.0G ╮
│                                      ││                                      │
│                                      ││                                      │
│                                    ▆ ││                                    ▆ │
│  24.3%  ──────────────────────────── ││  23.4%  ──────╴───────────────────── │
╰──────────────────────────────────────╯╰──────────────────────────────────────╯
╭ 21 processes ────────────────────────────────────────────────────────────────╮
│     pid name            cpu% ▾    mem   thr command                          │
│    3000 cc                50.0  40.0M     1 cc -O2 -c src/part0.c            │
│    1203 postgres          18.4   220M     1 postgres -D /var/lib/postgresql/…│
│     950 containerd         5.8  52.0M    14 /usr/bin/containerd              │
│     801 dockerd            4.4  96.0M    22 /usr/bin/dockerd -H fd://        │
│      51 kworker/1:2        4.2     0B     1 [kworker/1:2]                    │
│    1240 postgres           3.6  30.0M     1 postgres: checkpointer           │
│      14 ksoftirqd/0        3.0     0B     1 [ksoftirqd/0]                    │
│    1241 postgres           2.8  18.0M     1 postgres: walwriter              │
│     498 NetworkManager     2.0  21.0M     4 /usr/bin/NetworkManager -n       │
│       1 systemd            1.8  14.0M     1 /usr/lib/systemd/systemd --system│
│    4388 vim                0.9  32.0M     1 vim lib/main.dart                │
│     312 systemd-journal    0.3  48.0M     1 /lib/systemd/systemd-journald    │
│    2600 make               0.1   4.0M     1 make -j4                         │
│    2210 dart               0.0   140M     9 dart run example/monitor.dart    │
╰──────────────────────────────────────────────────────────────────────────────╯
 ↑↓ select  s < > sort  t tree  q quit
'''),
    );
    // the terminal's own colors: the sparklines, the gauges' filled parts
    expect(t, styleAt(37, 3, hasFg(theme.info.fg!)));
    expect(t, styleAt(77, 3, hasFg(theme.accent.fg!)));
    expect(t, styleAt(10, 4, hasFg(theme.success.fg!)));
    expect(t, styleAt(30, 4, hasFg(theme.border.fg!)));
    expect(t, styleAt(2, 0, hasFg(theme.primary.fg!)));
    expect(t, styleAt(2, 6, hasFg(theme.primary.fg!)));
    expect(t, styleAt(6, 7, hasAttr(Attr.bold)));
  });

  testTwk('a sample a second, a frame for each and none between: the '
      'sparklines grow by a bar, the numbers and the order change', (t) async {
    await start(t);
    final frames = t.terminal.frames.length;
    await t.pump(const Duration(milliseconds: 500));
    expect(t.terminal.frames, hasLength(frames));
    await t.pump(const Duration(milliseconds: 500));
    expect(t.terminal.frames, hasLength(frames + 1));
    await t.pump(const Duration(seconds: 1));
    expect(t.terminal.frames, hasLength(frames + 2));

    expect(
      t,
      matchesScreen('''
╭ cpu ──────────── load 1.24 1.11 0.90 ╮╭ mem ────────────────── 3.8G of 16.0G ╮
│                                      ││                                      │
│                                      ││                                      │
│                                  ▆▇▇ ││                                  ▆▆▆ │
│  30.9%  ────────╴─────────────────── ││  24.0%  ──────╴───────────────────── │
╰──────────────────────────────────────╯╰──────────────────────────────────────╯
╭ 21 processes ────────────────────────────────────────────────────────────────╮
│     pid name            cpu% ▾    mem   thr command                          │
│    3000 cc                90.0   100M     1 cc -O2 -c src/part0.c            │
│    1203 postgres           8.7   220M     1 postgres -D /var/lib/postgresql/…│
│     950 containerd         5.8  52.0M    14 /usr/bin/containerd              │
│      51 kworker/1:2        5.0     0B     1 [kworker/1:2]                    │
│      14 ksoftirqd/0        2.8     0B     1 [ksoftirqd/0]                    │
│    1240 postgres           2.5  30.0M     1 postgres: checkpointer           │
│       1 systemd            2.0  14.0M     1 /usr/lib/systemd/systemd --system│
│     801 dockerd            1.9  96.0M    22 /usr/bin/dockerd -H fd://        │
│     498 NetworkManager     1.7  21.0M     4 /usr/bin/NetworkManager -n       │
│    1241 postgres           1.0  18.0M     1 postgres: walwriter              │
│    2210 dart               0.9   140M     9 dart run example/monitor.dart    │
│    4388 vim                0.6  32.0M     1 vim lib/main.dart                │
│    2600 make               0.5   4.0M     1 make -j4                         │
│    1500 tmux: server       0.2   8.0M     1 tmux new -s work                 │
╰──────────────────────────────────────────────────────────────────────────────╯
 ↑↓ select  s < > sort  t tree  q quit
'''),
    );
  });

  testTwk('a process that ends leaves the table, one that starts comes in', (
    t,
  ) async {
    await start(t);
    expect(t, containsLine(contains(' 3000 cc ')));
    await t.pump(const Duration(seconds: 3));
    expect(t, isNot(containsLine(contains(' 3000 cc '))));
    expect(t, containsLine(contains(' 3001 cc ')));
    expect(t, containsLine(contains('cc -O2 -c src/part1.c')));
    expect(t, hasTextAt(0, 6, '╭ 21 processes '));
  });

  testTwk('a click on a title sorts by its column, again the other way; s, '
      '< and > from the keys; the order kept through the samples', (t) async {
    await start(t);
    await t.click(7, 7);
    await t.pump();
    expect(t, hasTextAt(1, 7, '   pid ▴ name '));
    expect(pids(t), [
      1, 2, 14, 51, 312, 498, 733, 801, 950, 1203, 1240, 1241, 1500, 1501, //
    ]);

    await t.click(7, 7);
    await t.pump();
    expect(t, hasTextAt(1, 7, '   pid ▾ name '));
    const descending = [
      4388, 4120, 4102, 3000, 2600, 2210, 1502, 1501, 1500, 1241, 1240, //
      1203, 950, 801,
    ];
    expect(pids(t), descending);
    await t.pump(const Duration(seconds: 3));
    expect(pids(t), [...descending]..[3] = 3001);

    await t.press('>');
    await t.pump();
    expect(t, hasTextAt(1, 7, '     pid name ▴ '));
    expect(pids(t).take(4), [498, 4120, 3001, 950]);
    await t.press('<');
    await t.pump();
    expect(t, hasTextAt(1, 7, '   pid ▴ name '));
    await t.press('s');
    await t.pump();
    expect(t, hasTextAt(1, 7, '   pid ▾ name '));
    expect(pids(t).first, 4388);
  });

  testTwk('the arrows select a process, which stays selected as the rows are '
      'sorted again', (t) async {
    await start(t);
    await t.press('down');
    await t.pump();
    expect(t, selected(8));
    await t.press('down down down');
    await t.pump();
    expect(tableRow(t, 801), 11);
    expect(t, selected(11));

    await t.pump(const Duration(seconds: 1));
    expect(tableRow(t, 801), 13);
    expect(t, selected(13));
    expect(t, isNot(selected(11)));
  });

  testTwk('t shows the processes under their parents, every parent expanded, '
      'and t the table again', (t) async {
    await start(t);
    await t.press('t');
    await t.pump();
    expect(
      t,
      matchesScreen('''
╭ cpu ──────────── load 0.97 1.10 0.90 ╮╭ mem ────────────────── 3.7G of 16.0G ╮
│                                      ││                                      │
│                                      ││                                      │
│                                    ▆ ││                                    ▆ │
│  24.3%  ──────────────────────────── ││  23.4%  ──────╴───────────────────── │
╰──────────────────────────────────────╯╰──────────────────────────────────────╯
╭ 21 processes ────────────────────────────────────────────────────────────────╮
│ ▾ systemd                                                     1    1.8  14.0M│
│ ├── systemd-journal                                         312    0.3  48.0M│
│ ├── NetworkManager                                          498    2.0  21.0M│
│ ├─▾ sshd                                                    733    0.0   9.0M│
│ │ └─▾ sshd                                                 4102    0.0  11.0M│
│ │   └─▾ bash                                               4120    0.0   5.0M│
│ │     └── vim                                              4388    0.9  32.0M│
│ ├─▾ dockerd                                                 801    4.4  96.0M│
│ │ └─▾ containerd                                            950    5.8  52.0M│
│ │   └─▾ postgres                                           1203   18.4   220M│
│ │     ├── postgres                                         1240    3.6  30.0M│
│ │     └── postgres                                         1241    2.8  18.0M│
│ └─▾ tmux: server                                           1500    0.0   8.0M│
│   ├─▾ zsh                                                  1501    0.0   6.0M│
│   │ └── dart                                               2210    0.0   140M│
╰──────────────────────────────────────────────────────────────────────────────╯
 ↑↓ select  ←→ fold  * unfold all  t table  q quit
'''),
    );
    // and kthreadd's below, past the end
    await t.press('end');
    await t.pump();
    expect(t.lines[21], startsWith('│ └── kworker/1:2 '));
    expect(t, selected(21));

    await t.press('t');
    await t.pump();
    expect(t, hasTextAt(1, 7, '     pid name            cpu% ▾'));
  });

  testTwk('Left collapses the process selected, through the samples, and '
      'Right expands it again', (t) async {
    await start(t);
    await t.press('t');
    await t.pump();
    await t.press('down down down down');
    await t.pump();
    expect(t, selected(10));
    await t.press('left');
    await t.pump();
    expect(t, hasTextAt(1, 10, ' ├─▸ sshd '));
    expect(t, hasTextAt(1, 11, ' ├─▾ dockerd '));
    await t.pump(const Duration(seconds: 1));
    expect(t, hasTextAt(1, 10, ' ├─▸ sshd '));
    expect(treeRow(t, 4102), -1);

    await t.press('right');
    await t.pump();
    expect(t, hasTextAt(1, 10, ' ├─▾ sshd '));
    expect(treeRow(t, 4102), 11);
  });

  testTwk('the process selected in the table is selected in the tree, its '
      'ancestors expanded, and the other way', (t) async {
    await start(t);
    // sshd collapsed in the tree, still selected in the table
    await t.press('t');
    await t.pump();
    await t.press('down down down down left t');
    await t.pump();
    await t.press('down');
    await t.pump();
    // the row after sshd's, sorted by the CPU used
    expect(tableRow(t, 1501), 21);
    expect(t, selected(21));

    // vim, the last pid, below sshd
    await t.click(7, 7);
    await t.pump();
    await t.click(7, 7);
    await t.pump();
    await t.press('home');
    await t.pump();
    expect(t, selected(tableRow(t, 4388)));
    await t.press('t');
    await t.pump();
    expect(t, hasTextAt(1, 10, ' ├─▾ sshd '));
    expect(treeRow(t, 4388), 13);
    expect(t, selected(13));
  });

  testTwk('the process selected shows in the tree and in the table, each '
      'mounted with it out of view from the top', (t) async {
    await start(t);
    // cc, the most CPU used, below the tree's first window
    await t.press('down t');
    await t.pump();
    expect(treeRow(t, 3000), 21);
    expect(t, selected(21));
    expect(t, hasTextAt(1, 7, ' ├─▾ sshd '));

    // sshd, no CPU used, below the table's first window
    await t.press('home');
    await t.pump();
    await t.press('down down down');
    await t.pump();
    expect(treeRow(t, 733), 10);
    await t.press('t');
    await t.pump();
    expect(tableRow(t, 733), 21);
    expect(t, selected(21));
  });

  testTwk('a read that fails is logged, and the next second reads again', (
    t,
  ) async {
    final source = _FailingOnce(SyntheticSource());
    await t.pumpWidget(Monitor(source: source), size: (80, 24));
    await t.pump(const Duration(seconds: 3));
    expect(t.logs.records.map((r) => r.message), [
      contains('reading failed: '),
    ]);
    expect(source.reads, greaterThan(2));
    expect(t, containsLine(contains(' processes ')));
  });

  testTwk('q quits', (t) async {
    await start(t);
    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  group('ProcSource', () {
    late Directory proc;

    setUp(() => proc = Directory.systemTemp.createTempSync('proc'));
    tearDown(() => proc.deleteSync(recursive: true));

    void write(String path, String text) => (File(
      '${proc.path}/$path',
    )..createSync(recursive: true)).writeAsStringSync(text);

    /// /proc/[pid]/stat of a process: [time] jiffies of user and system
    /// time, [rss] pages.
    void process(
      int pid,
      String name,
      int ppid, {
      required int time,
      int threads = 1,
      int rss = 0,
      String command = '',
    }) {
      write(
        '$pid/stat',
        '$pid ($name) S $ppid $pid $pid 0 -1 4194560 0 0 0 0 '
            '${time - time ~/ 4} ${time ~/ 4} 0 0 20 0 $threads 0 $pid '
            '1000000 $rss 18446744073709551615 0 0',
      );
      write(
        '$pid/cmdline',
        command.isEmpty ? '' : '${command.replaceAll(' ', '\x00')}\x00',
      );
    }

    test(
      'reads the processes of a directory laid out as /proc: how much of '
      'a CPU each used since the read before, the CPUs and the memory',
      () async {
        // two CPUs: 1000 jiffies, 850 of them idle
        write('stat', '''
cpu  100 0 50 800 50 0 0 0 0 0
cpu0 50 0 25 400 25 0 0 0 0 0
cpu1 50 0 25 400 25 0 0 0 0 0
intr 12345 0 0
''');
        write('meminfo', '''
MemTotal:       16000000 kB
MemFree:         1000000 kB
MemAvailable:   12000000 kB
''');
        write('loadavg', '0.52 0.58 0.59 1/123 4567\n');
        process(
          1,
          'systemd',
          0,
          time: 20,
          rss: 100,
          command: '/sbin/init splash',
        );
        process(2, 'kthreadd', 0, time: 8);
        // a name may hold a parenthesis and a blank
        process(42, 'odd) name', 1, time: 100, threads: 3, command: 'odd');
        final source = ProcSource(root: proc.path);

        final first = await source.read();
        expect(first.cpu, closeTo(.15, 1e-9));
        expect(first.memoryTotal, 16000000 * 1024);
        expect(first.memoryUsed, 4000000 * 1024);
        expect(first.load, (.52, .58, .59));
        expect(
          [
            for (final p in first.processes)
              (p.pid, p.ppid, p.name, p.command, p.threads, p.memory),
          ],
          unorderedEquals([
            (1, 0, 'systemd', '/sbin/init splash', 1, 100 * 4096),
            (2, 0, 'kthreadd', '', 1, 0),
            (42, 1, 'odd) name', 'odd', 3, 0),
          ]),
        );

        // a second later: 1000 jiffies more, 800 of them idle, so 500 a CPU;
        // kthreadd ended, a process 77 started
        write('stat', 'cpu  250 0 100 1550 100 0 0 0 0 0\ncpu0\ncpu1\n');
        process(1, 'systemd', 0, time: 270, rss: 100);
        process(42, 'odd) name', 1, time: 100, threads: 3);
        process(77, 'cc', 42, time: 50, command: 'cc -c a.c');
        Directory('${proc.path}/2').deleteSync(recursive: true);
        final second = await source.read();
        expect(second.cpu, closeTo(.2, 1e-9));
        expect(
          {for (final p in second.processes) p.pid: (p.cpu, p.command)},
          {
            1: (.5, '/sbin/init splash'),
            42: (0, 'odd'),
            77: (.1, 'cc -c a.c'),
          },
        );
      },
    );
  });
}

/// [source], whose first read fails.
final class _FailingOnce implements ProcessSource {
  _FailingOnce(this.source);

  final ProcessSource source;
  var reads = 0;

  @override
  Future<Sample> read() => reads++ == 0
      ? Future.error(const FormatException('a line of /proc cut short'))
      : source.read();
}
