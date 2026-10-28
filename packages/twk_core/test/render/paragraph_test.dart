// A paragraph breaks its spans into lines by word, by grapheme or not at
// all, cuts off what doesn't fit with an ellipsis where asked, places each
// line across its width, and asks for the room its text needs. Every frame
// goes through the terminal emulator too, which must show what the screen
// holds.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

const red = Color.rgb(200, 0, 0);
const blue = Color.rgb(0, 0, 200);
const plain = Pen();

/// A screen and a terminal emulator that splits text as the screen does.
final class View {
  View(
    this.width,
    this.height, {
    TextMode mode = TextMode.graphemes,
    int ambiguousWidth = 1,
  }) : screen = Screen(
         width,
         height,
         textMode: mode,
         ambiguousWidth: ambiguousWidth,
       ),
       vt = Vt(
         width,
         height,
         segmenter: TextSegmenter(mode: mode, ambiguousWidth: ambiguousWidth),
       ) {
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter);
  }

  final int width;
  final int height;
  final Screen screen;
  final Vt vt;
  late final PipelineOwner owner;

  /// Lays the tree out, paints it and shows the frame to the emulator;
  /// returns the rows of the screen.
  List<String> frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    final bytes = screen.render();
    if (bytes != null) {
      vt.feed(bytes);
    }
    expect(vt.errors, isEmpty, reason: 'what the emulator rejected');
    final rows = [
      for (var y = 0; y < height; y++)
        [
          for (var x = 0; x < width; x++)
            if ((screen.surface.cells[y * width + x] & kCont) == 0)
              screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
        ].join().trimRight(),
    ];
    expect(
      [for (final r in vt.dump().split('\n')) r.trimRight()],
      rows,
      reason: 'what the terminal shows',
    );
    return rows;
  }

  /// The rows [p] paints when it is exactly as wide as the screen: as many
  /// as it is tall.
  List<String> show(RenderParagraph p) {
    owner.root = RenderFlex(
      direction: Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [p],
    );
    return frame().sublist(0, p.height);
  }

  /// The foreground of the cell at [x], [y].
  Color fgAt(int x, int y) {
    final fg = screen.styles.fgOf(screen.surface.styles[y * width + x]);
    expect(vt.cell(x, y).fg, fg.value, reason: 'the color the terminal shows');
    return fg;
  }
}

/// The rows [text] takes in a paragraph [width] wide.
List<String> lay(
  String text,
  int width, {
  TextWrap wrap = TextWrap.word,
  TextOverflow overflow = TextOverflow.clip,
  int? maxLines,
  TextAlign align = TextAlign.left,
  TextMode mode = TextMode.graphemes,
  int ambiguousWidth = 1,
}) {
  final v = View(width, 12, mode: mode, ambiguousWidth: ambiguousWidth);
  return v.show(
    RenderParagraph(
      [(text, plain)],
      wrap: wrap,
      overflow: overflow,
      maxLines: maxLines,
      align: align,
    ),
  );
}

/// Lays its child out as wide as the child asks to be; counts its layouts
/// and paints.
final class Hug extends RenderObject with RenderObjectWithChildMixin {
  Hug(RenderObject child) {
    this.child = child;
  }

  var layouts = 0;
  var paints = 0;

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = c.maxW;
    height = c.maxH;
    final w = child!.getMaxIntrinsicWidth(height);
    child!.layout(BoxConstraints.tight(w < width ? w : width, height));
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    paintChild(ctx, child!);
  }
}

void main() {
  group('by word', () {
    test('breaks after spaces, which hang at the end of a line', () {
      expect(lay('the quick brown fox', 10), ['the quick', 'brown fox']);
      expect(lay('aaa    bbb', 5), ['aaa', 'bbb']);
      // what a line starts with stays
      expect(lay('  ab cd', 4), ['  ab', 'cd']);
    });

    test('neither counts nor draws the spaces that hang', () {
      final v = View(6, 2);
      const hl = Pen(bg: red);
      Color? bg(int x, int y) =>
          v.screen.styles.bgOf(v.screen.surface.styles[y * 6 + x]);
      // one line
      v.show(RenderParagraph([('ab  ', hl)]));
      expect([bg(1, 0), bg(2, 0)], [red, isNot(red)]);
      expect(v.show(RenderParagraph([('ab  ', hl)], align: .right)), [
        '    ab',
      ]);
      // lines it breaks
      v.show(RenderParagraph([('ab   cd', hl)], align: .right));
      expect([bg(3, 0), bg(4, 0), bg(5, 0)], [isNot(red), red, red]);
    });

    test('breaks after a hyphen inside a word', () {
      expect(lay('well-known fact', 6), ['well-', 'known', 'fact']);
      // not after one that starts a word or follows another
      expect(lay('x --flag', 4), ['x', '--fl', 'ag']);
    });

    test('breaks Cyrillic between words', () {
      expect(lay('съешь же ещё этих', 12), ['съешь же ещё', 'этих']);
    });

    test('breaks between two CJK characters', () {
      expect(lay('你好世界和平', 5), ['你好', '世界', '和平']);
      expect(lay('你好世界和平', 6), ['你好世', '界和平']);
      expect(lay('これはペンです', 6), ['これは', 'ペンで', 'す']);
      expect(lay('hi 你好世界', 6), ['hi 你', '好世界']);
      // not before closing punctuation or a small kana, not after an
      // opening bracket
      expect(lay('你好，世界', 4), ['你', '好，', '世界']);
      expect(lay('あいうっ', 6), ['あい', 'うっ']);
      expect(lay('你好「世界」', 6), ['你好', '「世', '界」']);
      // fullwidth closing punctuation and small katakana
      for (final close in ['．', '：', '；', '？', '］', '｝', 'ㇰ']) {
        expect(lay('你好$close', 4), ['你', '好$close'], reason: close);
      }
    });

    test('keeps emoji and combining marks whole', () {
      expect(lay('👍 ok 🎉 done', 5), ['👍 ok', '🎉', 'done']);
      expect(lay('cafe\u0301 nai\u0308ve', 5), ['cafe\u0301', 'nai\u0308ve']);
      expect(lay('ok 👨\u200D👩\u200D👧 go', 4), [
        'ok',
        '👨\u200D👩\u200D👧',
        'go',
      ]);
    });

    test('breaks a word longer than the line between graphemes', () {
      expect(lay('abcdefgh ij', 3), ['abc', 'def', 'gh', 'ij']);
      // a wide glyph that doesn't fit goes to the next line
      expect(lay('ab你好', 3), ['ab', '你', '好']);
    });

    test('keeps the clusters of a grapheme together in legacy mode', () {
      const family = '👨\u200D👩\u200D👧';
      // three emoji there, six columns
      expect(lay('abcd$family', 7, mode: TextMode.legacy), ['abcd', family]);
      expect(lay('abcd$family', 7), ['abcd$family']);
    });

    test('breaks where the text breaks', () {
      expect(lay('one\ntwo\r\n\nthree', 10), ['one', 'two', '', 'three']);
      expect(lay('one\r\ntwo', 10, mode: TextMode.legacy), ['one', 'two']);
      expect(lay('a\n', 10), ['a', '']);
      expect(lay('', 10), ['']);
    });

    test('breaks after a zero width space', () {
      expect(lay('abc\u200Bdef', 4), ['abc', 'def']);
    });

    test('carries a word on across spans', () {
      final v = View(6, 3);
      const a = Pen(fg: red);
      const b = Pen(fg: blue);
      expect(
        v.show(
          RenderParagraph([('foo', a), ('bar baz', b)]),
        ),
        ['foobar', 'baz'],
      );
      expect([v.fgAt(2, 0), v.fgAt(3, 0), v.fgAt(0, 1)], [red, blue, blue]);
    });
  });

  group('by grapheme', () {
    test('breaks between any two', () {
      const g = TextWrap.grapheme;
      expect(lay('hello world', 4, wrap: g), ['hell', 'o wo', 'rld']);
      expect(lay('аб你好', 3, wrap: g), ['аб', '你', '好']);
      expect(lay('e\u0301e\u0301e\u0301', 2, wrap: g), [
        'e\u0301e\u0301',
        'e\u0301',
      ]);
      expect(lay('a🎉b', 2, wrap: g), ['a', '🎉', 'b']);
    });
  });

  group('without wrapping', () {
    test('cuts a line off at the edge', () {
      const none = TextWrap.none;
      expect(lay('one two three', 5, wrap: none), ['one t']);
      expect(lay('ab\ncd', 5, wrap: none), ['ab', 'cd']);
      // half a wide glyph is a blank
      expect(lay('ab你', 3, wrap: none), ['ab']);
    });
  });

  group('an ellipsis', () {
    const none = TextWrap.none;

    test('at the end, the start or the middle of a line', () {
      expect(
        [
          for (final o in [
            TextOverflow.ellipsis,
            TextOverflow.ellipsisStart,
            TextOverflow.ellipsisMiddle,
          ])
            lay('hello world', 8, wrap: none, overflow: o),
        ],
        [
          ['hello w…'],
          ['…o world'],
          ['hell…rld'],
        ],
      );
    });

    test('keeps a path whole at both ends', () {
      expect(
        lay(
          '/home/user/projects/twk/lib/render.dart',
          20,
          wrap: none,
          overflow: TextOverflow.ellipsisMiddle,
        ),
        ['/home/user…nder.dart'],
      );
    });

    test('leaves no space next to it', () {
      expect(
        [
          for (final o in [
            TextOverflow.ellipsis,
            TextOverflow.ellipsisStart,
            TextOverflow.ellipsisMiddle,
          ])
            lay('aaa bbb ccc', 9, wrap: none, overflow: o),
        ],
        [
          ['aaa bbb…'],
          ['…bbb ccc'],
          ['aaa…b ccc'],
        ],
      );
    });

    test('splits no wide glyph, emoji or combining mark', () {
      expect(
        [
          for (final o in [
            TextOverflow.ellipsis,
            TextOverflow.ellipsisStart,
            TextOverflow.ellipsisMiddle,
          ])
            lay('你好世界', 6, wrap: none, overflow: o),
        ],
        [
          ['你好…'],
          ['…世界'],
          ['你…界'],
        ],
      );
      const end = TextOverflow.ellipsis;
      expect(lay('ab👨\u200D👩\u200D👧cd', 4, wrap: none, overflow: end), [
        'ab…',
      ]);
      expect(lay('cafe\u0301 ok', 5, wrap: none, overflow: end), [
        'cafe\u0301…',
      ]);
      // legacy mode: the family is three emoji that stay together
      expect(
        lay(
          'ab👨\u200D👩\u200D👧',
          7,
          wrap: none,
          overflow: end,
          mode: TextMode.legacy,
        ),
        ['ab…'],
      );
    });

    test('takes the room the terminal gives it', () {
      // two columns where ambiguous characters are wide
      expect(
        lay(
          'hello world',
          8,
          wrap: none,
          overflow: TextOverflow.ellipsis,
          ambiguousWidth: 2,
        ),
        ['hello…'],
      );
      // alone when nothing else fits; nothing when it doesn't fit either
      expect(lay('hello', 1, wrap: none, overflow: TextOverflow.ellipsis), [
        '…',
      ]);
    });

    test('is drawn in the pen of the text it stands for', () {
      final v = View(8, 1);
      const a = Pen(fg: red);
      const b = Pen(fg: blue);
      RenderParagraph p(List<(String, Pen)> spans, TextOverflow o) =>
          RenderParagraph(spans, wrap: TextWrap.none, overflow: o);

      // cut off where the spans meet: the pen of what it replaces, not of
      // what it follows
      expect(v.show(p([('hello w', a), ('orld', b)], .ellipsis)), [
        'hello w…',
      ]);
      expect([v.fgAt(6, 0), v.fgAt(7, 0)], [red, blue]);
      expect(v.show(p([('hell', a), ('o world', b)], .ellipsisStart)), [
        '…o world',
      ]);
      expect([v.fgAt(0, 0), v.fgAt(1, 0)], [red, blue]);
      expect(v.show(p([('hell', a), ('o world', b)], .ellipsisMiddle)), [
        'hell…rld',
      ]);
      expect([v.fgAt(3, 0), v.fgAt(4, 0)], [red, blue]);
    });
  });

  group('maxLines', () {
    const text = 'the quick brown fox jumps';

    test('leaves the lines beyond it out', () {
      expect(lay(text, 10, maxLines: 2), ['the quick', 'brown fox']);
      expect(lay(text, 10, maxLines: 5), ['the quick', 'brown fox', 'jumps']);
    });

    test('with an ellipsis, shows that text was left out', () {
      expect(
        [
          for (final o in [
            TextOverflow.ellipsis,
            TextOverflow.ellipsisStart,
            TextOverflow.ellipsisMiddle,
          ])
            lay(text, 10, maxLines: 2, overflow: o),
        ],
        [
          ['the quick', 'brown fox…'],
          ['…brown fox', 'jumps'],
          ['the qu…fox', 'jumps'],
        ],
      );
      expect(
        lay(
          'abcdefgh',
          3,
          wrap: TextWrap.grapheme,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        ['abc', 'de…'],
      );
    });

    test('cuts off at the line breaks of the text', () {
      expect(
        [
          for (final o in [
            TextOverflow.ellipsis,
            TextOverflow.ellipsisStart,
            TextOverflow.ellipsisMiddle,
          ])
            lay('aaa\nbbb\nccc', 10, maxLines: 2, overflow: o),
        ],
        [
          ['aaa', 'bbb…'],
          ['…bbb', 'ccc'],
          ['aaa…bbb', 'ccc'],
        ],
      );
      expect(
        lay(
          'ab\ncd\nef',
          10,
          wrap: TextWrap.none,
          maxLines: 1,
          overflow: TextOverflow.ellipsisMiddle,
        ),
        ['ab…ef'],
      );
    });

    test('with mixed scripts', () {
      expect(
        lay(
          'Привет 你好世界 👋 cafe\u0301',
          8,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        ['Привет', '你好世…'],
      );
    });
  });

  group('alignment', () {
    test('places each line at the left, in the middle or at the right', () {
      expect(
        [
          for (final a in [TextAlign.left, TextAlign.center, TextAlign.right])
            lay('ab cd', 10, align: a),
        ],
        [
          ['ab cd'],
          ['  ab cd'],
          ['     ab cd'],
        ],
      );
      expect(lay('aaa bb', 4, align: TextAlign.center), ['aaa', ' bb']);
      expect(lay('你好 мир', 6, align: TextAlign.right), ['  你好', '   мир']);
    });

    test('starts a line too long for it at the left', () {
      expect(lay('abcdef', 4, wrap: TextWrap.none, align: TextAlign.right), [
        'abcd',
      ]);
    });

    test('justified, stretches the wrapped lines between their words', () {
      const j = TextAlign.justify;
      expect(lay('aa bb cc dd ee', 9, align: j), ['aa  bb cc', 'dd ee']);
      expect(lay('aa bb cc dd', 10, align: j), ['aa  bb  cc', 'dd']);
      // the indent stays as it is
      expect(lay('  aa bb cc', 9, align: j), ['  aa   bb', 'cc']);
      // not a line the text breaks, nor one without spaces
      expect(lay('aa bb\ncc', 9, align: j), ['aa bb', 'cc']);
      expect(lay('你好世界和平', 5, align: j), ['你好', '世界', '和平']);
    });

    test('justified, fills the gaps in the pen of the space', () {
      final v = View(9, 2);
      const a = Pen(bg: red);
      const b = Pen(bg: blue);
      expect(
        v.show(
          RenderParagraph([('aa', a), (' bb cc dd', b)], align: .justify),
        ),
        ['aa  bb cc', 'dd'],
      );
      Color bg(int x) {
        final s = v.screen.surface.styles[x];
        expect(v.vt.cell(x, 0).bg, v.screen.styles.bgOf(s).value);
        return v.screen.styles.bgOf(s);
      }

      expect([bg(1), bg(2), bg(3), bg(4)], [red, blue, blue, blue]);
    });
  });

  group('intrinsic sizes', () {
    final v = View(20, 2);
    List<int> widths(String text, [TextWrap wrap = TextWrap.word]) {
      final p = RenderParagraph([(text, plain)], wrap: wrap);
      v.owner.root = p;
      return [p.getMinIntrinsicWidth(1), p.getMaxIntrinsicWidth(1)];
    }

    test('are its longest unbreakable piece and its longest line', () {
      expect(widths('the quick brown'), [5, 15]);
      expect(widths('well-known'), [5, 10]);
      expect(widths('你好世界'), [2, 8]);
      expect(widths('ab\ncdef gh'), [4, 7]);
      // the spaces at the end hang
      expect(widths('ab  '), [2, 2]);
      expect(widths('ab你', TextWrap.grapheme), [2, 4]);
      expect(widths('ab cd\nefg', TextWrap.none), [5, 5]);
      // a mark without a base is dropped, as the canvas drops it
      expect(widths('\u093Fab'), [2, 2]);
    });

    test('the height is the lines at a width, up to maxLines', () {
      final p = RenderParagraph([('the quick brown fox', plain)]);
      v.owner.root = p;
      expect(
        [p.getMinIntrinsicHeight(10), p.getMaxIntrinsicHeight(10)],
        [
          2,
          2,
        ],
      );
      expect(p.getMinIntrinsicHeight(100), 1);
      expect(p.getMinIntrinsicHeight(5), 4);
      p.maxLines = 3;
      expect(p.getMaxIntrinsicHeight(5), 3);
    });

    test('are measured as the owner it is attached to draws it', () {
      const family = '👨\u200D👩\u200D👧';
      final legacy = View(10, 1, mode: TextMode.legacy);
      final p = RenderParagraph([(family, plain)]);
      expect(p.getMaxIntrinsicWidth(1), 2);
      legacy.owner.root = p;
      expect(p.getMaxIntrinsicWidth(1), 6);
      expect(legacy.frame(), [family]);
    });
  });

  group('changes', () {
    test('moved to another screen, draws its clusters there', () {
      const text = 'e\u0301 \u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
      final a = View(6, 1);
      final p = RenderParagraph([(text, plain)]);
      a.owner.root = p;
      expect(a.frame(), [text]);
      p.detach();
      // another glyph table, which gives the ids out in another order
      final b = View(6, 1);
      b.owner.root = RenderParagraph([('o\u0308', plain)]);
      b.frame();
      b.owner.root = p;
      expect(b.frame(), [text]);
    });

    test('an owner that splits text otherwise splits it again', () {
      const text = 'abcd\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
      final graphemes = View(7, 2);
      final p = RenderParagraph([(text, plain)]);
      graphemes.owner.root = p;
      expect(graphemes.frame(), [text, '']);
      p.detach();
      final legacy = View(7, 2, mode: TextMode.legacy);
      legacy.owner.root = p;
      expect(legacy.frame(), ['abcd', text.substring(4)]);
    });

    test('new text is laid out again, with the parent that asked', () {
      final v = View(12, 2);
      final p = RenderParagraph([('ab', plain)]);
      final hug = Hug(p);
      v.owner.root = hug;
      expect(v.frame(), ['ab', '']);
      p.spans = [('abc 你好世界', plain)];
      expect(v.frame(), ['abc 你好世界', '']);
      expect(hug.layouts, 2);
      p.spans = [('x', plain)];
      expect(v.frame(), ['x', '']);
    });

    test('a new pen repaints once without a layout', () {
      final v = View(6, 1);
      // new instances on each call
      Pen fg(int r) => Pen(fg: Color.rgb(r, 0, 0));
      final p = RenderParagraph([('ab', fg(200)), ('cd', fg(200))]);
      final hug = Hug(p);
      v.owner.root = hug;
      v.frame();
      p.spans = [('ab', fg(200)), ('cd', fg(100))];
      expect(v.frame(), ['abcd']);
      expect([v.fgAt(1, 0), v.fgAt(2, 0)], [red, const Color.rgb(100, 0, 0)]);
      expect([hug.layouts, hug.paints], [1, 2]);
      expect(v.owner.hasWork, isFalse);
      // the same pens in another list: nothing to do
      p.spans = [('ab', fg(200)), ('cd', fg(100))];
      expect(v.owner.hasWork, isFalse);
    });

    test('new text in more spans is drawn in their pens', () {
      final v = View(6, 1);
      final p = RenderParagraph([('ab', const Pen(fg: red))]);
      v.owner.root = p;
      v.frame();
      p.spans = [('ab', const Pen(fg: red)), ('cd', const Pen(fg: blue))];
      expect(v.frame(), ['abcd']);
      expect([v.fgAt(1, 0), v.fgAt(2, 0)], [red, blue]);
    });

    test('painted with another style table, looks its pens up there', () {
      final v = View(2, 1);
      final p = RenderParagraph([
        ('a', const Pen(fg: red)),
        ('b', const Pen(bg: blue, attrs: Attr.bold)),
      ]);
      v.owner.root = p;
      v.frame();
      // the pens of the first table have other ids in this one
      final other = Screen(2, 1);
      other.styles
        ..pen(const Pen(fg: blue))
        ..pen(const Pen(attrs: Attr.strike))
        ..pen(const Pen(bg: red));
      List<(Color, Color?, int)> cells(Screen s) => [
        for (var x = 0; x < 2; x++)
          (
            s.styles.fgOf(s.surface.styles[x]),
            s.styles.bgOf(s.surface.styles[x]),
            s.styles.attrsOf(s.surface.styles[x]),
          ),
      ];
      final shown = [
        (red, Color.defaultColor, 0),
        (Color.defaultColor, blue, Attr.bold),
      ];
      expect(cells(v.screen), shown);
      v.owner
        ..markAllDirty()
        ..flushPaint(
          PaintContext(other.canvas, other.surface, other.presenter),
        );
      expect(cells(other), shown);
      // and in the first one again
      v.owner.markAllDirty();
      v.frame();
      expect(cells(v.screen), shown);
    });

    test('new settings are laid out again', () {
      final v = View(6, 3);
      final p = RenderParagraph([('aa bb cc', plain)]);
      v.owner.root = p;
      expect(v.frame(), ['aa bb', 'cc', '']);
      p.wrap = TextWrap.none;
      expect(v.frame(), ['aa bb', '', '']);
      p.overflow = TextOverflow.ellipsis;
      expect(v.frame(), ['aa bb…', '', '']);
      p
        ..wrap = TextWrap.grapheme
        ..overflow = TextOverflow.clip;
      expect(v.frame(), ['aa bb', 'cc', '']);
      p.maxLines = 1;
      expect(v.frame(), ['aa bb', '', '']);
      p
        ..wrap = TextWrap.word
        ..align = TextAlign.right;
      expect(v.frame(), [' aa bb', '', '']);
    });
  });

  test('a mixed-script paragraph shows in the terminal as on the screen', () {
    const text =
        'Hello мир! 你好世界 👋🏽 cafe\u0301 🇺🇦 '
        '\u0915\u094D\u0937\u093F 👨\u200D👩\u200D👧 end';
    for (final mode in TextMode.values) {
      for (final wrap in TextWrap.values) {
        for (final align in TextAlign.values) {
          final v = View(11, 8, mode: mode);
          v.owner.root = RenderParagraph(
            [(text, plain)],
            wrap: wrap,
            align: align,
            maxLines: 6,
            overflow: TextOverflow.ellipsisMiddle,
          );
          // frame() compares the emulator with the screen
          final rows = v.frame();
          expect(rows.where((r) => r.isNotEmpty), isNotEmpty);
        }
      }
    }
  });

  test('moved to an owner that draws text otherwise, it is laid out again '
      'as that owner measures it', () {
    final p = RenderParagraph([('±±±', plain)]);
    final narrow = View(3, 3);
    narrow.owner.root = p;
    expect(narrow.frame(), ['±±±', '', '']);
    final wide = View(3, 3, ambiguousWidth: 2);
    wide.owner.root = p;
    expect(wide.frame(), ['±', '±', '±']);
  });
}
