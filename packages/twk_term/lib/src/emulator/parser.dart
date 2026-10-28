/// The byte-level state machine of a DEC/xterm terminal (after Paul
/// Williams' VT500 parser): UTF-8 text in runs, C0 controls, ESC, CSI with
/// sub-parameters, OSC, DCS and the strings a terminal skips (SOS, PM,
/// APC). C1 controls as single bytes are not recognised: the input is
/// UTF-8, where 0x80..0x9F are parts of characters.
library;

import 'dart:typed_data';

/// What the parser hands its sequences to.
abstract interface class VtHandler {
  /// Printable ASCII, `data[start, end)`.
  void printAscii(Uint8List data, int start, int end);

  /// Printable text with characters beyond ASCII (decoded from UTF-8, a
  /// malformed sequence as U+FFFD).
  void printText(String text);

  /// A C0 control (or DEL, which is ignored).
  void execute(int byte);

  /// `ESC [intermediates] final`; [intermediates] packed as in
  /// [VtParser.intermediates].
  void escDispatch(int intermediates, int finalByte);

  /// `CSI [prefix] params [intermediates] final`.
  void csiDispatch(VtParams params, int prefix, int intermediates, int final_);

  /// `OSC data (BEL | ST)`: the payload, and whether it ended with BEL
  /// (an answer ends the same way).
  void oscDispatch(Uint8List data, int length, {required bool bel});

  /// `DCS [prefix] params [intermediates] final data ST`.
  void dcsDispatch(
    VtParams params,
    int prefix,
    int intermediates,
    int final_,
    Uint8List data,
    int length,
  );
}

/// Parameters of a CSI or DCS sequence. A parameter left out is -1; a
/// sub-parameter (after `:`) is flagged by [isSub].
final class VtParams {
  /// The most parameters a sequence keeps; those past it are dropped.
  static const max = 32;

  /// The parameters, the first [length] of them set: each a number, or -1
  /// where it was left out.
  final values = Int32List(max);

  /// How many of [values] the sequence has.
  var length = 0;
  var _sub = 0;

  /// Parameter [i], or [fallback] when it is missing or out of range.
  @pragma('vm:prefer-inline')
  int at(int i, [int fallback = 0]) {
    if (i >= length) {
      return fallback;
    }
    final v = values[i];
    return v < 0 ? fallback : v;
  }

  /// Parameter [i] where 0 and missing mean 1 (counts and positions).
  @pragma('vm:prefer-inline')
  int count(int i) {
    final v = at(i);
    return v == 0 ? 1 : v;
  }

  /// Whether parameter [i] is a sub-parameter of the one before (`:`).
  bool isSub(int i) => (_sub >> i) & 1 != 0;

  void _reset() {
    length = 0;
    _sub = 0;
  }

  @override
  String toString() => [
    for (var i = 0; i < length; i++) '${isSub(i) ? ':' : ';'}${values[i]}',
  ].join();
}

enum _State {
  ground,
  escape,
  escapeIntermediate,
  csiEntry,
  csiParam,
  csiIntermediate,
  csiIgnore,
  oscString,
  dcsEntry,
  dcsParam,
  dcsIntermediate,
  dcsPassthrough,
  dcsIgnore,
  ignoreString,
}

/// Feeds bytes to a [VtHandler]. Sequences may be split across [feed]
/// calls anywhere, a UTF-8 character too.
final class VtParser {
  /// A parser in the ground state, handing what it reads to [handler].
  VtParser(this.handler);

  /// What the parser hands its text, controls and sequences to.
  final VtHandler handler;

  /// The most bytes of an OSC or DCS string kept; the rest is dropped (the
  /// sequence is still dispatched, cut).
  static const int maxString = 1 << 20;

  _State _state = _State.ground;
  final _params = VtParams();

  /// More parameters than [VtParams.max] came: the rest are dropped.
  var _dropping = false;
  var _prefix = 0;

  /// Up to two intermediate bytes, the first in the low byte; 0xFFFF when
  /// there were more (the sequence is ignored).
  var intermediates = 0;
  var _string = Uint8List(256);
  var _stringLength = 0;
  var _dcsFinal = 0;

  /// ESC seen inside a string: a following `\` ends it (ST).
  var _stringEsc = false;

  // UTF-8 decoding across feeds.
  var _need = 0;
  var _cp = 0;
  var _min = 0;
  var _text = Uint16List(256);

  /// Back to the ground state, a partial sequence or character dropped.
  void reset() {
    _state = _State.ground;
    _need = 0;
    _stringEsc = false;
  }

  /// Reads [bytes], handing [handler] each piece of text, control and
  /// sequence they complete; one they start and don't end is completed by
  /// the next call.
  void feed(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final end = data.length;
    var i = 0;
    while (i < end) {
      final b = data[i];
      if (_state == _State.ground) {
        if (b >= 0x20 && b != 0x7F) {
          i = _printRun(data, i, end);
          continue;
        }
        if (_need > 0) {
          _flushPartial();
        }
        i++;
        if (b == 0x1B) {
          _enterEscape();
        } else {
          handler.execute(b);
        }
        continue;
      }
      i++;
      _advance(b);
    }
  }

  /// Prints the run of text bytes from [start]; returns where it ended.
  int _printRun(Uint8List data, int start, int end) {
    var j = start;
    var high = 0;
    while (j < end) {
      final b = data[j];
      if (b < 0x20 || b == 0x7F) {
        break;
      }
      high |= b;
      j++;
    }
    if (high < 0x80 && _need == 0) {
      handler.printAscii(data, start, j);
      return j;
    }
    // long stretches of ASCII between the rest go as ASCII; a mark after
    // one still joins its last character (the handler joins it)
    var from = start;
    for (var k = start; k < j;) {
      if (data[k] >= 0x80) {
        k++;
        continue;
      }
      var m = k + 1;
      while (m < j && data[m] < 0x80) {
        m++;
      }
      if (m - k >= _asciiStretch) {
        if (k > from) {
          _decode(data, from, k);
        }
        if (_need > 0) {
          _flushPartial();
        }
        handler.printAscii(data, k, m);
        from = m;
      }
      k = m;
    }
    if (from < j) {
      _decode(data, from, j);
    }
    return j;
  }

  /// The shortest stretch of ASCII in other text printed as ASCII.
  static const _asciiStretch = 16;

  void _decode(Uint8List data, int start, int end) {
    if (_text.length < end - start + 2) {
      _text = Uint16List((end - start + 2) * 2);
    }
    final out = _text;
    var n = 0;
    var need = _need;
    var cp = _cp;
    var min = _min;
    for (var i = start; i < end; i++) {
      final b = data[i];
      if (need > 0) {
        if (b & 0xC0 == 0x80) {
          cp = (cp << 6) | (b & 0x3F);
          if (--need == 0) {
            final bad = cp < min || (cp >= 0xD800 && cp < 0xE000);
            n = _putCp(out, n, bad ? 0xFFFD : cp);
          }
          continue;
        }
        need = 0;
        out[n++] = 0xFFFD; // cut short: the byte starts something new
      }
      if (b < 0x80) {
        out[n++] = b;
      } else if (b & 0xE0 == 0xC0) {
        cp = b & 0x1F;
        need = 1;
        min = 0x80;
      } else if (b & 0xF0 == 0xE0) {
        cp = b & 0x0F;
        need = 2;
        min = 0x800;
      } else if (b & 0xF8 == 0xF0 && b <= 0xF4) {
        cp = b & 0x07;
        need = 3;
        min = 0x10000;
      } else {
        out[n++] = 0xFFFD;
      }
    }
    _need = need;
    _cp = cp;
    _min = min;
    if (n > 0) {
      handler.printText(String.fromCharCodes(out, 0, n));
    }
  }

  @pragma('vm:prefer-inline')
  static int _putCp(Uint16List out, int n, int cp) {
    if (cp > 0x10FFFF) {
      out[n] = 0xFFFD;
      return n + 1;
    }
    if (cp < 0x10000) {
      out[n] = cp;
      return n + 1;
    }
    final v = cp - 0x10000;
    out[n] = 0xD800 | (v >> 10);
    out[n + 1] = 0xDC00 | (v & 0x3FF);
    return n + 2;
  }

  /// A character cut short by a control: printed as U+FFFD.
  void _flushPartial() {
    _need = 0;
    handler.printText('\uFFFD');
  }

  void _enterEscape() {
    _state = _State.escape;
    intermediates = 0;
  }

  void _clearParams() {
    _params._reset();
    _dropping = false;
    _prefix = 0;
    intermediates = 0;
  }

  void _collect(int b) {
    if (intermediates == 0) {
      intermediates = b;
    } else if (intermediates < 0x100) {
      intermediates |= b << 8;
    } else {
      intermediates = 0xFFFF;
    }
  }

  void _paramByte(int b) {
    final p = _params;
    if (b >= 0x30 && b <= 0x39) {
      if (_dropping) {
        return;
      }
      if (p.length == 0) {
        p.length = 1;
        p.values[0] = -1;
      }
      final v = p.values[p.length - 1];
      final d = (v < 0 ? 0 : v) * 10 + b - 0x30;
      p.values[p.length - 1] = d > 0xFFFF ? 0xFFFF : d;
      return;
    }
    // ';' or ':' starts the next parameter
    if (p.length == 0) {
      p.length = 1;
      p.values[0] = -1;
    }
    if (p.length < VtParams.max) {
      if (b == 0x3A) {
        p._sub |= 1 << p.length;
      }
      p.values[p.length++] = -1;
    } else {
      _dropping = true;
    }
  }

  void _stringPut(int b) {
    if (_stringLength == _string.length) {
      if (_stringLength >= maxString) {
        return;
      }
      _string = Uint8List(_string.length * 2)..setAll(0, _string);
    }
    _string[_stringLength++] = b;
  }

  /// One byte in any state but ground.
  void _advance(int b) {
    // anywhere: CAN and SUB abort, ESC starts over (in a string it may be
    // the start of ST)
    if (b == 0x18 || b == 0x1A) {
      _state = _State.ground;
      _stringEsc = false;
      return;
    }
    switch (_state) {
      case _State.ground:
        break;
      case _State.escape:
        if (b == 0x1B) {
          _enterEscape();
        } else if (b < 0x20) {
          handler.execute(b);
        } else if (b < 0x30) {
          _collect(b);
          _state = _State.escapeIntermediate;
        } else if (b == 0x5B) {
          _clearParams();
          _state = _State.csiEntry;
        } else if (b == 0x5D) {
          _stringLength = 0;
          _state = _State.oscString;
        } else if (b == 0x50) {
          _clearParams();
          _state = _State.dcsEntry;
        } else if (b == 0x58 || b == 0x5E || b == 0x5F) {
          _state = _State.ignoreString;
        } else if (b < 0x7F) {
          _state = _State.ground;
          handler.escDispatch(0, b);
        }
      case _State.escapeIntermediate:
        if (b == 0x1B) {
          _enterEscape();
        } else if (b < 0x20) {
          handler.execute(b);
        } else if (b < 0x30) {
          _collect(b);
        } else if (b < 0x7F) {
          _state = _State.ground;
          if (intermediates != 0xFFFF) {
            handler.escDispatch(intermediates, b);
          }
        }
      case _State.csiEntry || _State.csiParam:
        if (b == 0x1B) {
          _enterEscape();
        } else if (b < 0x20) {
          handler.execute(b);
        } else if (b < 0x30) {
          _collect(b);
          _state = _State.csiIntermediate;
        } else if (b < 0x3C) {
          _paramByte(b);
          _state = _State.csiParam;
        } else if (b < 0x40) {
          // a private marker opens the sequence; later it's malformed
          if (_state == _State.csiEntry) {
            _prefix = b;
            _state = _State.csiParam;
          } else {
            _state = _State.csiIgnore;
          }
        } else if (b < 0x7F) {
          _state = _State.ground;
          handler.csiDispatch(_params, _prefix, intermediates, b);
        }
      case _State.csiIntermediate:
        if (b == 0x1B) {
          _enterEscape();
        } else if (b < 0x20) {
          handler.execute(b);
        } else if (b < 0x30) {
          _collect(b);
        } else if (b < 0x40) {
          _state = _State.csiIgnore;
        } else if (b < 0x7F) {
          _state = _State.ground;
          if (intermediates != 0xFFFF) {
            handler.csiDispatch(_params, _prefix, intermediates, b);
          }
        }
      case _State.csiIgnore:
        if (b == 0x1B) {
          _enterEscape();
        } else if (b < 0x20) {
          handler.execute(b);
        } else if (b >= 0x40 && b < 0x7F) {
          _state = _State.ground;
        }
      case _State.oscString:
        if (_stringEsc) {
          _stringEsc = false;
          _state = _State.ground;
          handler.oscDispatch(_string, _stringLength, bel: false);
          if (b != 0x5C) {
            // an ESC that is no ST ends the string and starts a sequence
            _enterEscape();
            _advance(b);
          }
        } else if (b == 0x07) {
          _state = _State.ground;
          handler.oscDispatch(_string, _stringLength, bel: true);
        } else if (b == 0x1B) {
          _stringEsc = true;
        } else if (b >= 0x20) {
          _stringPut(b);
        }
      case _State.dcsEntry || _State.dcsParam:
        if (b == 0x1B) {
          _enterEscape();
        } else if (b < 0x20) {
          // ignored
        } else if (b < 0x30) {
          _collect(b);
          _state = _State.dcsIntermediate;
        } else if (b < 0x3C) {
          _paramByte(b);
          _state = _State.dcsParam;
        } else if (b < 0x40) {
          if (_state == _State.dcsEntry) {
            _prefix = b;
            _state = _State.dcsParam;
          } else {
            _state = _State.dcsIgnore;
          }
        } else if (b < 0x7F) {
          _dcsStart(b);
        }
      case _State.dcsIntermediate:
        if (b == 0x1B) {
          _enterEscape();
        } else if (b < 0x20) {
          // ignored
        } else if (b < 0x30) {
          _collect(b);
        } else if (b < 0x40) {
          _state = _State.dcsIgnore;
        } else if (b < 0x7F) {
          _dcsStart(b);
        }
      case _State.dcsPassthrough:
        if (_stringEsc) {
          _stringEsc = false;
          _state = _State.ground;
          if (intermediates != 0xFFFF) {
            handler.dcsDispatch(
              _params,
              _prefix,
              intermediates,
              _dcsFinal,
              _string,
              _stringLength,
            );
          }
          if (b != 0x5C) {
            _enterEscape();
            _advance(b);
          }
        } else if (b == 0x1B) {
          _stringEsc = true;
        } else {
          _stringPut(b);
        }
      case _State.dcsIgnore || _State.ignoreString:
        if (_stringEsc) {
          _stringEsc = false;
          if (b == 0x5C) {
            _state = _State.ground;
          } else {
            _enterEscape();
            _advance(b);
          }
        } else if (b == 0x1B) {
          _stringEsc = true;
        } else if (b == 0x07 && _state == _State.ignoreString) {
          _state = _State.ground; // as xterm, BEL ends an APC too
        }
    }
  }

  void _dcsStart(int b) {
    if (b == 0x71 && intermediates == 0) {
      _state = _State.dcsIgnore; // sixel graphics: not kept
      return;
    }
    _dcsFinal = b;
    _stringLength = 0;
    _state = _State.dcsPassthrough;
  }
}
