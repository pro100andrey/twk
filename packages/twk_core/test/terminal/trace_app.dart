// Shows what is typed until q, for trace_test.dart, which runs it in a
// pseudo-terminal (tool/pty_run.py) with TWK_TRACE_INPUT and
// TWK_TRACE_OUTPUT set.
import 'package:twk_core/twk_core.dart';

Future<void> main() async {
  final terminal = await Terminal.open();
  final app = TwkApp(terminal);
  final pen = app.screen.styles.pen(const Pen(fg: Color.rgb(200, 200, 0)));
  final line = RenderText('typed: ', pen);
  var quitting = false;
  await app.run(
    line,
    (e) {
      if (e is KeyEvent && e.code == KeyCode.char) {
        if (e.char == 'q') {
          // after one more frame: what came with the q is shown, also on
          // a machine so slow that it came in the same read
          quitting = true;
          app.requestFrame();
        } else {
          line.text = '${line.text}${e.char}';
        }
      }
    },
    afterPresent: () {
      if (quitting) {
        app.quit();
      }
    },
  );
}
