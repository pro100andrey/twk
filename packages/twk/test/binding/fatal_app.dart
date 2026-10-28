// An app whose input listener throws, run by fatal_test.dart in a process
// of its own with the error left unhandled, so the test can read what
// reaches stderr.
import 'dart:io';
import 'dart:typed_data';

// the libraries of twk it runs on, not all of twk: it compiles in about
// 60 % of the time
import 'package:twk/src/binding/binding.dart';
import 'package:twk/src/layout/layout.dart';
import 'package:twk_core/twk_core.dart';

/// A terminal in memory that says on stderr when it is restored.
final class _Terminal implements TerminalBackend {
  final _term = HeadlessTerminal();

  @override
  TerminalInfo get info => _term.info;

  @override
  int get width => _term.width;

  @override
  int get height => _term.height;

  @override
  Stream<InputEvent> get events => _term.events;

  void type(String text) => _term.type(text);

  @override
  void write(Uint8List bytes) => _term.write(bytes);

  @override
  Future<void> flush() => _term.flush();

  @override
  Future<void> close() async {
    stderr.writeln('restored');
    await _term.close();
  }
}

Future<void> main() async {
  final term = _Terminal();
  final done = runApp(
    Column(
      children: [
        InputListener(
          onEvent: (e) => throw StateError('boom'),
          child: const SizedBox(),
        ),
      ],
    ),
    terminal: term,
  );
  term.type('x');
  await done;
}
