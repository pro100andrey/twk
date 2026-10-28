/// Text read apart from the escape sequences and controls in it, for
/// [AnsiStream] to act on them and [stripAnsi] to take them out:
/// [EscapeReader].
///
/// @docImport 'stream.dart';
/// @docImport 'strip.dart';
library;

/// Reads text with escape sequences in it, a piece at a time, telling its
/// runs of [text] from the [control]s a terminal acts on and the [csi] and
/// [osc] sequences, and passing over every other escape sequence, the DCS,
/// APC, PM and SOS strings, and the other C1 controls.
///
/// A C0 control within an escape or a CSI is a [control], and the sequence
/// goes on after it; CAN and SUB cancel a sequence, and ESC or a C1 control
/// ends it and starts the next. A piece may end within a sequence: the next
/// piece goes on with it.
final class EscapeReader {
  /// A reader in the ground state, handing what it reads to [text],
  /// [control], [csi] and [osc]; a CSI without [csi], or an OSC without
  /// [osc], is passed over as the other sequences are.
  EscapeReader({required this.text, required this.control, this.csi, this.osc});

  /// Takes a run of characters that are not controls.
  final void Function(String text) text;

  /// Takes a C0 control other than ESC, or DEL, that is out of a sequence,
  /// or a C0 control other than ESC, CAN and SUB within an escape or a CSI.
  final void Function(int control) control;

  /// Takes the parameter bytes and the final byte of a CSI with neither a
  /// private marker nor an intermediate byte, of 64 parameter bytes at
  /// most.
  final void Function(String params, int last)? csi;

  /// Takes the string of an OSC, of 8192 code units at most, ended by BEL,
  /// ESC or ST.
  final void Function(String string)? osc;

  int _state = _ground;

  /// Parameter bytes of the CSI being read.
  final _params = StringBuffer();

  /// Whether the CSI being read has a private marker, or is malformed or
  /// too long.
  var _csiOther = false;

  /// Whether the CSI being read has an intermediate byte.
  var _csiIntermediate = false;

  /// The string of the OSC being read, or null when it is too long or
  /// there is no [osc] to take it.
  StringBuffer? _osc;

  /// Reads [s], going on with the sequence the last piece ended in.
  void read(String s) {
    var start = -1;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (_state == _ground) {
        if (c >= 0x20 && c != 0x7F && (c < 0x80 || c >= 0xA0)) {
          if (start < 0) {
            start = i;
          }
          continue;
        }
        if (start >= 0) {
          text(s.substring(start, i));
          start = -1;
        }
        _control(c);
      } else if (!_sequence(c)) {
        i--;
      }
    }
    if (start >= 0) {
      text(s.substring(start));
    }
  }

  /// Drops the sequence being read.
  void end() => _state = _ground;

  /// Acts on control [c] out of a sequence, and on ESC and C1 controls
  /// within one.
  void _control(int c) {
    switch (c) {
      case 0x1B:
        _state = _escape;
      case >= 0x80 && < 0xA0:
        _c1(c);
      default:
        control(c);
    }
  }

  /// Acts on the C1 control [c]: one that starts a sequence starts it, and
  /// any other ends the one being read.
  void _c1(int c) {
    switch (c) {
      case 0x9B:
        _startCsi();
      case 0x9D:
        _startOsc();
      case 0x90 || 0x98 || 0x9E || 0x9F:
        _state = _string;
      default:
        _state = _ground;
    }
  }

  /// Reads [c] within a sequence; false when [c] ends it without being part
  /// of it, to be read again as text.
  bool _sequence(int c) {
    if (c == 0x1B || (c >= 0x80 && c < 0xA0)) {
      if (_state == _oscString && (c == 0x1B || c == 0x9C)) {
        _endOsc();
      }
      _control(c);
      return true;
    }
    if (c == 0x18 || c == 0x1A) {
      _state = _ground;
      return true;
    }
    switch (_state) {
      case _escape:
        switch (c) {
          case < 0x20:
            control(c);
          case 0x5B:
            _startCsi();
          case 0x5D:
            _startOsc();
          case 0x50 || 0x58 || 0x5E || 0x5F:
            _state = _string;
          case <= 0x2F:
            _state = _escapeIntermediate;
          case < 0x7F:
            _state = _ground;
          case 0x7F:
            break;
          default:
            _state = _ground;
            return false;
        }
      case _escapeIntermediate:
        switch (c) {
          case < 0x20:
            control(c);
          case <= 0x2F || 0x7F:
            break;
          case < 0x7F:
            _state = _ground;
          default:
            _state = _ground;
            return false;
        }
      case _csi:
        switch (c) {
          case < 0x20:
            control(c);
          case <= 0x2F:
            _csiIntermediate = true;
          case >= 0x3C && <= 0x3F:
            // a private marker, or a malformed CSI where it is not first
            _csiOther = true;
          case <= 0x3B:
            if (_csiIntermediate || _params.length >= _maxParams) {
              _csiOther = true;
            } else {
              _params.writeCharCode(c);
            }
          case < 0x7F:
            _state = _ground;
            if (!_csiOther && !_csiIntermediate) {
              csi?.call(_params.toString(), c);
            }
          case 0x7F:
            break;
          default:
            _state = _ground;
            return false;
        }
      case _oscString:
        if (c == 0x07) {
          _endOsc();
          _state = _ground;
        } else if (c >= 0x20 && c != 0x7F) {
          final osc = _osc;
          if (osc != null) {
            if (osc.length < _maxOsc) {
              osc.writeCharCode(c);
            } else {
              _osc = null;
            }
          }
        }
      case _string:
        break;
    }
    return true;
  }

  void _startCsi() {
    _params.clear();
    _csiOther = false;
    _csiIntermediate = false;
    _state = _csi;
  }

  void _startOsc() {
    _osc = osc == null ? null : StringBuffer();
    _state = _oscString;
  }

  void _endOsc() {
    final string = _osc?.toString();
    _osc = null;
    if (string != null) {
      osc?.call(string);
    }
  }
}

// States of reading.
const _ground = 0;
const _escape = 1;
const _escapeIntermediate = 2;
const _csi = 3;
const _oscString = 4;

/// A DCS, SOS, PM or APC string, passed over whole.
const _string = 5;

/// The most parameter bytes a CSI is read with.
const _maxParams = 64;

/// The most code units an OSC is read with.
const _maxOsc = 8192;
