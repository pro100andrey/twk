// A small app in the inline mode, for runs in a real terminal and the end
// to end check in a pseudo-terminal: steps appear under a spinner one by
// one in a region of at most 8 rows below what the shell printed; every
// ten steps they are committed to the terminal's history above the region,
// which shrinks. Any key typed shows on the last line; q, Esc or Ctrl+C
// quits, as does --seconds. The region stays on the screen afterwards.
//
//   dart run test/inline/inline_demo.dart
//   python3 tool/pty_run.py --input none --out /tmp/inline.bin -- sh -c \
//       'printf "history 1\nhistory 2\n"; exec dart run test/inline/inline_demo.dart --seconds=3'
//   dart run tool/replay.dart --inline /tmp/inline.bin 100 30
import 'dart:async';
import 'dart:io';

import 'package:twk_core/twk_core.dart';

const _spinner = <String>['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧'];

/// Rows of text, each with its pen, asking for as many rows as it has.
final class _Rows extends RenderObject {
  _Rows(this.background);
  final int background;
  var _rows = <(String, int)>[];

  void show(List<(String, int)> rows) {
    _rows = rows;
    markNeedsLayout();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  int computeMaxIntrinsicHeight(int width) => _rows.length;

  @override
  void paint(PaintContext ctx) {
    ctx.canvas.fill(0, 0, width, height, background);
    for (var i = 0; i < _rows.length; i++) {
      ctx.canvas.text(0, i, _rows[i].$1, _rows[i].$2);
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
      const TerminalOptions(alternateScreen: false),
    );
  } on TerminalException catch (e) {
    stderr.writeln('inline_demo: $e (run it in a terminal)');
    exitCode = 2;
    return;
  }
  final app = TwkApp(terminal, maxInlineRows: 8);
  final t = app.screen.styles;
  final header = t.pen(
    const Pen(fg: Color.rgb(90, 200, 255), attrs: Attr.bold),
  );
  const donePen = Pen(fg: Color.rgb(90, 200, 120));
  final done = t.pen(donePen);
  const dim = Pen(fg: Color.rgb(150, 150, 160), attrs: Attr.dim);
  final plain = t.pen(const Pen());

  final rows = _Rows(plain);
  var tick = 0;
  var steps = 0;
  var committed = 0;
  var typed = '';
  String step(int i) => '  ✓ step ${committed + i} · 你好 · ok';
  void update() {
    rows.show([
      (
        '${_spinner[tick % _spinner.length]} working: '
            'step ${committed + steps + 1}',
        header,
      ),
      for (var i = 1; i <= steps; i++) (step(i), done),
      ('> $typed', plain),
    ]);
  }

  update();
  final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
    tick++;
    if (tick.isEven) {
      steps++;
      if (steps == 10) {
        // finished steps go to the history, the region shrinks to the rest
        app.commit(
          RenderParagraph([
            for (var i = 1; i <= steps; i++) ('${step(i)}\n', donePen),
            ('  $steps steps committed', dim),
          ]),
        );
        committed += steps;
        steps = 0;
        app.shrinkRegion();
      }
    }
    update();
  });
  final stop = seconds == null
      ? null
      : Timer(Duration(seconds: seconds), app.quit);
  try {
    await app.run(rows, (e) {
      switch (e) {
        case KeyEvent(code: KeyCode.escape) ||
            KeyEvent(code: KeyCode.char, char: 'c', ctrl: true) ||
            KeyEvent(code: KeyCode.char, char: 'q', modifiers: 0):
          app.quit();
        case KeyEvent(code: KeyCode.char, :final char, modifiers: 0):
          typed += char;
          update();
        default:
      }
    });
  } finally {
    ticker.cancel();
    stop?.cancel();
  }
}
