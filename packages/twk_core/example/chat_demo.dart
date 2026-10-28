// Live demo: an agent-chat screen on the retained render tree, fullscreen
// (the default) or in the inline mode.
//
//   dart run example/chat_demo.dart              # q / Esc / Ctrl+C to quit
//   dart run example/chat_demo.dart --seconds=5  # quit automatically
//   dart run example/chat_demo.dart --inline     # below the shell's history
//   dart run example/chat_demo.dart --editor=nano
//
// Fullscreen, the log fills the alternate screen above the input and status
// lines. With --inline the header, input and status lines are a region of
// the normal screen, and every finished line is committed to the
// terminal's history above it, where the terminal scrolls and selects it.
//
// Keys: type + Enter adds a line; Ctrl+E hands the terminal to an editor
// on a file holding the input, and the lines it leaves there come back as
// the input, joined (the editor is --editor, else $EDITOR, else vi, run by
// `sh -c '<editor> "$1"'` as git runs it; on Windows by cmd, else notepad);
// Ctrl+Y copies the input (OSC 52); fullscreen, Up/Down/PgUp/PgDn or the
// mouse wheel scroll the log. The status bar shows the cost of the last
// frame. print() in the handlers goes to the app's log (with TWK_LOG=path
// also to that file as it comes), written to stderr after exit with the
// frame stats.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:twk_core/twk_core.dart';

const _spinner = <String>['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧'];

const _phrases = <String>[
  'tool: ran 412 tests ✓ all passed',
  'assistant: the presenter diffs only damaged spans',
  'user: проверь прокрутку и ширину эмодзи 🧪',
  'tool: compiled 87 files · 你好 · 0 warnings',
  'assistant: hardware scroll moved the log by one row',
  'tool: grapheme clusters 👨‍👩‍👧 and flags 🇺🇦 are one cell each',
];

const _user = Pen(fg: Color.rgb(80, 160, 255));
const _tool = Pen(
  fg: Color.rgb(90, 200, 120),
  link: 'file:///tmp/twk_core_build.log',
);

/// A line of the terminal's history: in its own colors, but for user and
/// tool lines.
Pen _penOf(String line) => line.startsWith('user')
    ? _user
    : (line.startsWith('tool') ? _tool : const Pen());

Future<void> main(List<String> args) async {
  final seconds = args
      .where((a) => a.startsWith('--seconds='))
      .map((a) => int.parse(a.substring(10)))
      .firstOrNull;
  final inline = args.contains('--inline');
  final editor =
      args
          .where((a) => a.startsWith('--editor='))
          .map((a) => a.substring(9))
          .firstOrNull ??
      Platform.environment['EDITOR'] ??
      (Platform.isWindows ? 'notepad' : 'vi');

  final Terminal terminal;
  try {
    terminal = await Terminal.open(TerminalOptions(alternateScreen: !inline));
  } on TerminalException catch (e) {
    stderr.writeln('chat_demo: $e (run it in a terminal)');
    exitCode = 2;
    return;
  }
  final app = TwkApp(terminal);
  final t = app.screen.styles;

  final bg = t.pen(
    const Pen(bg: Color.rgb(16, 18, 24), fg: Color.rgb(200, 200, 200)),
  );

  final header = t.pen(
    const Pen(fg: .rgb(255, 255, 255), bg: .rgb(0, 90, 180), attrs: Attr.bold),
  );
  final headerDim = t.pen(
    const Pen(fg: Color.rgb(200, 220, 255), bg: Color.rgb(0, 90, 180)),
  );
  final input = t.pen(
    const Pen(
      fg: Color.rgb(255, 140, 0),
      bg: Color.rgb(24, 26, 34),
      attrs: Attr.bold,
    ),
  );
  final status = t.pen(
    const Pen(
      fg: Color.rgb(150, 150, 160),
      bg: Color.rgb(30, 30, 40),
      attrs: Attr.italic,
    ),
  );
  final user = t.pen(_user);
  final tool = t.pen(_tool);
  final assistant = t.pen(const Pen(fg: Color.rgb(220, 220, 220)));

  final title = RenderText(
    ' twk_core · chat demo · Ctrl+E: editor',
    header,
    boundary: true,
  );
  final right = RenderText('', headerDim, boundary: true);
  final messages = RenderLog(
    pen: bg,
    itemPen: (_, line) => line.startsWith('user')
        ? user
        : (line.startsWith('tool') ? tool : assistant),
  );
  final inputLine = RenderText('> ', input, boundary: true);
  final statusLine = RenderText('', status, boundary: true);

  final root = RenderBox(
    pen: bg,
    boundary: true,
    child: RenderColumn(<(RenderObject, int?)>[
      (RenderRow(<(RenderObject, int?)>[(title, null), (right, 26)]), 1),
      if (!inline) (messages, null),
      (inputLine, 1),
      (statusLine, 1),
    ]),
  );

  // fullscreen a line of the log; inline a line of the terminal's history
  void add(String line) {
    if (inline) {
      app.commit(RenderParagraph([(line, _penOf(line))]));
    } else {
      messages.add(line);
    }
  }

  for (var i = 0; i < 30; i++) {
    add(_phrases[i % _phrases.length]);
  }
  terminal.setTitle('twk_core · chat demo');

  // text-field cursor: a bar after the typed text, measured the way the
  // canvas draws it (in the terminal's text mode), on the input line: the
  // last row but one of the screen or of the inline region's three
  final segmenter = app.screen.canvas.segmenter;
  void placeCursor(String typed) {
    final w = stringWidth(
      typed,
      mode: segmenter.mode,
      ambiguousWidth: segmenter.ambiguousWidth,
    );
    app.screen.presenter
      ..cursorVisible = true
      ..cursorShape = CursorShape.bar
      ..cursorX = 2 + w
      ..cursorY = inline ? 1 : app.screen.height - 2;
  }

  var typed = '';
  void setTyped(String text) {
    typed = text;
    inputLine.text = '> $typed';
    placeCursor(typed);
  }

  placeCursor(typed);
  var tick = 0;
  var lineNo = 30;
  final info = terminal.info;
  void updateStatus() {
    final s = app.stats;
    final avg = s.frames == 0 ? 0 : s.bytes ~/ s.frames;
    statusLine.text =
        ' frame ${s.lastMicros}µs ${s.lastBytes}B · avg ${avg}B · '
        '${s.frames} frames · ${terminal.width}x${terminal.height} · '
        'sync=${info.caps.synchronizedOutput} text=${info.textMode.name} '
        'color=${info.colorMode.name}';
  }

  // the input in a file for the editor, its lines back as the input
  var editing = false;
  Future<void> edit() async {
    editing = true;
    final dir = await Directory.systemTemp.createTemp('chat_demo');
    final file = File('${dir.path}${Platform.pathSeparator}message.txt');
    try {
      await file.writeAsString(typed.isEmpty ? '' : '$typed\n');
      final code = await app.suspend(() async {
        final p = Platform.isWindows
            ? await Process.start(
                editor,
                [file.path],
                runInShell: true,
                mode: ProcessStartMode.inheritStdio,
              )
            : await Process.start('sh', [
                '-c',
                '$editor "\$1"',
                'sh',
                file.path,
              ], mode: ProcessStartMode.inheritStdio);
        return p.exitCode;
      });
      if (code == 0) {
        print('editor exited with 0');
        final lines = (await file.readAsString()).split('\n');
        setTyped(
          lines.map((l) => l.trim()).where((l) => l.isNotEmpty).join(' '),
        );
      } else {
        log('editor exited with $code, input kept', level: LogLevel.warning);
      }
    } finally {
      await dir.delete(recursive: true);
      editing = false;
    }
  }

  final spin = Timer.periodic(const Duration(milliseconds: 100), (_) {
    tick++;
    right.text =
        '${_spinner[tick & 7]} tok/s ${900 + (tick * 37) % 400}  '
        '${DateTime.now().toIso8601String().substring(11, 19)}';
    updateStatus();
  });
  final feed = Timer.periodic(const Duration(milliseconds: 350), (_) {
    add('${_phrases[lineNo % _phrases.length]} #$lineNo');
    lineNo++;
  });
  Timer? stop;
  if (seconds != null) {
    stop = Timer(Duration(seconds: seconds), app.quit);
  }

  await app.run(root, (e) {
    if (e is ResizeEvent) {
      placeCursor(typed);
    }
    switch (e) {
      case KeyEvent(code: KeyCode.escape) ||
          KeyEvent(code: KeyCode.char, char: 'c', ctrl: true):
        app.quit();
      case KeyEvent(code: KeyCode.char, char: 'q', modifiers: 0)
          when typed.isEmpty:
        app.quit();
      case KeyEvent(code: KeyCode.enter):
        if (typed.isNotEmpty) {
          add('user: $typed');
          print('sent: $typed');
        }
        setTyped('');
      case KeyEvent(code: KeyCode.backspace):
        if (typed.isNotEmpty) {
          // one user-perceived character: a whole grapheme cluster
          setTyped(typed.substring(0, graphemeBoundaries(typed).last.$1));
        }
      case KeyEvent(code: KeyCode.char, :final char, modifiers: 0):
        setTyped(typed + char);
      case PasteEvent(:final text):
        setTyped(typed + text.replaceAll('\n', ' '));
      case KeyEvent(code: KeyCode.char, char: 'y', ctrl: true):
        terminal.copyToClipboard(typed); // OSC 52
      case KeyEvent(code: KeyCode.char, char: 'e', ctrl: true) when !editing:
        unawaited(edit());
      case KeyEvent(code: KeyCode.up) || MouseEvent(kind: MouseKind.wheelUp)
          when !inline:
        messages.scrollBy(-1);
      case KeyEvent(code: KeyCode.down) || MouseEvent(kind: MouseKind.wheelDown)
          when !inline:
        messages.scrollBy(1);
      case KeyEvent(code: KeyCode.pageUp) when !inline:
        messages.scrollBy(-10);
      case KeyEvent(code: KeyCode.pageDown) when !inline:
        messages.scrollBy(10);
      default:
        break;
    }
  });
  spin.cancel();
  feed.cancel();
  stop?.cancel();
  // what print wrote meanwhile (run() has written the warnings and errors)
  for (final r in app.logs.records) {
    if (r.level.index < LogLevel.warning.index) {
      stderr.writeln(r);
    }
  }
  final s = app.stats;
  stderr.writeln(
    'chat_demo: ${s.frames} frames, ${s.bytes} bytes '
    '(avg ${s.frames == 0 ? 0 : s.bytes ~/ s.frames} B/frame, '
    'median ${s.medianMicros} µs/frame core time); '
    'terminal: $info',
  );
}
