part of 'emulator.dart';

/// What the parser found, applied to the emulator.
final class _Dispatch implements VtHandler {
  _Dispatch(this.t);

  final TerminalEmulator t;

  @override
  void printAscii(Uint8List data, int start, int end) =>
      t._printAscii(data, start, end);

  @override
  void printText(String text) => t._printText(text);

  @override
  void execute(int byte) {
    switch (byte) {
      case 0x07:
        t._event(const BellRang());
      case 0x08:
        t._setColumn(t._x - 1);
      case 0x09:
        t._tab(1);
      case 0x0A || 0x0B || 0x0C:
        t._index();
        if (t.mode(TerminalMode.newLine)) {
          t._x = 0;
        }
        t._pendingWrap = false;
      case 0x0D:
        t._x = 0;
        t._pendingWrap = false;
      case 0x0E:
        t._gl = 1;
      case 0x0F:
        t._gl = 0;
      default:
      // NUL, ENQ, DEL and the rest: nothing
    }
  }

  @override
  void escDispatch(int intermediates, int finalByte) {
    if (intermediates == 0) {
      switch (finalByte) {
        case 0x37: // 7 DECSC
          t._saveCursor();
        case 0x38: // 8 DECRC
          t._restoreCursor();
        case 0x44: // D IND
          t
            .._index()
            .._pendingWrap = false;
        case 0x45: // E NEL
          t
            .._index()
            .._x = 0
            .._pendingWrap = false;
        case 0x48: // H HTS
          t._tabs[t._x] = 1;
        case 0x4D: // M RI
          t
            .._reverseIndex()
            .._pendingWrap = false;
        case 0x63: // c RIS
          t.reset();
        case 0x3D: // = DECKPAM
          t._setMode(TerminalMode.keypad, on: true);
        case 0x3E: // > DECKPNM
          t._setMode(TerminalMode.keypad, on: false);
        case 0x4E: // N SS2
          t._singleShift = 2;
        case 0x4F: // O SS3
          t._singleShift = 3;
        case 0x6E: // n LS2
          t._gl = 2;
        case 0x6F: // o LS3
          t._gl = 3;
        case 0x5C || 0x7C || 0x7D || 0x7E: // ST, LS3R, LS2R, LS1R
          break;
        default:
          t._unknown('ESC ${String.fromCharCode(finalByte)}');
      }
      return;
    }
    if (intermediates == 0x23) {
      if (finalByte == 0x38) {
        t._alignmentTest(); // ESC # 8
      }
      return; // double width and height lines: drawn single
    }
    if (intermediates >= 0x28 && intermediates <= 0x2B) {
      // ESC ( ) * + designate G0..G3
      t._charsets[intermediates - 0x28] = switch (finalByte) {
        0x30 => _decGraphics,
        0x41 => _uk,
        _ => _ascii,
      };
      return;
    }
    if (intermediates == 0x25 || intermediates == 0x20) {
      return; // ESC % G (UTF-8), ESC SP F (7-bit controls): as they are
    }
    final inter = String.fromCharCodes([
      intermediates & 0xFF,
      if (intermediates > 0xFF) intermediates >> 8,
    ]);
    t._unknown('ESC $inter${String.fromCharCode(finalByte)}');
  }

  @override
  void csiDispatch(VtParams p, int prefix, int intermediates, int final_) {
    if (intermediates != 0) {
      _csiIntermediate(p, prefix, intermediates, final_);
      return;
    }
    if (prefix != 0) {
      _csiPrivate(p, prefix, final_);
      return;
    }
    switch (final_) {
      case 0x40: // @ ICH
        t._insertChars(p.count(0));
      case 0x41: // A CUU
        t._cursorUp(p.count(0));
      case 0x42 || 0x65: // B CUD, e VPR
        t._cursorDown(p.count(0));
      case 0x43 || 0x61: // C CUF, a HPR
        t._setColumn(t._x + p.count(0));
      case 0x44: // D CUB
        t._setColumn(t._x - p.count(0));
      case 0x45: // E CNL
        t
          .._cursorDown(p.count(0))
          .._x = 0;
      case 0x46: // F CPL
        t
          .._cursorUp(p.count(0))
          .._x = 0;
      case 0x47 || 0x60: // G CHA, ` HPA
        t._setColumn(p.count(0) - 1);
      case 0x48 || 0x66: // H CUP, f HVP
        t._moveTo(p.count(1) - 1, p.count(0) - 1);
      case 0x49: // I CHT
        t._tab(p.count(0));
      case 0x4A: // J ED
        t._eraseDisplay(p.at(0));
      case 0x4B: // K EL
        t._eraseLine(p.at(0));
      case 0x4C: // L IL
        t._insertLines(p.count(0), delete: false);
      case 0x4D: // M DL
        t._insertLines(p.count(0), delete: true);
      case 0x50: // P DCH
        t._deleteChars(p.count(0));
      case 0x53: // S SU
        t._scrollUp(p.count(0));
      case 0x54: // T SD (with more parameters: mouse highlighting, ignored)
        if (p.length <= 1) {
          t._scrollDown(p.count(0));
        }
      case 0x58: // X ECH
        t._screen.lines[t._y].erase(t._x, t._x + p.count(0), t._eraseStyleNow);
        t._pendingWrap = false;
      case 0x5A: // Z CBT
        t._backTab(p.count(0));
      case 0x62: // b REP
        t._repeat(p.count(0));
      case 0x63: // c DA1
        if (p.at(0) == 0) {
          t._reply('\x1b[?62;22;52c');
        }
      case 0x64: // d VPA
        t._moveTo(t._x, p.count(0) - 1);
      case 0x67: // g TBC
        switch (p.at(0)) {
          case 0:
            t._tabs[t._x] = 0;
          case 3:
            t._tabs.fillRange(0, t._tabs.length, 0);
        }
      case 0x68 || 0x6C: // h SM, l RM
        for (var i = 0; i < p.length; i++) {
          final m = TerminalMode.of(p.at(i), private: false);
          if (m == null) {
            t._unknown('CSI ${p.at(i)} ${String.fromCharCode(final_)}');
          } else {
            t._applyMode(m, on: final_ == 0x68);
          }
        }
      case 0x6D: // m SGR
        _sgr(p);
      case 0x6E: // n DSR
        switch (p.at(0)) {
          case 5:
            t._reply('\x1b[0n');
          case 6:
            t._reply('\x1b[${_reportRow()};${t._x + 1}R');
        }
      case 0x72: // r DECSTBM
        final top = p.count(0) - 1;
        final bottom = p.at(1) == 0 || p.at(1) > t._height
            ? t._height
            : p.at(1);
        if (top < bottom - 1) {
          t
            .._top = top
            .._bottom = bottom
            .._moveTo(0, 0);
        }
      case 0x73: // s SCOSC
        t._saveCursor();
      case 0x75: // u SCORC
        t._restoreCursor();
      case 0x74: // t XTWINOPS
        _windowOps(p);
      case 0x71 || 0x78: // q DECLL, x DECREQTPARM
        break;
      default:
        t._unknown('CSI $p ${String.fromCharCode(final_)}');
    }
  }

  int _reportRow() => t._y + 1 - (t.mode(TerminalMode.origin) ? t._top : 0);

  void _csiPrivate(VtParams p, int prefix, int final_) {
    switch ((prefix, final_)) {
      case (0x3F, 0x68 || 0x6C): // ? h DECSET, ? l DECRST
        for (var i = 0; i < p.length; i++) {
          t._privateMode(p.at(i), on: final_ == 0x68);
        }
      case (0x3F, 0x4A): // ? J DECSED
        t._eraseDisplay(p.at(0));
      case (0x3F, 0x4B): // ? K DECSEL
        t._eraseLine(p.at(0));
      case (0x3F, 0x6E): // ? n DSR
        switch (p.at(0)) {
          case 6:
            t._reply('\x1b[?${_reportRow()};${t._x + 1}R');
          case 15:
            t._reply('\x1b[?13n'); // no printer
          case 25:
            t._reply('\x1b[?21n'); // UDKs locked
          case 26:
            t._reply('\x1b[?27;1;0;0n'); // North American keyboard, ready
          case 996:
            final dark = Brightness.ofRgb(t.backgroundColor) == Brightness.dark;
            t._reply('\x1b[?997;${dark ? 1 : 2}n');
        }
      case (0x3F, 0x73): // ? s XTSAVE
        for (var i = 0; i < p.length; i++) {
          final m = TerminalMode.of(p.at(i), private: true);
          if (m != null) {
            t._savedModes[m] = t.mode(m);
          }
        }
      case (0x3F, 0x72): // ? r XTRESTORE
        for (var i = 0; i < p.length; i++) {
          final m = TerminalMode.of(p.at(i), private: true);
          final on = m == null ? null : t._savedModes[m];
          if (on != null) {
            t._privateMode(p.at(i), on: on);
          }
        }
      case (0x3E, 0x63): // > c DA2
        if (p.at(0) == 0) {
          t._reply('\x1b[>1;10;0c');
        }
      case (0x3D, 0x63): // = c DA3
        if (p.at(0) == 0) {
          t._reply('\x1bP!|00000000\x1b\\');
        }
      case (0x3E, 0x71): // > q XTVERSION
        if (p.at(0) == 0) {
          t._reply('\x1bP>|twk_term 0.1.0\x1b\\');
        }
      case (0x3F, 0x75): // ? u: the kitty keyboard flags asked for
        t._reply('\x1b[?${t.keyboardFlags}u');
      case (0x3E, 0x75): // > u: pushed
        final flags = t._screen.keyFlags..add(p.at(0) & 0x1F);
        if (flags.length > _keyFlagsDepth) {
          flags.removeAt(0);
        }
      case (0x3C, 0x75): // < u: popped
        final flags = t._screen.keyFlags;
        final n = p.count(0);
        if (n >= flags.length) {
          flags
            ..clear()
            ..add(0);
        } else {
          flags.length -= n;
        }
      case (0x3D, 0x75): // = u: set, or'ed or and'ed off
        final flags = t._screen.keyFlags;
        final f = p.at(0) & 0x1F;
        flags.last = switch (p.at(1)) {
          2 => flags.last | f,
          3 => flags.last & ~f,
          _ => f,
        };
      case (0x3E, 0x6D || 0x6E || 0x74 || 0x54 || 0x66 || 0x70):
      // XTMODKEYS, XTFMTKEYS, title modes, pointer mode: nothing to do
      case (0x3F, 0x6D || 0x53 || 0x57):
        // XTQMODKEYS, XTSMGRAPHICS, DECST8C
        break;
      default:
        t._unknown(
          'CSI ${String.fromCharCode(prefix)}$p ${String.fromCharCode(final_)}',
        );
    }
  }

  void _csiIntermediate(VtParams p, int prefix, int inter, int final_) {
    switch ((prefix, inter, final_)) {
      case (0, 0x20, 0x71): // SP q DECSCUSR
        final shape = switch (p.at(0)) {
          0 => CursorShape.terminalDefault, // the host's own
          1 => CursorShape.blinkingBlock,
          2 => CursorShape.block,
          3 => CursorShape.blinkingUnderline,
          4 => CursorShape.underline,
          5 => CursorShape.blinkingBar,
          6 => CursorShape.bar,
          _ => null,
        };
        if (shape != null && shape != t._cursorShape) {
          t._cursorShape = shape;
          t._event(CursorShapeChanged(shape));
        }
      case (0, 0x21, 0x70): // ! p DECSTR
        t._softReset();
      case (0x3F, 0x24, 0x70): // ? $ p DECRQM
        final code = p.at(0);
        t._reply('\x1b[?$code;${t._privateModeValue(code)}\$y');
      case (0, 0x24, 0x70): // $ p DECRQM (ANSI)
        final code = p.at(0);
        final m = TerminalMode.of(code, private: false);
        final v = m == null ? 0 : (t.mode(m) ? 1 : 2);
        t._reply('\x1b[$code;$v\$y');
      case (0, 0x22, 0x70 || 0x71): // " p DECSCL, " q DECSCA
      case (0, 0x27, _): // DECIC, DECDC, locator: not spoken
      case (0, 0x2A, 0x78): // * x DECSACE
        break;
      default:
        t._unknown(
          'CSI ${prefix == 0 ? '' : String.fromCharCode(prefix)}$p'
          '${String.fromCharCode(inter & 0xFF)}${String.fromCharCode(final_)}',
        );
    }
  }

  // ---------------------------------------------------------------- SGR --

  void _sgr(VtParams p) {
    if (p.length == 0) {
      t._sgrReset();
      return;
    }
    var i = 0;
    while (i < p.length) {
      final v = p.at(i);
      var next = i + 1;
      while (next < p.length && p.isSub(next)) {
        next++; // sub-parameters belong to this one
      }
      switch (v) {
        case 0:
          t._sgrReset();
        case 1:
          t._attrs |= Attr.bold;
        case 2:
          t._attrs |= Attr.dim;
        case 3:
          t._attrs |= Attr.italic;
        case 4:
          final style = next > i + 1 ? p.at(i + 1) : 1;
          t._attrs =
              (t._attrs & ~Attr.underlineMask) |
              (style >= 0 && style <= 5 ? style << 3 : Attr.underline);
        case 5 || 6:
          t._attrs |= Attr.blink;
        case 7:
          t._attrs |= Attr.reverse;
        case 8:
          t._attrs |= Attr.hidden;
        case 9:
          t._attrs |= Attr.strike;
        case 21:
          t._attrs = (t._attrs & ~Attr.underlineMask) | Attr.doubleUnderline;
        case 22:
          t._attrs &= ~(Attr.bold | Attr.dim);
        case 23:
          t._attrs &= ~Attr.italic;
        case 24:
          t._attrs &= ~Attr.underlineMask;
        case 25:
          t._attrs &= ~Attr.blink;
        case 27:
          t._attrs &= ~Attr.reverse;
        case 28:
          t._attrs &= ~Attr.hidden;
        case 29:
          t._attrs &= ~Attr.strike;
        case >= 30 && <= 37:
          t._fg = Color.indexed(v - 30);
        case 38 || 48 || 58:
          final (color, end) = _extendedColor(p, i, next);
          next = end;
          if (color != null) {
            if (v == 38) {
              t._fg = color;
            } else if (v == 48) {
              t._bg = color;
            } else {
              t._ul = color;
            }
          }
        case 39:
          t._fg = Color.defaultColor;
        case >= 40 && <= 47:
          t._bg = Color.indexed(v - 40);
        case 49:
          t._bg = Color.defaultColor;
        case 53:
          t._attrs |= Attr.overline;
        case 55:
          t._attrs &= ~Attr.overline;
        case 59:
          t._ul = Color.defaultColor;
        case >= 90 && <= 97:
          t._fg = Color.indexed(v - 90 + 8);
        case >= 100 && <= 107:
          t._bg = Color.indexed(v - 100 + 8);
        default:
        // fonts, frames, ideograms and the rest: nothing
      }
      i = next;
    }
    t._styleDirty = true;
  }

  /// The color of 38/48/58 at [i]: `5;n`, `2;r;g;b`, or the colon forms
  /// `5:n`, `2::r:g:b` and `2:r:g:b` (sub-parameters up to [subEnd]); and
  /// the index after it.
  (Color?, int) _extendedColor(VtParams p, int i, int subEnd) {
    if (subEnd > i + 1) {
      final kind = p.at(i + 1, -1);
      final subs = subEnd - i - 1;
      if (kind == 5 && subs >= 2) {
        return (Color.indexed(p.at(i + 2) & 0xFF), subEnd);
      }
      if (kind == 2 && subs >= 4) {
        final o = subs >= 5 ? i + 3 : i + 2; // with a color space id or not
        return (_rgb(p.at(o), p.at(o + 1), p.at(o + 2)), subEnd);
      }
      return (null, subEnd);
    }
    final kind = p.at(i + 1, -1);
    if (kind == 5 && i + 2 < p.length) {
      return (Color.indexed(p.at(i + 2) & 0xFF), i + 3);
    }
    if (kind == 2 && i + 4 < p.length) {
      return (_rgb(p.at(i + 2), p.at(i + 3), p.at(i + 4)), i + 5);
    }
    return (null, kind == 5 ? i + 3 : (kind == 2 ? i + 5 : i + 2));
  }

  static Color _rgb(int r, int g, int b) =>
      Color.rgb(r > 255 ? 255 : r, g > 255 ? 255 : g, b > 255 ? 255 : b);

  /// The current SGR as parameters (DECRQSS).
  String _sgrString() {
    final out = <String>['0'];
    final a = t._attrs;
    final u = (a & Attr.underlineMask) >> 3;
    for (final (bit, param) in const [
      (Attr.bold, '1'),
      (Attr.dim, '2'),
      (Attr.italic, '3'),
      (Attr.underline, '4'),
      (Attr.blink, '5'),
      (Attr.reverse, '7'),
      (Attr.hidden, '8'),
      (Attr.strike, '9'),
      (Attr.overline, '53'),
    ]) {
      if (bit == Attr.underline) {
        if (u != 0) {
          out.add(u == 1 ? '4' : '4:$u');
        }
      } else if (a & bit != 0) {
        out.add(param);
      }
    }
    void color(Color c, int base) {
      if (c.isDefault) {
        return;
      }
      if (c.isIndexed) {
        final n = c.index;
        if (base != 50 && n < 8) {
          out.add('${base + n}');
        } else if (base != 50 && n < 16) {
          out.add('${base + 60 + n - 8}');
        } else {
          out.add('${base + 8}:5:$n');
        }
      } else {
        out.add('${base + 8}:2::${c.r}:${c.g}:${c.b}');
      }
    }

    color(t._fg, 30);
    color(t._bg, 40);
    color(t._ul, 50);
    return out.join(';');
  }

  // --------------------------------------------------------- XTWINOPS --

  void _windowOps(VtParams p) {
    switch (p.at(0)) {
      case 8:
        final rows = p.at(1);
        final cols = p.at(2);
        t._event(
          ResizeRequested(
            cols == 0 ? t._width : cols,
            rows == 0 ? t._height : rows,
          ),
        );
      case 14:
        if (t.cellPixelWidth > 0 && t.cellPixelHeight > 0) {
          t._reply(
            '\x1b[4;${t._height * t.cellPixelHeight};'
            '${t._width * t.cellPixelWidth}t',
          );
        }
      case 16:
        if (t.cellPixelWidth > 0 && t.cellPixelHeight > 0) {
          t._reply('\x1b[6;${t.cellPixelHeight};${t.cellPixelWidth}t');
        }
      case 18:
        t._reply('\x1b[8;${t._height};${t._width}t');
      case 19:
        t._reply('\x1b[9;${t._height};${t._width}t');
      case 22:
        if (t._titleStack.length < 10) {
          t._titleStack.add((t._title, t._iconName));
        }
      case 23:
        if (t._titleStack.isNotEmpty) {
          final (title, icon) = t._titleStack.removeLast();
          final which = p.at(1);
          if (which != 1 && title != t._title) {
            t._title = title;
            t._event(TitleChanged(title));
          }
          if (which != 2 && icon != t._iconName) {
            t._iconName = icon;
            t._event(IconNameChanged(icon));
          }
        }
      default:
      // window moves, raises, reports of its state: not a window here
    }
  }

  // -------------------------------------------------------------- OSC --

  @override
  void oscDispatch(Uint8List data, int length, {required bool bel}) {
    var i = 0;
    var code = 0;
    while (i < length && data[i] >= 0x30 && data[i] <= 0x39) {
      code = code * 10 + data[i] - 0x30;
      i++;
    }
    if (i == 0 || (i < length && data[i] != 0x3B)) {
      t._unknown('OSC ${String.fromCharCodes(data, 0, length)}');
      return;
    }
    final arg = i < length
        ? utf8.decode(
            Uint8List.sublistView(data, i + 1, length),
            allowMalformed: true,
          )
        : '';
    final end = bel ? '\x07' : '\x1b\\';
    switch (code) {
      case 0 || 1 || 2:
        if (code != 1 && arg != t._title) {
          t._title = arg;
          t._event(TitleChanged(arg));
        }
        if (code != 2 && arg != t._iconName) {
          t._iconName = arg;
          t._event(IconNameChanged(arg));
        }
      case 4:
        _palette(arg, end);
      case 7:
        final uri = Uri.tryParse(arg);
        if (uri != null) {
          t._cwd = uri;
          t._event(WorkingDirectoryChanged(uri));
        }
      case 8:
        final semi = arg.indexOf(';');
        final uri = semi < 0 ? '' : arg.substring(semi + 1);
        t._link = uri.isEmpty ? null : uri;
        t._styleDirty = true;
      case 9:
        if (arg.startsWith('4;') || arg == '4') {
          final parts = arg.split(';');
          final state = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
          final value = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
          t._event(ProgressChanged(state, value.clamp(0, 100)));
        } else {
          t._event(NotificationRequested('', arg));
        }
      case 10 || 11 || 12:
        _dynamicColors(code, arg, end);
      case 22:
        t._event(PointerShapeChanged(arg));
      case 52:
        _clipboard(arg);
      case 104:
        if (arg.isEmpty) {
          t._resetPalette();
        } else {
          for (final s in arg.split(';')) {
            final n = int.tryParse(s);
            if (n != null && n >= 0 && n < 256) {
              t.palette[n] = _xtermPalette[n];
            }
          }
        }
        t._event(const ColorsChanged());
      case 110:
        t._fgSet = null;
        t._event(const ColorsChanged());
      case 111:
        t._bgSet = null;
        t._event(const ColorsChanged());
      case 112:
        t._cursorSet = null;
        t._event(const ColorsChanged());
      case 133:
        _promptMark(arg);
      case 777:
        final parts = arg.split(';');
        if (parts.first == 'notify') {
          t._event(
            NotificationRequested(
              parts.length > 1 ? parts[1] : '',
              parts.length > 2 ? parts.sublist(2).join(';') : '',
            ),
          );
        }
      case 1337 || 99 || 5522 || 3008:
      // iTerm2's, kitty's notifications and clipboard, context: not spoken
      default:
        t._unknown('OSC $code');
    }
  }

  void _palette(String arg, String end) {
    final parts = arg.split(';');
    var changed = false;
    for (var k = 0; k + 1 < parts.length; k += 2) {
      final n = int.tryParse(parts[k]);
      if (n == null || n < 0 || n > 255) {
        continue;
      }
      if (parts[k + 1] == '?') {
        t._reply('\x1b]4;$n;${_colorSpec(t.palette[n])}$end');
      } else {
        final rgb = _parseColor(parts[k + 1]);
        if (rgb != null) {
          t.palette[n] = rgb;
          changed = true;
        }
      }
    }
    if (changed) {
      t._event(const ColorsChanged());
    }
  }

  /// OSC 10, 11, 12: a value each for that color and the ones after it.
  void _dynamicColors(int code, String arg, String end) {
    var changed = false;
    var c = code;
    for (final spec in arg.split(';')) {
      if (c > 12) {
        break;
      }
      if (spec == '?') {
        final rgb = switch (c) {
          10 => t.foregroundColor,
          11 => t.backgroundColor,
          _ => t.cursorColor,
        };
        t._reply('\x1b]$c;${_colorSpec(rgb)}$end');
      } else {
        final rgb = _parseColor(spec);
        if (rgb != null) {
          switch (c) {
            case 10:
              t._fgSet = rgb;
            case 11:
              t._bgSet = rgb;
            default:
              t._cursorSet = rgb;
          }
          changed = true;
        }
      }
      c++;
    }
    if (changed) {
      t._event(const ColorsChanged());
    }
  }

  static String _colorSpec(int rgb) {
    String ch(int v) => (v * 257).toRadixString(16).padLeft(4, '0');
    return 'rgb:${ch((rgb >> 16) & 0xFF)}/${ch((rgb >> 8) & 0xFF)}/'
        '${ch(rgb & 0xFF)}';
  }

  /// `rgb:r/g/b` (1 to 4 hex digits each) or `#rgb` (1 to 4 digits a
  /// channel) as 0xRRGGBB.
  static int? _parseColor(String spec) {
    int? channel(String hex) {
      if (hex.isEmpty || hex.length > 4) {
        return null;
      }
      final v = int.tryParse(hex, radix: 16);
      if (v == null) {
        return null;
      }
      final max = (1 << (4 * hex.length)) - 1;
      return (v * 255 / max).round();
    }

    List<String>? parts;
    if (spec.startsWith('rgb:')) {
      parts = spec.substring(4).split('/');
    } else if (spec.startsWith('#') && (spec.length - 1) % 3 == 0) {
      final n = (spec.length - 1) ~/ 3;
      parts = [
        for (var k = 0; k < 3; k++) spec.substring(1 + k * n, 1 + (k + 1) * n),
      ];
    }
    if (parts == null || parts.length != 3) {
      return null;
    }
    final r = channel(parts[0]);
    final g = channel(parts[1]);
    final b = channel(parts[2]);
    if (r == null || g == null || b == null) {
      return null;
    }
    return (r << 16) | (g << 8) | b;
  }

  void _clipboard(String arg) {
    final semi = arg.indexOf(';');
    if (semi < 0) {
      return;
    }
    final selection = semi == 0 ? 'c' : arg.substring(0, semi);
    final data = arg.substring(semi + 1);
    if (data == '?') {
      t._event(ClipboardRead(selection));
      return;
    }
    try {
      final text = utf8.decode(base64.decode(data), allowMalformed: true);
      t._event(ClipboardWrite(selection, text));
    } on FormatException {
      // not base64: nothing to write
    }
  }

  void _promptMark(String arg) {
    if (arg.isEmpty) {
      return;
    }
    final mark = switch (arg[0]) {
      'A' => PromptMark.promptStart,
      'B' => PromptMark.commandStart,
      'C' => PromptMark.outputStart,
      'D' => PromptMark.commandEnd,
      _ => null,
    };
    if (mark == null) {
      return;
    }
    int? exit;
    if (mark == PromptMark.commandEnd && arg.length > 2 && arg[1] == ';') {
      exit = int.tryParse(arg.substring(2).split(';').first);
    }
    t._event(PromptMarked(mark, t._y, exitCode: exit));
  }

  // -------------------------------------------------------------- DCS --

  @override
  void dcsDispatch(
    VtParams params,
    int prefix,
    int intermediates,
    int final_,
    Uint8List data,
    int length,
  ) {
    final body = String.fromCharCodes(data, 0, length);
    if (intermediates == 0x24 && final_ == 0x71) {
      // $ q DECRQSS
      final answer = switch (body) {
        'm' => '${_sgrString()}m',
        'r' => '${t._top + 1};${t._bottom}r',
        ' q' => '${t._cursorShape.code == 0 ? 1 : t._cursorShape.code} q',
        '"p' => '62;1"p',
        '"q' => '0"q',
        _ => null,
      };
      t._reply(
        answer == null ? '\x1bP0\$r\x1b\\' : '\x1bP1\$r$answer\x1b\\',
      );
      return;
    }
    if (intermediates == 0x2B && final_ == 0x71) {
      // + q XTGETTCAP: no capability is told
      t._reply('\x1bP0+r$body\x1b\\');
      return;
    }
    t._unknown('DCS ${String.fromCharCode(final_)}');
  }
}
