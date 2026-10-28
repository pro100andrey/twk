// The optimised Canvas/Surface (typed arrays, interned styles, compose
// cache, opaque fast paths, wide-glyph bookkeeping) is compared against a
// deliberately naive reference painter written with plain objects.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/src/canvas.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_core/src/surface.dart';
import 'package:twk_core/src/unicode/unicode.dart';

import 'support/harness.dart' as h show fillChars, samples;

final samples = <String>[
  ...h.samples,
  'и\u{306}й', // decomposed short i
  'क\u{93F}क\u{94D}ष', // Devanagari: spacing mark, virama conjunct
  '☃\u{FE0F} ❤\u{200D}🔥',
  'Ж\u{200D}Ж',
  'ก\u{E33}ไทย',
  '①②③',
  'x\u{301}\u{302}y',
  // conjoining jamo L V T, L L V
  '\u{1100}\u{1161}\u{11A8}\u{1100}\u{1100}\u{1161}',
  '\u{AC00}\u{11A8}a', // LV + T
];
const List<int> fillChars = h.fillChars;

// ---------------------------------------------------------------- reference --

final class RCell {
  RCell();
  var text = ' ';
  var role = 0; // 0 narrow, 2 wide leading, -1 trailing
  var fg = 0;
  var bg = 0;
  var attrs = 0;
  var ul = 0;
  String? link;
  RCell copy() => RCell()
    ..link = link
    ..text = text
    ..role = role
    ..fg = fg
    ..bg = bg
    ..attrs = attrs
    ..ul = ul;
}

int _paletteRgb(int i) {
  const base = <int>[
    0x000000,
    0xcd0000,
    0x00cd00,
    0xcdcd00,
    0x0000ee,
    0xcd00cd,
    0x00cdcd,
    0xe5e5e5,
    0x7f7f7f,
    0xff0000,
    0x00ff00,
    0xffff00,
    0x5c5cff,
    0xff00ff,
    0x00ffff,
    0xffffff,
  ];
  if (i < 16) {
    return base[i];
  }
  if (i < 232) {
    const lv = <int>[0, 95, 135, 175, 215, 255];
    final k = i - 16;
    return (lv[k ~/ 36] << 16) | (lv[(k ~/ 6) % 6] << 8) | lv[k % 6];
  }
  final v = 8 + 10 * (i - 232);
  return (v << 16) | (v << 8) | v;
}

int _rgb(int c) =>
    c == 0 ? 0 : ((c & 0x2000000) != 0 ? _paletteRgb(c & 0xFF) : c & 0xFFFFFF);

int _blend(Color src, int alpha, int dst) {
  final s = _rgb(src.value);
  final d = _rgb(dst);
  int ch(int sh) =>
      ((((s >> sh) & 255) * alpha + ((d >> sh) & 255) * (255 - alpha)) / 255)
          .round();
  return 0x1000000 | (ch(16) << 16) | (ch(8) << 8) | ch(0);
}

final class RefCanvas {
  RefCanvas(this.w, this.h) : grid = _grid(w, h);
  int w;
  int h;
  List<List<RCell>> grid;
  var ox = 0;
  var oy = 0;
  var cx0 = 0;
  var cy0 = 0;
  late int cx1 = w;
  late int cy1 = h;
  final stack = <List<int>>[];
  final seg = TextSegmenter();

  static List<List<RCell>> _grid(int w, int h) =>
      List.generate(h, (_) => List.generate(w, (_) => RCell()));

  void resize(int nw, int nh) {
    if (nw == w && nh == h) {
      reset();
      return;
    }
    w = nw;
    h = nh;
    grid = _grid(nw, nh);
    reset();
  }

  void reset() {
    ox = oy = cx0 = cy0 = 0;
    cx1 = w;
    cy1 = h;
    stack.clear();
  }

  void save() => stack.add([ox, oy, cx0, cy0, cx1, cy1]);
  void restore() {
    final s = stack.removeLast();
    ox = s[0];
    oy = s[1];
    cx0 = s[2];
    cy0 = s[3];
    cx1 = s[4];
    cy1 = s[5];
  }

  void clipRect(int x, int y, int cw, int ch) {
    cx0 = max(cx0, x + ox);
    cy0 = max(cy0, y + oy);
    cx1 = min(cx1, x + ox + cw);
    cy1 = min(cy1, y + oy + ch);
    if (cx1 <= cx0 || cy1 <= cy0) {
      cx0 = cx1 = cy0 = cy1 = 0;
    }
  }

  void _compose(RCell c, Pen p) {
    final bg = p.bg == null || p.bgAlpha == 0
        ? c.bg
        : (p.bgAlpha < 255 ? _blend(p.bg!, p.bgAlpha, c.bg) : p.bg!.value);
    c
      ..fg = p.fg == null
          ? c.fg
          : (p.fgAlpha < 255 ? _blend(p.fg!, p.fgAlpha, bg) : p.fg!.value)
      ..bg = bg
      ..attrs = p.attrs
      ..ul = p.underlineColor.value
      ..link = p.link;
  }

  void _blankPartner(int y, int x) {
    final c = grid[y][x];
    if (c.role == 2) {
      grid[y][x + 1]
        ..text = ' '
        ..role = 0;
    } else if (c.role == -1) {
      grid[y][x - 1]
        ..text = ' '
        ..role = 0;
    }
  }

  void putNarrow(int y, int x, String t, Pen p) {
    _blankPartner(y, x);
    final c = grid[y][x];
    _compose(c, p);
    c
      ..text = t
      ..role = 0;
  }

  void putWide(int y, int x, String t, Pen p) {
    if (grid[y][x].role == -1) {
      _blankPartner(y, x);
    }
    if (grid[y][x + 1].role == 2) {
      _blankPartner(y, x + 1);
    }
    final c = grid[y][x];
    _compose(c, p);
    c
      ..text = t
      ..role = 2;
    grid[y][x + 1]
      ..text = ''
      ..role = -1
      ..fg = c.fg
      ..bg = c.bg
      ..attrs = c.attrs
      ..ul = c.ul
      ..link = c.link;
  }

  void place(int y, int ax, int cw, String t, Pen p) {
    if (cw == 1) {
      if (ax >= cx0 && ax < cx1) {
        putNarrow(y, ax, t, p);
      }
    } else {
      final l = ax >= cx0 && ax < cx1;
      final r = ax + 1 >= cx0 && ax + 1 < cx1;
      if (l && r) {
        putWide(y, ax, t, p);
      } else if (l) {
        putNarrow(y, ax, ' ', p);
      } else if (r) {
        putNarrow(y, ax + 1, ' ', p);
      }
    }
  }

  void text(int x, int y, String s, Pen p) {
    final ay = y + oy;
    if (ay < cy0 || ay >= cy1) {
      return;
    }
    var ax = x + ox;
    final scan = ClusterScan();
    var i = 0;
    while (i < s.length) {
      if (ax >= cx1) {
        break;
      }
      seg.scan(s, i, scan);
      var t = s.substring(i, scan.end);
      var cw = scan.width;
      if (cw == 0) {
        i = scan.end;
        if (t != '\t') {
          continue;
        }
        t = ' ';
        cw = 1;
      } else {
        // spec: a leading mark (no base) is dropped, the rest re-segmented
        final first = t.runes.first;
        final g = segmentationProperty(first) & 0x0F;
        if (seg.mode == TextMode.graphemes &&
            (g == gcbExtend ||
                g == gcbZWJ ||
                g == gcbSpacingMark ||
                codePointWidth(first) == 0)) {
          i += first > 0xFFFF ? 2 : 1;
          continue;
        }
        i = scan.end;
      }
      place(ay, ax, cw, t, p);
      ax += cw;
    }
  }

  void fill(int x, int y, int fw, int fh, Pen p, int cp) {
    var cw = codePointWidth(cp);
    var t = String.fromCharCode(cp);
    if (cw == 0) {
      t = ' ';
      cw = 1;
    }
    for (var yy = y + oy; yy < y + oy + fh; yy++) {
      if (yy < cy0 || yy >= cy1) {
        continue;
      }
      final x0 = max(x + ox, cx0);
      final x1 = min(x + ox + fw, cx1);
      var xx = x0;
      if (cw == 1) {
        for (; xx < x1; xx++) {
          putNarrow(yy, xx, t, p);
        }
      } else {
        if (x0 < x1 && (x0 - (x + ox)).isOdd) {
          putNarrow(yy, xx++, ' ', p); // the clip cut a glyph
        }
        for (; xx + 1 < x1; xx += 2) {
          putWide(yy, xx, t, p);
        }
        if (xx < x1) {
          putNarrow(yy, xx, ' ', p);
        }
      }
    }
  }

  void clear(Pen opaque) {
    for (final row in grid) {
      for (final c in row) {
        c
          ..text = ' '
          ..role = 0
          ..fg = opaque.fg!.value
          ..bg = opaque.bg!.value
          ..attrs = opaque.attrs
          ..ul = opaque.underlineColor.value
          ..link = opaque.link;
      }
    }
  }

  void scrollRows(int top, int bottom, int n) {
    final old = [
      for (final r in grid) [for (final c in r) c.copy()],
    ];
    for (var y = top; y < bottom; y++) {
      final src = y + n;
      for (var x = 0; x < w; x++) {
        grid[y][x] = src >= top && src < bottom ? old[src][x].copy() : RCell();
      }
    }
  }
}

// ------------------------------------------------------------------- test --

void main() {
  for (final mode in TextMode.values) {
    test(
      'optimised canvas == naive reference (random ops, ${mode.name})',
      () => _run(mode),
    );
  }
}

void _run(TextMode mode) {
  {
    var checked = 0;
    for (var seed = 0; seed < 600; seed++) {
      final rnd = Random(1000 + seed);
      var w = 1 + rnd.nextInt(24);
      var h = 1 + rnd.nextInt(8);
      final styles = StyleTable();
      final glyphs = GlyphTable();
      final surface = Surface(w, h);
      final cv = Canvas(
        surface,
        styles,
        glyphs,
        segmenter: TextSegmenter(mode: mode),
      );
      final ref = RefCanvas(w, h)..seg.mode = mode;
      final pens = <Pen>[
        const Pen(),
        const Pen(fg: Color.rgb(200, 200, 200), bg: Color.rgb(20, 20, 30)),
        const Pen(fg: Color.rgb(255, 140, 0), attrs: Attr.bold),
        const Pen(bg: Color.rgb(38, 44, 58)),
        const Pen(fg: Color.red, attrs: Attr.dim | Attr.italic),
        const Pen(
          fg: Color.indexed(200),
          bg: Color.indexed(17),
          attrs: Attr.curlyUnderline,
          underlineColor: Color.rgb(255, 0, 0),
        ),
        const Pen(bg: Color.rgb(255, 255, 255), bgAlpha: 96),
        const Pen(fg: Color.rgb(10, 250, 10), fgAlpha: 128),
        const Pen(fg: Color.brightWhite, bg: Color.blue, attrs: Attr.underline),
        const Pen(fg: Color.blue, link: 'https://example.com/x'),
      ];
      final ids = [for (final p in pens) styles.pen(p)];
      for (var step = 0; step < 40; step++) {
        final pi = rnd.nextInt(pens.length);
        switch (rnd.nextInt(9)) {
          case 0:
          case 1:
          case 2:
            final s = samples[rnd.nextInt(samples.length)];
            final x = rnd.nextInt(w + 6) - 3;
            final y = rnd.nextInt(h + 2) - 1;
            cv.text(x, y, s, ids[pi]);
            ref.text(x, y, s, pens[pi]);
          case 3:
            final s = samples[rnd.nextInt(samples.length)];
            final x = rnd.nextInt(w + 6) - 3;
            final y = rnd.nextInt(h);
            cv.run(x, y, cv.shape(s), ids[pi]);
            ref.text(x, y, s, pens[pi]);
          case 4:
          case 5:
            final x = rnd.nextInt(w + 4) - 2;
            final y = rnd.nextInt(h + 2) - 1;
            final fw = rnd.nextInt(w + 2);
            final fh = rnd.nextInt(h + 1);
            final cp = fillChars[rnd.nextInt(fillChars.length)];
            cv.fill(x, y, fw, fh, ids[pi], cp);
            ref.fill(x, y, fw, fh, pens[pi], cp);
          case 6:
            final tx = rnd.nextInt(w) - w ~/ 3;
            final ty = rnd.nextInt(h) - h ~/ 3;
            final cx = rnd.nextInt(w);
            final cy = rnd.nextInt(h);
            final cw = rnd.nextInt(w) + 1;
            final ch = rnd.nextInt(h) + 1;
            cv
              ..save()
              ..translate(tx, ty)
              ..clipRect(cx, cy, cw, ch);
            ref
              ..save()
              ..ox += tx
              ..oy += ty
              ..clipRect(cx, cy, cw, ch);
            for (var k = 0; k < 3; k++) {
              final s = samples[rnd.nextInt(samples.length)];
              final x = rnd.nextInt(w) - 2;
              final y = rnd.nextInt(h);
              cv.text(x, y, s, ids[pi]);
              ref.text(x, y, s, pens[pi]);
              final cp = fillChars[rnd.nextInt(fillChars.length)];
              final fx = rnd.nextInt(w) - 2;
              final fy = rnd.nextInt(h);
              final fw = rnd.nextInt(6);
              final fh = rnd.nextInt(3);
              cv.fill(fx, fy, fw, fh, ids[(pi + k) % ids.length], cp);
              ref.fill(fx, fy, fw, fh, pens[(pi + k) % pens.length], cp);
            }
            cv.restore();
            ref.restore();
          case 7:
            if (h >= 2) {
              final top = rnd.nextInt(h - 1);
              final bottom = top + 1 + rnd.nextInt(h - top);
              final n = rnd.nextInt(5) - 2;
              surface.scrollRows(top, bottom, n);
              ref.scrollRows(top, bottom, n);
            }
          case 8:
            if (rnd.nextInt(5) == 0) {
              surface.clear(styles.opaqueStyleOf(ids[1]));
              ref.clear(pens[1]);
            } else if (rnd.nextInt(4) == 0) {
              w = 1 + rnd.nextInt(24);
              h = 1 + rnd.nextInt(8);
              surface.resize(w, h);
              cv.reset();
              ref.resize(w, h);
            }
        }
        // compare
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final i = y * w + x;
            final c = surface.cells[i];
            final st = surface.styles[i];
            final r = ref.grid[y][x];
            final role = (c & kCont) != 0 ? -1 : ((c & kWide) != 0 ? 2 : 0);
            final text = role == -1 ? '' : glyphs.stringOf(c);
            final ok =
                role == r.role &&
                text == r.text &&
                styles.fgOf(st).value == r.fg &&
                styles.bgOf(st).value == r.bg &&
                styles.attrsOf(st) == r.attrs &&
                styles.underlineColorOf(st).value == r.ul &&
                styles.linkOf(st) == r.link;
            if (!ok) {
              fail(
                'seed $seed step $step cell ($x,$y): '
                'canvas "$text"/$role '
                'fg=${styles.fgOf(st).value.toRadixString(16)} '
                'bg=${styles.bgOf(st).value.toRadixString(16)} '
                'a=${styles.attrsOf(st)} | '
                'ref "${r.text}"/${r.role} fg=${r.fg.toRadixString(16)} '
                'bg=${r.bg.toRadixString(16)} a=${r.attrs}',
              );
            }
            checked++;
          }
        }
      }
    }
    expect(checked, greaterThan(100000));
  }
}
