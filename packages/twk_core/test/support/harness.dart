/// Test harness: core (styles, glyphs, surface, canvas, presenter) wired to
/// the [Vt] oracle, plus a random scene generator.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:twk_core/src/canvas.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_core/src/surface.dart';
import 'package:twk_core/src/unicode/unicode.dart';
import 'package:twk_test/vt.dart';

final class Harness {
  Harness(
    int w,
    int h, {
    TerminalCaps caps = const TerminalCaps(),
    bool vtBce = true,
    bool vtKonsoleLines = false,
    bool vtKonsoleImages = false,
    TextSegmenter? vtSegmenter,
    bool strict = true,
  }) : styles = StyleTable(),
       glyphs = GlyphTable(),
       surface = Surface(w, h),
       vt = Vt(
         w,
         h,
         bce: vtBce,
         konsoleLines: vtKonsoleLines,
         konsoleImages: vtKonsoleImages,
         segmenter: vtSegmenter,
         strict: strict,
       ),
       inline = false,
       history = const [] {
    canvas = Canvas(surface, styles, glyphs);
    presenter = Presenter(w, h, styles, glyphs, caps: caps);
    pens = registerPens(styles);
  }

  /// The inline mode: the surface is a region [h] rows tall on a normal
  /// screen of [w] x [screenHeight] cells (with a scrollback), below the
  /// [history] whatever ran before printed; its last line ends with a line
  /// break when [atLineStart], so the region starts on the line after it.
  /// The emulator guards the history and takes no absolute row.
  Harness.inline(
    int w,
    int h, {
    required int screenHeight,
    this.history = const [],
    bool atLineStart = true,
    TerminalCaps caps = const TerminalCaps(),
    bool vtBce = true,
    bool vtKonsoleImages = false,
    TextSegmenter? vtSegmenter,
    bool strict = true,
  }) : styles = StyleTable(),
       glyphs = GlyphTable(),
       surface = Surface(w, h),
       vt = Vt(
         w,
         screenHeight,
         bce: vtBce,
         konsoleImages: vtKonsoleImages,
         segmenter: vtSegmenter,
         strict: strict,
         scrollback: true,
         allowLineFeed: true,
         relativeOnly: true,
       ),
       inline = true,
       _narrowest = w {
    for (var i = 0; i < history.length; i++) {
      vt.feed(utf8.encode(history[i]));
      if (atLineStart || i < history.length - 1) {
        vt.feed(const [0x0D, 0x0A]);
      }
    }
    final above = atLineStart ? vt.cy : vt.cy + 1;
    vt.guardRows(above);
    regionTop = vt.history.length + above;
    canvas = Canvas(surface, styles, glyphs);
    presenter = Presenter(
      w,
      h,
      styles,
      glyphs,
      caps: caps,
      inline: true,
      atLineStart: atLineStart,
    )..screenHeight = screenHeight;
    pens = registerPens(styles);
  }

  final StyleTable styles;
  final GlyphTable glyphs;
  final Surface surface;
  late final Canvas canvas;
  late final Presenter presenter;
  final Vt vt;
  late final List<int> pens;
  var frames = 0;
  var totalBytes = 0;

  /// Whether this is [Harness.inline].
  final bool inline;

  /// What was printed before the inline region (see [Harness.inline]).
  final List<String> history;

  /// Line of the region's first row, counted from the first line of the
  /// scrollback (inline mode).
  var regionTop = 0;

  /// The narrowest the terminal has been: the history is cut to it.
  var _narrowest = 0;

  /// Inline mode: the rows committed and written, oldest first (see
  /// [commit]).
  final committed = <CommittedRow>[];

  /// Inline mode: rows committed for the next frame.
  final _pending = <CommittedRow>[];

  /// Screen row of the surface's first row.
  int get top => inline ? regionTop - vt.history.length : 0;

  // a text field being edited across frames (see randomOp)
  String? editLine;
  var editX = 0;
  var editY = 0;
  var editPen = 0;

  /// Presents the surface and feeds the bytes to the terminal. Rows
  /// committed since the last frame are then on the lines above the
  /// region, which the emulator guards from now on.
  int frame() {
    final n = presenter.present(surface);
    vt.feed(presenter.out.view);
    frames++;
    totalBytes += n;
    if (_pending.isNotEmpty) {
      for (final r in _pending) {
        committed.add(r..line = regionTop++);
      }
      _pending.clear();
      vt.guardRows(top);
    }
    return n;
  }

  /// Inline mode: rows [from, to) of [rows] go to the history with the
  /// next frame ([Presenter.commit]).
  void commit(Surface rows, [int from = 0, int? to]) {
    presenter.commit(rows, from, to);
    final w = rows.width;
    for (var y = from; y < (to ?? rows.height); y++) {
      _pending.add(
        CommittedRow(
          rows.cells.sublist(y * w, y * w + w),
          rows.styles.sublist(y * w, y * w + w),
          min(w, surface.width),
        ),
      );
    }
  }

  /// Inline mode: differences between the committed rows and the lines
  /// they are on, up to the narrowest the terminal has been since (a
  /// resize cuts them as it cuts the history).
  List<String> committedMismatches({int limit = 5}) {
    final out = <String>[];
    for (final r in committed) {
      final line = r.line < vt.history.length
          ? vt.history[r.line]
          : [
              for (var x = 0; x < vt.width; x++)
                vt.cell(x, r.line - vt.history.length),
            ];
      for (var x = 0; x < r.limit; x++) {
        final c = r.cells[x];
        if ((c & kSkip) != 0 || ((c & kWide) != 0 && x + 1 >= r.limit)) {
          continue;
        }
        final why = _compare(c, r.styles[x], line[x]);
        if (why != null) {
          out.add('committed line ${r.line} ($x) $why');
          if (out.length >= limit) {
            return out;
          }
        }
      }
    }
    return out;
  }

  void resize(int w, int h) {
    // same size: no SIGWINCH, the terminal keeps its content
    if (w == surface.width && h == surface.height) {
      return;
    }
    surface.resize(w, h);
    canvas
      ..surface = surface
      ..reset();
    vt.resize(w, h);
  }

  /// Inline mode: the terminal becomes [w] x [screenHeight] cells and keeps
  /// what it shows (see [Vt.resizeKeeping]); the region keeps its height
  /// where the screen has room for it.
  void resizeTerminal(int w, int screenHeight, {bool pull = false}) {
    vt.resizeKeeping(w, screenHeight, pull: pull);
    final h = surface.height < screenHeight ? surface.height : screenHeight;
    surface.resize(w, h);
    canvas.reset();
    presenter.resize(w, h);
    // The region is found again by moving up from the cursor by the
    // cursor's row in it: the same line, unless the screen got so short
    // that the line went into the scrollback (then the screen's first row).
    if (regionTop < vt.history.length) {
      regionTop = vt.history.length;
    }
    if (w < _narrowest) {
      _narrowest = w;
    }
    for (final r in [...committed, ..._pending]) {
      r.limit = min(r.limit, w);
    }
  }

  /// Inline mode: the region becomes [h] rows tall.
  void resizeRegion(int h) {
    surface.resize(surface.width, h);
    canvas.reset();
  }

  /// Inline mode: lines of the history that are no longer what was printed
  /// (a resize may have cut them at the narrowest width the terminal had).
  List<String> historyChanges() {
    final lines = vt.lines;
    final out = <String>[];
    for (var i = 0; i < history.length; i++) {
      final want = history[i];
      final cut = want.substring(0, min(want.length, _narrowest)).trimRight();
      if (!want.startsWith(lines[i]) || lines[i].length < cut.length) {
        out.add('history line $i: want "$want" got "${lines[i]}"');
      }
    }
    return out;
  }

  /// Inline mode: screen rows below the region that are not blank.
  List<String> notBlankBelow() => [
    for (var y = top + surface.height; y < vt.height; y++)
      for (var x = 0; x < vt.width; x++)
        if (vt.cell(x, y).text != ' ' || vt.cell(x, y).bg != 0)
          '($x,$y) below the region: "${vt.cell(x, y).text}"',
  ];

  /// Differences between what the terminal shows and what the surface asks
  /// for. With [ignoreUncertain], cells holding glyphs whose width terminals
  /// disagree on (and their trailing halves) are not compared.
  List<String> mismatches({bool ignoreUncertain = false, int limit = 5}) {
    final out = <String>[];
    final w = surface.width;
    final h = surface.height;
    final top = this.top;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final c = surface.cells[i];
        if ((c & kSkip) != 0) {
          continue;
        }
        if (ignoreUncertain) {
          // The terminal may render this glyph differently, but its cells
          // must hold pieces of *this* glyph or blanks - never stale content.
          final lead = (c & kCont) != 0 && x > 0 ? surface.cells[i - 1] : c;
          if ((lead & kUncertain) != 0) {
            final v = vt.cell(x, top + y);
            final cluster = glyphs.stringOf(lead);
            if (v.text != ' ' &&
                v.text.isNotEmpty &&
                !cluster.contains(v.text)) {
              out.add(
                '($x,$y) stale "${v.text}" in cells of uncertain "$cluster"',
              );
              if (out.length >= limit) {
                return out;
              }
            }
            continue;
          }
        }
        final s = surface.styles[i];
        final v = vt.cell(x, top + y);
        final why = _compare(c, s, v);
        if (why != null) {
          out.add('($x,$y) $why');
          if (out.length >= limit) {
            return out;
          }
        }
      }
    }
    return out;
  }

  String? _compare(int c, int s, VtCell v) {
    if ((c & kCont) != 0) {
      return v.role == -1
          ? null
          : 'want trailing half, got "${v.text}" role ${v.role}';
    }
    final wantRole = (c & kWide) != 0 ? 2 : 0;
    final text = glyphs.stringOf(c);
    if (v.role != wantRole || v.text != text) {
      return 'want "$text"/$wantRole got "${v.text}"/${v.role}';
    }
    final fg = styles.fgOf(s).value;
    final bg = styles.bgOf(s).value;
    final attrs = styles.attrsOf(s);
    final ul = styles.underlineColorOf(s).value;
    final blank = text == ' ' && (attrs & Attr.reverse) == 0;
    if (bg != v.bg) {
      return 'bg want ${bg.toRadixString(16)} got ${v.bg.toRadixString(16)}';
    }
    const visible =
        Attr.underlineMask | Attr.strike | Attr.overline | Attr.reverse;
    if (blank) {
      if ((attrs & visible) != (v.attrs & visible)) {
        return 'attrs(blank) want $attrs got ${v.attrs}';
      }
      // lines on a space are drawn in the foreground colour (an underline
      // unless it has its own colour)
      final linesUseFg =
          (attrs & (Attr.strike | Attr.overline)) != 0 ||
          ((attrs & Attr.underlineMask) != 0 && ul == 0);
      if (linesUseFg && fg != v.fg) {
        return 'fg(blank) want ${fg.toRadixString(16)} '
            'got ${v.fg.toRadixString(16)}';
      }
    } else {
      if (fg != v.fg) {
        return 'fg want ${fg.toRadixString(16)} got ${v.fg.toRadixString(16)}';
      }
      if (attrs != v.attrs) {
        return 'attrs want $attrs got ${v.attrs}';
      }
    }
    if ((attrs & Attr.underlineMask) != 0 && ul != v.ul) {
      return 'ul color';
    }
    final link = styles.linkOf(s);
    if (link != v.link) {
      return 'link want $link got ${v.link}';
    }
    return null;
  }
}

/// A row committed to the history: its cells, the line it is on, and how
/// many of its columns the terminal still shows.
final class CommittedRow {
  CommittedRow(this.cells, this.styles, this.limit);
  final Uint32List cells;
  final Uint32List styles;
  var limit = 0;
  var line = -1;
}

List<int> registerPens(StyleTable t) => <int>[
  t.pen(const Pen()), // inherits everything, resets attrs
  t.pen(const Pen(fg: Color.rgb(200, 200, 200), bg: Color.rgb(20, 20, 30))),
  t.pen(const Pen(fg: Color.rgb(255, 140, 0), attrs: Attr.bold)),
  t.pen(const Pen(bg: Color.rgb(38, 44, 58))),
  t.pen(const Pen(fg: Color.red, attrs: Attr.dim | Attr.italic)),
  t.pen(
    const Pen(
      fg: Color.indexed(200),
      bg: Color.indexed(17),
      attrs: Attr.curlyUnderline,
      underlineColor: Color.rgb(255, 0, 0),
    ),
  ),
  t.pen(const Pen(attrs: Attr.reverse | Attr.strike)),
  t.pen(const Pen(bg: Color.rgb(255, 255, 255), bgAlpha: 96)),
  t.pen(
    const Pen(
      fg: Color.brightWhite,
      bg: Color.blue,
      attrs: Attr.bold | Attr.underline,
    ),
  ),
  t.pen(
    const Pen(fg: Color.rgb(90, 200, 120), attrs: Attr.overline | Attr.blink),
  ),
  t.pen(const Pen(fg: Color.defaultColor, bg: Color.defaultColor)),
  t.pen(
    const Pen(
      fg: Color.blue,
      attrs: Attr.underline,
      link: 'https://example.com/docs',
    ),
  ),
  t.pen(const Pen(link: 'file:///tmp/report.md')),
];

const samples = <String>[
  'hello world',
  'мир труд май',
  '你好世界',
  'a\tb',
  'e\u{301}x\u{308}',
  '🧪 ok',
  '❤\u{FE0F}!',
  '❤ plain',
  '👨\u{200D}👩\u{200D}👧 family',
  '🇺🇦🇩🇪',
  '±─│┼',
  'x\x1by\x07',
  '\u{301}lead',
  '한글 테스트',
  '👍🏽',
  'क्षत्रिय',
  'tail🧪',
  'и\u{306}й',
  'क\u{93F}क\u{94D}ष',
  'Ж\u{200D}Ж',
  '①②③',
  'e\u{301}e\u{301}e\u{301}e\u{301}', // a run of identical clusters
  '────────══',
  'क\u{94D}', // ends with a virama: joins a following consonant
  'ष',
  '🇺',
  '🇦',
  '\u{1100}', // Hangul L: joins a following syllable
  '가',
  '\u{600}', // Prepend
  '\u{93F}x', // starts with a spacing mark
  '🧪\u{200D}', // ends with an emoji ZWJ: joins a following pictograph
];

const fillChars = <int>[
  0x20,
  0x20,
  0x2588,
  0x2591,
  0x2500,
  0x4F60,
  0x1F9EA,
  0x2603,
];

/// Applies a random drawing operation (and sometimes a structural one).
void randomOp(Harness hs, Random rnd) {
  final s = hs.surface;
  final cv = hs.canvas;
  final w = s.width;
  final h = s.height;
  final pen = hs.pens[rnd.nextInt(hs.pens.length)];
  switch (rnd.nextInt(18)) {
    case 17:
      // a scroll view narrower than the screen (side panel / bordered list)
      if (h >= 3 && w >= 4) {
        final x0 = rnd.nextInt(w - 2);
        final x1 = x0 + 2 + rnd.nextInt(w - x0 - 1);
        final top = rnd.nextInt(h - 2);
        final bottom = top + 2 + rnd.nextInt(h - top - 1);
        final n = (rnd.nextInt(2) + 1) * (rnd.nextBool() ? 1 : -1);
        s.scrollRect(x0, x1, top, bottom, n);
        cv
          ..save()
          ..clipRect(x0, top, x1 - x0, bottom - top)
          ..text(
            x0,
            n > 0 ? bottom - 1 : top,
            samples[rnd.nextInt(samples.length)],
            pen,
          )
          ..restore();
      }
    case 16:
      // two stacked panes scroll by different amounts, nothing declared
      // (multi-block auto-detection)
      if (h >= 8) {
        final m = 3 + rnd.nextInt(h - 5);
        final snap = Surface(w, h)
          ..cells.setAll(0, s.cells)
          ..styles.setAll(0, s.styles);
        s.blit(snap, 0, 1, w, m - 1, 0, 0); // top pane up by 1
        cv.text(
          0,
          m - 1,
          'top ${rnd.nextInt(999)} ${samples[rnd.nextInt(samples.length)]}',
          pen,
        );
        final k = 1 + rnd.nextInt(2);
        if (h - m > k) {
          s.blit(snap, 0, m + k, w, h - m - k, 0, m); // bottom pane up by k
          cv.text(0, h - 1, 'bottom ${rnd.nextInt(999)}', pen);
        }
      }
    case 14:
    case 15:
      // text field editing: insert or delete characters in the middle
      var line = hs.editLine;
      if (line == null || rnd.nextInt(10) == 0) {
        line = List.generate(
          1 + rnd.nextInt(4),
          (_) => samples[rnd.nextInt(samples.length)],
        ).join(' ');
        hs
          ..editX = rnd.nextInt(w ~/ 2 + 1)
          ..editY = rnd.nextInt(h)
          ..editPen = hs.pens[rnd.nextInt(hs.pens.length)];
      } else {
        final at = rnd.nextInt(line.length + 1);
        if (rnd.nextBool() || line.isEmpty) {
          const ins = <String>['x', 'ab', 'я', '你', ' ', 'tool', '🧪'];
          line =
              line.substring(0, at) +
              ins[rnd.nextInt(ins.length)] +
              line.substring(at);
        } else {
          final end = (at + 1 + rnd.nextInt(3)).clamp(0, line.length);
          line =
              line.substring(
                0,
                at < end
                    ? at
                    : end - 1 < 0
                    ? 0
                    : end - 1,
              ) +
              line.substring(end);
        }
      }
      hs.editLine = line;
      cv
        ..fill(hs.editX, hs.editY, w - hs.editX, 1, hs.pens[1])
        ..text(hs.editX, hs.editY, line, hs.editPen);
    case 0:
    case 1:
    case 2:
      cv.fill(
        rnd.nextInt(w + 4) - 2,
        rnd.nextInt(h + 2) - 1,
        rnd.nextInt(w + 2),
        rnd.nextInt(h + 1),
        pen,
        fillChars[rnd.nextInt(fillChars.length)],
      );
    case 3:
    case 4:
    case 5:
    case 6:
      cv.text(
        rnd.nextInt(w + 6) - 3,
        rnd.nextInt(h + 2) - 1,
        samples[rnd.nextInt(samples.length)],
        pen,
      );
    case 7:
      final r = cv.shape(samples[rnd.nextInt(samples.length)]);
      cv.run(rnd.nextInt(w + 4) - 2, rnd.nextInt(h), r, pen);
    case 8:
      cv
        ..save()
        ..translate(rnd.nextInt(w) - w ~/ 3, rnd.nextInt(h) - h ~/ 3)
        ..clipRect(
          rnd.nextInt(w),
          rnd.nextInt(h),
          rnd.nextInt(w) + 1,
          rnd.nextInt(h) + 1,
        );
      for (var k = 0; k < 3; k++) {
        cv
          ..text(
            rnd.nextInt(w) - 2,
            rnd.nextInt(h),
            samples[rnd.nextInt(samples.length)],
            hs.pens[rnd.nextInt(hs.pens.length)],
          )
          ..fill(
            rnd.nextInt(w) - 2,
            rnd.nextInt(h),
            rnd.nextInt(6),
            rnd.nextInt(3),
            hs.pens[rnd.nextInt(hs.pens.length)],
            fillChars[rnd.nextInt(fillChars.length)],
          );
      }
      cv.restore();
    case 9:
      // retained scroll: rows move on the surface (recorded), possibly
      // several times per frame, with drawing in between
      if (h >= 2) {
        final top = rnd.nextInt(h - 1);
        final bottom = top + 1 + rnd.nextInt(h - top);
        final n = (rnd.nextInt(3) + 1) * (rnd.nextBool() ? 1 : -1);
        s.scrollRows(top, bottom, n);
        if (rnd.nextBool()) {
          cv.text(
            0,
            n > 0 ? bottom - 1 : top,
            samples[rnd.nextInt(samples.length)],
            pen,
          );
        }
      }
    case 10:
      if (rnd.nextInt(6) == 0) {
        s.clear(hs.styles.opaqueStyleOf(hs.pens[1]));
      }
    case 11:
      final src = Surface(1 + rnd.nextInt(w), 1 + rnd.nextInt(h));
      Canvas(src, hs.styles, hs.glyphs)
        ..fill(0, 0, src.width, src.height, hs.pens[1])
        ..text(
          rnd.nextInt(src.width),
          rnd.nextInt(src.height),
          samples[rnd.nextInt(samples.length)],
          pen,
        );
      s.blit(
        src,
        rnd.nextInt(src.width),
        0,
        src.width,
        src.height,
        rnd.nextInt(w + 2) - 1,
        rnd.nextInt(h + 2) - 1,
      );
    case 12:
      // immediate-mode style move (content repainted shifted, nothing
      // recorded): either declared to the presenter or left to detection
      if (h >= 3) {
        final n = rnd.nextBool() ? 1 : -1;
        final snap = Surface(w, h)
          ..cells.setAll(0, s.cells)
          ..styles.setAll(0, s.styles);
        s.blit(snap, 0, n > 0 ? 1 : 0, w, h - 1, 0, n > 0 ? 0 : 1);
        cv.text(0, n > 0 ? h - 1 : 0, 'new line ${rnd.nextInt(999)}', pen);
        if (rnd.nextBool()) {
          hs.presenter.scrollRegion(0, h, n);
        }
      }
    default:
      cv.text(
        rnd.nextInt(w),
        rnd.nextInt(h),
        String.fromCharCode(0x41 + rnd.nextInt(26)),
        pen,
      );
  }
}
