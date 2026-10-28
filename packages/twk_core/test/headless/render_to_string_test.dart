// A render tree laid out and painted once, read back as text or as the
// bytes a terminal would get.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

/// Paints [lines] from the top left corner, each with its pen.
final class Lines extends RenderObject {
  Lines(this.lines);
  final List<(String, int)> lines;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    for (var y = 0; y < lines.length; y++) {
      ctx.canvas.text(0, y, lines[y].$1, lines[y].$2);
    }
  }
}

void main() {
  late StyleTable styles;
  late int plain;
  setUp(() {
    styles = StyleTable();
    plain = styles.pen(const Pen());
  });

  test('gives one line per row, without the blanks after the text', () {
    final root = Lines([('one', plain), ('', plain), ('  two', plain)]);
    expect(renderToString(root, 8, 4, styles: styles), 'one\n\n  two\n');
  });

  test('gives a wide glyph once for its two cells', () {
    final root = Lines([
      ('中文ok', plain),
      ('a👩‍💻b', plain),
      ('e\u0301', plain),
    ]);
    expect(
      renderToString(root, 8, 3, styles: styles),
      '中文ok\na👩‍💻b\ne\u0301',
    );
  });

  test('cuts a row at the width', () {
    final root = Lines([('abcdef', plain), ('ab中文', plain)]);
    expect(renderToString(root, 3, 2, styles: styles), 'abc\nab');
  });

  test('lays the tree out at the size given', () {
    final root = RenderBox(
      pen: styles.pen(const Pen(bg: Color.rgb(0, 0, 80))),
      padX: 1,
      padY: 1,
      child: RenderText('hi', plain),
    );
    expect(renderToString(root, 6, 3, styles: styles), '\n hi\n');
    expect((root.width, root.height), (6, 3));
  });

  test('with ansi, gives the bytes that show the screen with its styles', () {
    final bold = styles.pen(const Pen(attrs: Attr.bold));
    final red = styles.pen(const Pen(fg: Color.rgb(200, 0, 0)));
    final out = renderToString(
      Lines([('a', bold), ('中b', red)]),
      4,
      2,
      styles: styles,
      ansi: true,
    );
    final vt = Vt(4, 2)..feed(utf8.encode(out));
    expect(vt.errors, isEmpty);
    expect(
      [
        for (final (x, y) in [(0, 0), (1, 0), (0, 1), (2, 1)])
          (vt.cell(x, y).text, vt.cell(x, y).fg, vt.cell(x, y).attrs),
      ],
      [
        ('a', 0, Attr.bold),
        (' ', 0, 0),
        ('中', const Color.rgb(200, 0, 0).value, 0),
        ('b', const Color.rgb(200, 0, 0).value, 0),
      ],
    );
  });

  test('paints a tree painted before in full', () {
    final log = RenderLog(
      pen: styles.pen(const Pen(bg: Color.rgb(0, 0, 0))),
      itemPen: (_, _) => plain,
    )..add('kept');
    expect(renderToString(log, 6, 2, styles: styles), ' kept\n');
    expect(renderToString(log, 6, 2, styles: styles), ' kept\n');
  });

  test('leaves the tree detached', () {
    final text = RenderText('hi', plain);
    renderToString(
      RenderBox(pen: plain, child: text),
      4,
      1,
      styles: styles,
    );
    expect(text.owner, isNull);
  });

  test("the tree's own warnings go to onLog: an overflow, in debug", () {
    final records = <LogRecord>[];
    final column = RenderFlex(
      direction: Axis.vertical,
      children: [
        for (final t in ['a', 'b', 'c']) RenderText(t, plain),
      ],
    );
    expect(
      renderToString(column, 4, 2, styles: styles, onLog: records.add),
      'a\nb',
    );
    var asserts = false;
    assert(asserts = true, 'only in debug');
    expect(records, hasLength(asserts ? 1 : 0));
    if (asserts) {
      expect(records.single.level, LogLevel.warning);
      expect(records.single.message, contains('overflowed by 1 row'));
    }
  });
}
