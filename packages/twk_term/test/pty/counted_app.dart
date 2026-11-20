// Draws three frames in the screen mode of its first argument
// (`fullscreen`, `inline` or `plain`), then ends and writes how many bytes
// its terminal counted as written ([CountingBackend.bytesWritten]) to the
// file of its second: what counted_bytes_test.dart compares with what a
// pseudo-terminal received.
import 'dart:io';

import 'package:twk_core/twk_core.dart';

/// Rows of text that change from frame to frame.
final class _Rows extends RenderObject {
  _Rows(this.pen);
  final int pen;
  var step = 0;

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxWidth;
    height = c.maxHeight;
  }

  @override
  int computeMaxIntrinsicHeight(int width) => 3;

  @override
  void paint(PaintContext ctx) {
    ctx.canvas.fill(0, 0, width, height, pen);
    for (var y = 0; y < 3 && y < height; y++) {
      ctx.canvas.text(0, y, 'row $y of step $step', pen);
    }
  }
}

Future<void> main(List<String> args) async {
  final mode = args[0];
  final terminal = await Terminal.open(
    TerminalOptions(
      alternateScreen: mode == 'fullscreen',
      plain: mode == 'plain' ? true : null,
      probeTimeout: const Duration(seconds: 5),
    ),
  );
  final app = TwkApp(terminal);
  final rows = _Rows(app.screen.styles.pen(const Pen()));
  await app.run(
    rows,
    (e) {},
    afterPresent: () {
      if (rows.step >= 2) {
        app.quit();
      } else {
        rows.step++;
        rows.markNeedsPaint();
        app.requestFrame();
      }
    },
  );
  File(args[1]).writeAsStringSync('${terminal.bytesWritten}');
}
