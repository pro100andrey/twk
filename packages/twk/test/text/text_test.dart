// Text and Text.rich: their spans in styles merged onto the default text
// style, drawn by a paragraph with the settings they pass down, the same
// render object updated, and nothing laid out or painted again for a
// rebuild that changes nothing.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show RenderParagraph, Screen;
import 'package:twk_test/twk_test.dart' show Shot, Vt;

import '../layout/view.dart' show Toggle, toggleIn;

const red = Color.rgb(200, 0, 0);
const green = Color.rgb(0, 200, 0);
const blue = Color.rgb(0, 0, 200);

void main() {
  group('Text', () {
    test('draws its string in its style', () {
      final v = Shot(
        const Text(
          'hi',
          style: Style(fg: red, attrs: Attr.bold),
        ),
        4,
        1,
      );
      expect(v.rows, ['hi']);
      expect(v.cells(0, 3), [
        ('h', red.value, 0, Attr.bold),
        ('i', red.value, 0, Attr.bold),
        (' ', 0, 0, 0),
      ]);
    });

    test("rich, draws each span in its style merged onto the Text's", () {
      final v = Shot(
        Text.rich(
          [
            'a'.fg(blue),
            'b'.italic,
            const Span('c', Style(attrsOff: Attr.bold)),
          ],
          style: const Style(fg: red, bg: green, attrs: Attr.bold),
        ),
        4,
        1,
      );
      expect(v.cells(0, 4), [
        ('a', blue.value, green.value, Attr.bold),
        ('b', red.value, green.value, Attr.bold | Attr.italic),
        ('c', red.value, green.value, 0),
        (' ', 0, 0, 0),
      ]);
    });

    test('passes how to break, cut off and align its lines down', () {
      final v = Shot(
        const Text(
          'the quick brown fox jumps',
          wrap: TextWrap.grapheme,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          align: TextAlign.right,
        ),
        10,
        3,
      );
      final paragraph = v.top as RenderParagraph;
      expect(
        [
          paragraph.wrap,
          paragraph.overflow,
          paragraph.maxLines,
          paragraph.align,
        ],
        [TextWrap.grapheme, TextOverflow.ellipsis, 2, TextAlign.right],
      );
      expect(v.rows, ['the quick', 'brown fox…', '']);

      final w = Shot(
        const Text(
          'the quick brown fox jumps',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          align: TextAlign.right,
        ),
        10,
        3,
      );
      expect(w.rows, [' the quick', 'brown fox…', '']);

      final x = Shot(
        const Text(
          'abcdefgh',
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
        ),
        3,
        2,
      );
      expect(x.rows, ['ab…', '']);
    });

    test('new settings change the same render object', () {
      final v = Shot(const Text('ab cd'), 6, 2);
      final paragraph = v.top as RenderParagraph;
      expect(paragraph.spans, [('ab cd', const Pen())]);
      v.pump(
        Text.rich(
          ['ab'.fg(red), '+cd'.bold],
          style: const Style(bg: blue),
          wrap: TextWrap.none,
          maxLines: 1,
          overflow: TextOverflow.ellipsisStart,
          align: TextAlign.center,
        ),
      );
      expect(v.top, same(paragraph));
      expect(paragraph.spans, [
        ('ab', const Pen(fg: red, bg: blue)),
        ('+cd', const Pen(bg: blue, attrs: Attr.bold)),
      ]);
      expect(
        [
          paragraph.wrap,
          paragraph.overflow,
          paragraph.maxLines,
          paragraph.align,
        ],
        [TextWrap.none, TextOverflow.ellipsisStart, 1, TextAlign.center],
      );
      expect(v.rows, ['ab+cd', '']);
      expect(v.cells(0, 5), [
        ('a', red.value, blue.value, 0),
        ('b', red.value, blue.value, 0),
        ('+', 0, blue.value, Attr.bold),
        ('c', 0, blue.value, Attr.bold),
        ('d', 0, blue.value, Attr.bold),
      ]);
      v.pump(const Text('xyz'));
      expect(v.top, same(paragraph));
      expect(v.rows, ['xyz', '']);
      expect(v.cells(0, 1), [('x', 0, 0, 0)]);
    });

    test('rebuilt the same asks for neither a layout nor a paint', () {
      // new instances on each build
      Style red(int r) => Style(fg: Color.rgb(r, 0, 0));
      Widget text() => DefaultTextStyle(
        style: red(100),
        child: Text.rich(
          [Span('a${'b' * 2}', red(200)), 'c'.bold],
          style: red(150),
          maxLines: 2,
        ),
      );
      final v = Shot(Toggle(text, text), 6, 2);
      toggleIn(v.root).toggle();
      v.owner.buildScope();
      expect(v.pipeline.hasWork, isFalse);
    });

    test('a new style repaints it, new text lays it out again', () {
      final v = Shot(const _Counted(Text('ab', style: Style(fg: red))), 6, 1);
      final counted = v.top as _RenderCounted;
      expect(counted.layouts, 1);
      v.pump(const _Counted(Text('ab', style: Style(fg: blue))));
      expect(counted.layouts, 1);
      expect(v.cells(0, 2), [
        ('a', blue.value, 0, 0),
        ('b', blue.value, 0, 0),
      ]);
      v.pump(const _Counted(Text('abc', style: Style(fg: blue))));
      expect(counted.layouts, 2);
      expect(v.rows, ['abc']);
    });

    test('painted with another style table, takes its pens from it', () {
      final v = Shot(Text.rich(['a'.fg(red), 'b'.bg(blue).underline]), 4, 1);
      final other = Screen(4, 1);
      // the pens of the first table have other ids in this one
      other.styles
        ..pen(const Pen(fg: green))
        ..pen(const Pen(bg: green))
        ..pen(const Pen(attrs: Attr.strike));
      final vt = Vt(4, 1);
      v.pipeline
        ..markAllDirty()
        ..flushPaint(
          PaintContext(other.canvas, other.surface, other.presenter),
        );
      vt.feed(other.render()!);
      expect(
        [
          for (var x = 0; x < 2; x++)
            (
              vt.cell(x, 0).text,
              vt.cell(x, 0).fg,
              vt.cell(x, 0).bg,
              vt.cell(x, 0).attrs,
            ),
        ],
        [('a', red.value, 0, 0), ('b', 0, blue.value, Attr.underline)],
      );
    });
  });

  group('DefaultTextStyle', () {
    test('is the style under that of each Text below it', () {
      final v = Shot(
        DefaultTextStyle(
          style: const Style(fg: red, bg: blue),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('a'),
              const Text('b', style: Style(fg: green)),
              Text.rich(['c'.bold, 'd'.bg(green)]),
            ],
          ),
        ),
        4,
        3,
      );
      expect(v.rows, ['a', 'b', 'cd']);
      expect(
        [v.cells(0, 1), v.cells(1, 1), v.cells(2, 2)],
        [
          [('a', red.value, blue.value, 0)],
          [('b', green.value, blue.value, 0)],
          [
            ('c', red.value, blue.value, Attr.bold),
            ('d', red.value, green.value, 0),
          ],
        ],
      );
    });

    test('merges onto the one above it', () {
      final v = Shot(
        const DefaultTextStyle(
          style: Style(fg: red, attrs: Attr.bold | Attr.italic),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle(
                style: Style(bg: blue, attrsOff: Attr.bold),
                child: Text('a'),
              ),
              Text('b'),
            ],
          ),
        ),
        4,
        2,
      );
      expect(
        [v.cells(0, 1), v.cells(1, 1)],
        [
          [('a', red.value, blue.value, Attr.italic)],
          [('b', red.value, 0, Attr.bold | Attr.italic)],
        ],
      );
    });

    test('a new one repaints the Texts below it in its style', () {
      final v = Shot(
        Toggle(
          () => const DefaultTextStyle(
            style: Style(fg: red),
            child: Text('a'),
          ),
          () => const DefaultTextStyle(
            style: Style(fg: blue),
            child: Text('a'),
          ),
        ),
        4,
        1,
      );
      expect(v.cells(0, 1), [('a', red.value, 0, 0)]);
      toggleIn(v.root).toggle();
      v.frame();
      expect(v.cells(0, 1), [('a', blue.value, 0, 0)]);
    });

    test('of a context with none above it is an empty style', () {
      Style? found;
      Shot(_Probe((context) => found = DefaultTextStyle.of(context)), 1, 1);
      expect(found, const Style());
    });
  });
}

/// Lays its child out within loose constraints, so that a new size of the
/// child lays it out again; counts its layouts.
final class _Counted extends SingleChildRenderObjectWidget {
  const _Counted(Widget child) : super(child: child);

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderCounted createRenderObject(BuildContext context) => _RenderCounted();
}

final class _RenderCounted extends RenderObject
    with RenderObjectWithChildMixin {
  var layouts = 0;

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    child!.layout(BoxConstraints(0, c.maxW, 0, c.maxH), parentUsesSize: true);
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) => paintChild(ctx, child!);
}

/// Calls [probe] with its context when it is built; shows a blank.
final class _Probe extends StatelessWidget {
  const _Probe(this.probe);

  final void Function(BuildContext context) probe;

  @override
  Widget build(BuildContext context) {
    probe(context);
    return const Text('');
  }
}

extension on Shot {
  /// Glyph, text color, background and attributes of the first [count]
  /// cells of row [y], as the emulator keeps them.
  List<(String, int, int, int)> cells(int y, int count) => [
    for (var x = 0; x < count; x++)
      if (vt.cell(x, y) case final c) (c.text, c.fg, c.bg, c.attrs),
  ];
}
