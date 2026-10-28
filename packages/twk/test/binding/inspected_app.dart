// An app run by service_extensions_test.dart in a process of its own with
// a VM service, which the test calls the app's service extensions over.
// It says on stdout when it has drawn its first frame, and runs until it
// is killed.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// the libraries of twk it runs on, not all of twk: it compiles in about
// 60 % of the time
import 'package:twk/src/binding/binding.dart';
import 'package:twk/src/text/text.dart';
import 'package:twk_core/twk_core.dart';

Future<void> main() async {
  final term = _Terminal();
  final done = runApp(const Text('inspected'), terminal: term);
  await term.written;
  // a terminal in memory waits for no input: this keeps the isolate alive
  final alive = ReceivePort();
  stdout.writeln('running');
  await done;
  alive.close();
}

/// A terminal in memory that tells when the first frame is written to it.
final class _Terminal implements TerminalBackend {
  final _term = HeadlessTerminal(width: 20, height: 3);
  final _written = Completer<void>();

  /// Completes once a frame has been written.
  Future<void> get written => _written.future;

  @override
  TerminalInfo get info => _term.info;

  @override
  int get width => _term.width;

  @override
  int get height => _term.height;

  @override
  Stream<InputEvent> get events => _term.events;

  @override
  void write(Uint8List bytes) {
    _term.write(bytes);
    if (!_written.isCompleted) {
      _written.complete();
    }
  }

  @override
  Future<void> flush() => _term.flush();

  @override
  Future<void> close() => _term.close();
}
