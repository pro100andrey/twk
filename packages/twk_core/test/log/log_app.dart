// An app on a stand-in terminal, run by log_process_test.dart in a process
// of its own: it prints, logs and fails, so the test can read what reached
// stdout, stderr and the file TWK_LOG names.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';

final class _Terminal implements TerminalBackend {
  @override
  final info = TerminalInfo(
    caps: const TerminalCaps(),
    textMode: TextMode.graphemes,
    ambiguousWidth: 1,
    colorMode: ColorMode.trueColor,
    foregroundRgb: null,
    backgroundRgb: null,
    inBandResize: false,
    graphemeMode: false,
    kittyKeyboard: false,
    answeredQueries: false,
  );
  @override
  var width = 20;
  @override
  var height = 4;

  final input = StreamController<InputEvent>();
  @override
  Stream<InputEvent> get events => input.stream;

  @override
  void write(Uint8List bytes) {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    stderr.writeln('restored');
    await input.close();
  }
}

Future<void> main() async {
  final term = _Terminal();
  final app = TwkApp(term);
  final root = RenderText('app', app.screen.styles.pen(const Pen()));
  final done = app.run(root, (e) {
    print('in a handler');
    log('slow', level: LogLevel.warning);
    Timer(Duration.zero, () => throw StateError('fatal'));
  });
  term.input.add(const KeyEvent(KeyCode.enter));
  await done;
}
