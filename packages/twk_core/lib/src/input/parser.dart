/// [InputParser], the decoder of what a terminal sends into
/// [InputEvent]s.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../unicode/unicode.dart';
import 'events.dart';

/// Decodes the bytes a terminal sends into [InputEvent]s, read by read.
///
/// Input may be split at any byte (a read can end in the middle of an
/// escape sequence or a UTF-8 character), and one read may hold several
/// sequences: what is incomplete waits for the next [feed]. A lone ESC is
/// either the Escape key or the start of a sequence, so it waits too
/// ([hasPending]) until more bytes come or [flush] is called after a short
/// pause. A bracketed paste is held until its end marker and comes as one
/// [PasteEvent] ([endPaste] where the marker got lost).
///
/// What it holds is bounded, as the far end of a link need not be a
/// terminal: a paste longer than [pasteLimit] comes in [PasteEvent]s of
/// at most that many bytes each ([PasteEvent.more] on all but the last),
/// and a sequence still unterminated after [sequenceLimit] bytes is given
/// up, an [UnknownSequence] of what came, and the rest of it dropped up
/// to its end.
///
/// It decodes the keys of the legacy encodings and of the kitty keyboard
/// protocol ([KittyKeyboardFlags]), SGR mouse reports (mode 1006), focus
/// and in-band resize reports, and the replies to the queries a terminal
/// is probed with; a sequence it has no event for is an
/// [UnknownSequence]. `Terminal` keeps one per terminal, as
/// does `HeadlessTerminal`:
///
/// ```dart
/// final parser = InputParser();
/// final events = parser.feed('a\x1b[A'.codeUnits);
/// // [KeyEvent(KeyCode.char, char: 'a'), KeyEvent(KeyCode.up)]
/// final escape = [...parser.feed([0x1b]), ...parser.flush()];
/// // [KeyEvent(KeyCode.escape)], once flushed
/// ```
final class InputParser {
  /// A parser with no bytes fed yet.
  InputParser();

  // the bytes the reads before left undecoded: [_len] of [_store], which
  // a read's bytes are copied into (a Uint8List's as one block)
  var _store = Uint8List(256);
  var _len = 0;
  Uint8List get _buf => Uint8List.sublistView(_store, 0, _len);

  var _inPaste = false;

  // the bracketed paste's bytes so far: [_pasteLength] of [_paste]
  var _paste = Uint8List(256);
  var _pasteLength = 0;

  /// Whether a cursor position query (`CSI 6 n`) is out: its reply
  /// `CSI row ; col R` reads as F3 with modifiers, and is decoded as a
  /// [CursorReport] only while one is expected ([cursorReportsExpected]),
  /// each such reply taking one. False by default; `Terminal` sets it
  /// while its own query is out (when it opens and when it takes the
  /// terminal back). Set, one reply is expected.
  bool get expectCursorReport => cursorReportsExpected > 0;
  set expectCursorReport(bool expect) => cursorReportsExpected = expect ? 1 : 0;

  /// How many replies to cursor position queries (`CSI 6 n`) are still
  /// expected ([expectCursorReport]): as many as were asked in one write.
  var cursorReportsExpected = 0;

  static const _pasteEnd = <int>[0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E];

  /// The most bytes of a paste held before what came is delivered, a
  /// [PasteEvent] of its own, the paste going on: 1 MiB.
  static const int pasteLimit = 1 << 20;

  /// The most bytes of an unterminated escape sequence held: 64 KiB,
  /// many times the longest reply a terminal sends.
  static const int sequenceLimit = 1 << 16;

  // the rest of a sequence given up at [sequenceLimit], dropped up to its
  // end: a CSI's parameters and final byte, or a string's BEL or ST; an
  // ESC that ended a string and may be its ST's start
  _Drop _dropping = _Drop.none;

  // how far into the string sequence pending at the buffer's start the
  // reads before scanned for its end: the next read goes on from there
  var _stringScanned = 0;

  /// Whether an escape sequence is waiting for more input (call [flush]
  /// after a pause: a lone ESC may be the Escape key). Never for a
  /// character split across reads, which can only be completed, Alt and
  /// one (ESC before it) included, nor inside a bracketed paste, which ends
  /// only with its end marker.
  bool get hasPending =>
      !_inPaste &&
      _len > 0 &&
      _store[0] == 0x1B &&
      // what a read leaves after ESC is a sequence's introducer (ASCII)
      // or the start of a character (a UTF-8 lead byte)
      (_len == 1 || _store[1] < 0x80);

  /// Whether the pending sequence got past ESC and its introducer (its
  /// parameters arrived): then it isn't a key typed with Alt and the rest
  /// is on its way, so it deserves a longer wait than a lone ESC.
  bool get sequenceStarted => hasPending && _len > 2;

  /// Decodes [bytes], what one read of the input brought, with what the
  /// reads before left incomplete: the events complete so far, in order.
  /// What is incomplete waits for the next [feed] or a [flush].
  List<InputEvent> feed(List<int> bytes) {
    final n = bytes.length;
    if (_len + n > _store.length) {
      final g = Uint8List(
        _len + n > 2 * _store.length ? _len + n : 2 * _store.length,
      )..setRange(0, _len, _store);
      _store = g;
    }
    if (bytes is Uint8List) {
      _store.setRange(_len, _len + n, bytes);
    } else {
      final st = _store;
      for (var i = 0; i < n; i++) {
        final v = bytes[i];
        st[_len + i] = v & ~0xFF == 0 ? v : 0xFF;
      }
    }
    _len += n;
    return _drain(eof: false);
  }

  /// Resolves pending bytes as if no more input will follow (a lone ESC
  /// becomes the Escape key). An open bracketed paste stays open: see
  /// [endPaste].
  List<InputEvent> flush() => _drain(eof: true);

  /// Whether a bracketed paste has started and its end marker hasn't come.
  bool get inPaste => _inPaste;

  /// Ends an open bracketed paste whose end marker got lost (cut by
  /// something between the terminal and the app): delivers what arrived,
  /// so later input isn't taken for pasted text forever.
  List<InputEvent> endPaste() {
    if (!_inPaste) {
      return const [];
    }
    _addPaste(_buf, 0, _len);
    _len = 0;
    return [_pasteEvent()];
  }

  /// Appends `b[start..to)` to the paste. A value that is no byte goes in
  /// as 0xFF, which UTF-8 decodes to U+FFFD as it would decode the value.
  /// Given [out], what goes past [pasteLimit] delivers the paste so far
  /// there, a piece of it.
  void _addPaste(Uint8List b, int start, int to, [List<InputEvent>? out]) {
    var from = start;
    if (out != null) {
      while (_pasteLength + to - from > pasteLimit) {
        final take = pasteLimit - _pasteLength;
        _addPaste(b, from, from + take);
        from += take;
        out.add(_pastePiece());
      }
    }
    final n = to - from;
    if (_pasteLength + n > _paste.length) {
      final grown = Uint8List(
        (_pasteLength + n > 2 * _paste.length)
            ? _pasteLength + n
            : 2 * _paste.length,
      )..setRange(0, _pasteLength, _paste);
      _paste = grown;
    }
    final p = _paste;
    var k = _pasteLength;
    for (var i = from; i < to; i++) {
      final v = b[i];
      p[k++] = v & ~0xFF == 0 ? v : 0xFF;
    }
    _pasteLength = k;
  }

  PasteEvent _pasteEvent() {
    final e = _pasteText(_pasteLength);
    _pasteLength = 0;
    if (_paste.length > 1 << 16) {
      _paste = Uint8List(256); // a large paste's buffer isn't kept
    }
    _inPaste = false;
    return e;
  }

  /// What of a paste over [pasteLimit] can go now: up to its last whole
  /// character, a CR held back for the LF that may follow it; the rest
  /// stays, the start of the next piece.
  PasteEvent _pastePiece() {
    final p = _paste;
    var cut = _pasteLength;
    var lead = cut - 1;
    while (lead > 0 && cut - lead < 4 && p[lead] & 0xC0 == 0x80) {
      lead--;
    }
    final c = p[lead];
    final length = c < 0x80
        ? 1
        : c >= 0xF0
        ? 4
        : c >= 0xE0
        ? 3
        : c >= 0xC0
        ? 2
        : 1;
    if (cut - lead < length) {
      cut = lead;
    }
    if (cut > 0 && p[cut - 1] == 0x0D) {
      cut--;
    }
    final e = _pasteText(cut, more: true);
    p.setRange(0, _pasteLength - cut, p, cut);
    _pasteLength -= cut;
    return e;
  }

  PasteEvent _pasteText(int length, {bool more = false}) => PasteEvent(
    utf8
        .decode(Uint8List.sublistView(_paste, 0, length), allowMalformed: true)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n'),
    more: more,
  );

  /// Puts an ESC back at [i] of the bytes kept: the one a dropped string
  /// ended with, which starts what follows ([_drop]).
  void _insertEsc(int i) {
    if (_len + 1 > _store.length) {
      _store = Uint8List(2 * _store.length)..setRange(0, _len, _store);
    }
    _store.setRange(i + 1, _len + 1, _store, i);
    _store[i] = 0x1B;
    _len++;
  }

  /// Drops what is left of a sequence given up ([_dropping]) from [pos];
  /// returns where what follows it starts, [b]'s length while it goes on.
  /// [b] is to be taken again after, as an ESC put back may grow it.
  int _drop(Uint8List b, int pos) {
    var i = pos;
    if (_dropping == _Drop.stringEsc) {
      _dropping = _Drop.none;
      if (b[i] == 0x5C) {
        return i + 1;
      }
      // an ESC that starts what follows
      _insertEsc(i);
      return i;
    }
    for (; i < b.length; i++) {
      final c = b[i];
      if (_dropping == _Drop.csi) {
        if (c >= 0x20 && c <= 0x3F) {
          continue;
        }
        _dropping = _Drop.none;
        return c >= 0x40 && c <= 0x7E ? i + 1 : i;
      }
      if (c == 0x07) {
        _dropping = _Drop.none;
        return i + 1;
      }
      if (c == 0x1B) {
        if (i + 1 >= b.length) {
          _dropping = _Drop.stringEsc;
          return i + 1;
        }
        _dropping = _Drop.none;
        return b[i + 1] == 0x5C ? i + 2 : i;
      }
    }
    return i;
  }

  // reused across reads: typing allocates only the events themselves
  final _text = StringBuffer();
  final _segmenter = TextSegmenter();
  final _scan = ClusterScan();

  // the key of each printable ASCII character, made once: what typing
  // mostly is, given out without a string, a segmentation or an event
  static final List<KeyEvent> _asciiKeys = [
    for (var c = 0x20; c < 0x7F; c++)
      KeyEvent(KeyCode.char, char: String.fromCharCode(c)),
  ];

  void _flushText(List<InputEvent> out) {
    final text = _text;
    if (text.isEmpty) {
      return;
    }
    final s = text.toString();
    text.clear();
    for (var i = 0; i < s.length; i = _scan.end) {
      _segmenter.scan(s, i, _scan);
      out.add(KeyEvent(KeyCode.char, char: s.substring(i, _scan.end)));
    }
  }

  List<InputEvent> _drain({required bool eof}) {
    final out = <InputEvent>[];
    var pos = 0;
    var b = _buf;
    final text = _text;
    while (pos < b.length) {
      if (_dropping != _Drop.none) {
        pos = _drop(b, pos);
        b = _buf;
        continue;
      }
      if (_inPaste) {
        final end = _indexOf(b, _pasteEnd, pos);
        if (end < 0) {
          // keep a possible partial end marker in the buffer (only bytes
          // of the pasted text itself can belong to it)
          var keep = 0;
          for (var k = _pasteEnd.length - 1; k > 0; k--) {
            if (k <= b.length - pos && _endsWithPrefix(b, k)) {
              keep = k;
              break;
            }
          }
          _addPaste(b, pos, b.length - keep, out);
          pos = b.length - keep;
          break;
        }
        _addPaste(b, pos, end, out);
        out.add(_pasteEvent());
        pos = end + _pasteEnd.length;
        continue;
      }

      final c = b[pos];
      if (c == 0x1B) {
        _flushText(out);
        final n = _escape(b, pos, out, eof);
        if (n == 0) {
          if (b.length - pos > sequenceLimit) {
            _giveUp(b, pos, out);
            pos = b.length;
            continue;
          }
          break;
        } // incomplete: wait for more bytes
        pos += n;
        continue;
      }
      if (c < 0x20 || c == 0x7F) {
        _flushText(out);
        out.add(_control(c, 0));
        pos++;
        continue;
      }
      // printable ASCII with no text before it to join and ASCII after it,
      // which no cluster continues: a key of its own
      if (c < 0x7F &&
          text.isEmpty &&
          (pos + 1 == b.length || b[pos + 1] < 0x80)) {
        out.add(_asciiKeys[c - 0x20]);
        pos++;
        continue;
      }
      // UTF-8
      final cp = _utf8At(b, pos, eof);
      final len = _utf8Length;
      if (len == 0) {
        break;
      } // incomplete character
      text.writeCharCode(cp);
      pos += len;
    }
    _flushText(out);
    if (pos > 0) {
      _store.setRange(0, _len - pos, _store, pos);
      _len -= pos;
      if (_len == 0 && _store.length > 1 << 16) {
        _store = Uint8List(256); // a large read's buffer isn't kept
      }
    }
    if (pos > 0) {
      // the sequence a scan went into is decoded, or no more at the start
      _stringScanned = 0;
    }
    // at eof every decoder takes what it was given, even cut short
    assert(!eof || _inPaste || _len == 0, 'left at eof: $_buf');
    return out;
  }

  /// Gives up the unterminated sequence at [pos], longer than
  /// [sequenceLimit]: an [UnknownSequence] of what came, its rest dropped.
  void _giveUp(Uint8List b, int pos, List<InputEvent> out) {
    out.add(UnknownSequence(b.sublist(pos)));
    // after ESC ESC, the sequence the second ESC starts
    final at = b[pos + 1] == 0x1B ? pos + 1 : pos;
    _dropping = b[at + 1] == 0x5B ? _Drop.csi : _Drop.string;
    if (b.last == 0x1B && _dropping == _Drop.string) {
      _dropping = _Drop.stringEsc;
    }
  }

  static bool _endsWithPrefix(Uint8List b, int k) {
    if (b.length < k) {
      return false;
    }
    for (var i = 0; i < k; i++) {
      if (b[b.length - k + i] != _pasteEnd[i]) {
        return false;
      }
    }
    return true;
  }

  static int _indexOf(Uint8List b, List<int> pat, int from) {
    outer:
    for (var i = from; i + pat.length <= b.length; i++) {
      for (var k = 0; k < pat.length; k++) {
        if (b[i + k] != pat[k]) {
          continue outer;
        }
      }
      return i;
    }
    return -1;
  }

  // the byte length of the character [_utf8At] decoded last
  static var _utf8Length = 0;

  /// Decodes one UTF-8 character: returns its code point and sets
  /// [_utf8Length] to its byte length, or returns 0 and sets it to 0 when
  /// it is incomplete.
  static int _utf8At(Uint8List b, int pos, bool eof) {
    final c = b[pos];
    int need;
    int cp;
    if (c < 0x80) {
      return _decoded(c, 1);
    }
    if (c >= 0xC2 && c <= 0xDF) {
      need = 1;
      cp = c & 0x1F;
    } else if (c >= 0xE0 && c <= 0xEF) {
      need = 2;
      cp = c & 0x0F;
    } else if (c >= 0xF0 && c <= 0xF4) {
      need = 3;
      cp = c & 0x07;
    } else {
      return _decoded(0xFFFD, 1);
    }
    for (var k = 1; k <= need; k++) {
      if (pos + k >= b.length) {
        return eof ? _decoded(0xFFFD, b.length - pos) : _decoded(0, 0);
      }
      final cc = b[pos + k];
      if (cc & 0xC0 != 0x80) {
        return _decoded(0xFFFD, k);
      }
      cp = (cp << 6) | (cc & 0x3F);
    }
    if (cp > 0x10FFFF ||
        (cp >= 0xD800 && cp <= 0xDFFF) ||
        cp < const [0, 0x80, 0x800, 0x10000][need]) {
      // out of range, a surrogate, or overlong (could hide a control)
      return _decoded(0xFFFD, need + 1);
    }
    return _decoded(cp, need + 1);
  }

  @pragma('vm:prefer-inline')
  static int _decoded(int cp, int length) {
    _utf8Length = length;
    return cp;
  }

  /// Whether the terminal's Backspace key sends `^H` (0x08) and
  /// Ctrl+Backspace DEL (0x7F), the other way round from the usual: which
  /// of the two is [KeyCode.backspace] with [Mod.ctrl]. False by default;
  /// `Terminal` sets it from the tty's erase character
  /// (`TerminalLink.eraseChar`).
  var backspaceSendsCtrlH = false;

  /// The key of the control byte [c], a C0 control or DEL but never ESC,
  /// which starts a sequence and is decoded by [_escape].
  KeyEvent _control(int c, int mods) {
    switch (c) {
      case 0x0D:
      case 0x0A:
        return KeyEvent(KeyCode.enter, modifiers: mods);
      case 0x09:
        return KeyEvent(KeyCode.tab, modifiers: mods);
      case 0x7F:
        return KeyEvent(
          KeyCode.backspace,
          modifiers: backspaceSendsCtrlH ? mods | Mod.ctrl : mods,
        );
      case 0x08:
        return KeyEvent(
          KeyCode.backspace,
          modifiers: backspaceSendsCtrlH ? mods : mods | Mod.ctrl,
        );
      case 0x00:
        return KeyEvent(KeyCode.char, char: ' ', modifiers: mods | Mod.ctrl);
    }
    if (c >= 0x01 && c <= 0x1A) {
      return KeyEvent(
        KeyCode.char,
        char: String.fromCharCode(0x60 + c),
        modifiers: mods | Mod.ctrl,
      );
    }
    // 0x1C..0x1F: ctrl + \ ] ^ _
    return KeyEvent(
      KeyCode.char,
      char: String.fromCharCode(0x40 + c),
      modifiers: mods | Mod.ctrl,
    );
  }

  /// Parses an escape sequence at [pos]; returns bytes consumed, 0 if more
  /// input is needed.
  int _escape(Uint8List b, int pos, List<InputEvent> out, bool eof) {
    if (pos + 1 >= b.length) {
      if (!eof) {
        return 0;
      }
      out.add(const KeyEvent(KeyCode.escape));
      return 1;
    }
    final n = b[pos + 1];
    switch (n) {
      case 0x5B: // [
        return _csi(b, pos, out, eof);
      case 0x4F: // O  (SS3)
        return _ss3Sequence(b, pos, out, eof);
      case 0x5D: // ]  OSC
      case 0x50: // P  DCS
      case 0x5F: // _  APC
      case 0x5E: // ^  PM
        return _stringSequence(b, pos, out, eof, osc: n == 0x5D);
      case 0x1B:
        if (pos + 2 >= b.length && !eof) {
          return 0;
        }
        if (pos + 2 < b.length && (b[pos + 2] == 0x5B || b[pos + 2] == 0x4F)) {
          return _escapePrefixed(b, pos, out, eof);
        }
        out.add(const KeyEvent(KeyCode.escape, modifiers: Mod.alt));
        return 2;
    }
    // Alt + key
    if (n < 0x20 || n == 0x7F) {
      out.add(_control(n, Mod.alt));
      return 2;
    }
    final cp = _utf8At(b, pos + 1, eof);
    final len = _utf8Length;
    if (len == 0) {
      return 0;
    }
    out.add(
      KeyEvent(KeyCode.char, char: String.fromCharCode(cp), modifiers: Mod.alt),
    );
    return 1 + len;
  }

  /// ESC before a key sequence: Alt + that key (how urxvt and the Linux
  /// console send Alt+arrows); before anything else, Escape and then it.
  int _escapePrefixed(Uint8List b, int pos, List<InputEvent> out, bool eof) {
    final inner = <InputEvent>[];
    final n = _escape(b, pos + 1, inner, eof);
    if (n == 0) {
      return 0;
    }
    if (inner
        case [
          KeyEvent(:final code, :final char, :final modifiers, :final kind),
        ]
        when modifiers & Mod.alt == 0) {
      out.add(
        KeyEvent(code, char: char, modifiers: modifiers | Mod.alt, kind: kind),
      );
    } else {
      out
        ..add(const KeyEvent(KeyCode.escape))
        ..addAll(inner);
    }
    return 1 + n;
  }

  /// SS3 (`ESC O x`), also in the old form with a modifier parameter
  /// (`ESC O 5 P`). Anything else after `ESC O` is Alt+O followed by it.
  int _ss3Sequence(Uint8List b, int pos, List<InputEvent> out, bool eof) {
    var i = pos + 2;
    while (i < b.length && b[i] >= 0x30 && b[i] <= 0x39) {
      i++;
    }
    final digits = i > pos + 2;
    if (i >= b.length) {
      if (!eof) {
        return 0;
      }
      if (!digits) {
        out.add(const KeyEvent(KeyCode.char, char: 'O', modifiers: Mod.alt));
        return 2;
      }
      out.add(UnknownSequence(b.sublist(pos)));
      return b.length - pos;
    }
    final f = b[i];
    if (f < 0x40 || f > 0x7E) {
      if (!digits) {
        out.add(const KeyEvent(KeyCode.char, char: 'O', modifiers: Mod.alt));
        return 2;
      }
      out.add(UnknownSequence(b.sublist(pos, i)));
      return i - pos;
    }
    final len = i + 1 - pos;
    final k = _ss3(f);
    // a modifier has at most three digits: more make no key, not phantom
    // ones of the digits left
    if (k == null || i - pos - 2 > 3) {
      out.add(UnknownSequence(b.sublist(pos, pos + len)));
      return len;
    }
    var param = 0; // at most three digits
    for (var k = pos + 2; k < i; k++) {
      param = param * 10 + b[k] - 0x30;
    }
    final mods = digits ? _modifiers(param) : 0;
    out.add(mods == 0 ? k : KeyEvent(k.code, modifiers: mods));
    return len;
  }

  static KeyEvent? _ss3(int f) => switch (f) {
    0x41 => const KeyEvent(KeyCode.up),
    0x42 => const KeyEvent(KeyCode.down),
    0x43 => const KeyEvent(KeyCode.right),
    0x44 => const KeyEvent(KeyCode.left),
    0x48 => const KeyEvent(KeyCode.home),
    0x46 => const KeyEvent(KeyCode.end),
    0x50 => const KeyEvent(KeyCode.f1),
    0x51 => const KeyEvent(KeyCode.f2),
    0x52 => const KeyEvent(KeyCode.f3),
    0x53 => const KeyEvent(KeyCode.f4),
    0x4D => const KeyEvent(KeyCode.enter),
    _ => null,
  };

  /// OSC / DCS / APC / PM: terminated by BEL or ST (ESC \). Any other ESC
  /// aborts the string and starts a new sequence (as in a terminal's own
  /// parser), so a truncated reply can't swallow the input after it.
  int _stringSequence(
    Uint8List b,
    int pos,
    List<InputEvent> out,
    bool eof, {
    required bool osc,
  }) {
    if (pos + 2 >= b.length) {
      if (!eof) {
        return 0;
      }
      // nothing after the introducer: the Alt+key it also is
      out.add(
        KeyEvent(
          KeyCode.char,
          char: String.fromCharCode(b[pos + 1]),
          modifiers: Mod.alt,
        ),
      );
      return 2;
    }
    final from = pos == 0 && _stringScanned > 2 ? _stringScanned : pos + 2;
    var i = from;
    for (; i < b.length; i++) {
      final c = b[i];
      int end;
      if (c == 0x07) {
        end = i + 1;
      } else if (c == 0x1B && i + 1 < b.length && b[i + 1] == 0x5C) {
        end = i + 2;
      } else if (c == 0x1B && i + 1 >= b.length) {
        break; // ST or a new sequence: wait to see which
      } else if (c == 0x1B) {
        out.add(UnknownSequence(b.sublist(pos, i)));
        return i - pos;
      } else {
        continue;
      }
      if (osc) {
        final body = String.fromCharCodes(b.sublist(pos + 2, i));
        out.add(_oscReply(body) ?? UnknownSequence(b.sublist(pos, end)));
      } else {
        out.add(UnknownSequence(b.sublist(pos, end)));
      }
      return end - pos;
    }
    if (eof) {
      out.add(UnknownSequence(b.sublist(pos)));
      return b.length - pos;
    }
    if (pos == 0) {
      _stringScanned = i;
    }
    return 0;
  }

  // "11;rgb:RRRR/GGGG/BBBB" or "4;N;rgb:…", 1 to 4 hex digits per channel
  static final _colorReply = RegExp(
    r'^(1[01]|4;(\d{1,3}));'
    r'rgb:([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})/([0-9a-fA-F]{1,4})$',
  );

  static InputEvent? _oscReply(String body) {
    final m = _colorReply.firstMatch(body);
    if (m == null) {
      return null;
    }
    int ch(String h) {
      final v = int.parse(h, radix: 16);
      final max = (1 << (4 * h.length)) - 1;
      return (v * 255 / max).round();
    }

    final rgb =
        (ch(m.group(3)!) << 16) | (ch(m.group(4)!) << 8) | ch(m.group(5)!);
    final index = m.group(2);
    if (index == null) {
      return ColorReport(int.parse(m.group(1)!), rgb);
    }
    final i = int.parse(index);
    return i > 255 ? null : ColorReport(4, rgb, index: i);
  }

  int _csi(Uint8List b, int pos, List<InputEvent> out, bool eof) {
    var i = pos + 2;
    var prefix = 0;
    if (i < b.length &&
        (b[i] == 0x3C || b[i] == 0x3D || b[i] == 0x3E || b[i] == 0x3F)) {
      prefix = b[i];
      i++;
    }
    final pStart = i;
    while (i < b.length && b[i] >= 0x30 && b[i] <= 0x3B) {
      i++;
    }
    final pEnd = i;
    var inter = 0;
    while (i < b.length && b[i] >= 0x20 && b[i] <= 0x2F) {
      inter = b[i];
      i++;
    }
    if (i >= b.length) {
      if (!eof) {
        return 0;
      }
      if (i == pos + 2) {
        // nothing after the introducer: the Alt+key it also is
        out.add(const KeyEvent(KeyCode.char, char: '[', modifiers: Mod.alt));
        return 2;
      }
      // cut off: its parameters are not text
      out.add(UnknownSequence(b.sublist(pos)));
      return b.length - pos;
    }
    final fin = b[i];
    if (fin == 0x1B) {
      // an ESC aborts the sequence and starts a new one
      out.add(UnknownSequence(b.sublist(pos, i)));
      return i - pos;
    }
    final len = i + 1 - pos;
    if (fin < 0x40 || fin > 0x7E) {
      out.add(UnknownSequence(b.sublist(pos, pos + len)));
      return len;
    }
    if (prefix == 0 &&
        fin == 0x7E &&
        pEnd - pStart == 3 &&
        b[pStart] == 0x32 &&
        b[pStart + 1] == 0x30 &&
        b[pStart + 2] == 0x30) {
      _inPaste = true; // bracketed paste start: CSI 200 ~
      _pasteLength = 0;
      return len;
    }
    final event = _readParams(b, pStart, pEnd)
        ? _mapCsi(prefix, inter, fin)
        : null;
    if (event != null) {
      out.add(event);
      return len;
    }
    // what no mapping knows, off the way of those it does: an X10 mouse
    // report's three bytes after `CSI M`
    if (fin == 0x4D && prefix == 0 && pEnd == pStart && inter == 0) {
      return _x10Mouse(b, pos, i + 1, out, eof);
    }
    out.add(UnknownSequence(b.sublist(pos, pos + len)));
    return len;
  }

  // The parameters of the CSI sequence being decoded, split on ';', each
  // with ':' sub-parameters (an empty one is 0): [_paramCount] of them,
  // parameter i the values `_values[_starts[i] .. _starts[i + 1])` - never
  // none. Reused, so decoding a sequence allocates only its event.
  var _values = List<int>.filled(16, 0);
  var _starts = List<int>.filled(17, 0);
  var _paramCount = 0;

  /// Reads the parameter bytes `b[from..to)` (digits, ':' and ';') into
  /// [_values]; false where a number is too large for an int.
  bool _readParams(Uint8List b, int from, int to) {
    _paramCount = 0;
    if (from == to) {
      return true;
    }
    // at most one value per byte and one more, as many parameters
    if (to - from + 2 > _starts.length) {
      _values = List<int>.filled(to - from + 1, 0);
      _starts = List<int>.filled(to - from + 2, 0);
    }
    final values = _values;
    final starts = _starts;
    var n = 0;
    var count = 0;
    var v = 0;
    var digits = 0; // significant ones
    var numberStart = from;
    for (var i = from; i < to; i++) {
      final c = b[i];
      if (c >= 0x3A) {
        if (digits > 15) {
          final big = _bigParam(b, numberStart, i);
          if (big == null) {
            return false;
          }
          v = big;
        }
        values[n++] = v;
        if (c == 0x3B) {
          starts[++count] = n;
        }
        v = 0;
        digits = 0;
        numberStart = i + 1;
      } else if (digits > 0 || c != 0x30) {
        v = v * 10 + c - 0x30;
        digits++;
      }
    }
    if (digits > 15) {
      final big = _bigParam(b, numberStart, to);
      if (big == null) {
        return false;
      }
      v = big;
    }
    values[n++] = v;
    starts[++count] = n;
    _paramCount = count;
    return true;
  }

  /// The number `b[from..to)`, too long for [_readParams] to add up
  /// exactly on every platform, as `int.parse` reads it; null where it is
  /// too large for an int.
  static int? _bigParam(Uint8List b, int from, int to) =>
      int.tryParse(String.fromCharCodes(b, from, to));

  /// The first value of parameter [i], [d] where there is none.
  int _p(int i, [int d = 0]) => i < _paramCount ? _values[_starts[i]] : d;

  /// Value [k] of parameter [i], [d] where there is none.
  int _sub(int i, int k, [int d = 0]) =>
      i < _paramCount && k < _starts[i + 1] - _starts[i]
      ? _values[_starts[i] + k]
      : d;

  InputEvent? _mapCsi(int prefix, int inter, int fin) {
    final count = _paramCount;
    if (prefix == 0x3C && (fin == 0x4D || fin == 0x6D)) {
      // M, m
      return _sgrMouse(_p(0), _p(1), _p(2), fin == 0x6D);
    }
    if (prefix == 0x3F) {
      if (fin == 0x79 && inter == 0x24) {
        // $ y
        return ModeReport(_p(0), _p(1));
      }
      if (fin == 0x75) {
        // u
        return KeyboardFlagsReport(_p(0));
      }
      if (fin == 0x63) {
        // c
        return DeviceAttributes(<int>[for (var i = 0; i < count; i++) _p(i)]);
      }
      if (fin == 0x6E && _p(0) == 997 && count == 2) {
        // n
        return switch (_p(1)) {
          1 => const ColorSchemeReport(Brightness.dark),
          2 => const ColorSchemeReport(Brightness.light),
          _ => null,
        };
      }
      return null;
    }
    if (prefix != 0) {
      return null;
    }

    final mods = _modifiers(_p(1, 1));
    final kind = switch (_sub(1, 1, 1)) {
      2 => KeyKind.repeat,
      3 => KeyKind.release,
      _ => KeyKind.press,
    };
    switch (fin) {
      case 0x41: // A
        return KeyEvent(KeyCode.up, modifiers: mods, kind: kind);
      case 0x42: // B
        return KeyEvent(KeyCode.down, modifiers: mods, kind: kind);
      case 0x43: // C
        return KeyEvent(KeyCode.right, modifiers: mods, kind: kind);
      case 0x44: // D
        return KeyEvent(KeyCode.left, modifiers: mods, kind: kind);
      case 0x48: // H
        return KeyEvent(KeyCode.home, modifiers: mods, kind: kind);
      case 0x46: // F
        return KeyEvent(KeyCode.end, modifiers: mods, kind: kind);
      case 0x50: // P
        return KeyEvent(KeyCode.f1, modifiers: mods, kind: kind);
      case 0x51: // Q
        return KeyEvent(KeyCode.f2, modifiers: mods, kind: kind);
      case 0x53: // S
        return KeyEvent(KeyCode.f4, modifiers: mods, kind: kind);
      case 0x52: // R
        if (cursorReportsExpected > 0 && count == 2) {
          cursorReportsExpected--;
          return CursorReport(_p(1, 1) - 1, _p(0, 1) - 1);
        }
        return KeyEvent(KeyCode.f3, modifiers: mods, kind: kind);
      case 0x5A: // Z: Shift+Tab, with what else is held where it is told
        return KeyEvent(KeyCode.tab, modifiers: mods | Mod.shift, kind: kind);
      case 0x49: // I
        return const FocusEvent(true);
      case 0x4F: // O
        return const FocusEvent(false);
      case 0x74: // t
        if (_p(0) == 48 && count >= 3) {
          return ResizeEvent(_p(2), _p(1));
        }
        return null;
      case 0x7E: // ~
        final first = _p(0);
        if (first == 27 && count >= 3) {
          // xterm's modifyOtherKeys: CSI 27 ; mods ; code ~
          return _codeKey(_p(2), mods, kind);
        }
        final key = switch (first) {
          1 || 7 => KeyCode.home,
          2 => KeyCode.insert,
          3 => KeyCode.delete,
          4 || 8 => KeyCode.end,
          5 => KeyCode.pageUp,
          6 => KeyCode.pageDown,
          11 => KeyCode.f1,
          12 => KeyCode.f2,
          13 => KeyCode.f3,
          14 => KeyCode.f4,
          15 => KeyCode.f5,
          17 => KeyCode.f6,
          18 => KeyCode.f7,
          19 => KeyCode.f8,
          20 => KeyCode.f9,
          21 => KeyCode.f10,
          23 => KeyCode.f11,
          24 => KeyCode.f12,
          _ => null,
        };
        if (key == null) {
          return null;
        }
        return KeyEvent(key, modifiers: mods, kind: kind);
      case 0x75: // u
        // kitty keyboard protocol:
        //   CSI code[:shifted[:base]] ; mods[:event] [; text] u
        final code = _p(0);
        final key = switch (code) {
          13 => KeyCode.enter,
          9 => KeyCode.tab,
          27 => KeyCode.escape,
          127 => KeyCode.backspace,
          8 => KeyCode.backspace,
          _ => KeyCode.char,
        };
        if (key != KeyCode.char) {
          return KeyEvent(key, modifiers: mods, kind: kind);
        }
        if (code >= _kittyFunctionalFirst && code <= _kittyFunctionalLast) {
          return _kittyFunctionalKey(code, mods, kind);
        }
        if (code < 0x20 || code > 0x10FFFF) {
          return null;
        }
        // a key that types text (no modifier but Shift) is the text it
        // types, Shift taken into it, as without the flags 4, 8 and 16; a
        // shortcut (Ctrl, Alt, Super) is its unshifted key, modifiers kept
        final typed = mods & ~Mod.shift == 0 ? _typedText(mods) : null;
        return KeyEvent(
          KeyCode.char,
          char: typed ?? String.fromCharCode(code),
          modifiers: typed == null ? mods : 0,
          kind: kind,
        );
    }
    return null;
  }

  /// The key xterm's modifyOtherKeys tells by [code], what the key types
  /// (Shift taken into it), with [mods]: one that only Shift modifies is
  /// the text it types, a shortcut a letter's unshifted key, modifiers
  /// kept, as the kitty protocol's are. Null for a code point that is no
  /// character.
  static KeyEvent? _codeKey(int code, int mods, KeyKind kind) {
    final key = switch (code) {
      13 => KeyCode.enter,
      9 => KeyCode.tab,
      27 => KeyCode.escape,
      127 || 8 => KeyCode.backspace,
      _ => KeyCode.char,
    };
    if (key != KeyCode.char) {
      return KeyEvent(key, modifiers: mods, kind: kind);
    }
    if (!_isTextCodePoint(code)) {
      return null;
    }
    if (mods & ~Mod.shift == 0) {
      return KeyEvent(
        KeyCode.char,
        char: String.fromCharCode(code),
        kind: kind,
      );
    }
    final letter = code >= 0x41 && code <= 0x5A ? code + 0x20 : code;
    return KeyEvent(
      KeyCode.char,
      char: String.fromCharCode(letter),
      modifiers: mods,
      kind: kind,
    );
  }

  /// A mouse report in X10's encoding, `CSI M` and three bytes from
  /// [from], each 32 more than the button and the column and row from 1,
  /// as a terminal that ignores SGR's (1006) sends: the event, and not
  /// the three bytes as keys. A byte below 33, which no column or row is,
  /// is read as the first.
  int _x10Mouse(
    Uint8List b,
    int pos,
    int from,
    List<InputEvent> out,
    bool eof,
  ) {
    if (from + 3 > b.length) {
      if (!eof) {
        return 0;
      }
      out.add(UnknownSequence(b.sublist(pos)));
      return b.length - pos;
    }
    int at(int k) => b[from + k] < 0x21 ? 1 : b[from + k] - 0x20;
    final cb = b[from] - 0x20;
    final release = cb & 3 == 3 && cb & (32 | 64) == 0;
    out.add(_sgrMouse(cb < 0 ? 3 : cb, at(1), at(2), release));
    return from + 3 - pos;
  }

  /// What a kitty protocol key that types text types, where its sequence
  /// tells: the associated text (`; text u`, flag 16), else, with Shift
  /// held ([mods]), the shifted key (`code:shifted`, flag 4). Null where
  /// it tells neither, or names a code point that is no character.
  String? _typedText(int mods) {
    if (_paramCount > 2) {
      final from = _starts[2];
      final to = _starts[3];
      var any = false;
      var text = true;
      for (var i = from; i < to; i++) {
        final c = _values[i];
        any = any || c != 0;
        text = text && _isTextCodePoint(c);
      }
      if (any) {
        return text ? String.fromCharCodes(_values, from, to) : null;
      }
    }
    if (mods & Mod.shift != 0 && _paramCount > 0 && _starts[1] > 1) {
      final shifted = _values[1];
      return _isTextCodePoint(shifted) ? String.fromCharCode(shifted) : null;
    }
    return null;
  }

  /// Not a control (C0, DEL, C1), nor a surrogate, nor past Unicode.
  static bool _isTextCodePoint(int c) =>
      c >= 0x20 &&
      (c < 0x7F || c > 0x9F) &&
      (c < 0xD800 || c > 0xDFFF) &&
      c <= 0x10FFFF;

  /// [Mod] bits of a modifier parameter (1 + bits), without the Caps Lock
  /// (64) and Num Lock (128) states the kitty protocol reports with them.
  static int _modifiers(int param) => param < 1 ? 0 : (param - 1) & ~(64 | 128);

  // kitty keyboard protocol: keys without a code point of their own
  // (keypad, F13+, media, lock and modifier keys) use these Private Use
  // Area codes
  static const _kittyFunctionalFirst = 57344;
  static const _kittyFunctionalLast = 57454;
  static const _kittyKeypadFirst = 57399; // KP_0
  static const _kittyKeypadText = '0123456789./*-+';
  static const List<KeyCode?> _kittyKeypadKeys = [
    KeyCode.enter, // 57414 KP_ENTER
    null, // KP_EQUAL, KP_SEPARATOR: text, below
    null,
    KeyCode.left, // 57417
    KeyCode.right,
    KeyCode.up,
    KeyCode.down,
    KeyCode.pageUp,
    KeyCode.pageDown,
    KeyCode.home,
    KeyCode.end,
    KeyCode.insert,
    KeyCode.delete, // 57426
  ];

  /// A keypad key as the key or character it stands for; null for the
  /// keys there is no [KeyCode] for.
  static KeyEvent? _kittyFunctionalKey(int code, int mods, KeyKind kind) {
    final i = code - _kittyKeypadFirst;
    final text = switch (code) {
      57415 => '=',
      57416 => ',',
      _ when i >= 0 && i < _kittyKeypadText.length => _kittyKeypadText[i],
      _ => null,
    };
    if (text != null) {
      return KeyEvent(KeyCode.char, char: text, modifiers: mods, kind: kind);
    }
    final k = i - _kittyKeypadText.length;
    final key = k >= 0 && k < _kittyKeypadKeys.length
        ? _kittyKeypadKeys[k]
        : null;
    return key == null ? null : KeyEvent(key, modifiers: mods, kind: kind);
  }

  // called from two places since X10's reports came, where AOT inlined
  // it at one: a mouse event of the keys benchmark 5 % slower without
  @pragma('vm:prefer-inline')
  static InputEvent _sgrMouse(int cb, int x, int y, bool release) {
    var mods = 0;
    if (cb & 4 != 0) {
      mods |= Mod.shift;
    }
    if (cb & 8 != 0) {
      mods |= Mod.alt;
    }
    if (cb & 16 != 0) {
      mods |= Mod.ctrl;
    }
    final motion = cb & 32 != 0;
    final extra = cb & 128 != 0; // buttons 8-11 (back, forward, ...)
    final wheel = cb & 64 != 0 && !extra;
    final low = cb & 3;
    final MouseKind kind;
    if (wheel) {
      kind = switch (low) {
        0 => MouseKind.wheelUp,
        1 => MouseKind.wheelDown,
        2 => MouseKind.wheelLeft,
        _ => MouseKind.wheelRight,
      };
    } else if (motion) {
      kind = low == 3 && !extra ? MouseKind.move : MouseKind.drag;
    } else {
      kind = release ? MouseKind.up : MouseKind.down;
    }
    return MouseEvent(
      kind,
      x - 1,
      y - 1,
      button: extra ? 8 + low : (wheel || low == 3 ? 0 : low),
      modifiers: mods,
    );
  }
}

/// What [InputParser] drops of a sequence it gave up.
enum _Drop { none, csi, string, stringEsc }
