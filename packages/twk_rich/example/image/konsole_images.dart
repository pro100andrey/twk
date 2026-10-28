// What Konsole does with kitty images when the rows beside them scroll: a
// picture in a header, and below it a log that scrolls up in hardware
// (DECSTBM and SU) a line at a time, then down, then pictures that replace
// one another. Konsole moves every image up on any scroll up, the
// header's too; twk, told the terminal is Konsole (`konsoleImages`),
// places them again. The picture must stay in the header the whole time.
// Ends by itself ten seconds after the last picture, or at a key.
//
//   dart run example/image/konsole_images.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';
import 'package:twk_rich/image.dart';

/// A picture of [w] x [h] pixels: a gradient of hue [hue] (0 to 5), a
/// white frame and a white diagonal, so that a move or a cut shows.
Uint8List _picture(int w, int h, int hue) {
  final b = Bitmap(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final edge = x < 2 || y < 2 || x >= w - 2 || y >= h - 2;
      final diagonal = (x * h ~/ w - y).abs() < 2;
      final t = 255 * x ~/ w;
      final (r, g, bl) = switch (hue % 6) {
        0 => (255, t, 40),
        1 => (255 - t, 255, 40),
        2 => (40, 255, t),
        3 => (40, 255 - t, 255),
        4 => (t, 40, 255),
        _ => (255, 40, 255 - t),
      };
      b.setPixel(
        x,
        y,
        edge || diagonal ? 0xFFFFFFFF : 0xFF000000 | r << 16 | g << 8 | bl,
      );
    }
  }
  return encodePng(b);
}

Future<void> main() async {
  final term = await Terminal.open();
  final caps = term.info.caps;
  final screen = Screen(
    term.width,
    term.height,
    caps: caps,
    textMode: term.info.textMode,
    colorMode: term.info.colorMode,
  );
  final quit = Completer<void>();
  final keys = term.events.listen((e) {
    if (e is KeyEvent && !quit.isCompleted) {
      quit.complete();
    }
  });
  Future<bool> pause(int ms) async {
    await Future.any([
      quit.future,
      Future<void>.delayed(Duration(milliseconds: ms)),
    ]);
    return quit.isCompleted;
  }

  void frame() {
    final bytes = screen.render();
    if (bytes != null) {
      term.write(bytes);
    }
  }

  const cols = 8;
  const rows = 4;
  final cw = caps.cellPixelWidth == 0 ? 10 : caps.cellPixelWidth;
  final ch = caps.cellPixelHeight == 0 ? 20 : caps.cellPixelHeight;
  TerminalImage picture(int hue) => TerminalImage(
    GraphicsProtocol.kitty,
    _picture(cols * cw, rows * ch, hue),
    pixelWidth: cols * cw,
    pixelHeight: rows * ch,
  );
  final s = screen.styles;
  final header = s.pen(const Pen(bg: Color.blue, fg: Color.white));
  final text = s.pen(const Pen());
  final w = term.width;
  final h = term.height;
  final c = screen.canvas
    ..fill(0, 0, w, rows + 2, header)
    ..text(
      12,
      1,
      'graphics=${caps.graphics.name} konsoleImages=${caps.konsoleImages}',
      header,
    )
    ..text(12, 2, 'the picture stays here, framed and whole', header)
    ..text(12, 3, 'while the log below scrolls', header);
  var image = picture(0);
  c.image(2, 1, cols, rows, image);
  if (caps.graphics != GraphicsProtocol.kitty) {
    c.text(2, 1, 'no kitty', header);
  }
  const top = rows + 2;
  for (var y = top; y < h; y++) {
    c.text(0, y, 'log line ${y - top}', text);
  }
  frame();
  var line = h - top;
  var done = await pause(800);
  // the log scrolls up in hardware, a line at a time
  for (var k = 0; k < 40 && !done; k++, line++) {
    screen.surface.scrollRows(top, h, 1);
    c.text(0, h - 1, 'log line $line: scrolled up', text);
    frame();
    done = await pause(120);
  }
  // and down
  for (var k = 0; k < 10 && !done; k++) {
    screen.surface.scrollRows(top, h, -1);
    c.text(0, top, 'log line ${top + k}: scrolled down', text);
    frame();
    done = await pause(120);
  }
  // pictures replacing one another, each under the id of the one before
  for (var k = 1; k <= 12 && !done; k++) {
    image = picture(k);
    c.image(2, 1, cols, rows, image);
    frame();
    done = await pause(250);
  }
  if (!done) {
    c.text(12, 4, 'done: press a key', header);
    frame();
    await pause(10000);
  }
  await keys.cancel();
  final leave = screen.leave();
  if (leave != null) {
    term.write(leave);
  }
  await term.close();
}
