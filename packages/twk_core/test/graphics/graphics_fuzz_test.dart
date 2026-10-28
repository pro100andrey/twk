// Random scenes with images among the text, scrolls and repaints of the
// presenter fuzz: after every frame the terminal shows each image the
// surface has where it is, over blanks, and every other cell as asked.
import 'dart:math';

import 'package:test/test.dart';
import 'package:twk_core/src/graphics.dart';
import 'package:twk_core/src/presenter.dart';

import '../presenter_fuzz_test.dart' show commitRandomRows;
import '../support/harness.dart';
import 'graphics_test.dart' show image, notBlank;

/// Shows an image of [pool] at a random place, over a random background,
/// cut by a clip now and then.
void randomImage(Harness hs, Random rnd, List<TerminalImage> pool) {
  final w = hs.surface.width;
  final h = hs.surface.height;
  final img = pool[rnd.nextInt(pool.length)];
  final cols = img.pixelWidth ~/ 10;
  final rows = img.pixelHeight ~/ 20;
  final x = rnd.nextInt(w + 2) - 2;
  final y = rnd.nextInt(h + 2) - 2;
  hs.canvas.save();
  if (rnd.nextInt(4) == 0) {
    hs.canvas.clipRect(0, 1, w, h - 2);
  }
  hs.canvas
    ..fill(x, y, cols, rows, hs.pens[rnd.nextInt(hs.pens.length)])
    ..image(x, y, cols, rows, img)
    ..restore();
}

/// The images of [protocol] on the surface of [hs] that the terminal can
/// show, and those it shows, both as (protocol, x, y, cols, rows) with the
/// rows counted from the region's first; fails where the cells of an image
/// are not blanks in the surface's styles.
(Set<(GraphicsProtocol, int, int, int, int)>, Set<Object>) images(
  Harness hs,
  GraphicsProtocol protocol,
  String where,
) {
  final want = <(GraphicsProtocol, int, int, int, int)>{};
  for (final p in hs.surface.images) {
    final cols = p.right - p.left;
    final rows = p.bottom - p.top;
    expect(
      notBlank(hs, p.left, p.top, cols, rows),
      isEmpty,
      reason: '$where: under $p',
    );
    if (p.image.protocol == protocol &&
        (p.whole || protocol == GraphicsProtocol.kitty)) {
      want.add((protocol, p.left, p.top, cols, rows));
    }
  }
  return (
    want,
    {
      for (final i in hs.vt.images)
        if (i.cells == i.cols * i.rows)
          (i.protocol, i.x, i.y - hs.top, i.cols, i.rows),
    },
  );
}

void main() {
  for (final (name, caps) in [
    ('kitty', const TerminalCaps(graphics: GraphicsProtocol.kitty)),
    (
      'kitty, left/right margins, REP',
      const TerminalCaps(
        graphics: GraphicsProtocol.kitty,
        leftRightMargins: true,
        repeatChar: true,
      ),
    ),
    ('sixel', const TerminalCaps(graphics: GraphicsProtocol.sixel)),
    (
      'sixel, no BCE, no synchronized output',
      const TerminalCaps(
        graphics: GraphicsProtocol.sixel,
        backgroundColorErase: false,
        synchronizedOutput: false,
      ),
    ),
    (
      'iTerm2, left/right margins',
      const TerminalCaps(
        graphics: GraphicsProtocol.iterm2,
        leftRightMargins: true,
      ),
    ),
    // Konsole moves its images itself (Vt.konsoleImages)
    (
      'kitty on Konsole',
      const TerminalCaps(
        graphics: GraphicsProtocol.kitty,
        konsoleImages: true,
        konsoleLines: true,
        repeatChar: true,
      ),
    ),
    (
      'sixel on Konsole',
      const TerminalCaps(
        graphics: GraphicsProtocol.sixel,
        konsoleImages: true,
        konsoleLines: true,
      ),
    ),
  ]) {
    test('presenter with images vs terminal emulator: $name', () {
      final protocol = caps.graphics;
      final pool = [
        for (final (c, r) in [(1, 1), (3, 2), (4, 3), (2, 4)])
          image(protocol, cols: c, rows: r, seed: c),
        image(
          protocol == GraphicsProtocol.kitty
              ? GraphicsProtocol.sixel
              : GraphicsProtocol.kitty,
          cols: 2,
        ),
      ];
      var drawn = 0;
      var scrolled = 0;
      for (var seed = 0; seed < 120; seed++) {
        final rnd = Random(seed);
        final w = 8 + rnd.nextInt(24);
        final h = 4 + rnd.nextInt(10);
        final hs = Harness(
          w,
          h,
          caps: caps,
          vtBce: caps.backgroundColorErase,
          vtKonsoleLines: caps.konsoleLines,
          vtKonsoleImages: caps.konsoleImages,
        );
        for (var f = 0; f < 25; f++) {
          for (var k = 1 + rnd.nextInt(4); k > 0; k--) {
            if (rnd.nextInt(3) == 0) {
              randomImage(hs, rnd, pool);
            } else if (rnd.nextInt(40) == 0) {
              hs.presenter.invalidate();
            } else {
              randomOp(hs, rnd);
            }
          }
          hs.frame();
          drawn += hs.presenter.stats.images;
          if (hs.presenter.stats.scrollOps > 0 &&
              hs.surface.images.isNotEmpty) {
            scrolled++;
          }
          final where = 'seed $seed frame $f';
          expect(hs.mismatches(), isEmpty, reason: where);
          final (want, shown) = images(hs, protocol, where);
          expect(shown, containsAll(want), reason: where);
          if (protocol == GraphicsProtocol.kitty) {
            expect(hs.vt.images, hasLength(want.length), reason: where);
            expect(
              hs.vt.kittyImages.length,
              // Konsole keeps them all, under ids taken again
              lessThanOrEqualTo(caps.konsoleImages ? 4 : want.length),
              reason: '$where: images no placement shows are freed',
            );
          }
        }
      }
      expect(drawn, greaterThan(500));
      expect(scrolled, greaterThan(20));
      printOnFailure('$drawn drawn, $scrolled frames scrolled with images');
    });
  }

  for (final (protocol, konsole) in [
    (GraphicsProtocol.kitty, false),
    (GraphicsProtocol.sixel, false),
    (GraphicsProtocol.kitty, true),
    (GraphicsProtocol.sixel, true),
  ]) {
    test('an inline region with images vs terminal emulator: '
        '${protocol.name}${konsole ? ' on Konsole' : ''}', () {
      final pool = [
        for (final (c, r) in [(1, 1), (3, 2), (2, 3)])
          image(protocol, cols: c, rows: r, seed: c),
      ];
      var drawn = 0;
      var committed = 0;
      for (var seed = 0; seed < 100; seed++) {
        final rnd = Random(seed);
        final w = 6 + rnd.nextInt(20);
        final screenH = 3 + rnd.nextInt(8);
        final hs = Harness.inline(
          w,
          1 + rnd.nextInt(screenH),
          screenHeight: screenH,
          history: ['h ${rnd.nextInt(99)}'],
          caps: TerminalCaps(graphics: protocol, konsoleImages: konsole),
          vtKonsoleImages: konsole,
        );
        for (var f = 0; f < 25; f++) {
          if (rnd.nextInt(6) == 0) {
            hs.resizeRegion(1 + rnd.nextInt(screenH));
          }
          for (var k = rnd.nextInt(5); k > 0; k--) {
            if (rnd.nextInt(3) == 0) {
              randomImage(hs, rnd, pool);
            } else {
              randomOp(hs, rnd);
            }
          }
          if (rnd.nextInt(5) == 0) {
            commitRandomRows(hs, rnd, 3);
          }
          hs.presenter.screenHeight = screenH;
          hs.frame();
          drawn += hs.presenter.stats.images;
          committed += hs.presenter.stats.committedRows;
          final where = 'seed $seed frame $f';
          expect(
            [...hs.mismatches(), ...hs.historyChanges()],
            isEmpty,
            reason: where,
          );
          final (want, shown) = images(hs, protocol, where);
          expect(shown, containsAll(want), reason: where);
        }
      }
      expect(drawn, greaterThan(200));
      expect(committed, greaterThan(200));
    });
  }
}
