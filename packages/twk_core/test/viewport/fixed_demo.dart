// A small app in a fixed viewport, for runs in a real terminal and the
// end to end check in a pseudo-terminal: a box of 36 x 7 cells from
// column 10 of row 3 of the normal screen, with a spinner, a counter, the
// last mouse event (relative to the box) and the keys typed; the rest of
// the screen stays as it was. q, Esc or Ctrl+C quits, as does --seconds.
// The box stays on the screen afterwards, the cursor where it was.
//
//   dart run test/viewport/fixed_demo.dart
//   python3 tool/pty_run.py --input none --out /tmp/fixed.bin -- \
//       dart run test/viewport/fixed_demo.dart --seconds=3
//   dart run tool/replay.dart --inline --viewport=10,3,36,7 \
//       /tmp/fixed.bin 100 30
import 'dart:async';
import 'dart:io';

import 'package:twk_core/twk_core.dart';

const _spinner = <String>['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧'];

/// A frame around rows of text, each with its pen.
final class _Box extends RenderObject {
  _Box(this.border);
  final int border;
  var _rows = <(String, int)>[];

  void show(List<(String, int)> rows) {
    _rows = rows;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    final cv = ctx.canvas..fill(0, 0, width, height, border);
    if (width < 2 || height < 2) {
      return;
    }
    cv
      ..text(0, 0, '┌${'─' * (width - 2)}┐', border)
      ..text(0, height - 1, '└${'─' * (width - 2)}┘', border);
    for (var y = 1; y < height - 1; y++) {
      cv
        ..text(0, y, '│', border)
        ..text(width - 1, y, '│', border);
    }
    for (var i = 0; i < _rows.length && i + 1 < height - 1; i++) {
      cv
        ..save()
        ..clipRect(1, 1, width - 2, height - 2)
        ..text(2, i + 1, _rows[i].$1, _rows[i].$2)
        ..restore();
    }
  }
}

Future<void> main(List<String> args) async {
  final seconds = args
      .where((a) => a.startsWith('--seconds='))
      .map((a) => int.parse(a.substring(10)))
      .firstOrNull;

  final Terminal terminal;
  try {
    terminal = await Terminal.open(
      const TerminalOptions(alternateScreen: false, normalScreenMouse: true),
    );
  } on TerminalException catch (e) {
    stderr.writeln('fixed_demo: $e (run it in a terminal)');
    exitCode = 2;
    return;
  }
  final app = TwkApp(terminal, viewport: const Viewport.fixed(10, 3, 36, 7));
  final t = app.screen.styles;
  final border = t.pen(
    const Pen(fg: Color.rgb(90, 200, 255), bg: Color.rgb(20, 24, 34)),
  );
  final header = t.pen(
    const Pen(
      fg: Color.rgb(255, 200, 90),
      bg: Color.rgb(20, 24, 34),
      attrs: Attr.bold,
    ),
  );
  final text = t.pen(
    const Pen(fg: Color.rgb(220, 220, 220), bg: Color.rgb(20, 24, 34)),
  );

  final box = _Box(border);
  var tick = 0;
  var typed = '';
  var pointer = 'no mouse event yet';
  void update() {
    box.show([
      ('${_spinner[tick % _spinner.length]} a fixed viewport', header),
      ('frames: ${app.stats.frames} · 你好 · ok', text),
      (pointer, text),
      ('> $typed', text),
    ]);
  }

  update();
  final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
    tick++;
    update();
  });
  final stop = seconds == null
      ? null
      : Timer(Duration(seconds: seconds), app.quit);
  try {
    await app.run(box, (e) {
      switch (e) {
        case KeyEvent(code: KeyCode.escape) ||
            KeyEvent(code: KeyCode.char, char: 'c', ctrl: true) ||
            KeyEvent(code: KeyCode.char, char: 'q', modifiers: 0):
          app.quit();
        case KeyEvent(code: KeyCode.char, :final char, modifiers: 0):
          typed += char;
          update();
        case MouseEvent(:final kind, :final x, :final y):
          pointer = 'mouse ${kind.name} at $x, $y';
          update();
        default:
      }
    });
  } finally {
    ticker.cancel();
    stop?.cancel();
  }
}
