// The emulator records the images a terminal shows: kitty placements, which
// stay over their cells while text is printed or erased there and scroll
// with them, and sixel and iTerm2 images, whose pixels are their cells';
// what an application gets wrong about them is an error.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart' show GraphicsProtocol;
import 'package:twk_test/vt.dart';

String b64(int n) => base64.encode(List.filled(n, 7));

/// kitty: image [id] of [n] bytes sent and placed at the cursor over
/// [cols] x [rows] cells as placement [p].
String kitty(int id, {int n = 12, int p = 1, int cols = 3, int rows = 2}) =>
    '\x1b_Ga=T,f=100,t=d,i=$id,p=$p,c=$cols,r=$rows,C=1,q=2;${b64(n)}\x1b\\';

/// A sixel image of [w] x [h] pixels.
String sixel(int w, int h) => '\x1bP0;1;0q"1;1;$w;$h#0;2;0;0;0#0~~~~-~~\x1b\\';

/// An iTerm2 image of [n] bytes over [cols] x [rows] cells.
String iterm2(int n, int cols, int rows, {bool stay = true}) =>
    '\x1b]1337;File=inline=1;size=$n;width=$cols;height=$rows;'
    'preserveAspectRatio=0${stay ? ';doNotMoveCursor=1' : ''}:${b64(n)}\x07';

Vt fed(String s, {int w = 10, int h = 6, bool strict = true}) =>
    Vt(w, h, strict: strict)..feed(utf8.encode(s));

List<String> shown(Vt vt) => [for (final i in vt.images) '$i'];

void main() {
  group('kitty', () {
    test('sent in chunks, placed, placed again by its id, deleted', () {
      final data = b64(9000);
      final vt = fed(
        '\x1b[2;3H\x1b_Ga=t,f=100,t=d,i=5,q=2,m=1;${data.substring(0, 4096)}'
        '\x1b\\\x1b_Gm=1;${data.substring(4096, 8192)}\x1b\\'
        '\x1b_Gm=0;${data.substring(8192)}\x1b\\'
        '\x1b_Ga=p,i=5,p=2,c=4,r=2,C=1,q=2\x1b\\',
      );
      expect(vt.kittyImages, {5: 9000});
      expect(shown(vt), ['kitty 5/2 4x2 at (2, 1), 9000 bytes']);
      expect((vt.cx, vt.cy), (2, 1), reason: 'C=1: the cursor stays');
      vt.feed(utf8.encode('\x1b[4;6H\x1b_Ga=p,i=5,p=2,c=4,r=2,C=1,q=2\x1b\\'));
      expect(shown(vt), ['kitty 5/2 4x2 at (5, 3), 9000 bytes']);
      vt.feed(utf8.encode('\x1b_Ga=d,d=i,i=5,p=2,q=2\x1b\\'));
      expect(shown(vt), isEmpty);
      expect(vt.kittyImages, {5: 9000});
      vt.feed(utf8.encode('\x1b_Ga=d,d=I,i=5,q=2\x1b\\'));
      expect(vt.kittyImages, isEmpty);
    });

    test('text printed or erased in its cells leaves it, ED 2 deletes it '
        'and frees the image', () {
      final vt = fed('\x1b[2;2H${kitty(1)}x\x1b[K');
      expect(shown(vt), ['kitty 1/1 3x2 at (1, 1), 12 bytes']);
      vt.feed(utf8.encode('\x1b[2J'));
      expect(shown(vt), isEmpty);
      expect(vt.kittyImages, isEmpty);
    });

    test('it scrolls with its rows, cut where they leave the region', () {
      final vt = fed('\x1b[3;2H${kitty(1)}\x1b[2;5r\x1b[S\x1b[r');
      expect(shown(vt), ['kitty 1/1 3x2 at (1, 1), 12 bytes']);
      vt.feed(utf8.encode('\x1b[2;5r\x1b[S\x1b[r'));
      expect(shown(vt), ['kitty 1/1 3x1 at (1, 1), 12 bytes']);
      vt.feed(utf8.encode('\x1b[2;5r\x1b[S\x1b[r'));
      expect(shown(vt), isEmpty);
    });

    test('what a presenter must not send is an error', () {
      Vt bad(String s) => fed(s, strict: false);
      expect(bad('\x1b_Ga=p,i=9,p=1,c=1,r=1,C=1,q=2\x1b\\').errors, [
        'a kitty placement of image 9, which the terminal lacks',
      ]);
      expect(
        bad('\x1b_Ga=T,f=100,i=1,p=1,c=1,r=1,q=2;${b64(3)}\x1b\\').errors,
        ['a kitty placement that moves the cursor (no C=1)'],
      );
      expect(bad('\x1b_Ga=t,f=100,i=1;${b64(3)}\x1b\\').errors, [
        'a kitty command the terminal answers (no q=2)',
      ]);
      expect(bad('\x1b_Ga=T,f=100,i=1,C=1,q=2;${b64(3)}\x1b\\').errors, [
        'a kitty placement not sized in cells (c, r)',
      ]);
      expect(bad('x${kitty(1, cols: 1, rows: 1)}').errors, isEmpty);
      expect(bad('\x1b[1;1Hx\x1b[1;1H${kitty(1)}').errors, [
        'kitty image over text',
      ]);
      expect(bad('\x1b[6;1H${kitty(1)}').errors, [
        'a kitty image of 3x2 cells at (0, 5) reaches past the screen',
      ]);
      // the probe's query, and a command without an id, keep nothing
      expect(
        fed('\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\\x1b_G\x07x\x1b\\')
            .kittyImages,
        isEmpty,
      );
    });
  });

  group('sixel', () {
    test('its pixels cover the cells they reach into; text takes them '
        'away', () {
      final vt = fed('\x1b[2;2H\x1b[?8452h${sixel(25, 30)}\x1b[?8452l');
      expect(shown(vt), [
        'sixel 3x2 at (1, 1), ${sixel(25, 30).length - 4} bytes',
      ]);
      expect((vt.cx, vt.cy), (4, 2), reason: '8452: right of its last row');
      vt.feed(utf8.encode('\x1b[2;3Hx\x1b[3;2H\x1b[2X'));
      expect(vt.images.single.cells, 3);
    });

    test('it moves the cursor below itself, past the last row an '
        'error', () {
      final vt = fed('\x1b[5;1H${sixel(10, 40)}', strict: false);
      expect(vt.errors, ['a sixel image scrolled the screen']);
      expect(fed('\x1b[2;1H${sixel(10, 40)}').cy, 3);
      expect(fed('\x1bP0;1;0q#0~\x1b\\', strict: false).errors, [
        'a sixel image without its size (raster attributes)',
      ]);
    });

    test('it scrolls with its cells', () {
      final vt = fed('\x1b[3;1H\x1b7\x1b[?8452h${sixel(20, 20)}\x1b8\x1b[S');
      expect(shown(vt).single, startsWith('sixel 2x1 at (0, 1)'));
    });
  });

  group('iTerm2', () {
    test('shown inline in cells; the cursor stays with doNotMoveCursor', () {
      final vt = fed('\x1b[2;3H${iterm2(40, 4, 2)}');
      expect(shown(vt), ['iterm2 4x2 at (2, 1), 40 bytes']);
      expect((vt.cx, vt.cy), (2, 1));
      expect(fed('\x1b[2;3H${iterm2(40, 4, 2, stay: false)}').cy, 3);
      // text over its top left cell: the rectangle is still around the rest
      final over = fed('\x1b[2;3H${iterm2(40, 4, 2)}x');
      expect(shown(over), ['iterm2 4x2 at (2, 1), 7 cells, 40 bytes']);
      expect(
        fed(
          '\x1b]1337;File=inline=1;size=9;width=2;height=1:${b64(3)}\x07',
          strict: false,
        ).errors,
        ['an iTerm2 file whose size is not that of its data'],
      );
      expect(
        fed(
          '\x1b]1337;File=inline=1;size=3;width=2;height=auto:${b64(3)}\x07',
          strict: false,
        ).errors,
        ['an iTerm2 file not shown inline in cells'],
      );
    });
  });

  test('DECSC and DECRC: the cursor and SGR come back', () {
    final vt = fed('\x1b[2;3H\x1b[1m\x1b7\x1b[0m\x1b[5;5H\x1b8x');
    expect((vt.cx, vt.cy), (3, 1));
    expect(vt.cell(2, 1).attrs, 1);
    expect(fed('\x1b8', strict: false).errors, ['DECRC without DECSC']);
  });

  test('what tmux passes through reaches the terminal outside', () {
    final wrapped =
        '\x1bPtmux;${kitty(3).replaceAll('\x1b', '\x1b\x1b')}\x1b\\';
    final vt = fed('\x1b[2;2H$wrapped');
    expect(shown(vt), ['kitty 3/1 3x2 at (1, 1), 12 bytes']);
    expect(vt.images.single.protocol, GraphicsProtocol.kitty);
  });

  test('the sizes asked in pixels or cells have no screen effect', () {
    expect(fed('\x1b[14t\x1b[16t\x1b[18t').errors, isEmpty);
  });
}
