// A terminal in memory, for TerminalShell and for a Terminal over a link:
// what it was given to write, its modes, input and resizes by hand.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:twk_core/src/terminal/link.dart'
    show DeclaringLink, TerminalDeclaration;
import 'package:twk_core/terminal.dart';

/// The terminal a shell serves: what it was given to write, whether it is
/// in raw mode, its size, what it declares it does; input and resizes go in
/// by hand.
final class FakeLink implements DeclaringLink {
  FakeLink({
    this.columns = 20,
    this.lines = 4,
    this.environment = const {'TERM': 'xterm-kitty', 'NO_COLOR': '1'},
    this.declaration = const TerminalDeclaration(),
    this.refusesRaw = false,
  });

  /// [enterRaw] throws what StdioLink does on a stdin that is no terminal
  /// (/dev/null).
  final bool refusesRaw;

  @override
  final Map<String, String> environment;

  @override
  final TerminalDeclaration declaration;

  @override
  bool get windows => false;

  @override
  int columns;

  @override
  int lines;

  @override
  int? get eraseChar => 0x7F;

  /// Whether the console is in raw mode, and every change of it.
  var raw = false;
  final rawChanges = <bool>[];

  /// Everything written, in order.
  final output = BytesBuilder();

  String get text => latin1.decode(output.toBytes());

  var flushes = 0;
  var closed = false;

  final _input = StreamController<List<int>>();
  final _resizes = StreamController<void>.broadcast();

  /// The terminal's input: [text], UTF-8 encoded.
  void type(String text) => _input.add(utf8.encode(text));

  /// What the terminal answers, typed one at each [flush] in turn: a
  /// round of queries each, those of a round asked only once the one
  /// before was answered.
  void answerRounds(List<String> rounds) => _rounds.addAll(rounds);
  final _rounds = <String>[];

  /// The terminal's input fails with [error]: its far end went away.
  void fail(Object error) => _input.addError(error);

  /// The terminal was resized.
  void resize(int columns, int lines) {
    this.columns = columns;
    this.lines = lines;
    _resizes.add(null);
  }

  @override
  void enterRaw() {
    if (refusesRaw) {
      throw const TerminalException('not a terminal');
    }
    raw = true;
    rawChanges.add(true);
  }

  @override
  void restore() {
    raw = false;
    rawChanges.add(false);
  }

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void add(List<int> bytes) => output.add(bytes);

  @override
  Future<void> flush() async {
    flushes++;
    if (_rounds.isNotEmpty) {
      type(_rounds.removeAt(0));
    }
  }

  @override
  Stream<void> get resizes => _resizes.stream;

  /// What the link was told puts the terminal back if the program dies
  /// ([restoreWith]), as text.
  var restoring = '';

  @override
  void restoreWith(List<int> bytes) => restoring = latin1.decode(bytes);

  @override
  Future<void> close() async {
    closed = true;
    await _resizes.close();
  }
}
