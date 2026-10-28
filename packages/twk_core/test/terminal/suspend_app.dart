// An app that hands the terminal to other programs and takes it back, for
// runs in a real terminal and the end to end checks in a pseudo-terminal:
// s runs a shell command that reads a line (`read x`) after half a second,
// so what is typed before is the command's too; Ctrl+Z stops the app for
// the shell it was started from (`fg` brings it back); t sends the app
// SIGTERM; q, Esc or Ctrl+C quits, as does --seconds. --stop-after=S
// stops it for the shell after S seconds, --inline runs it in the inline
// mode. The size it last drew at and how often it handed the terminal
// over go to stderr at the end; it exits with status 1 if it drew nothing
// after taking the terminal back, or if the size it last drew at isn't
// the terminal's. suspend_pty_test.dart runs it in a pseudo-terminal.
//
//   dart run test/terminal/suspend_app.dart
//   python3 tool/pty_run.py --suspended 'suspended> ' \
//       --input '1:s,@0.2:hello\r,@1.5:q' --out /tmp/suspend.bin -- \
//       dart run test/terminal/suspend_app.dart
//   dart run tool/replay.dart --fullscreen /tmp/suspend.bin 100 30
import 'dart:async';
import 'dart:io';

import 'package:twk_core/twk_core.dart';

const _command = r'printf "suspended> "; sleep 0.5; read x; echo "got $x"';

/// Rows of text, asking for as many rows as there are.
final class _Rows extends RenderObject {
  _Rows(this.pen);
  final int pen;
  var _rows = <String>[];

  void show(List<String> rows) {
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
    ctx.canvas.fill(0, 0, width, height, pen);
    for (var i = 0; i < _rows.length; i++) {
      ctx.canvas.text(0, i, _rows[i], pen);
    }
  }
}

double? _option(List<String> args, String name) => args
    .where((a) => a.startsWith('--$name='))
    .map((a) => double.parse(a.substring(name.length + 3)))
    .firstOrNull;

Future<void> main(List<String> args) async {
  final seconds = _option(args, 'seconds');
  final stopAfter = _option(args, 'stop-after');
  final inline = args.contains('--inline');

  final Terminal terminal;
  try {
    terminal = await Terminal.open(
      TerminalOptions(alternateScreen: !inline),
    );
  } on TerminalException catch (e) {
    stderr.writeln('suspend_app: $e (run it in a terminal)');
    exitCode = 2;
    return;
  }
  final app = TwkApp(terminal);
  final rows = _Rows(app.screen.styles.pen(const Pen()));
  var handedOver = 0;
  var last = 'none yet';
  var framesBack = 0; // frames drawn when the terminal was last taken back
  void update() => rows.show([
    'suspend app ${terminal.width}x${terminal.height}',
    'handed over $handedOver times, last: $last',
    's: sh  ctrl+z: shell  t: SIGTERM  q: quit',
  ]);

  Future<void> shell() async {
    final code = await app.suspend(() async {
      final p = await Process.start('sh', [
        '-c',
        _command,
      ], mode: ProcessStartMode.inheritStdio);
      return p.exitCode;
    });
    handedOver++;
    last = 'sh exit $code';
    framesBack = app.stats.frames;
    update();
  }

  Future<void> stop() async {
    await app.suspendToShell();
    handedOver++;
    last = 'fg';
    framesBack = app.stats.frames;
    update();
  }

  update();
  final quitTimer = seconds == null
      ? null
      : Timer(Duration(milliseconds: (seconds * 1000).round()), app.quit);
  final stopTimer = stopAfter == null
      ? null
      : Timer(Duration(milliseconds: (stopAfter * 1000).round()), stop);
  try {
    await app.run(rows, (e) {
      switch (e) {
        case ResizeEvent():
          update();
        case KeyEvent(code: KeyCode.escape) ||
            KeyEvent(code: KeyCode.char, char: 'c', ctrl: true) ||
            KeyEvent(code: KeyCode.char, char: 'q', modifiers: 0):
          app.quit();
        case KeyEvent(code: KeyCode.char, char: 'z', ctrl: true):
          unawaited(stop());
        case KeyEvent(code: KeyCode.char, char: 's', modifiers: 0):
          unawaited(shell());
        case KeyEvent(code: KeyCode.char, char: 't', modifiers: 0):
          Process.killPid(pid);
        default:
      }
    });
  } finally {
    quitTimer?.cancel();
    stopTimer?.cancel();
  }
  stderr.writeln(
    'drew at ${terminal.width}x${terminal.height}, '
    'handed over $handedOver times',
  );
  if (handedOver > 0 && app.stats.frames == framesBack) {
    stderr.writeln('nothing drawn after the terminal was taken back');
    exitCode = 1;
  }
  if (terminal.width != stdout.terminalColumns ||
      terminal.height != stdout.terminalLines) {
    stderr.writeln('a resize was missed');
    exitCode = 1;
  }
}
