// The gallery in a browser, on xterm.js (twk_web). Built with dart2wasm
// next to index.html, which loads xterm.js:
//
//   dart compile wasm web/main.dart -o web/main.wasm
//   python3 -m http.server -d web 8080      # then http://localhost:8080
//
// The page's URL hash is the route it opens at (README.md, "Routes"):
// http://localhost:8080/#/controls/button?theme=light.
import 'package:gallery/gallery.dart';
import 'package:gallery/src/shell/tokens.dart' show galleryThemes;
import 'package:twk/twk.dart';
import 'package:twk_web/twk_web.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final element = web.document.querySelector('#terminal')! as web.HTMLElement;
  final hash = web.window.location.hash;
  final route = hash.isEmpty ? null : GalleryRoute.parse(hash);
  // the terminal's own colors the route's theme's, so that the cells the
  // grid leaves at the edges and the page around it are of a piece with it
  final theme = (galleryThemes[route?.theme] ?? galleryThemes['dark']!).$2;
  final background = _css(theme.background.bg, '#000000');
  web.document.body!.style.background = background;
  await runWebApp(
    element,
    galleryApp(route: route),
    options: XtermOptions(
      fontFamily: 'ui-monospace, Menlo, Consolas, monospace',
      fontSize: 15,
      theme: XtermTheme(
        background: background,
        foreground: _css(theme.text.fg, '#ffffff'),
      ),
    ),
  );
  element.textContent = 'The gallery quit. Reload the page to run it again.';
}

/// [color] as CSS writes it, [fallback] where it is not a 24-bit one.
String _css(Color? color, String fallback) {
  final v = color?.value ?? 0;
  return v & 0x1000000 == 0
      ? fallback
      : '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}
