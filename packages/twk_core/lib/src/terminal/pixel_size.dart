/// A terminal's pixel size from the tty (`TIOCGWINSZ`), through libc via
/// `dart:ffi` only, on Linux and macOS.
library;

import 'dart:ffi';
import 'dart:io';

import '../platform/libc.dart' as c;

/// TIOCGWINSZ, for [c.ioctl]: the tty's `struct winsize`.
final _tiocgwinsz = Platform.isMacOS ? 0x40087468 : 0x5413;

/// A cell's size in pixels, as the tty of this process says (the window's
/// `ws_xpixel` and `ws_ypixel` over its columns and rows): null where the
/// platform has no such call, the descriptors are no terminal or the
/// terminal reports no pixels (zeros: many do not; the Linux console, a
/// pseudo-terminal nobody sized).
({int width, int height})? ttyCellPixelSize() {
  if (!(Platform.isLinux || Platform.isAndroid || Platform.isMacOS)) {
    return null;
  }
  final ws = c.calloc(1, 4 * sizeOf<Uint16>());
  if (ws == nullptr) {
    return null;
  }
  try {
    final p = ws.cast<Uint16>();
    // stdout, then stdin and stderr: whichever is the terminal
    for (final fd in const [1, 0, 2]) {
      if (c.ioctl(fd, _tiocgwinsz, ws) != 0) {
        continue;
      }
      final rows = p[0];
      final cols = p[1];
      final w = cols > 0 ? p[2] ~/ cols : 0;
      final h = rows > 0 ? p[3] ~/ rows : 0;
      if (w > 0 && h > 0) {
        return (width: w, height: h);
      }
    }
    return null;
  } finally {
    c.free(ws);
  }
}
