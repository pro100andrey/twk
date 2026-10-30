// Images in reserved cells: the presenter draws them with the protocol the
// terminal has (kitty graphics, sixel, iTerm2), over blanks in the styles
// of their cells, places them again or sends them again when they move,
// and takes them away when they go; the test emulator records what the
// terminal shows.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/byte_sink.dart';
import 'package:twk_core/src/graphics.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_core/src/surface.dart';
import 'package:twk_core/src/terminal/sequences.dart';
import 'package:twk_test/vt.dart';

import '../support/harness.dart';

/// An image of [protocol], [cols] x [rows] cells of the emulator's 10 x 20
/// pixels; [bytes] of data (sixel data sized by its raster attributes).
TerminalImage image(
  GraphicsProtocol protocol, {
  int cols = 4,
  int rows = 2,
  int bytes = 60,
  int seed = 0,
}) {
  final w = cols * 10;
  final h = rows * 20;
  final data = protocol == GraphicsProtocol.sixel
      ? ascii.encode('0;1;0q"1;1;$w;$h#0;2;0;0;0#0${'~' * bytes}')
      : Uint8List.fromList([for (var i = 0; i < bytes; i++) (i + seed) & 0xFF]);
  return TerminalImage(protocol, data, pixelWidth: w, pixelHeight: h);
}

Harness harness(
  GraphicsProtocol protocol, {
  int w = 20,
  int h = 8,
  Multiplexer multiplexer = Multiplexer.none,
}) => Harness(
  w,
  h,
  caps: TerminalCaps(graphics: protocol, graphicsMultiplexer: multiplexer),
);

String out(Harness hs) => latin1.decode(hs.presenter.out.view);

/// The images the emulator shows, as `protocol cols x rows at (x, y)`.
List<String> shown(Harness hs) => [
  for (final i in hs.vt.images)
    [
      '${i.protocol.name} ${i.cols}x${i.rows} at (${i.x}, ${i.y})',
      if (i.cells != i.cols * i.rows) '(${i.cells} cells)',
    ].join(' '),
];

/// Cells of the emulator in the rectangle of the surface that are not
/// blanks in the background the surface has there.
List<String> notBlank(Harness hs, int x, int y, int w, int h) => [
  for (var yy = y; yy < y + h; yy++)
    for (var xx = x; xx < x + w; xx++)
      if (hs.vt.cell(xx, hs.top + yy) case VtCell(:final text, :final bg)
          when text != ' ' ||
              bg !=
                  hs.styles
                      .bgOf(hs.surface.styles[yy * hs.surface.width + xx])
                      .value)
        '($xx, $yy) "$text" ${bg.toRadixString(16)}',
];

/// Fills the screen with text in pen 1 and shows [img] at (2, 1) over a
/// background of pen 3.
void paint(Harness hs, TerminalImage img, {int x = 2, int y = 1}) {
  final c = hs.canvas;
  for (var r = 0; r < hs.surface.height; r++) {
    c.text(0, r, 'row $r of the screen text'.padRight(40), hs.pens[1]);
  }
  c
    ..fill(x, y, img.pixelWidth ~/ 10, img.pixelHeight ~/ 20, hs.pens[3])
    ..image(x, y, img.pixelWidth ~/ 10, img.pixelHeight ~/ 20, img);
}

void main() {
  for (final protocol in [
    GraphicsProtocol.kitty,
    GraphicsProtocol.sixel,
    GraphicsProtocol.iterm2,
  ]) {
    group('${protocol.name}:', () {
      test("an image is drawn once, over blanks in its cells' styles", () {
        final hs = harness(protocol);
        final img = image(protocol);
        paint(hs, img);
        hs.frame();
        expect(shown(hs), ['${protocol.name} 4x2 at (2, 1)']);
        expect(hs.vt.images.single.bytes, img.data.length);
        expect(hs.mismatches(), isEmpty);
        expect(notBlank(hs, 2, 1, 4, 2), isEmpty);
        expect(hs.presenter.stats.images, 1);
        // painted again as it was: nothing to write
        paint(hs, img);
        expect(hs.frame(), 0);
        expect(shown(hs), ['${protocol.name} 4x2 at (2, 1)']);
      });

      test('a scroll moves it: kitty places it again, sixel and iTerm2 '
          'rewrite the rows and send it again', () {
        final hs = harness(protocol);
        final img = image(protocol);
        paint(hs, img, y: 3);
        hs.frame();
        hs.surface.scrollRows(0, 8, 2);
        hs.canvas
          ..text(0, 6, 'new row 6'.padRight(20), hs.pens[1])
          ..text(0, 7, 'new row 7'.padRight(20), hs.pens[1]);
        hs.frame();
        final o = out(hs);
        if (protocol == GraphicsProtocol.kitty) {
          expect(hs.presenter.stats.scrollOps, 1);
          expect(o, contains('a=p,i=1,p=1,c=4,r=2'));
          expect(o, isNot(contains('a=T')));
        } else {
          expect(hs.presenter.stats.scrollOps, 0, reason: 'no SU over it');
          expect(hs.presenter.stats.images, 1);
        }
        expect(shown(hs), ['${protocol.name} 4x2 at (2, 1)']);
        expect(hs.mismatches(), isEmpty);
        expect(notBlank(hs, 2, 1, 4, 2), isEmpty);
      });

      test('scrolled partly out of a view: kitty shows the rest of it, '
          'sixel and iTerm2 none of it', () {
        final hs = harness(protocol);
        final img = image(protocol);
        paint(hs, img);
        hs.frame();
        hs.surface.scrollRows(0, 8, 2);
        hs.frame();
        if (protocol == GraphicsProtocol.kitty) {
          expect(shown(hs), ['kitty 4x1 at (2, 0)']);
          expect(hs.vt.images.single.crop, (0, 20, 40, 20));
        } else {
          expect(shown(hs), isEmpty);
        }
        expect(hs.mismatches(), isEmpty);
        expect(notBlank(hs, 2, 0, 4, 1), isEmpty);
      });

      test('moved elsewhere: kitty places it again without sending it', () {
        final hs = harness(protocol);
        final img = image(protocol);
        paint(hs, img);
        hs.frame();
        paint(hs, img, x: 9, y: 4);
        hs.frame();
        expect(shown(hs), ['${protocol.name} 4x2 at (9, 4)']);
        if (protocol == GraphicsProtocol.kitty) {
          expect(out(hs), contains('a=p,i=1,p=1,'));
          expect(out(hs), isNot(contains('a=T')));
        }
        expect(hs.mismatches(), isEmpty);
        expect(notBlank(hs, 9, 4, 4, 2), isEmpty);
      });

      test('replaced by another image, which is sent; kitty deletes the '
          'old one', () {
        final hs = harness(protocol);
        paint(hs, image(protocol));
        hs.frame();
        final next = image(protocol, bytes: 90, seed: 7);
        paint(hs, next);
        hs.frame();
        expect(shown(hs), ['${protocol.name} 4x2 at (2, 1)']);
        expect(hs.vt.images.single.bytes, next.data.length);
        if (protocol == GraphicsProtocol.kitty) {
          expect(out(hs), contains('a=d,d=I,i=1,q=2'));
          expect(hs.vt.kittyImages, {2: 90});
        }
        expect(hs.mismatches(), isEmpty);
      });

      test('drawn over, it goes: kitty deletes it, sixel and iTerm2 keep '
          'the pixels of the cells still reserved, until the rows write '
          'over them', () {
        final hs = harness(protocol);
        paint(hs, image(protocol));
        hs.frame();
        hs.canvas.text(3, 2, 'x', hs.pens[2]);
        hs.frame();
        expect(hs.surface.images, isEmpty);
        expect(
          shown(hs),
          protocol == GraphicsProtocol.kitty
              ? isEmpty
              : ['${protocol.name} 4x2 at (2, 1) (7 cells)'],
        );
        expect(hs.vt.kittyImages, isEmpty);
        expect(hs.mismatches(), isEmpty);
        hs.canvas.fill(0, 0, 20, 8, hs.pens[1]);
        hs.frame();
        expect(shown(hs), isEmpty);
        expect(hs.mismatches(), isEmpty);
      });

      test('a forgotten screen gets it again, kitty sending it anew', () {
        final hs = harness(protocol);
        final img = image(protocol);
        paint(hs, img);
        hs.frame();
        hs.presenter.invalidate();
        hs.frame();
        expect(hs.presenter.stats.images, 1);
        if (protocol == GraphicsProtocol.kitty) {
          expect(out(hs), contains('a=T,f=100,t=d,i=1,p=1,'));
        }
        expect(shown(hs), ['${protocol.name} 4x2 at (2, 1)']);
        expect(hs.mismatches(), isEmpty);
      });

      test("on the last row it doesn't scroll the screen", () {
        final hs = harness(protocol);
        paint(hs, image(protocol), y: 6);
        hs.frame();
        expect(shown(hs), ['${protocol.name} 4x2 at (2, 6)']);
        expect(hs.mismatches(), isEmpty);
      });

      test('through tmux, wrapped', () {
        final hs = harness(protocol, multiplexer: Multiplexer.tmux);
        paint(hs, image(protocol));
        hs.frame();
        expect(out(hs), contains('\x1bPtmux;\x1b\x1b'));
        expect(shown(hs), ['${protocol.name} 4x2 at (2, 1)']);
        expect(hs.mismatches(), isEmpty);
      });

      test('an image of another protocol leaves its cells blank', () {
        final hs = harness(protocol);
        final other = protocol == GraphicsProtocol.kitty
            ? GraphicsProtocol.sixel
            : GraphicsProtocol.kitty;
        paint(hs, image(other));
        hs.frame();
        expect(shown(hs), isEmpty);
        expect(hs.presenter.stats.images, 0);
        expect(notBlank(hs, 2, 1, 4, 2), isEmpty);
        expect(hs.mismatches(), isEmpty);
      });
    });
  }

  test('no protocol: the cells stay blank and nothing else is written', () {
    final hs = harness(GraphicsProtocol.none);
    paint(hs, image(GraphicsProtocol.kitty));
    hs.frame();
    expect(out(hs), isNot(contains('\x1b_G')));
    expect(notBlank(hs, 2, 1, 4, 2), isEmpty);
    expect(hs.mismatches(), isEmpty);
  });

  test('kitty: a big image goes in chunks of 4096 bytes of base64', () {
    final hs = harness(GraphicsProtocol.kitty);
    final img = image(GraphicsProtocol.kitty, bytes: 10000);
    paint(hs, img);
    hs.frame();
    final o = out(hs);
    expect(o, contains(',C=1,q=2,m=1;'));
    expect('\x1b_Gm=1;'.allMatches(o).length, 2);
    expect('\x1b_Gm=0;'.allMatches(o).length, 1);
    expect(hs.vt.images.single.bytes, 10000);
  });

  test('kitty: two placements of one image, the image sent once and '
      'deleted with the last', () {
    final hs = harness(GraphicsProtocol.kitty);
    final img = image(GraphicsProtocol.kitty, cols: 2, rows: 1);
    hs.canvas
      ..image(1, 1, 2, 1, img)
      ..image(10, 3, 2, 1, img);
    hs.frame();
    expect(shown(hs), ['kitty 2x1 at (1, 1)', 'kitty 2x1 at (10, 3)']);
    expect('a=T'.allMatches(out(hs)).length, 1);
    hs.canvas.text(10, 3, 'ab', hs.pens[1]);
    hs.frame();
    expect(out(hs), contains('a=d,d=i,i=1,p=2,q=2'));
    expect(hs.vt.kittyImages, {1: img.data.length});
    hs.canvas.text(1, 1, 'ab', hs.pens[1]);
    hs.frame();
    expect(out(hs), contains('a=d,d=I,i=1,q=2'));
    expect(hs.vt.kittyImages, isEmpty);
    expect(hs.mismatches(), isEmpty);
  });

  test('a frame that takes an image away is a synchronized update', () {
    final hs = harness(GraphicsProtocol.kitty);
    hs.canvas.image(0, 0, 1, 1, image(GraphicsProtocol.kitty, cols: 1));
    hs.frame();
    hs.canvas.text(0, 0, 'x', hs.pens[0]);
    hs.frame();
    expect(out(hs), startsWith('\x1b[?2026h'));
    expect(out(hs), endsWith('\x1b[?2026l'));
    expect(hs.vt.kittyImages, isEmpty);
  });

  test('kitty: leaving the screen deletes the images', () {
    final hs = harness(GraphicsProtocol.kitty);
    paint(hs, image(GraphicsProtocol.kitty));
    hs.frame();
    expect(hs.presenter.leave(), greaterThan(0));
    hs.vt.feed(hs.presenter.out.view);
    expect(hs.vt.kittyImages, isEmpty);
    expect(shown(hs), isEmpty);
  });

  test('a scroll view shows an image as its rows come in', () {
    final hs = harness(GraphicsProtocol.kitty);
    final img = image(GraphicsProtocol.kitty, rows: 3);
    final s = hs.surface;
    // a view of rows 2 to 6 of a list whose image starts on row 5
    void view(int offset, int from, int to) {
      hs.canvas
        ..save()
        ..clipRect(0, from, 20, to - from)
        ..fill(0, from, 20, to - from, hs.pens[3])
        ..image(2, 5 - offset, 4, 3, img)
        ..restore();
    }

    view(0, 2, 6);
    hs.frame();
    expect(shown(hs), ['kitty 4x1 at (2, 5)']);
    s.scrollRows(2, 6, 1);
    view(1, 5, 6);
    expect(s.images.single.top, 4);
    hs.frame();
    expect(shown(hs), ['kitty 4x2 at (2, 4)']);
    expect(hs.vt.images.single.crop, (0, 0, 40, 40));
    s.scrollRows(2, 6, 1);
    view(2, 5, 6);
    hs.frame();
    expect(shown(hs), ['kitty 4x3 at (2, 3)']);
    expect(hs.vt.images.single.crop, isNull);
    expect(hs.mismatches(), isEmpty);
  });

  test('an inline region places kitty images again as rows go into the '
      'history above it', () {
    final hs = Harness.inline(
      20,
      4,
      screenHeight: 8,
      history: [r'$ run'],
      caps: const TerminalCaps(graphics: GraphicsProtocol.kitty),
    );
    final img = image(GraphicsProtocol.kitty);
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    expect(hs.vt.images.single.y - hs.top, 1);
    final rows = Surface(20, 2);
    hs.commit(rows);
    hs.canvas.image(2, 1, 4, 2, img);
    hs.frame();
    expect(out(hs), contains('a=p,i=1,p=1,'));
    expect(hs.vt.images.single.y - hs.top, 1);
    expect(hs.mismatches(), isEmpty);
  });

  test('without images a frame is what it was', () {
    final scenes = [
      for (final graphics in GraphicsProtocol.values)
        harness(graphics, w: 30, h: 10),
    ];
    for (var f = 0; f < 20; f++) {
      final bytes = <String>{};
      for (final hs in scenes) {
        hs.canvas.text(f % 7, f % 10, samples[f % samples.length], hs.pens[2]);
        if (f.isEven) {
          hs.surface.scrollRows(0, 10, 1);
        }
        hs.frame();
        bytes.add(out(hs));
      }
      expect(bytes, hasLength(1));
    }
  });

  group('the surface keeps its images', () {
    final img = image(GraphicsProtocol.kitty);
    ImagePlacement at(int x, int y) =>
        ImagePlacement(img, x, y, 4, 2, x, y, x + 4, y + 2);

    test('one drawn over another takes its place; the same one in pieces '
        'is one', () {
      final s = Surface(20, 8)
        ..place(at(0, 0))
        ..place(at(10, 0))
        ..place(at(2, 1));
      expect(s.images.map((p) => (p.x, p.y)), [(10, 0), (2, 1)]);
      s.place(ImagePlacement(img, 2, 1, 4, 2, 2, 1, 6, 2));
      expect(s.images, hasLength(2));
      expect(s.images.last.whole, isTrue);
    });

    test('they move with the rows, those cut by the scroll go', () {
      final s = Surface(20, 8)
        ..place(at(0, 3))
        ..place(at(10, 5))
        ..scrollRows(2, 6, 1);
      expect(s.images.map((p) => (p.x, p.y, p.top, p.bottom)), [(0, 2, 2, 4)]);
      s.scrollRect(0, 8, 0, 8, -3);
      expect(s.images.map((p) => (p.y, p.top, p.bottom)), [(5, 5, 7)]);
      s.scrollRect(0, 8, 0, 8, -2);
      expect(s.images.map((p) => (p.y, p.top, p.bottom)), [(7, 7, 8)]);
      s.scrollRows(0, 8, -1);
      expect(s.images, isEmpty);
      s
        ..place(at(0, 0))
        ..resize(10, 4);
      expect(s.images, isEmpty);
      s
        ..place(at(0, 0))
        ..clear();
      expect(s.images, isEmpty);
    });
  });

  test('image data goes through a multiplexer as passthroughSequence '
      'wraps the sequence it is in, written as it is', () {
    final random = Random(3);
    for (final multiplexer in Multiplexer.values) {
      for (final length in [0, 1, 200, 251, 252, 253, 4096, 10000]) {
        final data = Uint8List.fromList([
          for (var i = 0; i < length; i++) 0x21 + random.nextInt(0x5E),
        ]);
        for (final (head, tail) in [
          ('\x1b_Ga=T,f=100;', '\x1b\\'),
          ('\x1b]1337;File=inline=1:', '\x07'),
          ('\x1bPq"1;1;4;2', '\x1b\\'),
        ]) {
          for (final (start, end) in [(0, length), (length ~/ 3, length)]) {
            final out = ByteSink();
            putImageData(out, head, data, start, end, tail, multiplexer);
            expect(
              latin1.decode(out.view),
              passthroughSequence(
                '$head${latin1.decode(data.sublist(start, end))}$tail',
                multiplexer,
              ),
              reason: '${multiplexer.name}, $length, $start',
            );
          }
        }
      }
    }
  });
}
