// An app of package:twk in a fixed viewport of the normal screen, for the
// runs in a pseudo-terminal of viewport_test.dart and the end to end check:
// a box of 30 x 5 cells from column 10 of row 3 that shows the order its
// text is drawn in, the last press of the mouse in it (in its own cells)
// and the keys typed; the rest of the screen stays as it was. q quits.
// --bidi=app or --bidi=terminal says who orders right-to-left text.
//
//   python3 tool/pty_run.py --when 'pressed nothing' --when 'at 2, 1' \
//       --input '#1:\x1b[<0;13;5M\x1b[<0;13;5m,#2:q' \
//       --out /tmp/viewport.bin -- \
//       dart run packages/twk/test/binding/viewport_app.dart
//   dart run tool/replay.dart --inline --viewport=10,3,30,5 \
//       /tmp/viewport.bin 100 30
// the libraries of twk it runs on, not all of twk: it compiles in about
// 60 % of the time
import 'package:twk/src/binding/binding.dart';
import 'package:twk/src/framework/framework.dart';
import 'package:twk/src/gestures/gestures.dart';
import 'package:twk/src/layout/layout.dart';
import 'package:twk/src/text/text.dart';
import 'package:twk_core/twk_core.dart';

Future<void> main(List<String> args) async {
  BidiReordering? bidi;
  for (final a in args) {
    if (a.startsWith('--bidi=')) {
      bidi = BidiReordering.values.byName(a.substring('--bidi='.length));
    }
  }
  await runApp(
    const _Panel(),
    mode: ScreenMode.inline,
    viewport: const Viewport.fixed(10, 3, 30, 5),
    bidi: bidi,
  );
}

final class _Panel extends StatefulWidget {
  const _Panel();

  @override
  State<_Panel> createState() => _PanelState();
}

final class _PanelState extends State<_Panel> {
  var _pressed = 'nothing';
  var _typed = '';

  bool _onEvent(InputEvent event) {
    switch (event) {
      case KeyEvent(code: KeyCode.char, char: 'q', kind: KeyKind.press):
        AppBinding.of(context).quit();
      case KeyEvent(code: KeyCode.char, :final char, kind: KeyKind.press):
        setState(() => _typed += char);
      default:
        return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final order = AppBinding.of(context).textOrder.name;
    return InputListener(
      onEvent: _onEvent,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onDown: (e) => setState(() => _pressed = 'at ${e.x}, ${e.y}'),
        child: Box(
          border: const Border.all(type: BorderType.rounded),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('text in $order order'),
              Text('pressed $_pressed'),
              Text('> $_typed'),
            ],
          ),
        ),
      ),
    );
  }
}
