/// What SGR sequences and OSC 8 links set: the [Style] of the text written
/// after them.
library;

import 'package:twk/twk.dart' show Style;
import 'package:twk_core/twk_core.dart' show Attr, Color;

/// The colors, attributes and link a terminal writes text in, as SGR
/// sequences (`CSI … m`) and OSC 8 set them. What is reset is unset in
/// [style], so it takes its value from the style the text is merged onto.
final class Rendition {
  Color? _fg;
  Color? _bg;
  Color? _underline;
  var _attrs = 0;
  String? _link;
  Style? _style;

  /// The style of text written now.
  Style get style => _style ??= Style(
    fg: _fg,
    bg: _bg,
    underlineColor: _underline,
    attrs: _attrs,
    link: _link,
  );

  /// Sets the hyperlink target (OSC 8); empty ends the link.
  void link(String target) {
    _link = target.isEmpty ? null : target;
    _style = null;
  }

  /// Applies the parameters of an SGR sequence: digits, `;` between
  /// parameters and `:` between the parts of one.
  void select(String params) {
    _style = null;
    final list = _parameters(params);
    for (var k = 0; k < list.length; k++) {
      final parts = list[k];
      final code = parts[0] < 0 ? 0 : parts[0];
      if (parts.length > 1) {
        switch (code) {
          case 4:
            _underlineKind(parts[1] < 0 ? 0 : parts[1]);
          case 38:
            _fg = _color(parts, 1) ?? _fg;
          case 48:
            _bg = _color(parts, 1) ?? _bg;
          case 58:
            _underline = _color(parts, 1) ?? _underline;
        }
        continue;
      }
      switch (code) {
        case 0:
          _fg = _bg = _underline = null;
          _attrs = 0;
        case 1:
          _attrs |= Attr.bold;
        case 2:
          _attrs |= Attr.dim;
        case 3:
          _attrs |= Attr.italic;
        case 4:
          _underlineKind(1);
        case 5 || 6:
          _attrs |= Attr.blink;
        case 7:
          _attrs |= Attr.reverse;
        case 8:
          _attrs |= Attr.hidden;
        case 9:
          _attrs |= Attr.strike;
        case 21:
          _underlineKind(2);
        case 22:
          _attrs &= ~(Attr.bold | Attr.dim);
        case 23:
          _attrs &= ~Attr.italic;
        case 24:
          _underlineKind(0);
        case 25:
          _attrs &= ~Attr.blink;
        case 27:
          _attrs &= ~Attr.reverse;
        case 28:
          _attrs &= ~Attr.hidden;
        case 29:
          _attrs &= ~Attr.strike;
        case >= 30 && <= 37:
          _fg = Color.indexed(code - 30);
        case 39:
          _fg = null;
        case >= 40 && <= 47:
          _bg = Color.indexed(code - 40);
        case 49:
          _bg = null;
        case 53:
          _attrs |= Attr.overline;
        case 55:
          _attrs &= ~Attr.overline;
        case 59:
          _underline = null;
        case >= 90 && <= 97:
          _fg = Color.indexed(code - 90 + 8);
        case >= 100 && <= 107:
          _bg = Color.indexed(code - 100 + 8);
        case 38 || 48 || 58:
          // the color's parts are the parameters that follow
          final kind = k + 1 < list.length ? list[k + 1][0] : -1;
          final count = switch (kind) {
            5 => 1,
            2 => 3,
            _ => -1,
          };
          if (count < 0 || k + 1 + count >= list.length) {
            return;
          }
          final color = _color([
            code,
            for (var j = k + 1; j <= k + 1 + count; j++) list[j][0],
          ], 1);
          k += 1 + count;
          if (color != null) {
            switch (code) {
              case 38:
                _fg = color;
              case 48:
                _bg = color;
              default:
                _underline = color;
            }
          }
      }
    }
  }

  void _underlineKind(int kind) {
    if (kind <= 5) {
      _attrs = (_attrs & ~Attr.underlineMask) | (kind * Attr.underline);
    }
  }
}

/// The color [parts] give from [start] on: `5:index`, `2:r:g:b` or
/// `2:space:r:g:b`; null where they give none.
Color? _color(List<int> parts, int start) {
  int at(int k) => k < parts.length && parts[k] > 0 ? parts[k] : 0;
  final kind = parts[start];
  final count = parts.length - start - 1;
  if (kind == 5 && count >= 1) {
    final index = at(start + 1);
    return index <= 255 ? Color.indexed(index) : null;
  }
  if (kind == 2 && count >= 3) {
    final first = count == 3 ? start + 1 : start + 2;
    final r = at(first);
    final g = at(first + 1);
    final b = at(first + 2);
    return r <= 255 && g <= 255 && b <= 255 ? Color.rgb(r, g, b) : null;
  }
  return null;
}

/// Parameters as lists of their parts, -1 for a part left empty; a number
/// too large for a parameter is cut to 65535.
List<List<int>> _parameters(String params) {
  final list = <List<int>>[];
  var parts = <int>[];
  var value = -1;
  for (var k = 0; k < params.length; k++) {
    final c = params.codeUnitAt(k);
    if (c >= 0x30 && c <= 0x39) {
      value = value < 0 ? c - 0x30 : value * 10 + c - 0x30;
      if (value > 0xFFFF) {
        value = 0xFFFF;
      }
    } else {
      parts.add(value);
      value = -1;
      if (c == 0x3B) {
        list.add(parts);
        parts = <int>[];
      }
    }
  }
  return list..add(parts..add(value));
}
