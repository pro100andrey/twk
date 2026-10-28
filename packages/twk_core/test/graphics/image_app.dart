// Opens the terminal and shows an image in the protocol TWK_GRAPHICS names,
// moves it with a scroll, takes it away and closes the terminal, for
// image_pty_test.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';

/// A PNG of one red pixel.
final Uint8List _png = base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIA'
  'X8jx0gAAAABJRU5ErkJggg==',
);

/// 40 x 36 red pixels as sixel.
final Uint8List _sixel = ascii.encode(
  '0;1;0q"1;1;40;36#1;2;100;0;0${'#1!40~-' * 6}',
);

Future<void> main() async {
  final term = await Terminal.open();
  final info = term.info;
  final screen = Screen(
    term.width,
    term.height,
    caps: info.caps,
    textMode: info.textMode,
    colorMode: info.colorMode,
  );
  final protocol = info.caps.graphics;
  final image = TerminalImage(
    protocol,
    Uint8List.fromList(protocol == GraphicsProtocol.sixel ? _sixel : _png),
    pixelWidth: 40,
    pixelHeight: 36,
  );
  final pen = screen.styles.pen(const Pen(bg: Color.blue));
  void frame() {
    final bytes = screen.render();
    if (bytes != null) {
      term.write(bytes);
    }
  }

  screen.canvas
    ..text(0, 0, 'an image in ${protocol.name}', 0)
    ..fill(2, 3, 4, 2, pen)
    ..image(2, 3, 4, 2, image);
  frame();
  await term.flush();
  screen.surface.scrollRows(1, term.height, 1);
  frame();
  await term.flush();
  screen.canvas.fill(0, 1, term.width, term.height - 1, 0);
  frame();
  final leave = screen.leave();
  if (leave != null) {
    term.write(leave);
  }
  await term.close();
}
