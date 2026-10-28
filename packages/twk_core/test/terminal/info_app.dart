// Opens the terminal TWK_SHELL names (stdin and stdout are pipes) and
// prints what twk found out about it as one line of JSON: for the VS Code
// extension's tests (editors/vscode/src/test/unit/webview/twk_probe.test.ts),
// which serve it a headless xterm.js with each switch of the twk terminal
// and hold what twk found to what the switch says. With `keys` it then
// prints each key it reads, as a line `key <code> <char> <modifiers>`,
// until Ctrl+Q. With TWK_INFO_WAIT=1 in its environment (the extension's
// tests in VS Code, which see the terminal and not stdout) it shows the
// same on the terminal, `name=value` a line, says its progress is 40 %
// (OSC 9;4) and waits for a key.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/terminal.dart';

Future<void> main(List<String> args) async {
  final Terminal term;
  try {
    term = await Terminal.open(
      const TerminalOptions(probeTimeout: Duration(milliseconds: 500)),
    );
  } on TerminalException catch (e) {
    stdout.writeln(jsonEncode({'error': e.message}));
    return;
  }
  final info = term.info;
  final caps = info.caps;
  final found = {
    'colorMode': info.colorMode.name,
    'answeredQueries': info.answeredQueries,
    'synchronizedOutput': caps.synchronizedOutput,
    'kittyKeyboard': info.kittyKeyboard,
    'kittyKeyboardFlags': info.kittyKeyboardFlags,
    'graphics': caps.graphics.name,
    'cellPixelWidth': caps.cellPixelWidth,
    'cellPixelHeight': caps.cellPixelHeight,
    'notifications': info.notifications.name,
    'progressReports': info.progressReports,
    'pointerShapes': info.pointerShapes,
    'repeatChar': caps.repeatChar,
    'ambiguousWidth': info.ambiguousWidth,
    'bidi': info.bidi.name,
  };
  stdout.writeln(jsonEncode(found));
  if (Platform.environment['TWK_INFO_WAIT'] == '1') {
    final lines = [for (final e in found.entries) '${e.key}=${e.value}'];
    term.write(
      Uint8List.fromList(
        utf8.encode('\x1b[H${lines.join('\r\n')}\x1b]9;4;1;40\x1b\\'),
      ),
    );
    await term.flush();
    await term.events.firstWhere((e) => e is KeyEvent);
  }
  if (args.contains('keys')) {
    await for (final e in term.events) {
      if (e is! KeyEvent) {
        continue;
      }
      stdout.writeln('key ${e.code.name} ${jsonEncode(e.char)} ${e.modifiers}');
      if (e.code == KeyCode.char && e.char == 'q' && e.modifiers == Mod.ctrl) {
        break;
      }
    }
  }
  await term.close();
}
