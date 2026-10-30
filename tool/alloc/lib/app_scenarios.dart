/// Apps of package:twk and twk_rich as users run them: what a frame of each
/// costs when the app does what it is for.
library;

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
  });
  final String name;
  final String about;
  final Future<(AppRun, void Function(int i))> Function(int w, int h) start;
  final String unit;
  final int perStep;

  /// The steps counted by default: whole cycles of what repeats, so where
  /// the warm-up left off doesn't matter.
  final int steps;
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
  AppScenario(
    'table-100k',
    'a Table.source of 100k rows × 4 columns, Down/Up moving the selection',
    (w, h) async {
      final r = await AppRun.start(
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
  AppScenario(
    'gauges-live',
    'eight LineGauges beside their labels moving a step a frame, under a '
        'page of text',
    (w, h) async {
      final ratio = ValueNotifier<double>(0);
      final r = await AppRun.start(
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
  ),
  AppScenario(
    'markdown-stream',
    'an answer streaming into a MarkdownView, 6 characters a frame, '
        'the whole of 8000 counted',
    (w, h) async {
      final doc = _answer();
      final state = _Stream();
      final r = await AppRun.start(
        ListenableBuilder(
          listenable: state,
          builder: (_, _) => SingleChildScrollView(
            child: MarkdownView.blocks(
              state.md.blocks,
              definitions: state.md.definitions,
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
  ),
  AppScenario(
    'log-append',
    'a LogView following its end, a line added a frame, 1000 before',
    (w, h) async {
      final log = LogController();
      for (var k = 0; k < 1000; k++) {
        log.add(_phrases[k % _phrases.length]);
      }
      final r = await AppRun.start(
        LogView(controller: log),
        width: w,
        height: h,
      );
      return (
        r,
        (int i) {
          log.add(_phrases[i % _phrases.length]);
          return r.pump();
        },
      );
    },
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
