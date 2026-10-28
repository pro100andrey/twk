// Images on Konsole (TerminalCaps.konsoleImages), against the emulator's
// Konsole images (Vt.konsoleImages): Konsole keeps its images apart from
// the rows, moves all of them up on every scroll up, the scrolled rows or
// not, and none on a scroll down, and keeps a deleted kitty image's data
// until an image sent under its id replaces it. The presenter places every
// kitty image again after a scroll, scrolls no rows in hardware while a
// sixel or iTerm2 image is shown, and gives a new kitty image the id of
// one it deleted.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/src/graphics.dart';
import 'package:twk_core/src/presenter.dart';

import '../support/harness.dart';
import 'graphics_test.dart' show image, notBlank, shown;

/// A screen of 20 x 8 on Konsole, the presenter told it is
/// ([TerminalCaps.konsoleImages]) or not.
Harness konsole(GraphicsProtocol protocol, {required bool told}) => Harness(
  20,
  8,
  caps: TerminalCaps(graphics: protocol, konsoleImages: told),
  vtKonsoleImages: true,
);

/// A header of rows 0 and 1 with [img] at (2, 0), and a list in rows 2 to
/// 7, each row's text from [first] on.
void paint(Harness hs, TerminalImage img, {int first = 0}) {
  final c = hs.canvas
    ..fill(0, 0, 20, 2, hs.pens[3])
    ..image(2, 0, 4, 2, img);
  for (var r = 2; r < 8; r++) {
    c.text(0, r, 'item ${first + r - 2}'.padRight(20), hs.pens[1]);
  }
}

String out(Harness hs) => latin1.decode(hs.presenter.out.view);

void main() {
  for (final told in [true, false]) {
    test('kitty: the list below the header scrolls up in hardware, and the '
        'image in the header stays where it is${told ? '' : ' (not told: '
                  'Konsole moves it up)'}', () {
      final hs = konsole(GraphicsProtocol.kitty, told: told);
      final img = image(GraphicsProtocol.kitty);
      paint(hs, img);
      hs.frame();
      expect(shown(hs), ['kitty 4x2 at (2, 0)']);
      hs.surface.scrollRows(2, 8, 1);
      paint(hs, img, first: 1);
      hs.frame();
      expect(hs.presenter.stats.scrollOps, 1);
      expect(hs.mismatches(), isEmpty);
      if (told) {
        expect(out(hs), contains('a=p,i=1,p=1,c=4,r=2'));
        expect(shown(hs), ['kitty 4x2 at (2, 0)']);
      } else {
        expect(shown(hs), ['kitty 4x1 at (2, 0)']);
      }
    });
  }

  test('kitty: an image in the rows a scroll down moves is placed again; '
      'one above them stays', () {
    final hs = konsole(GraphicsProtocol.kitty, told: true);
    final a = image(GraphicsProtocol.kitty);
    final b = image(GraphicsProtocol.kitty, seed: 3);
    paint(hs, a);
    hs.canvas.image(10, 3, 4, 2, b);
    hs.frame();
    hs.surface.scrollRows(2, 8, -1);
    hs.canvas.text(0, 2, 'item -1'.padRight(20), hs.pens[1]);
    hs.frame();
    expect(hs.presenter.stats.scrollOps, 1);
    expect(shown(hs), ['kitty 4x2 at (2, 0)', 'kitty 4x2 at (10, 4)']);
    expect(hs.mismatches(), isEmpty);
  });

  for (final told in [true, false]) {
    test('inline: a scroll of the region moves no image of it out of its '
        'cells${told ? '' : ' (not told: the DL moves the one above up)'}', () {
      final hs = Harness.inline(
        20,
        6,
        screenHeight: 10,
        history: [r'$ run'],
        caps: TerminalCaps(
          graphics: GraphicsProtocol.kitty,
          konsoleImages: told,
        ),
        vtKonsoleImages: true,
      );
      final img = image(GraphicsProtocol.kitty);
      hs.canvas.image(2, 0, 4, 2, img);
      for (var r = 2; r < 6; r++) {
        hs.canvas.text(0, r, 'line $r', hs.pens[1]);
      }
      hs.frame();
      hs.surface.scrollRows(2, 6, 1);
      hs.canvas.text(0, 5, 'line 6', hs.pens[1]);
      hs.frame();
      expect(hs.presenter.stats.scrollOps, 1);
      expect(hs.mismatches(), isEmpty);
      final i = hs.vt.images.single;
      expect((i.x, i.y - hs.top, i.rows), (2, told ? 0 : -1, 2));
    });
  }

  for (final protocol in [GraphicsProtocol.sixel, GraphicsProtocol.iterm2]) {
    for (final told in [true, false]) {
      test('${protocol.name}: with an image shown no rows scroll in '
          'hardware${told ? '' : ' (not told: Konsole moves it up)'}', () {
        final hs = konsole(protocol, told: told);
        final img = image(protocol);
        paint(hs, img);
        hs.frame();
        hs.surface.scrollRows(2, 8, 1);
        paint(hs, img, first: 1);
        hs.frame();
        expect(hs.mismatches(), isEmpty);
        if (told) {
          expect(hs.presenter.stats.scrollOps, 0);
          expect(shown(hs), ['${protocol.name} 4x2 at (2, 0)']);
          expect(notBlank(hs, 2, 0, 4, 2), isEmpty);
        } else {
          expect(hs.presenter.stats.scrollOps, 1);
          expect(shown(hs), ['${protocol.name} 4x1 at (2, 0)']);
        }
      });
    }
  }

  for (final told in [true, false]) {
    test('kitty: images shown one after another take the id of the one '
        'deleted, which Konsole keeps the data of${told ? '' : ' (not told: '
                  'it keeps every image)'}', () {
      final hs = konsole(GraphicsProtocol.kitty, told: told);
      for (var k = 0; k < 5; k++) {
        paint(hs, image(GraphicsProtocol.kitty, bytes: 60 + k, seed: k));
        hs.frame();
        expect(hs.vt.images.single.bytes, 60 + k);
      }
      expect(hs.mismatches(), isEmpty);
      expect(hs.vt.kittyImages.length, told ? 1 : 5);
    });
  }

  test('kitty: the ids of the images deleted on leaving the screen are '
      'those of the images shown on coming back', () {
    final hs = konsole(GraphicsProtocol.kitty, told: true);
    paint(hs, image(GraphicsProtocol.kitty));
    hs.canvas.image(10, 4, 4, 2, image(GraphicsProtocol.kitty, seed: 1));
    hs.frame();
    expect(hs.vt.kittyImages.keys, {1, 2});
    hs.presenter.leave();
    hs.vt.feed(hs.presenter.out.view);
    expect(hs.vt.images, isEmpty);
    hs.presenter.invalidate();
    paint(hs, image(GraphicsProtocol.kitty, seed: 2));
    hs.canvas.image(10, 4, 4, 2, image(GraphicsProtocol.kitty, seed: 3));
    hs.frame();
    expect(hs.vt.images, hasLength(2));
    expect(hs.vt.kittyImages.keys, {1, 2});
    expect(hs.mismatches(), isEmpty);
  });
}
