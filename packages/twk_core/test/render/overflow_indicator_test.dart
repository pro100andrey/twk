// A flex, a wrap or a grid whose children need more room than it has marks
// the edge they are cut off at, in debug mode, and says so in the log once
// for each time the overflow starts; a box that clips on purpose does
// neither.
import 'package:test/test.dart';
import 'package:twk_core/terminal.dart' show LogLevel, LogRecord;
import 'package:twk_core/twk_core.dart';

/// A render tree filling a whole screen.
final class View {
  View(this.width, this.height) : screen = Screen(width, height) {
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
      ..onLog = records.add;
  }

  final int width;
  final int height;
  final Screen screen;
  late final PipelineOwner owner;
  final records = <LogRecord>[];

  void frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    screen.render();
  }

  List<String> rows() => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
      ].join().trimRight(),
  ];

  List<String> show(RenderObject root) {
    owner.root = root;
    frame();
    return rows();
  }

  /// The colors of the cell at [x], [y].
  (Color, Color) colorsAt(int x, int y) {
    final style = StyleId(screen.surface.styles[y * width + x]);
    return (screen.styles.fgOf(style), screen.styles.bgOf(style));
  }
}

final class Label extends RenderObject {
  Label(String text) : _text = text;

  String _text;

  void set(String value) {
    _text = value;
    markNeedsLayout();
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainWidth(_text.length);
    height = c.constrainHeight(1);
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.text(0, 0, _text, ctx.canvas.styles.pen(const Pen()));
}

/// A label that is a repaint boundary, repainted on its own.
final class Boundary extends Label {
  Boundary(super.text);

  @override
  bool get isRepaintBoundary => true;

  void repaintWith(String value) {
    _text = value;
    markNeedsPaint();
  }
}

RenderObject cell(RenderObject child, int row, int column) =>
    child
      ..parentData = (GridParentData()
        ..row = row
        ..column = column);

RenderFlex row(List<RenderObject> children) => RenderFlex(children: children);

RenderFlex column(List<RenderObject> children) => RenderFlex(
  direction: Axis.vertical,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

void main() {
  PipelineOwner.debugOverflowIndicatorByDefault = true;

  group('a row', () {
    test('marks its right edge: hatches, and the cells cut off', () {
      final v = View(6, 2);
      expect(v.show(row([Label('abcd'), Label('efgh')])), [
        'abcd+2',
        '     ▚',
      ]);
      expect(v.colorsAt(5, 1), (Color.yellow, Color.black));
      expect(v.colorsAt(5, 0), (Color.black, Color.yellow));
    });

    test('logs the overflow once, with a report', () {
      final v = View(6, 2)
        ..show(row([Label('abcd'), Label('efgh')]))
        ..frame();
      expect(v.records, hasLength(1));
      final record = v.records.single;
      expect(record.level, LogLevel.warning);
      expect(
        record.message,
        'A RenderFlex overflowed by 2 columns on the right.',
      );
      expect(record.error, isA<OverflowReport>());
      final report = record.error! as OverflowReport;
      expect((report.right, report.bottom), (2, 0));
    });

    test('shows no marker where it fits', () {
      final v = View(6, 2);
      expect(v.show(row([Label('abc'), Label('def')])), ['abcdef', '']);
      expect(v.records, isEmpty);
    });

    test('keeps the marker when a boundary over it repaints', () {
      final v = View(6, 2);
      final boundary = Boundary('cdefgh');
      expect(v.show(row([Label('ab'), boundary])), ['abcd+2', '     ▚']);
      boundary.repaintWith('uvwxyz');
      v.frame();
      expect(v.rows(), ['abuv+2', '     ▚']);
    });

    test('follows the overflow as it grows, shrinks and is gone', () {
      final v = View(6, 2);
      final last = Label('efgh');
      v.show(row([Label('abcd'), last]));
      expect(v.rows(), ['abcd+2', '     ▚']);
      last.set('efghij');
      v.frame();
      expect(v.rows(), ['abcd+4', '     ▚']);
      last.set('ef');
      v.frame();
      expect(v.rows(), ['abcdef', '']);
    });
  });

  test('a column marks its bottom edge', () {
    final v = View(6, 2);
    expect(v.show(column([Label('a'), Label('b'), Label('c')])), [
      'a',
      '▚▚▚▚+1',
    ]);
    expect(v.records.single.message, contains('1 row on the bottom'));
  });

  test('a wrap marks the edge its runs are cut off at', () {
    final v = View(5, 1);
    final wrap = RenderWrap(
      spacing: 1,
      children: [Label('ab'), Label('cd'), Label('ef')],
    );
    expect(v.show(wrap), ['▚▚▚+1']);
    expect(v.records.single.message, contains('A RenderWrap overflowed'));
  });

  test('a grid marks the edge its tracks are cut off at', () {
    final v = View(6, 1);
    final grid = RenderGrid(
      columns: const [GridTrack.fixed(4), GridTrack.fixed(4)],
      rows: const [GridTrack.fixed(1)],
      children: [cell(Label('a'), 0, 0), cell(Label('b'), 0, 1)],
    );
    expect(v.show(grid), ['a   +2']);
    expect(v.records.single.message, contains('A RenderGrid overflowed'));
  });

  test('a box that clips on purpose shows no marker and logs nothing', () {
    final v = View(6, 2);
    final flex = row([Label('abcd'), Label('efgh')])..overflowIntended = true;
    expect(v.show(flex), ['abcdef', '']);
    expect(v.records, isEmpty);
    flex.overflowIntended = false;
    v.frame();
    expect(v.rows(), ['abcd+2', '     ▚']);
    expect(v.records, hasLength(1));
  });

  test('the owner turns the markers off; the log keeps the warning', () {
    final v = View(6, 2);
    v.owner.debugOverflowIndicator = false;
    expect(v.show(row([Label('abcd'), Label('efgh')])), ['abcdef', '']);
    expect(v.records, hasLength(1));
    v.owner.debugOverflowIndicator = true;
    v.frame();
    expect(v.rows(), ['abcd+2', '     ▚']);
  });

  test('is warned of again once the overflow was gone', () {
    final v = View(6, 1);
    final last = Label('efgh');
    v.show(row([Label('abcd'), last]));
    expect(v.records, hasLength(1));
    last.set('efghi');
    v.frame();
    expect(v.records, hasLength(1), reason: 'the same overflow, grown');
    last.set('ef');
    v.frame();
    last.set('efgh');
    v.frame();
    expect(v.records, hasLength(2));
  });

  test('a box of no cell shows no marker', () {
    final v = View(6, 2);
    final inner = row([Label('abcd'), Label('efgh')]);
    expect(
      v.show(
        RenderBox(
          pen: v.screen.styles.pen(const Pen()),
          padX: 3,
          padY: 1,
          child: inner,
        ),
      ),
      ['', ''],
    );
  });

  test('TWK_DEBUG=overflow turns the marker on', () {
    PipelineOwner.debugOverflowIndicatorByDefault = false;
    addTearDown(() => PipelineOwner.debugOverflowIndicatorByDefault = true);
    final off = TwkApp(HeadlessTerminal(), environment: const {});
    expect(off.owner.debugOverflowIndicator, isFalse);
    final on = TwkApp(
      HeadlessTerminal(),
      environment: const {'TWK_DEBUG': 'overflow'},
    );
    expect(on.owner.debugOverflowIndicator, isTrue);
  });

  test('an owner for data has the marker off whatever the default is', () {
    expect(PipelineOwner.debugOverflowIndicatorByDefault, isTrue);
    expect(PipelineOwner.forData(() {}).debugOverflowIndicator, isFalse);
    expect(PipelineOwner(() {}).debugOverflowIndicator, isTrue);
  });
}
