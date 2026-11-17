/// [EmulatorScreen], the adapter of [ScreenPort] over two of twk_term's
/// `TerminalEmulator`s.
library;

import 'dart:typed_data';

import 'package:twk_core/twk_core.dart' show KeyEvent, MouseEvent;
import 'package:twk_term/twk_term.dart' show MouseProtocol, TerminalEmulator;

import 'ports.dart';

/// What the frame emulator shows.
final class _View implements ScreenView {
  _View(this._term);

  final TerminalEmulator _term;

  @override
  int get width => _term.width;

  @override
  int get height => _term.height;

  @override
  String line(int y) => _term.lineText(y).trimRight();

  @override
  bool isContinuation(int x, int y) =>
      x > 0 &&
      x < _term.width &&
      y < _term.height &&
      _term.cellText(x, y).isEmpty;

  @override
  int get cursorX => _term.cursorX;

  @override
  int get cursorY => _term.cursorY;

  @override
  bool get cursorVisible => _term.cursorVisible;

  @override
  bool get alternateScreen => _term.alternateScreen;

  @override
  String get text => [for (var y = 0; y < height; y++) line(y)].join('\n');
}

/// Two emulators of the same size: one that answers (everything it
/// receives, as it arrives) and one that does not (the frames' bytes).
final class EmulatorScreen implements ScreenPort {
  /// Emulators of [width] by [height] cells.
  ///
  /// [checker], when given, takes the frame emulator's bytes as well: a
  /// test's strict terminal, which fails on a sequence a real terminal
  /// would not take.
  EmulatorScreen({
    int width = 80,
    int height = 24,
    this.checker,
    TerminalEmulator Function(int width, int height)? emulator,
  }) : _answering = (emulator ?? _make)(width, height),
       _frame = (emulator ?? _make)(width, height) {
    _answering.onOutput = (bytes) {
      final capture = _capture;
      if (capture != null) {
        capture.add(bytes);
      } else {
        _answer?.call(bytes);
      }
    };
    frame = _View(_frame);
  }

  static TerminalEmulator _make(int width, int height) =>
      TerminalEmulator(width: width, height: height);

  /// Takes the bytes the frame emulator takes, or null.
  final void Function(Uint8List bytes)? checker;

  final TerminalEmulator _answering;
  final TerminalEmulator _frame;
  void Function(Uint8List bytes)? _answer;
  List<Uint8List>? _capture;

  @override
  void answerTo(void Function(Uint8List bytes)? sink) => _answer = sink;

  @override
  late final ScreenView frame;

  @override
  void feedAnswering(List<int> bytes) => _answering.feed(bytes);

  @override
  void feedFrame(List<int> bytes) {
    _frame.feed(bytes);
    checker?.call(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  }

  Uint8List _encode(void Function() send) {
    final got = _capture = <Uint8List>[];
    try {
      send();
    } finally {
      _capture = null;
    }
    return Uint8List.fromList([for (final b in got) ...b]);
  }

  @override
  Uint8List encodeKey(KeyEvent key) => _encode(() => _answering.sendKey(key));

  @override
  Uint8List encodeText(String text) => _encode(() => _answering.sendText(text));

  @override
  Uint8List encodePaste(String text) =>
      _encode(() => _answering.sendPaste(text));

  @override
  Uint8List encodeMouse(MouseEvent event) =>
      _encode(() => _answering.sendMouse(event));

  @override
  bool get mouseTracked => _answering.mouseProtocol != MouseProtocol.off;

  @override
  void resizeAnswering(int width, int height) =>
      _answering.resize(width, height);

  @override
  void resizeFrame(int width, int height) => _frame.resize(width, height);
}
