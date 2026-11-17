import 'package:twk_web/twk_web.dart';
import 'package:web/web.dart' as web;
import 'package:web_template/web_template.dart';

// web: the app in a browser, on xterm.js; built with dart2wasm next to
// index.html, which loads xterm.js:
//
//   dart compile wasm web/main.dart -o web/main.wasm
//   python3 -m http.server -d web 8080      # then http://localhost:8080
Future<void> main() async {
  final element = web.document.querySelector('#terminal')! as web.HTMLElement;
  await runWebApp(element, const Counter());
  element.textContent = 'The app quit. Reload the page to run it again.';
}
