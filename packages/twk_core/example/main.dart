// The smallest app on the core alone: a render tree on the terminal's
// alternate screen, a counter Space moves on, q to quit. The widgets of
// package:twk build such a tree for you; chat_demo.dart beside this is a
// larger one, fullscreen or inline.
//
//   dart run example/main.dart
import 'package:twk_core/twk_core.dart';

Future<void> main() async {
  final app = TwkApp(await Terminal.open());
  final styles = app.screen.styles;
  final hint = styles.pen(const Pen(fg: Color.brightBlack));
  final count = styles.pen(const Pen(fg: Color.green, attrs: Attr.bold));

  final label = RenderText('Pressed 0 times', count);
  final root = RenderBox(
    pen: styles.pen(const Pen()),
    padX: 2,
    padY: 1,
    child: RenderColumn(<(RenderObject, int?)>[
      (RenderText('Space counts, q quits', hint), 1),
      (label, 1),
    ]),
  );

  var pressed = 0;
  await app.run(root, (event) {
    if (event is! KeyEvent) {
      return;
    }
    if (event.char == 'q') {
      app.quit();
    } else if (event.char == ' ') {
      label.text = 'Pressed ${++pressed} times';
    }
  });
}
