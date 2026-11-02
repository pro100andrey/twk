/// Apps of package:twk and twk_rich as users run them: what a frame of each
/// costs when the app does what it is for.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';

import 'app_run.dart';

/// A workload of an app: [start] runs it on [AppRun] and returns its step
/// `i` (from 1), which changes something and pumps; [perStep] is how many
/// [unit]s a step is.
final class AppScenario {
  const AppScenario(
    this.name,
    this.about,
    this.start, {
    this.unit = 'frame',
    this.perStep = 1,
    this.steps = 300,
    this.quiet = false,
  });
  final String name;
  final String about;
  final Future<(AppRun, FutureOr<void> Function(int i))> Function(int w, int h)
  start;
  final String unit;
  final int perStep;

  /// The steps counted by default: whole cycles of what repeats, so where
  /// the warm-up left off doesn't matter.
  final int steps;

  /// Whether the scenario is expected to be still: the app allocates (near)
  /// nothing and writes no frame, which the report asserts (`alloc.dart`
  /// fails when it doesn't).
  final bool quiet;
}

const _phrases = <String>[
  'tool: ran 412 tests ✓ all passed',
  'assistant: the presenter diffs only damaged spans',
  'user: проверь прокрутку и ширину эмодзи 🧪',
  'tool: compiled 87 files · 你好 · 0 warnings',
  'assistant: hardware scroll moved the log by one row',
  'tool: grapheme clusters 👨‍👩‍👧 and flags 🇺🇦 are one cell each',
];

/// Up and down by a row: 0 … 200 … 0.
int _bounce(int i) {
  final k = i % 400;
  return k <= 200 ? k : 400 - k;
}

final appScenarios = <AppScenario>[
  AppScenario('app-idle', 'a still app: the clock moves, nothing changes', (
    w,
    h,
  ) async {
    final r = await AppRun.start(
      Column(children: [for (var y = 0; y < h; y++) Text(_phrases[y % 6])]),
      width: w,
      height: h,
    );
    return (r, (int _) => r.pump());
  }),
  AppScenario(
    'app-spinner',
    'a chat screen whose only motion is a Spinner ticking',
    (w, h) async {
      final r = await AppRun.start(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(children: [Text(' twk · bench  '), Spinner()]),
            Expanded(
              child: ListView.builder(
                itemCount: 1000,
                itemBuilder: (_, i) => Text('${_phrases[i % 6]} #$i'),
              ),
            ),
            const Text('> explain the diff'),
          ],
        ),
        width: w,
        height: h,
      );
      return (r, (int _) => r.pump());
    },
  ),
  AppScenario(
    'listview-scroll',
    'a ListView.builder of 100k items of 1 to 3 rows scrolled a row a frame',
    (w, h) async {
      final c = ScrollController();
      final r = await AppRun.start(
        ListView.builder(
          itemCount: 100000,
          controller: c,
          itemBuilder: (_, i) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = 0; k <= i % 3; k++)
                Text('${_phrases[(i + k) % 6]} #$i'),
            ],
          ),
        ),
        width: w,
        height: h,
      );
      return (
        r,
        (int i) {
          c.jumpTo(_bounce(i));
          return r.pump();
        },
      );
    },
    steps: 400,
  ),
  _table100k(
    'table-100k',
    'a Table.source of 100k rows × 4 columns, Down/Up moving the selection',
    null,
  ),
  _table100k(
    'table-100k-ascii',
    'a Table.source of 100k rows × 4 columns, Down/Up moving the selection',
    Glyphs.ascii,
  ),
  AppScenario(
    'textarea-10k',
    'a character typed (then deleted) mid-document in a TextArea of 10k lines',
    (w, h) async {
      final text = [
        for (var i = 0; i < 10000; i++) 'line $i: ${_phrases[i % 6]}',
      ].join('\n');
      final c = TextEditingController(text: text)
        ..selection = TextSelection.collapsed(offset: text.length ~/ 2);
      final r = await AppRun.start(
        TextArea(controller: c, autofocus: true, minLines: h, maxLines: h),
        width: w,
        height: h,
      );
      return (
        r,
        (int i) {
          // 16 typed, 16 deleted
          r.input(i % 32 < 16 ? const [0x78] : keyBackspace);
          return r.pump();
        },
      );
    },
    steps: 320,
  ),
  AppScenario(
    'field-in-dialog',
    'a character typed (then deleted) in a TextField of a dialog over a page '
        'of text',
    (w, h) async {
      final c = TextEditingController(text: 'notes.md');
      final r = await AppRun.start(
        Stack(
          children: [
            Column(
              children: [for (var y = 0; y < h; y++) Text(_phrases[y % 6])],
            ),
            Center(
              child: SizedBox(
                width: 40,
                child: Box(
                  style: const Style(bg: Color.rgb(0x22, 0x25, 0x2c)),
                  border: const Border.all(),
                  padding: const EdgeInsets.x(1),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Rename'),
                      TextField(controller: c, autofocus: true),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        width: w,
        height: h,
      );
      return (
        r,
        (int i) {
          // 16 typed, 16 deleted
          r.input(i % 32 < 16 ? const [0x78] : keyBackspace);
          return r.pump();
        },
      );
    },
    steps: 320,
  ),
  _gaugesLive(
    'gauges-live',
    'eight LineGauges beside their labels moving a step a frame, under a '
        'page of text',
    null,
  ),
  _gaugesLive(
    'gauges-live-ascii',
    'eight LineGauges beside their labels moving a step a frame, under a '
        'page of text',
    Glyphs.ascii,
  ),
  _markdownStream(
    'markdown-stream',
    'an answer streaming into a MarkdownView, 6 characters a frame, '
        'the whole of 8000 counted',
    null,
  ),
  _markdownStream(
    'markdown-stream-ascii',
    'an answer streaming into a MarkdownView, 6 characters a frame, '
        'the whole of 8000 counted',
    Glyphs.ascii,
  ),
  AppScenario(
    'log-append',
    'a LogView at its cap of 2000 lines following its end, a line added '
        'a frame: the oldest goes as it comes',
    (w, h) async {
      // at the cap from the start, as a log that has run a while is: the
      // same in every frame, however long the warm-up
      final log = LogController(maxLines: 2000);
      // one time for all: the lines are the same in every run
      final time = DateTime(2026, 10, 30, 12);
      for (var k = 0; k < 2000; k++) {
        log.add(_phrases[k % _phrases.length], time: time);
      }
      final r = await AppRun.start(
        LogView(controller: log),
        width: w,
        height: h,
      );
      return (
        r,
        (int i) {
          log.add(_phrases[i % _phrases.length], time: time);
          return r.pump();
        },
      );
    },
  ),
  AppScenario(
    'selection-list',
    'a SelectionList of 1000 items, Down/Up moving the cursor',
    (w, h) async {
      final r = await AppRun.start(
        SelectionList<int>(
          itemCount: 1000,
          keyOf: (i) => i,
          itemBuilder: (_, i) => Text(_phrases[i % _phrases.length]),
          autofocus: true,
        ),
        width: w,
        height: h,
      );
      return (
        r,
        (int i) {
          // down for 200 frames, past the bottom of the window, then up
          r.input(i % 400 < 200 ? keyDown : keyUp);
          return r.pump();
        },
      );
    },
    steps: 400,
  ),
  for (final mode in HandPointer.values) _handScenario(mode),
  const AppScenario(
    'chips-narrow',
    'Chip, ChipList, ValueStepper, SegmentedButton and Breadcrumbs with long '
        'labels in 28 columns, their state changing a frame: every label '
        'cut to fit again',
    _chipsNarrow,
    steps: 400,
  ),
  const AppScenario(
    'hidden-tab',
    'a page of text, and in a hidden tab (Offstage, TickerMode off) three '
        'Spinners, an indeterminate ProgressBar and a TaskList with running '
        'tasks showing their time: nothing may move',
    _hiddenTab,
    quiet: true,
  ),
  const AppScenario(
    'log-follow',
    'a LogView at its cap of 2000 lines following a file, a line appended a '
        'step; the file I/O is counted (see the scenario)',
    _logFollow,
    steps: 200,
  ),
  AppScenario(
    'mouse-flood',
    '100 mouse motions a frame over a screen of hover-lit cells, 8 a row',
    (w, h) async {
      final r = await AppRun.start(
        Column(
          children: [
            for (var y = 0; y < h; y++)
              Row(
                children: [
                  for (var x = 0; x < 8; x++) Expanded(child: _Hover(x, y)),
                ],
              ),
          ],
        ),
        width: w,
        height: h,
      );
      return (
        r,
        (int i) {
          for (var k = 0; k < 100; k++) {
            r.input(mouseMotion((i * 7 + k * 13) % w, (i * 3 + k * 5) % h));
          }
          return r.pump();
        },
      );
    },
    unit: 'event',
    perStep: 100,
  ),
];

/// [child] under the theme with [glyphs] (the dark theme otherwise as it is);
/// as it is for null.
Widget _themed(Glyphs? glyphs, Widget child) => glyphs == null
    ? child
    : Theme(
        data: ThemeData.dark.copyWith(glyphs: glyphs),
        child: child,
      );

AppScenario _table100k(String name, String about, Glyphs? glyphs) =>
    AppScenario(
      name,
      glyphs == null ? about : '$about, under Glyphs.ascii',
      (w, h) async {
        final r = await AppRun.start(
          _themed(
            glyphs,
            Table<_Row>.source(
              source: _Rows(100000),
              autofocus: true,
              columns: [
                TableColumn(
                  title: '#',
                  cell: (row) => TableCell('${row.index}'),
                  width: const GridTrack.fixed(7),
                  align: TextAlign.right,
                ),
                TableColumn(
                  title: 'Name',
                  cell: (row) => TableCell(row.name),
                  width: const GridTrack.fr(2),
                ),
                TableColumn(
                  title: 'Size',
                  cell: (row) => TableCell('${row.size}'),
                  width: const GridTrack.fixed(8),
                  align: TextAlign.right,
                ),
                TableColumn(
                  title: 'Kind',
                  cell: (row) => TableCell(row.kind),
                  width: const GridTrack.fr(1),
                ),
              ],
            ),
          ),
          width: w,
          height: h,
        );
        return (
          r,
          (int i) {
            // down for 200 frames, past the bottom of the window, then up
            r.input(i % 400 < 200 ? keyDown : keyUp);
            return r.pump();
          },
        );
      },
      steps: 400,
    );

AppScenario _gaugesLive(String name, String about, Glyphs? glyphs) =>
    AppScenario(
      name,
      glyphs == null ? about : '$about, under Glyphs.ascii',
      (w, h) async {
        final ratio = ValueNotifier<double>(0);
        final r = await AppRun.start(
          _themed(
            glyphs,
            Column(
              children: [
                for (var y = 0; y < h - 8; y++) Text(_phrases[y % 6]),
                for (var g = 0; g < 8; g++)
                  Row(
                    children: [
                      Text('cpu $g '),
                      Expanded(
                        child: ValueListenableBuilder<double>(
                          valueListenable: ratio,
                          builder: (_, v, _) => LineGauge(
                            ratio: (v + g / 8) % 1,
                            label: '',
                            segmented: true,
                            filledStyle: const Style(fg: Color.green),
                            unfilledStyle: const Style(fg: Color.white),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          width: w,
          height: h,
        );
        return (
          r,
          (int i) {
            // in the app's clock, as an input would be
            r.clock.run(() => ratio.value = i % 100 / 100);
            return r.pump();
          },
        );
      },
      steps: 400,
    );

AppScenario _markdownStream(String name, String about, Glyphs? glyphs) =>
    AppScenario(
      name,
      glyphs == null ? about : '$about, under Glyphs.ascii',
      (w, h) async {
        final doc = _answer();
        final state = _Stream();
        final r = await AppRun.start(
          _themed(
            glyphs,
            ListenableBuilder(
              listenable: state,
              builder: (_, _) => SingleChildScrollView(
                child: MarkdownView.blocks(
                  state.md.blocks,
                  definitions: state.md.definitions,
                ),
              ),
            ),
          ),
          width: w,
          height: h,
        );
        return (
          r,
          (int i) {
            // piece i of the answer, from the start again after the last
            final at = (i - 1) % _pieces * 6;
            if (at == 0) {
              state.md = MarkdownStream();
            }
            state.add(doc.substring(at, at + 6));
            return r.pump();
          },
        );
      },
      steps: _pieces,
    );

/// 20 mouse motions a frame over a screen of Buttons, a TabBar and a sortable
/// Table, under the theme with [ThemeData.handPointer] as [mode].
///
/// The rule it measures: every tap target is a MouseRegion that shows the
/// hand where the mode says (`off` none, `auto` where motion is reported
/// already, `on` everywhere, which has the terminal report all motion).
/// The runs differ in the shapes the terminal is told and what the regions
/// do as the pointer crosses them.
AppScenario _handScenario(HandPointer mode) => AppScenario(
  'hand-${mode.name}',
  '20 mouse motions a frame over 3 rows of Buttons, a TabBar and a sortable '
      'Table, under ThemeData.handPointer ${mode.name}',
  (w, h) async {
    final tabs = TabController(length: 4);
    final table = TableController(sortColumn: 0);
    final r = await AppRun.start(
      Theme(
        data: ThemeData.dark.copyWith(handPointer: mode),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var row = 0; row < 3; row++)
              Row(
                children: [
                  for (var b = 0; b < 8; b++)
                    Button('button $row.$b', onPressed: () {}),
                ],
              ),
            TabBar(
              controller: tabs,
              tabs: const ['Files', 'Search', 'Git', 'Settings'],
            ),
            Expanded(
              child: Table<_Row>(
                rows: [for (var i = 0; i < 200; i++) _Rows(200).rowAt(i)],
                controller: table,
                columns: [
                  TableColumn(
                    title: '#',
                    cell: (row) => TableCell('${row.index}'),
                    width: const GridTrack.fixed(7),
                    align: TextAlign.right,
                    compare: (a, b) => a.index.compareTo(b.index),
                  ),
                  TableColumn(
                    title: 'Name',
                    cell: (row) => TableCell(row.name),
                    width: const GridTrack.fr(2),
                    compare: (a, b) => a.name.compareTo(b.name),
                  ),
                  TableColumn(
                    title: 'Size',
                    cell: (row) => TableCell('${row.size}'),
                    width: const GridTrack.fixed(8),
                    align: TextAlign.right,
                    compare: (a, b) => a.size.compareTo(b.size),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      width: w,
      height: h,
      pointerShapes: true,
    );
    return (
      r,
      (int i) {
        for (var k = 0; k < 20; k++) {
          r.input(mouseMotion((i * 7 + k * 13) % w, (i * 3 + k * 5) % h));
        }
        return r.pump();
      },
    );
  },
  unit: 'event',
  perStep: 20,
  steps: 400,
);

/// Widgets with labels longer than the room they have, changing every
/// frame.
Future<(AppRun, FutureOr<void> Function(int))> _chipsNarrow(
  int w,
  int h,
) async {
  const labels = [
    'a long label that does not fit',
    'another label, longer than the room',
    'Ünïcödé и 中文 labels that are cut',
    'short',
  ];
  final choices = [
    for (var i = 0; i < 12; i++) Choice(i, '${labels[i % 4]} #$i'),
  ];
  final n = ValueNotifier<int>(0);
  final r = await AppRun.start(
    ValueListenableBuilder<int>(
      valueListenable: n,
      builder: (_, i, _) => SizedBox(
        width: 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var k = 0; k < 4; k++)
              Chip('${labels[(i + k) % 4]} #$i', selected: k == i % 4),
            ChipList<int>(
              chips: choices,
              selected: {i % 12, (i + 5) % 12},
              onSelectionChanged: (_) {},
              onDeleted: (_) {},
            ),
            ValueStepper<int>(
              values: choices,
              value: i % 12,
              onChanged: (_) {},
            ),
            SegmentedButton<int>(
              segments: choices.take(3).toList(),
              selected: {i % 3},
              onSelectionChanged: (_) {},
            ),
            Breadcrumbs(
              items: [
                for (var k = 0; k < 6; k++) 'folder with a long name $k',
              ],
              current: i % 6,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    ),
    width: w,
    height: h,
  );
  return (
    r,
    (int i) {
      r.clock.run(() => n.value = i);
      r.pump();
    },
  );
}

/// A visible page of text beside a hidden tab of everything that ticks.
Future<(AppRun, FutureOr<void> Function(int))> _hiddenTab(int w, int h) async {
  final r = await AppRun.start(
    Column(
      children: [
        for (var y = 0; y < h - 12; y++) Text(_phrases[y % 6]),
        const Offstage(
          child: TickerMode(
            enabled: false,
            child: Column(
              children: [
                Row(children: [Spinner(), Spinner(), Spinner()]),
                ProgressBar(),
                TaskList(
                  tasks: [
                    TaskItem('compile', status: TaskStatus.running),
                    TaskItem(
                      'test',
                      status: TaskStatus.running,
                      children: [
                        TaskItem('core', status: TaskStatus.running),
                        TaskItem('widgets', status: TaskStatus.running),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    width: w,
    height: h,
  );
  return (r, (int _) => r.pump());
}

/// A LogView following a file that a line is appended to a step.
///
/// What is counted: the app's frame and, with it, everything `followFile`
/// does to get the line: the directory watch's event, the file's length and
/// its read (`dart:io`'s futures and buffers), the decoding and the line
/// added. Not the tool's: the line is written by one `writeFromSync` of
/// bytes encoded in advance on a file kept open (a system call and no
/// object of the program's), and the step waits for the line in the real
/// event loop (a `Future.delayed(Duration.zero)` a turn, which counts
/// as its own timer and closure a turn: the µs column is that wait, so the
/// time means nothing here). The follower is started in the app's clock's zone,
/// so what it schedules runs when the step turns the clock.
Future<(AppRun, FutureOr<void> Function(int))> _logFollow(int w, int h) async {
  final dir = Directory.systemTemp.createTempSync('twk_alloc_follow');
  final file = File('${dir.path}/app.log')..writeAsStringSync('');
  final log = LogController(maxLines: 2000);
  final time = DateTime(2026, 10, 30, 12);
  for (var k = 0; k < 2000; k++) {
    log.add(_phrases[k % _phrases.length], time: time);
  }
  final r = await AppRun.start(
    LogView(controller: log),
    width: w,
    height: h,
  );
  final lines = [
    for (final p in _phrases) utf8.encode('$p\n'),
  ];
  final out = file.openSync(mode: FileMode.append);
  late final Future<void> Function() stopFollow;
  r.clock.run(() => stopFollow = log.followFile(file.path).cancel);
  r.onStop.add(() async {
    await stopFollow();
    log.dispose();
    out.closeSync();
    dir.deleteSync(recursive: true);
  });
  // told by the log each time lines come in, whatever its length at the cap
  var arrived = 0;
  log.addListener(() => arrived++);
  var seen = 0;
  Future<void> step(int i) async {
    out.writeFromSync(lines[i % lines.length]);
    seen++;
    // the line comes through the watch or the poll: turns of the real
    // event loop, and of the clock for what the follower scheduled
    for (var turn = 0; arrived < seen; turn++) {
      if (turn > 5000) {
        throw StateError('the followed line did not arrive');
      }
      await Future<void>.delayed(Duration.zero);
      r.clock.elapse(Duration.zero);
    }
    r.pump();
  }

  return (r, step);
}

typedef _Row = ({int index, String name, int size, String kind});

final class _Rows extends TableSource<_Row> {
  _Rows(this.rowCount);

  @override
  final int rowCount;

  @override
  _Row rowAt(int index) => (
    index: index,
    name: 'file_$index.${index.isEven ? 'dart' : 'md'}',
    size: index * 37 % 100000,
    kind: index % 3 == 0 ? 'text' : 'source',
  );
}

final class _Stream extends ChangeNotifier {
  var md = MarkdownStream();

  void add(String piece) {
    md.add(piece);
    notifyListeners();
  }
}

/// The pieces of 6 characters of [_answer]'s first 8000.
const int _pieces = 8000 ~/ 6;

/// About 8 KB of an agent's answer: headings, paragraphs, lists, code, a
/// table.
String _answer() {
  const part = '''
## Where the frame goes

The presenter compares every row with what the terminal shows and writes
only the cells that changed since the last frame. A **hardware scroll** moves
the log by a row when *most* of it moved, and `ICH`/`DCH` shift a line.

- the canvas packs a cell in 32 bits
- styles are interned in a table of their own
- grapheme clusters 👨‍👩‍👧 and flags 🇺🇦 are one cell each
  - nested: CJK 你好 takes two cells

```dart
final bytes = presenter.present(surface);
terminal.write(bytes);
```

| scenario | bytes | µs |
|----------|------:|---:|
| idle     |     0 |  3 |
| spinner  |    40 | 12 |

1. first the layout
2. then the paint, of the dirty boundaries only
3. then the diff

''';
  final b = StringBuffer();
  while (b.length < 8000) {
    b.write(part);
  }
  return b.toString();
}

/// A cell lit while the mouse is over it.
final class _Hover extends StatefulWidget {
  const _Hover(this.x, this.y);
  final int x;
  final int y;

  @override
  State<_Hover> createState() => _HoverState();
}

final class _HoverState extends State<_Hover> {
  var _on = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _on = true),
    onExit: (_) => setState(() => _on = false),
    child: Text(
      'r${widget.y} c${widget.x}',
      style: _on ? const Style(bg: Color.rgb(60, 60, 90)) : const Style(),
    ),
  );
}
