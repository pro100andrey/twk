/// The frame benchmark's scenarios: workloads of the core rendered a frame
/// at a time on a [FrameRig], the core wired up without a terminal. What
/// `tool/bench.dart` times and checks against the test emulator, and
/// `tool/alloc` counts the allocations of.
///
/// A scenario that needs a class of the core added since the oldest
/// commit the benchmark compiles against keeps its lines between
/// `// needs <class>` and `// end <class>`, which the benchmark leaves out
/// of a build against a core without it.
library;

import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';

/// The core wired up as an app's frame drives it, without a terminal: a
/// style table, a glyph table, a surface of `width` × `height` cells, the
/// canvas that paints it and the presenter that writes its changes.
final class FrameRig {
  /// A rig of `width` × `height` cells, the presenter's terminal of the
  /// default capabilities.
  FrameRig(int width, int height)
    : styles = StyleTable(),
      glyphs = GlyphTable(),
      surface = Surface(width, height) {
    canvas = Canvas(surface, styles, glyphs);
    presenter = Presenter(width, height, styles, glyphs);
  }

  /// The styles and pens of the frames.
  final StyleTable styles;

  /// The grapheme clusters the cells hold.
  final GlyphTable glyphs;

  /// The cells painted.
  final Surface surface;

  /// What paints the surface.
  late final Canvas canvas;

  /// What writes the surface's changes, to [Presenter.out].
  late final Presenter presenter;
}

/// A scenario that doesn't do what it is meant to: it isn't timed.
final class ScenarioBroken implements Exception {
  /// Broken as [message] says.
  ScenarioBroken(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => message;
}

/// What the scenarios' frames that write nothing return, kept so that
/// their work can't be optimised away; read it.
int get scenarioSink => _sink;
var _sink = 0;

/// A workload. [start] builds it on a [FrameRig], renders its first frame
/// and returns the function that runs frame `i` (from 1): the change,
/// layout, paint and present; it returns the bytes written. Frames of a
/// scenario that doesn't [write] to the terminal return 0.
final class FrameScenario {
  /// The scenario [name], doing what [about] says, started by [start].
  const FrameScenario(this.name, this.about, this.start, {this.write = true});

  /// Its name in a report: `wrap`, `list-scroll`.
  final String name;

  /// What a frame of it changes.
  final String about;

  /// Builds it on a rig and renders its first frame; the function that
  /// runs frame `i`.
  final int Function(int i) Function(FrameRig hs) start;

  /// Whether its frames write to the terminal.
  final bool write;
}

const _spinner = <String>['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧'];

const _phrases = <String>[
  'tool: ran 412 tests ✓ all passed',
  'assistant: the presenter diffs only damaged spans',
  'user: проверь прокрутку и ширину эмодзи 🧪',
  'tool: compiled 87 files · 你好 · 0 warnings',
  'assistant: hardware scroll moved the log by one row',
  'tool: grapheme clusters 👨‍👩‍👧 and flags 🇺🇦 are one cell each',
];

String _spin(int i) => '${_spinner[i & 7]} tok/s ${900 + (i * 37) % 400}';

/// The scenarios, in the order of the report.
final frameScenarios = <FrameScenario>[
  FrameScenario('idle', 'nothing changed', (hs) {
    final s = _Chat(hs)..render();
    return (_) => s.render();
  }),
  FrameScenario('spinner', 'the spinner and the rate in the header', (hs) {
    final s = _Chat(hs)..render();
    return (i) {
      s.right.text = _spin(i);
      return s.render();
    };
  }),
  FrameScenario('typing', 'a character typed or deleted mid-line', (hs) {
    final s = _Chat(hs);
    final p = hs.presenter
      ..cursorVisible = true
      ..cursorShape = CursorShape.bar;
    void type(int i) {
      // one character more or less each frame: 0, 1, …, 32, 31, …, 0
      final k = i % 64 <= 32 ? i % 64 : 64 - i % 64;
      s.input.text = '> explain the ${'x' * k}diff in the presenter, please';
      p.cursorX = 14 + k;
    }

    type(0);
    p.cursorY = hs.surface.height - 2;
    s.render();
    return (i) {
      type(i);
      return s.render();
    };
  }),
  FrameScenario('log-line', 'a line appended to the log, the count updated', (
    hs,
  ) {
    final s = _Chat(hs)..render();
    return (i) {
      s.log.add('${_phrases[i % _phrases.length]} #$i');
      s.status.text = ' ${s.log.length} messages';
      return s.render();
    };
  }),
  FrameScenario(
    'log-bar',
    'the same, the log beside a scrollbar column (no DECSLRM margins)',
    (hs) {
      final s = _Chat(hs, scrollbar: true)..render();
      return (i) {
        s.log.add('${_phrases[i % _phrases.length]} #$i');
        s.status.text = ' ${s.log.length} messages';
        return s.render();
      };
    },
  ),
  FrameScenario('repaint-all', 'every object repainted, the spinner changed', (
    hs,
  ) {
    final s = _Chat(hs)..render();
    return (i) {
      s.owner.markAllDirty();
      s.right.text = _spin(i);
      return s.render();
    };
  }),
  FrameScenario('full-frame', 'the screen forgotten: every cell written', (hs) {
    final s = _Chat(hs)..render();
    return (i) {
      hs.presenter.invalidate();
      s.owner.markAllDirty();
      s.right.text = _spin(i);
      return s.render();
    };
  }),
  FrameScenario(
    'tree',
    'one text changed in rows × 6 texts, no inner boundary',
    (
      hs,
    ) {
      final s = _Grid(hs)..render();
      return (i) {
        s.cells[(i * 7) % s.cells.length].text = 'cell $i';
        return s.render();
      };
    },
  ),
  FrameScenario(
    'wrap',
    'a word typed into a mixed-script paragraph, re-wrapped',
    (
      hs,
    ) {
      final s = _Prose(hs)..render();
      return (i) {
        s.type(i);
        return s.render();
      };
    },
  ),
  FrameScenario('ellipsis', 'the same cut off at 2/3 of the rows with "…"', (
    hs,
  ) {
    final s = _Prose(hs, maxLines: hs.surface.height * 2 ~/ 3)..render();
    final w = hs.surface.width;
    final last = (s.paragraph.maxLines! - 1) * w;
    var cut = false;
    for (var x = 0; x < w; x++) {
      cut = cut || (hs.surface.cells[last + x] & kGlyphMask) == 0x2026;
    }
    if (!cut) {
      throw ScenarioBroken('no ellipsis on line ${s.paragraph.maxLines}');
    }
    return (i) {
      s.type(i);
      return s.render();
    };
  }),
  FrameScenario(
    'wrap-bidi',
    'a word typed into a Latin, Hebrew and Arabic paragraph in visual order',
    (hs) {
      final s = _Prose(hs, sentences: _bidiSentences, visual: true)..render();
      return (i) {
        s.type(i);
        return s.render();
      };
    },
  ),
  FrameScenario(
    'pens',
    'a sentence of the paragraph highlighted: new pens, no layout',
    (hs) {
      final s = _Prose(hs)..render();
      return (i) {
        s.highlight(i);
        return s.render();
      };
    },
  ),
  // needs RenderList
  FrameScenario(
    'list-scroll',
    'a row scrolled in a list of 100k items of 1 to 3 rows, built as they come',
    (hs) {
      final s = _List(hs)..render();
      return (i) {
        // down a row a frame for 200 frames, then back up
        final k = i % 400;
        s.list.scrollOffset = k <= 200 ? k : 400 - k;
        return s.render();
      };
    },
  ),
  // end RenderList
  FrameScenario('keys', '2000 key and mouse events decoded', (_) {
    final bytes = _keyBytes(200);
    final parser = InputParser();
    final n = parser.feed(bytes).length;
    if (n != 2000 || parser.hasPending) {
      throw ScenarioBroken('decoded $n events, expected 2000');
    }
    return (_) {
      _sink += parser.feed(bytes).length;
      return 0;
    };
  }, write: false),
];

/// [n] repetitions of ten events: letters, a Cyrillic letter, arrows with
/// and without modifiers, a kitty-protocol key, SGR mouse press, release
/// and wheel.
Uint8List _keyBytes(int n) {
  const one =
      'ab'
      'ж'
      '\x1b[A'
      '\x1b[1;5C'
      '\x1b[97;5u'
      '\x1b[<0;10;5M'
      '\x1b[<0;10;5m'
      '\x1b[<64;10;5M'
      'z';
  final b = BytesBuilder(copy: false);
  final unit = Uint8List.fromList(one.runes.expand(_utf8).toList());
  for (var i = 0; i < n; i++) {
    b.add(unit);
  }
  return b.takeBytes();
}

List<int> _utf8(int cp) => cp < 0x80
    ? [cp]
    : cp < 0x800
    ? [0xC0 | cp >> 6, 0x80 | cp & 0x3F]
    : [0xE0 | cp >> 12, 0x80 | cp >> 6 & 0x3F, 0x80 | cp & 0x3F];

/// A render tree on a rig, driven the way `TwkApp` drives it.
abstract base class _Scene {
  _Scene(this.hs) : ctx = PaintContext(hs.canvas, hs.surface, hs.presenter);
  final FrameRig hs;
  final PaintContext ctx;
  final owner = PipelineOwner(() {});

  int render() {
    owner
      ..flushLayout(hs.surface.width, hs.surface.height)
      ..flushPaint(ctx);
    return hs.presenter.present(hs.surface);
  }
}

/// The screen of `example/chat_demo.dart`: header, log, input and status;
/// with `scrollbar`, a column right of the log: its track, and the thumb
/// at its foot.
final class _Chat extends _Scene {
  _Chat(super.hs, {bool scrollbar = false}) {
    final t = hs.styles;
    final bg = t.pen(
      const Pen(bg: Color.rgb(16, 18, 24), fg: Color.rgb(200, 200, 200)),
    );
    final header = t.pen(
      const Pen(
        fg: .rgb(255, 255, 255),
        bg: .rgb(0, 90, 180),
        attrs: Attr.bold,
      ),
    );
    final headerDim = t.pen(
      const Pen(fg: Color.rgb(200, 220, 255), bg: Color.rgb(0, 90, 180)),
    );
    final inputPen = t.pen(
      const Pen(
        fg: Color.rgb(255, 140, 0),
        bg: Color.rgb(24, 26, 34),
        attrs: Attr.bold,
      ),
    );
    final statusPen = t.pen(
      const Pen(
        fg: Color.rgb(150, 150, 160),
        bg: Color.rgb(30, 30, 40),
        attrs: Attr.italic,
      ),
    );
    final user = t.pen(const Pen(fg: Color.rgb(80, 160, 255)));
    final tool = t.pen(
      const Pen(
        fg: Color.rgb(90, 200, 120),
        link: 'file:///tmp/twk_core_build.log',
      ),
    );
    final assistant = t.pen(const Pen(fg: Color.rgb(220, 220, 220)));
    right = RenderText(_spin(0), headerDim, boundary: true);
    log = RenderLog(
      pen: bg,
      itemPen: (_, line) => line.startsWith('user')
          ? user
          : (line.startsWith('tool') ? tool : assistant),
    );
    input = RenderText('> ', inputPen, boundary: true);
    status = RenderText('', statusPen, boundary: true);
    owner.root = RenderBox(
      pen: bg,
      boundary: true,
      child: RenderColumn(<(RenderObject, int?)>[
        (
          RenderRow(<(RenderObject, int?)>[
            (RenderText(' twk_core · bench', header, boundary: true), null),
            (right, 26),
          ]),
          1,
        ),
        if (scrollbar)
          (
            RenderRow(<(RenderObject, int?)>[
              (log, null),
              (
                RenderColumn(<(RenderObject, int?)>[
                  (
                    RenderBox(pen: t.pen(const Pen(bg: Color.rgb(40, 42, 50)))),
                    null,
                  ),
                  (
                    RenderBox(
                      pen: t.pen(const Pen(bg: Color.rgb(120, 124, 140))),
                    ),
                    3,
                  ),
                ]),
                1,
              ),
            ]),
            null,
          )
        else
          (log, null),
        (input, 1),
        (status, 1),
      ]),
    );
    for (var i = 0; i < hs.surface.height; i++) {
      log.add('${_phrases[i % _phrases.length]} #$i');
    }
  }

  late final RenderText right;
  late final RenderLog log;
  late final RenderText input;
  late final RenderText status;
}

/// A tree with no repaint boundary below the root: one row of six texts
/// per screen row, so a change anywhere repaints all of it.
final class _Grid extends _Scene {
  _Grid(super.hs) {
    final t = hs.styles;
    final bg = t.pen(const Pen(bg: Color.rgb(16, 18, 24)));
    final pens = <int>[
      t.pen(const Pen(fg: Color.rgb(80, 160, 255))),
      t.pen(const Pen(fg: Color.rgb(90, 200, 120), attrs: Attr.bold)),
      t.pen(const Pen(fg: Color.rgb(220, 220, 220), bg: Color.rgb(38, 44, 58))),
    ];
    final w = hs.surface.width ~/ 6;
    RenderText cell(int x, int y) {
      final t = RenderText('r$y c$x · ячейка', pens[(x + y) % pens.length]);
      cells.add(t);
      return t;
    }

    owner.root = RenderBox(
      pen: bg,
      boundary: true,
      child: RenderColumn(<(RenderObject, int?)>[
        for (var y = 0; y < hs.surface.height; y++)
          (
            RenderRow(<(RenderObject, int?)>[
              for (var x = 0; x < 6; x++) (cell(x, y), x == 5 ? null : w),
            ]),
            1,
          ),
      ]),
    );
  }

  final cells = <RenderText>[];
}

const _latin = Pen(fg: Color.rgb(220, 220, 220));
const _cyrillic = Pen(fg: Color.rgb(120, 180, 255), attrs: Attr.italic);
const _cjk = Pen(fg: Color.rgb(255, 190, 90), attrs: Attr.bold);
const _emoji = Pen(fg: Color.rgb(90, 200, 120));
const _highlight = Pen(fg: Color.rgb(16, 18, 24), bg: Color.rgb(250, 200, 80));

/// The sentences of [_Prose], each a span in the pen of its script.
const _sentences = <(String, Pen)>[
  (
    'The presenter compares every row with what the terminal shows and '
        'writes only the cells that changed since the last frame. ',
    _latin,
  ),
  (
    'Абзац переносится по словам, а не по буквам: слово, которое не '
        'помещается, целиком уходит на следующую строку. ',
    _cyrillic,
  ),
  ('中文段落可以在任意两个汉字之间换行，但不会在句号或逗号之前断开。 ', _cjk),
  (
    'Emoji take two cells 🧪 🚀 and a family 👨‍👩‍👧 or a flag 🇺🇦 is one '
        'grapheme of several code points. ',
    _emoji,
  ),
  (
    'Hyphenated words like well-known and self-contained may break after '
        'the hyphen; spaces at the end of a line hang beyond it. ',
    _latin,
  ),
  ('日本語の文章も同じように折り返されます。「括弧」の内側では改行しません。 ', _cjk),
  (
    'Числа 1234 и 5678, тире — и «кавычки» остаются на своих местах. ',
    _cyrillic,
  ),
  ('한국어 문장은 음절 사이에서 줄이 바뀔 수 있습니다. ', _cjk),
];

/// The sentences of the bidi [_Prose]: a paragraph that runs left to
/// right, with right-to-left runs of Hebrew and Arabic in it, numbers and
/// brackets among them.
const _bidiSentences = <(String, Pen)>[
  (
    'The presenter compares every row with what the terminal shows and '
        'writes only the cells that changed since the last frame. ',
    _latin,
  ),
  (
    'פסקה נשברת לפי מילים ולא לפי אותיות: מילה שאינה נכנסת עוברת כולה '
        'לשורה הבאה (כמו 1234 ו-5678). ',
    _cyrillic,
  ),
  (
    'A line mixes שלום עולם with مرحبا بالعالم and [brackets] that mirror '
        'in a right-to-left run. ',
    _emoji,
  ),
  (
    'تنكسر الفقرة بين الكلمات، والأرقام ١٢٣ و456 تبقى في أماكنها «هنا». ',
    _cjk,
  ),
];

/// Where [_Prose.type] types [_typed]: after this start of the first
/// sentence.
const _lead = 'The presenter ';
const _typed = 'of the core, written in plain Dart with no dependencies, ';

/// A paragraph of mixed-script text (Latin, Cyrillic, CJK, emoji, or the
/// sentences given), word wrapped, about as long as fills 85% of the
/// screen's cells, on a box; in visual order when asked for.
final class _Prose extends _Scene {
  _Prose(
    super.hs, {
    int? maxLines,
    List<(String, Pen)> sentences = _sentences,
    bool visual = false,
  }) {
    if (visual) {
      owner.textOrder = TextOrder.visual;
    }
    final target = hs.surface.width * hs.surface.height * 17 ~/ 20;
    for (var k = 0, cells = 0; cells < target; k++) {
      final s = sentences[k % sentences.length];
      base.add(s);
      cells += stringWidth(s.$1);
    }
    _tail = base.first.$1.substring(_lead.length);
    paragraph = RenderParagraph(
      base,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      maxLines: maxLines,
    );
    owner.root = RenderBox(
      pen: hs.styles.pen(const Pen(bg: Color.rgb(16, 18, 24))),
      boundary: true,
      child: paragraph,
    );
  }

  final base = <(String, Pen)>[];
  late final RenderParagraph paragraph;
  late final String _tail;

  /// [_typed] typed into the first sentence a character a frame, then
  /// deleted again.
  void type(int i) {
    const n = 2 * _typed.length;
    final k = i % n <= _typed.length ? i % n : n - i % n;
    paragraph.spans = List.of(base)
      ..[0] = ('$_lead${_typed.substring(0, k)}$_tail', base.first.$2);
  }

  /// Sentence `i % spans` highlighted, the one before it no longer.
  void highlight(int i) {
    final h = i % base.length;
    paragraph.spans = [
      for (var k = 0; k < base.length; k++)
        if (k == h) (base[k].$1, _highlight) else base[k],
    ];
  }
}

// needs RenderList
/// A [RenderList] of 100k items over the screen, 1 to 3 rows of text each,
/// built as they come into view.
final class _List extends _Scene implements ListItemManager {
  _List(super.hs) {
    list = RenderList(
      items: this,
      itemCount: 100000,
      background: const Pen(bg: Color.rgb(16, 18, 24)),
    );
    owner.root = list;
  }

  late final RenderList list;

  static const _pen = Pen(fg: Color.rgb(220, 220, 220));

  @override
  void buildItem(int index) => list.insertItem(
    RenderParagraph([
      (
        [
          for (var k = 0; k <= index % 3; k++)
            '${_phrases[(index + k) % _phrases.length]} #$index',
        ].join('\n'),
        _pen,
      ),
    ]),
    index,
  );

  @override
  void dropItem(RenderObject item) => list.remove(item);
}
// end RenderList
