import 'dart:convert';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart';
import 'package:twk_term/twk_term.dart';

/// An emulator that records what it sends and the events it hands over.
final class Rig {
  Rig({int width = 10, int height = 4, int scrollback = 100, TextMode? mode})
    : t = TerminalEmulator(
        width: width,
        height: height,
        scrollbackLimit: scrollback,
        textMode: mode ?? TextMode.legacy,
        strict: true,
      ) {
    t
      ..onOutput = sent.addAll
      ..onEvent = events.add;
  }

  final TerminalEmulator t;
  final sent = <int>[];
  final events = <TerminalEvent>[];

  /// Feeds [s] (UTF-8); `\e` may stand for ESC and `^G` for BEL.
  void feed(String s) =>
      t.feedText(s.replaceAll(r'\e', '\x1b').replaceAll('^G', '\x07'));

  /// What was sent so far, ESC as `\e`; cleared.
  String takeSent() {
    final s = utf8.decode(sent, allowMalformed: true).replaceAll('\x1b', r'\e');
    sent.clear();
    return s;
  }

  /// The screen's rows as text, the blanks at their ends left out.
  List<String> get rows => [for (var y = 0; y < t.height; y++) t.lineText(y)];

  /// The scrollback's lines as text.
  List<String> get history => [
    for (var i = 0; i < t.scrollbackLength; i++)
      t.scrollbackLine(i).text(t.glyphs),
  ];

  (int, int) get cursor => (t.cursorX, t.cursorY);

  Color fg(int x, int y) => t.styles.fgOf(t.styleAt(x, y));
  Color bg(int x, int y) => t.styles.bgOf(t.styleAt(x, y));
  int attrs(int x, int y) => t.styles.attrsOf(t.styleAt(x, y));
  Color ul(int x, int y) => t.styles.underlineColorOf(t.styleAt(x, y));
  String? link(int x, int y) => t.styles.linkOf(t.styleAt(x, y));
}

/// A [Rig] fed [input].
Rig fed(
  String input, {
  int width = 10,
  int height = 4,
  int scrollback = 100,
  TextMode? mode,
}) =>
    Rig(width: width, height: height, scrollback: scrollback, mode: mode)
      ..feed(input);

/// [bytes] up to the first occurrence of [marker] (`\e` for ESC, `\r` for
/// CR) at or after [from]; with [last], the last occurrence.
Uint8List before(
  Uint8List bytes,
  String marker, {
  bool last = false,
  int from = 0,
}) {
  final m = marker.replaceAll(r'\e', '\x1b').replaceAll(r'\r', '\r').codeUnits;
  int? found;
  outer:
  for (var i = from; i + m.length <= bytes.length; i++) {
    for (var k = 0; k < m.length; k++) {
      if (bytes[i + k] != m[k]) {
        continue outer;
      }
    }
    found = i;
    if (!last) {
      break;
    }
  }
  if (found == null) {
    throw StateError('marker $marker not found');
  }
  return Uint8List.sublistView(bytes, 0, found);
}

/// The scrollback and the screen as the lines the program wrote: a line
/// that wrapped joined with the next, the blanks at each end left out.
List<String> logicalLines(TerminalEmulator t) {
  final lines = [
    for (var i = 0; i < t.scrollbackLength; i++) t.scrollbackLine(i),
    for (var y = 0; y < t.height; y++) t.line(y),
  ];
  final out = <String>[];
  final sb = StringBuffer();
  for (final line in lines) {
    if (line.wrapped) {
      for (var x = 0; x < line.width; x++) {
        final c = line.cells[x];
        if ((c & kCont) == 0) {
          sb.write(t.glyphs.stringOf(c));
        }
      }
    } else {
      sb.write(line.text(t.glyphs));
      out.add(sb.toString());
      sb.clear();
    }
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out;
}
