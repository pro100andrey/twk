// A twk app in the browser: what xterm.js answered the probe, a button
// the mouse or Enter presses, the last input, a spinner; q quits. Built
// with dart2wasm next to index.html, which loads xterm.js:
//
//   dart compile wasm web/main.dart -o web/main.wasm
//   python3 -m http.server -d web 8080      # then http://localhost:8080
import 'package:twk/twk.dart';
import 'package:twk_web/twk_web.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final element = web.document.querySelector('#terminal')! as web.HTMLElement;
  await runWebApp(
    element,
    const Demo(),
    options: XtermOptions(
      fontFamily: 'ui-monospace, Menlo, Consolas, monospace',
      fontSize: 15,
    ),
  );
  element.textContent = 'The app quit. Reload the page to run it again.';
}

/// What the terminal is, a counter and the last input.
final class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

final class _DemoState extends State<Demo> {
  var _presses = 0;
  var _last = 'nothing yet';

  bool _onEvent(InputEvent event) {
    final what = switch (event) {
      KeyEvent(kind: KeyKind.release) => null,
      KeyEvent(:final code, :final char, :final modifiers) =>
        'key ${modifiers == 0 ? '' : 'mod $modifiers '}'
            '${code == KeyCode.char ? char : code.name}',
      MouseEvent(:final kind, :final x, :final y) => 'mouse ${kind.name} $x,$y',
      PasteEvent(:final text) => 'paste of ${text.length} characters',
      FocusEvent(:final focused) => focused ? 'focus in' : 'focus out',
      ResizeEvent(:final width, :final height) => 'resize to $width×$height',
      _ => null,
    };
    if (what != null) {
      setState(() => _last = what);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final binding = AppBinding.of(context);
    final terminal = binding.twkApp.terminal;
    final info = terminal.info;
    String yes(bool on) => on ? 'yes' : 'no';
    String rgb(int? color) => color == null
        ? 'not told'
        : '#${color.toRadixString(16).padLeft(6, '0')}';
    Widget row(String name, String value) =>
        Text.rich([name.padRight(14).dim, Span(value)]);
    return KeyBindings(
      {'q': binding.quit},
      child: InputListener(
        onEvent: _onEvent,
        child: Box(
          border: const .all(type: .rounded),
          titles: const [
            BorderTitle(' twk on xterm.js '),
            BorderTitle(' q: quit ', alignment: .bottomRight),
          ],
          padding: const .only(left: 2, right: 2, top: 1, bottom: 1),
          child: Column(
            crossAxisAlignment: .start,
            gap: 1,
            children: [
              Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: [
                  row('size', '${terminal.width}×${terminal.height}'),
                  row('answered', yes(info.answeredQueries)),
                  row('synchronized', yes(info.caps.synchronizedOutput)),
                  row('colors', info.colorMode.name),
                  row('background', rgb(info.backgroundRgb)),
                  row('kitty keys', yes(info.kittyKeyboard)),
                ],
              ),
              Row(
                gap: 2,
                children: [
                  Button(
                    'Press',
                    autofocus: true,
                    onPressed: () => setState(() => _presses++),
                  ),
                  Text('pressed $_presses times'),
                ],
              ),
              Row(
                gap: 1,
                children: [
                  const Spinner(),
                  Text.rich(['last input '.dim, Span(_last)]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
