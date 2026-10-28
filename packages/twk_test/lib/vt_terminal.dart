/// A terminal backend in the inline mode whose output goes into the [Vt]
/// emulator as a normal screen with a scrollback, below lines printed
/// before the app ran: what a user would see, history included.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';

import 'vt.dart';

// Examples can assume:
// import 'dart:typed_data';

/// A [WindowBackend] for an app in the inline mode whose frames go into
/// a [Vt] ([vt]) with a scrollback, below [history]: what a user would see
/// on a normal screen, the lines printed before the app included. Input is
/// delivered with [type], and [resize] resizes it as a terminal that keeps
/// what it shows. [setTitle] writes the title to [frames] as a terminal
/// is sent it; it shows no notifications ([notify]).
///
/// A frame written below the line the shell printed, read back:
///
/// ```dart
/// final term = VtTerminal(width: 20, height: 4, history: [r'$ dart run']);
/// term.write(Uint8List.fromList('hello'.codeUnits));
/// assert(term.lines.take(2).join('|') == r'$ dart run|hello');
/// ```
final class VtTerminal implements WindowBackend {
  /// A [width] x [height] normal screen showing [history], the last line
  /// with its line break when [atLineStart]. The history is guarded: the
  /// emulator fails on any write to it, and on any absolute row. Input is
  /// decoded by a [HeadlessTerminal].
  VtTerminal({
    int width = 40,
    int height = 10,
    this.history = const [],
    bool atLineStart = true,
  }) : _input = HeadlessTerminal(width: width, height: height),
       vt = Vt(
         width,
         height,
         scrollback: true,
         allowLineFeed: true,
         relativeOnly: true,
       ) {
    for (var i = 0; i < history.length; i++) {
      vt.feed(utf8.encode(history[i]));
      if (atLineStart || i < history.length - 1) {
        vt.feed(const [0x0D, 0x0A]);
      }
    }
    vt.guardRows(atLineStart ? vt.cy : vt.cy + 1);
    info = TerminalInfo(
      caps: const TerminalCaps(),
      textMode: TextMode.graphemes,
      ambiguousWidth: 1,
      colorMode: ColorMode.trueColor,
      foregroundRgb: null,
      backgroundRgb: null,
      inBandResize: false,
      graphemeMode: false,
      kittyKeyboard: false,
      answeredQueries: true,
      alternateScreen: false,
      cursorColumn: vt.cx,
    );
  }

  final HeadlessTerminal _input;

  /// What the screen shows.
  final Vt vt;

  /// What was printed before the app.
  final List<String> history;

  @override
  late final TerminalInfo info;

  @override
  int get width => _input.width;

  @override
  int get height => _input.height;

  @override
  Stream<InputEvent> get events => _input.events;

  /// Every frame written, as written.
  final frames = <Uint8List>[];

  /// Whether [close] was called.
  var closed = false;

  /// Every line: the scrollback, then the screen.
  List<String> get lines => vt.lines;

  /// Delivers [text] as typed input.
  void type(String text) => _input.type(text);

  /// The terminal becomes [width] x [height] and keeps what it shows (see
  /// [Vt.resizeKeeping]); a [ResizeEvent] follows.
  void resize(int width, int height, {bool pull = false}) {
    vt.resizeKeeping(width, height, pull: pull);
    _input.resize(width, height);
  }

  @override
  void write(Uint8List bytes) {
    if (!closed) {
      frames.add(Uint8List.fromList(bytes));
      vt.feed(bytes);
    }
  }

  /// Writes the sequence that sets the window's title to [title]
  /// ([titleSequence]), which the screen does not show.
  @override
  void setTitle(String title) =>
      write(Uint8List.fromList(utf8.encode(titleSequence(title))));

  /// Nothing: the terminal shows no notifications
  /// ([TerminalInfo.notifications] is [NotificationProtocol.none]).
  @override
  void notify(String title, String body) {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    closed = true;
    await _input.close();
  }
}
