/// `twk decode`: [DecodeCommand], and what it is made of, the terminal's
/// traffic cut into sequences and named ([SequenceReader], [describeOutput],
/// [describeInput]) and grouped into frames ([SequenceLog]).
///
/// This is the second implementation of the VS Code extension's sequence log
/// (`editors/vscode/src/core/sequences.ts`, `seqlog.ts`); both are held to
/// `test/decode.golden.json`, which a change to a name made on one side fails
/// on the other until it follows.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:twk_core/twk_core.dart' show Trace, TraceDirection;

import 'cast.dart';
import 'completion.dart';

const _esc = 0x1b;
const _bel = 0x07;

/// A piece of the stream: [raw] is its bytes as latin1, so as long as they
/// are. Which of the other fields are meaningful depends on [kind]: `text`
/// ([text]), `control` ([code]), `esc` ([intermediates], [final_]), `ss3`
/// ([final_]), `csi` ([prefix], [params], [intermediates], [final_]), the
/// strings `osc`, `dcs`, `apc`, `pm` and `sos` ([body]) and `mouse`
/// ([button], [x], [y]).
final class SeqToken {
  /// A token of [kind] whose bytes are [raw].
  const SeqToken(
    this.kind,
    this.raw, {
    this.text = '',
    this.code = 0,
    this.prefix = '',
    this.params = '',
    this.intermediates = '',
    this.final_ = '',
    this.body = '',
    this.button = 0,
    this.x = 0,
    this.y = 0,
  });

  /// What it is: `text`, `control`, `esc`, `ss3`, `csi`, `osc`, `dcs`,
  /// `apc`, `pm`, `sos` or `mouse`.
  final String kind;

  /// Its bytes, one character each.
  final String raw;

  /// A text run, decoded from UTF-8.
  final String text;

  /// A control character's code.
  final int code;

  /// A CSI's private prefix (`?`, `<`, `=`, `>`), or empty.
  final String prefix;

  /// A CSI's parameters, after the prefix.
  final String params;

  /// The intermediate bytes (0x20-0x2F) of an ESC or a CSI.
  final String intermediates;

  /// The final byte of an ESC, SS3 or CSI (empty for ESC alone).
  final String final_;

  /// A string's content between its introducer and its end.
  final String body;

  /// An X10 mouse report's button, less 32.
  final int button;

  /// An X10 mouse report's column, less 32.
  final int x;

  /// An X10 mouse report's row, less 32.
  final int y;
}

String _latin1(Uint8List b, int from, int to) =>
    String.fromCharCodes(b, from, to);

const _strings = {
  0x5d: 'osc',
  0x50: 'dcs',
  0x5f: 'apc',
  0x5e: 'pm',
  0x58: 'sos',
};

/// Cuts a stream into [SeqToken]s, read by read. Of what the app writes
/// ([input] false) a sequence cut off at the end of a read waits for the
/// next; of what the terminal sends ([input] true) each read is whole (a
/// key, a report, an answer), so a lone ESC at its end is the Escape key,
/// and `CSI M` takes the three bytes of an X10 mouse report.
final class SequenceReader {
  /// A reader of what the terminal sent when [input], else of what the app
  /// wrote.
  SequenceReader({this.input = false}) {
    _decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.fromStringSink(_decoded));
  }

  /// Whether this reads what the terminal sent.
  final bool input;

  var _pending = Uint8List(0);
  final _decoded = StringBuffer();
  late final Sink<List<int>> _decoder;

  /// The tokens of [bytes], with what waited from the read before.
  List<SeqToken> read(List<int> bytes) {
    var data = Uint8List.fromList(bytes);
    if (_pending.isNotEmpty) {
      data = Uint8List.fromList([..._pending, ...bytes]);
      _pending = Uint8List(0);
    }
    final tokens = <SeqToken>[];
    var i = 0;
    var textFrom = -1;
    void flushText(int to) {
      if (textFrom >= 0) {
        final raw = _latin1(data, textFrom, to);
        _decoded.clear();
        _decoder.add(Uint8List.sublistView(data, textFrom, to));
        final text = _decoded.toString();
        textFrom = -1;
        if (text.isNotEmpty) {
          tokens.add(SeqToken('text', raw, text: text));
        }
      }
    }

    while (i < data.length) {
      final b = data[i];
      if (b == _esc) {
        flushText(i);
        final t = _escape(data, i);
        if (t == null) {
          _pending = Uint8List.fromList(data.sublist(i));
          return tokens;
        }
        tokens.add(t.$1);
        i = t.$2;
      } else if (b < 0x20 || b == 0x7f) {
        flushText(i);
        tokens.add(SeqToken('control', String.fromCharCode(b), code: b));
        i++;
      } else {
        if (textFrom < 0) {
          textFrom = i;
        }
        i++;
      }
    }
    flushText(data.length);
    return tokens;
  }

  /// What waits for the rest of a sequence, as latin1; empty when nothing
  /// does.
  String get waiting => _latin1(_pending, 0, _pending.length);

  (SeqToken, int)? _escape(Uint8List d, int i) {
    if (i + 1 >= d.length) {
      return input ? (const SeqToken('esc', '\x1b'), i + 1) : null;
    }
    final b1 = d[i + 1];
    final kind = _strings[b1];
    if (kind != null) {
      return _string(d, i, kind);
    }
    if (b1 == 0x5b) {
      return _csi(d, i);
    }
    if (b1 == 0x4f) {
      if (i + 2 >= d.length) {
        // ESC O at the end of a key: Alt+O
        return input
            ? (SeqToken('esc', _latin1(d, i, i + 2), final_: 'O'), i + 2)
            : null;
      }
      return (
        SeqToken(
          'ss3',
          _latin1(d, i, i + 3),
          final_: String.fromCharCode(d[i + 2]),
        ),
        i + 3,
      );
    }
    var j = i + 1;
    while (j < d.length && d[j] >= 0x20 && d[j] <= 0x2f) {
      j++;
    }
    if (j >= d.length) {
      return input
          ? (
              SeqToken(
                'esc',
                _latin1(d, i, j),
                intermediates: _latin1(d, i + 1, j),
              ),
              j,
            )
          : null;
    }
    return (
      SeqToken(
        'esc',
        _latin1(d, i, j + 1),
        intermediates: _latin1(d, i + 1, j),
        final_: String.fromCharCode(d[j]),
      ),
      j + 1,
    );
  }

  (SeqToken, int)? _csi(Uint8List d, int i) {
    var j = i + 2;
    final paramFrom = j;
    while (j < d.length && d[j] >= 0x30 && d[j] <= 0x3f) {
      j++;
    }
    final paramTo = j;
    while (j < d.length && d[j] >= 0x20 && d[j] <= 0x2f) {
      j++;
    }
    if (j >= d.length) {
      return input ? (SeqToken('esc', _latin1(d, i, j), final_: '['), j) : null;
    }
    var params = _latin1(d, paramFrom, paramTo);
    var prefix = '';
    if (params.isNotEmpty && '<=>?'.contains(params[0])) {
      prefix = params[0];
      params = params.substring(1);
    }
    final final_ = String.fromCharCode(d[j]);
    final intermediates = _latin1(d, paramTo, j);
    if (input &&
        final_ == 'M' &&
        prefix.isEmpty &&
        params.isEmpty &&
        intermediates.isEmpty) {
      // X10: CSI M Cb Cx Cy
      final end = j + 4;
      if (end <= d.length) {
        return (
          SeqToken(
            'mouse',
            _latin1(d, i, end),
            button: d[j + 1] - 32,
            x: d[j + 2] - 32,
            y: d[j + 3] - 32,
          ),
          end,
        );
      }
    }
    return (
      SeqToken(
        'csi',
        _latin1(d, i, j + 1),
        prefix: prefix,
        params: params,
        intermediates: intermediates,
        final_: final_,
      ),
      j + 1,
    );
  }

  /// A string of [kind]: OSC up to BEL or ST, the others up to ST, an ESC
  /// doubled inside tmux's passthrough.
  (SeqToken, int)? _string(Uint8List d, int i, String kind) {
    for (var j = i + 2; j < d.length; j++) {
      if (kind == 'osc' && d[j] == _bel) {
        return (
          SeqToken(kind, _latin1(d, i, j + 1), body: _latin1(d, i + 2, j)),
          j + 1,
        );
      }
      if (d[j] != _esc) {
        continue;
      }
      if (j + 1 >= d.length) {
        break;
      }
      if (d[j + 1] == 0x5c) {
        return (
          SeqToken(kind, _latin1(d, i, j + 2), body: _latin1(d, i + 2, j)),
          j + 2,
        );
      }
      if (kind == 'dcs' && d[j + 1] == _esc) {
        j++;
      }
    }
    if (input) {
      return (
        SeqToken(
          kind,
          _latin1(d, i, d.length),
          body: _latin1(d, i + 2, d.length),
        ),
        d.length,
      );
    }
    return null;
  }
}

/// Whether [t] begins (`CSI ? 2026 h`) or ends (`CSI ? 2026 l`) a
/// synchronized update, once for each 2026 among its modes: +n or -n.
int syncChange(SeqToken t) {
  if (t.kind != 'csi' ||
      t.prefix != '?' ||
      t.intermediates.isNotEmpty ||
      (t.final_ != 'h' && t.final_ != 'l')) {
    return 0;
  }
  final n = t.params.split(';').where((p) => p == '2026').length;
  return t.final_ == 'h' ? n : -n;
}

/// [raw] as the log shows it: ESC as `ESC`, other controls in caret
/// notation, bytes above 0x7E in hex, cut after [max] characters.
String visible(String raw, {int max = 160}) {
  final s = StringBuffer();
  for (final code in raw.codeUnits) {
    final so = s.toString();
    if (code == _esc) {
      s.write(so.isEmpty || so.endsWith(' ') ? 'ESC ' : ' ESC ');
    } else if (code < 0x20) {
      s.write('^${String.fromCharCode(code + 0x40)}');
    } else if (code == 0x7f) {
      s.write('^?');
    } else if (code > 0x7e && code <= 0xff) {
      s.write('\\x${code.toRadixString(16)}');
    } else {
      s.write(String.fromCharCode(code));
    }
    if (s.length > max) {
      return '${s.toString().substring(0, max)}… (${raw.length} bytes)';
    }
  }
  return s.toString().trimRight();
}

// JavaScript's numbers, as the sequence names print them: a parameter that
// is no number is NaN (here null), one that is missing is undefined.

/// The leading integer of [s] (`parseInt`), or null for NaN.
int? _parseInt(String s) =>
    int.tryParse(RegExp(r'^[+-]?\d+').firstMatch(s.trimLeft())?.group(0) ?? '');

/// `Number(s)` for the strings sequences hold: empty is 0, a non-number NaN
/// (null).
int? _number(String? s) {
  if (s == null) {
    return null;
  }
  final t = s.trim();
  return t.isEmpty ? 0 : int.tryParse(t);
}

/// The numbers of [params] (`1;31`), a missing one as [fallback].
List<int?> _numbers(String params, int fallback) => params.isEmpty
    ? [fallback]
    : [
        for (final p in params.split(RegExp('[;:]')))
          if (p.isEmpty) fallback else _parseInt(p),
      ];

/// Element [i] of [l] as JavaScript prints it: `undefined` past the end,
/// `NaN` for a non-number.
String _at(List<int?> l, int i) => i >= l.length ? 'undefined' : _p(l[i]);

String _p(int? v) => v?.toString() ?? 'NaN';

/// [l][[i]] as a number for comparing, null where it is missing or NaN.
int? _get(List<int?> l, int i) => i < l.length ? l[i] : null;

/// Element [i] of [l] when [i] is an index into it, else null.
T? _pick<T>(List<T> l, int? i) =>
    i != null && i >= 0 && i < l.length ? l[i] : null;

const _controls = {
  0x00: 'NUL',
  0x07: 'BEL bell',
  0x08: 'BS backspace',
  0x09: 'HT tab',
  0x0a: 'LF line feed',
  0x0b: 'VT',
  0x0c: 'FF',
  0x0d: 'CR carriage return',
  0x0e: 'SO',
  0x0f: 'SI',
  0x7f: 'DEL',
};

/// The DEC private modes by number.
const decModes = {
  1: 'application cursor keys',
  3: '132 columns',
  5: 'reverse video',
  6: 'origin mode',
  7: 'autowrap',
  9: 'X10 mouse',
  12: 'cursor blinking',
  25: 'cursor visible',
  47: 'alternate screen',
  66: 'application keypad',
  69: 'left and right margins',
  1000: 'mouse buttons',
  1002: 'mouse drags',
  1003: 'mouse motion',
  1004: 'focus events',
  1005: 'UTF-8 mouse',
  1006: 'SGR mouse',
  1007: 'alternate scroll',
  1015: 'urxvt mouse',
  1016: 'SGR pixel mouse',
  1047: 'alternate screen',
  1048: 'cursor saved',
  1049: 'alternate screen, cursor saved',
  2004: 'bracketed paste',
  2026: 'synchronized output',
  2027: 'grapheme clusters',
  2031: 'colour scheme reports',
  2048: 'in-band resize',
  8452: 'sixel cursor at the right',
};

const _ansiModes = {
  4: 'insert mode',
  20: 'automatic newline',
  12: 'local echo off',
};

String _modeNames(String params, Map<int, String> table) => _numbers(params, 0)
    .map(
      (n) => '${_p(n)}${n != null && table[n] != null ? ' ${table[n]}' : ''}',
    )
    .join(', ');

const _colors = [
  'black',
  'red',
  'green',
  'yellow',
  'blue',
  'magenta',
  'cyan',
  'white',
];

const _sgrNames = {
  0: 'reset',
  1: 'bold',
  2: 'dim',
  3: 'italic',
  5: 'blink',
  7: 'inverse',
  8: 'hidden',
  9: 'strikethrough',
  21: 'double underline',
  22: 'not bold or dim',
  23: 'not italic',
  24: 'not underlined',
  25: 'not blinking',
  27: 'not inverse',
  28: 'not hidden',
  29: 'not struck',
  39: 'fg default',
  49: 'bg default',
  53: 'overline',
  55: 'not overlined',
  59: 'underline colour default',
};

const _underlines = ['off', 'single', 'double', 'curly', 'dotted', 'dashed'];

/// What SGR [params] set, briefly: `bold, fg red`, `fg #ff8800`, `reset`.
String describeSgr(String params) {
  final out = <String>[];
  final ps = params.split(';');
  for (var i = 0; i < ps.length; i++) {
    final parts = ps[i].split(':');
    final head = parts.first;
    final sub = parts.sublist(1);
    final n = head.isEmpty ? 0 : _parseInt(head);
    void color(String which) {
      // 38;5;n, 38;2;r;g;b, and their colon forms
      final rest = sub.isNotEmpty ? sub : ps.sublist(i + 1);
      final mode = rest.isEmpty ? null : _parseInt(rest[0]);
      if (mode == 5) {
        out.add('$which ${rest.length > 1 ? rest[1] : '?'}');
        if (sub.isEmpty) {
          i += 2;
        }
      } else if (mode == 2) {
        // a colon form may name a colour space first: 38:2::r:g:b
        final from = sub.length >= 5 ? 2 : 1;
        final rgb = [
          for (var k = from; k < from + 3; k++)
            if (k < rest.length) rest[k],
        ];
        out.add(
          '$which #${rgb.map(_hexByte).join()}',
        );
        if (sub.isEmpty) {
          i += 4;
        }
      } else {
        out.add('$which ?');
      }
    }

    final plain = n == null ? null : _sgrNames[n];
    if (plain != null) {
      out.add(plain);
    } else if (n == 4) {
      out.add(
        sub.isNotEmpty
            ? 'underline ${_pick(_underlines, _number(sub[0])) ?? sub[0]}'
            : 'underline',
      );
    } else if (n == 38 || n == 48 || n == 58) {
      color(
        n == 38
            ? 'fg'
            : n == 48
            ? 'bg'
            : 'underline colour',
      );
    } else if (n != null && n >= 30 && n <= 37) {
      out.add('fg ${_colors[n - 30]}');
    } else if (n != null && n >= 40 && n <= 47) {
      out.add('bg ${_colors[n - 40]}');
    } else if (n != null && n >= 90 && n <= 97) {
      out.add('fg bright ${_colors[n - 90]}');
    } else if (n != null && n >= 100 && n <= 107) {
      out.add('bg bright ${_colors[n - 100]}');
    } else {
      out.add(_p(n));
    }
  }
  return out.join(', ');
}

String _hexByte(String v) =>
    (_parseInt(v) ?? 0).toRadixString(16).padLeft(2, '0');

const _cursorShapes = [
  'default',
  'blinking block',
  'block',
  'blinking underline',
  'underline',
  'blinking bar',
  'bar',
];

const _graphics = [
  '',
  'colour registers',
  'sixel geometry',
  'ReGIS geometry',
];

const _erase = ['to the end', 'to the start', 'all', 'and the scrollback'];

String _eraseName(String params) =>
    _pick(_erase, _numbers(params, 0)[0]) ?? params;

String _csiOut(SeqToken t) {
  final params = t.params;
  final n = _numbers(params, 1);
  final n0 = _at(n, 0);
  final key = '${t.prefix}${t.intermediates}${t.final_}';
  switch (key) {
    case 'A':
      return 'CUU cursor up $n0';
    case 'B':
      return 'CUD cursor down $n0';
    case 'C':
      return 'CUF cursor right $n0';
    case 'D':
      return 'CUB cursor left $n0';
    case 'E':
      return 'CNL cursor down $n0, to column 1';
    case 'F':
      return 'CPL cursor up $n0, to column 1';
    case 'G':
      return 'CHA cursor to column $n0';
    case 'H':
    case 'f':
      return 'CUP cursor to row $n0, column ${n.length > 1 ? _p(n[1]) : 1}';
    case 'J':
      return 'ED erase the screen ${_eraseName(params)}';
    case 'K':
      return 'EL erase the line ${_eraseName(params)}';
    case '?J':
      return 'DECSED erase the screen ${_eraseName(params)}, '
          'keeping protected cells';
    case '?K':
      return 'DECSEL erase the line ${_eraseName(params)}, '
          'keeping protected cells';
    case 'L':
      return 'IL insert $n0 lines';
    case 'M':
      return 'DL delete $n0 lines';
    case 'P':
      return 'DCH delete $n0 characters';
    case '@':
      return 'ICH insert $n0 blanks';
    case 'X':
      return 'ECH erase $n0 characters';
    case 'S':
      return 'SU scroll up $n0';
    case 'T':
      return 'SD scroll down $n0';
    case 'b':
      return 'REP repeat the last character $n0 times';
    case 'd':
      return 'VPA cursor to row $n0';
    case 'm':
      return 'SGR ${describeSgr(params)}';
    case 'r':
      return params.isEmpty
          ? 'DECSTBM scrolling region: all'
          : 'DECSTBM scrolling region rows $n0 to '
                '${n.length > 1 ? _p(n[1]) : 'the bottom'}';
    case 's':
      return params.isEmpty
          ? 'SCOSC save the cursor'
          : 'DECSLRM margins columns $n0 to '
                '${n.length > 1 ? _p(n[1]) : 'the right'}';
    case 'u':
      return 'SCORC restore the cursor';
    case 'c':
      return 'DA1 query: primary device attributes';
    case '>c':
      return 'DA2 query: secondary device attributes';
    case 'n':
      return _get(n, 0) == 6
          ? 'DSR query: the cursor position'
          : _get(n, 0) == 5
          ? 'DSR query: status'
          : 'DSR $params';
    case '?n':
      return _get(n, 0) == 996 ? 'query: the colour scheme' : 'DSR ? $params';
    case 't':
      return _windowOps(params);
    case 'h':
      return 'SM set ${_modeNames(params, _ansiModes)}';
    case 'l':
      return 'RM reset ${_modeNames(params, _ansiModes)}';
    case '?h':
      return 'DECSET ${_modeNames(params, decModes)}';
    case '?l':
      return 'DECRST ${_modeNames(params, decModes)}';
    case r'?$p':
      return 'DECRQM query: mode ${_modeNames(params, decModes)}';
    case r'$p':
      return 'DECRQM query: ANSI mode ${_modeNames(params, _ansiModes)}';
    case ' q':
      final shape = _pick(_cursorShapes, _numbers(params, 0)[0]);
      return 'DECSCUSR cursor shape ${shape ?? params}';
    case '>q':
      return 'XTVERSION query: the terminal name and version';
    case '?u':
      return 'kitty keyboard query: the flags';
    case '>u':
      return 'kitty keyboard push flags ${_p(_numbers(params, 0)[0])}';
    case '<u':
      return 'kitty keyboard pop $n0';
    case '=u':
      final mode = _get(n, 1);
      return 'kitty keyboard set flags ${_p(_numbers(params, 0)[0])}'
          '${mode != null && mode != 0 && mode != 1 ? ' (mode $mode)' : ''}';
    case '?S':
      final what = _pick(_graphics, _get(n, 0));
      return 'XTSMGRAPHICS ${what ?? params} query';
    case '!p':
      return 'DECSTR soft reset';
    case '>m':
      return 'XTMODKEYS $params';
    default:
      return 'CSI $key${params.isEmpty ? '' : ' $params'}';
  }
}

/// XTWINOPS (CSI ... t).
String _windowOps(String params) {
  final all = _numbers(params, 0);
  final op = all.first;
  final rest = all.sublist(1);
  switch (op) {
    case 8:
      return 'XTWINOPS resize to ${_at(rest, 0)} rows, ${_at(rest, 1)} columns';
    case 14:
      return 'XTWINOPS query: the window size in pixels';
    case 16:
      return 'XTWINOPS query: a cell size in pixels';
    case 18:
      return 'XTWINOPS query: the size in cells';
    case 22:
      return 'XTWINOPS push the title';
    case 23:
      return 'XTWINOPS pop the title';
    default:
      return 'XTWINOPS $params';
  }
}

/// An OSC, named by its number.
String _osc(String body, bool input) {
  final semi = body.indexOf(';');
  final ps = semi < 0 ? body : body.substring(0, semi);
  final pt = semi < 0 ? '' : body.substring(semi + 1);
  final query = pt == '?' || pt.endsWith(';?');
  String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
  switch (ps) {
    case '0':
      return 'OSC 0 title and icon "$pt"';
    case '1':
      return 'OSC 1 icon "$pt"';
    case '2':
      return 'OSC 2 title "$pt"';
    case '4':
      return input
          ? 'OSC 4 answer: palette $pt'
          : query
          ? 'OSC 4 query: palette colour ${pt.split(';')[0]}'
          : 'OSC 4 palette $pt';
    case '7':
      return 'OSC 7 the working directory $pt';
    case '8':
      final uri = pt.substring(pt.indexOf(';') + 1);
      return uri.isEmpty ? 'OSC 8 link end' : 'OSC 8 link to $uri';
    case '9':
      if (pt.startsWith('4;')) {
        final parts = pt.substring(2).split(';');
        final state = parts[0];
        final percent = parts.length > 1 ? parts[1] : '';
        final name = _pick(const [
          'removed',
          'set',
          'error',
          'indeterminate',
          'paused',
        ], _number(state));
        final shown = percent.isNotEmpty ? ' $percent%' : '';
        return 'OSC 9;4 progress ${name ?? state}$shown';
      }
      return 'OSC 9 notification "$pt"';
    case '10':
      return input
          ? 'OSC 10 answer: foreground $pt'
          : query
          ? 'OSC 10 query: the foreground colour'
          : 'OSC 10 foreground $pt';
    case '11':
      return input
          ? 'OSC 11 answer: background $pt'
          : query
          ? 'OSC 11 query: the background colour'
          : 'OSC 11 background $pt';
    case '12':
      return query
          ? 'OSC 12 query: the cursor colour'
          : 'OSC 12 cursor colour $pt';
    case '22':
      return 'OSC 22 pointer shape ${pt.isEmpty ? 'default' : pt}';
    case '52':
      return pt.endsWith(';?')
          ? 'OSC 52 clipboard query'
          : 'OSC 52 clipboard '
                '(${pt.length - pt.indexOf(';') - 1} base64 bytes)';
    case '99':
      return 'OSC 99 notification $pt';
    case '104':
      return 'OSC 104 reset the palette';
    case '110':
      return 'OSC 110 reset the foreground';
    case '111':
      return 'OSC 111 reset the background';
    case '112':
      return 'OSC 112 reset the cursor colour';
    case '133':
      return 'OSC 133 prompt mark $pt';
    case '777':
      return pt.startsWith('notify;')
          ? 'OSC 777 notification ${pt.substring(7)}'
          : 'OSC 777 $pt';
    case '1337':
      return pt.startsWith('File=')
          ? 'OSC 1337 iTerm2 image (${body.length} bytes)'
          : 'OSC 1337 ${cut(pt, 40)}';
    default:
      return 'OSC $ps${pt.isEmpty ? '' : ' ${cut(pt, 60)}'}';
  }
}

/// A DCS, named by what it begins with.
String _dcs(String body, bool input) {
  String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
  if (body.startsWith('tmux;')) {
    return 'DCS tmux passthrough';
  }
  if (input && body.startsWith('>|')) {
    return 'XTVERSION answer: ${body.substring(2)}';
  }
  if (input && RegExp(r'^[01]\$r').hasMatch(body)) {
    return body[0] == '1'
        ? 'DECRQSS answer: ${body.substring(3)}'
        : 'DECRQSS answer: not recognised';
  }
  if (input && RegExp(r'^[01]\+r').hasMatch(body)) {
    return 'XTGETTCAP answer ${body.substring(3)}';
  }
  if (body.startsWith(r'$q')) {
    return 'DECRQSS query: ${body.substring(2)}';
  }
  if (body.startsWith('+q')) {
    return 'XTGETTCAP query ${body.substring(2)}';
  }
  if (RegExp('^[0-9;]*q').hasMatch(body)) {
    return 'DCS sixel image (${body.length} bytes)';
  }
  return 'DCS ${cut(body, 40)}';
}

String _escOut(SeqToken t) {
  const names = {
    '7': 'DECSC save the cursor',
    '8': 'DECRC restore the cursor',
    'c': 'RIS reset the terminal',
    'D': 'IND index',
    'E': 'NEL next line',
    'M': 'RI reverse index',
    'H': 'HTS set a tab stop',
    '=': 'DECKPAM application keypad',
    '>': 'DECKPNM normal keypad',
    r'\': 'ST string terminator',
    '(B': 'G0 charset ASCII',
    '(0': 'G0 charset DEC line drawing',
    '#8': 'DECALN fill with E',
  };
  final key = '${t.intermediates}${t.final_}';
  return names[key] ?? 'ESC $key';
}

/// What a kitty graphics command says before its payload: its keys, at most
/// 40 characters.
String _kittyHead(String body) {
  final semi = body.indexOf(';');
  final end = semi < 0 ? body.length : semi;
  return body.substring(1, end < 40 ? end : 40);
}

String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

/// What [t], written by the app, is.
String describeOutput(SeqToken t) => switch (t.kind) {
  'text' => 'text "${t.text}"',
  'control' => _controls[t.code] ?? '^${String.fromCharCode(t.code + 0x40)}',
  'esc' => _escOut(t),
  'ss3' => 'SS3 ${t.final_}',
  'csi' => _csiOut(t),
  'osc' => _osc(t.body, false),
  'dcs' => _dcs(t.body, false),
  'apc' =>
    t.body.startsWith('G')
        ? 'APC kitty graphics ${_kittyHead(t.body)}'
        : 'APC ${_cut(t.body, 40)}',
  'pm' => 'PM ${_cut(t.body, 40)}',
  'sos' => 'SOS ${_cut(t.body, 40)}',
  'mouse' => 'CSI M ${t.button} ${t.x} ${t.y}',
  _ => t.kind,
};

/// The modifiers of xterm's and kitty's parameter (1 + shift 1, alt 2,
/// ctrl 4, super 8...).
String _modifiers(int? m) {
  if (m == null || m <= 1) {
    return '';
  }
  final bits = m - 1;
  const names = [
    'Shift',
    'Alt',
    'Ctrl',
    'Super',
    'Hyper',
    'Meta',
    'CapsLock',
    'NumLock',
  ];
  return [
    for (var i = 0; i < names.length; i++)
      if (bits & (1 << i) != 0) '${names[i]}+',
  ].join();
}

const _cursorKeys = {
  'A': 'Up',
  'B': 'Down',
  'C': 'Right',
  'D': 'Left',
  'H': 'Home',
  'F': 'End',
  'E': 'Begin',
  'P': 'F1',
  'Q': 'F2',
  'R': 'F3',
  'S': 'F4',
};

const _tildeKeys = {
  1: 'Home',
  2: 'Insert',
  3: 'Delete',
  4: 'End',
  5: 'PageUp',
  6: 'PageDown',
  7: 'Home',
  8: 'End',
  11: 'F1',
  12: 'F2',
  13: 'F3',
  14: 'F4',
  15: 'F5',
  17: 'F6',
  18: 'F7',
  19: 'F8',
  20: 'F9',
  21: 'F10',
  23: 'F11',
  24: 'F12',
  200: 'paste begins',
  201: 'paste ends',
};

const _kittyCodes = {
  9: 'Tab',
  13: 'Enter',
  27: 'Escape',
  32: 'Space',
  127: 'Backspace',
};

/// A key of [code] (a Unicode code point, or one of kitty's).
String _keyName(int? code) =>
    (code == null ? null : _kittyCodes[code]) ??
    (code != null && code > 32 && code < 0x110000
        ? String.fromCharCode(code)
        : 'key ${_p(code)}');

/// A mouse button of SGR's or X10's [b], with what it says of the
/// modifiers and motion.
String _mouseButton(int b) {
  final mods =
      '${b & 4 != 0 ? 'Shift+' : ''}'
      '${b & 8 != 0 ? 'Alt+' : ''}'
      '${b & 16 != 0 ? 'Ctrl+' : ''}';
  final motion = b & 32 != 0 ? ' moved' : '';
  final base = b & ~(4 | 8 | 16 | 32);
  final name = base >= 64
      ? _pick(const [
              'wheel up',
              'wheel down',
              'wheel left',
              'wheel right',
            ], base - 64) ??
            'button $base'
      : _pick(const ['left', 'middle', 'right', 'none'], base) ??
            'button $base';
  return '$mods$name$motion';
}

String _csiIn(SeqToken t) {
  final prefix = t.prefix;
  final params = t.params;
  final intermediates = t.intermediates;
  final final_ = t.final_;
  final n = _numbers(params, 1);
  if (prefix == '<' &&
      (final_ == 'M' || final_ == 'm') &&
      intermediates.isEmpty) {
    final v = _numbers(params, 0);
    final b = _get(v, 0) ?? 0;
    final what = _mouseButton(b);
    final act = b & 32 != 0
        ? ''
        : b >= 64
        ? ''
        : final_ == 'M'
        ? ' press'
        : ' release';
    return 'mouse $what$act at column ${_at(v, 1)}, row ${_at(v, 2)}';
  }
  if (prefix.isEmpty && intermediates.isEmpty) {
    final cursor = _cursorKeys[final_];
    if (cursor != null && (params.isEmpty || _get(n, 0) == 1)) {
      return 'key ${_modifiers(_get(n, 1))}$cursor';
    }
    if (final_ == '~') {
      final key = _get(n, 0);
      final named = key == null ? null : _tildeKeys[key];
      return named != null && key! >= 200
          ? named
          : 'key ${_modifiers(_get(n, 1))}${named ?? '~${_p(key)}'}';
    }
    if (final_ == 'u') {
      final fields = params.split(';');
      final code = _number(fields[0].split(':')[0]);
      final mod = fields.length > 1 ? _number(fields[1].split(':')[0]) : null;
      return 'key ${_modifiers(mod)}${_keyName(code)} (kitty)';
    }
    if (final_ == 'R') {
      return 'CPR answer: the cursor at row ${_at(n, 0)}, '
          'column ${n.length > 1 ? _p(n[1]) : 1}';
    }
    if (final_ == 'I') {
      return 'focus in';
    }
    if (final_ == 'O') {
      return 'focus out';
    }
    if (final_ == 't') {
      final v = _numbers(params, 0);
      final op = _get(v, 0);
      final a = _at(v, 1);
      final b = _at(v, 2);
      if (op == 6) {
        return 'answer: a cell is ${b}x$a pixels';
      }
      if (op == 4) {
        return 'answer: the window is ${b}x$a pixels';
      }
      if (op == 8) {
        return 'answer: the size is ${b}x$a cells';
      }
      if (op == 48) {
        return 'in-band resize: $params';
      }
    }
    if (final_ == 'Z') {
      return 'key Shift+Tab';
    }
  }
  if (prefix == '?' && final_ == 'c') {
    return 'DA1 answer: $params';
  }
  if (prefix == '>' && final_ == 'c') {
    return 'DA2 answer: $params';
  }
  if (prefix == '?' && intermediates == r'$' && final_ == 'y') {
    final v = _numbers(params, 0);
    final mode = _get(v, 0);
    final value = _get(v, 1);
    final modeName = mode == null ? null : decModes[mode];
    final state = _pick(const [
      'not recognised',
      'set',
      'reset',
      'permanently set',
      'permanently reset',
    ], value);
    return 'DECRPM answer: mode ${_p(mode)}'
        '${modeName != null ? ' $modeName' : ''} ${state ?? _at(v, 1)}';
  }
  if (prefix == '?' && final_ == 'u') {
    return 'kitty keyboard answer: flags ${_p(_numbers(params, 0)[0])}';
  }
  if (prefix == '?' && final_ == 'n') {
    return _get(n, 0) == 997
        ? 'colour scheme answer: ${_get(n, 1) == 1
              ? 'dark'
              : _get(n, 1) == 2
              ? 'light'
              : _at(n, 1)}'
        : 'DSR answer ? $params';
  }
  if (prefix == '?' && final_ == 'S') {
    return 'XTSMGRAPHICS answer: $params';
  }
  return 'CSI $prefix$intermediates$final_${params.isEmpty ? '' : ' $params'}';
}

/// What [t], sent by the terminal (typed, or answered), is.
String describeInput(SeqToken t) {
  switch (t.kind) {
    case 'text':
      return t.text == ' '
          ? 'key Space'
          : t.text.runes.length == 1
          ? 'key ${t.text}'
          : 'typed "${t.text}"';
    case 'control':
      return switch (t.code) {
        0x0d => 'key Enter',
        0x09 => 'key Tab',
        0x7f || 0x08 => 'key Backspace',
        0x00 => 'key Ctrl+Space',
        _ => 'key Ctrl+${String.fromCharCode(t.code + 0x40)}',
      };
    case 'esc':
      if (t.final_.isEmpty && t.intermediates.isEmpty) {
        return 'key Escape';
      }
      final key = t.final_ == '\x7f' ? 'Backspace' : t.final_;
      return 'key Alt+${t.intermediates}$key';
    case 'ss3':
      return 'key ${_cursorKeys[t.final_] ?? 'SS3 ${t.final_}'}';
    case 'csi':
      return _csiIn(t);
    case 'osc':
      return _osc(t.body, true);
    case 'dcs':
      return _dcs(t.body, true);
    case 'mouse':
      final motion = t.button & 32;
      final act = motion != 0 || (t.button & 3) == 3 ? '' : ' press';
      final what = (t.button & 3) == 3 && motion == 0
          ? 'release'
          : _mouseButton(t.button);
      return 'mouse (X10) $what$act at column ${t.x}, row ${t.y}';
    default:
      return '${t.kind.toUpperCase()} ${_cut(t.body, 40)}';
  }
}

/// Which way an entry went: written by the app, sent by the terminal, or
/// said of the session.
enum Direction {
  /// Written by the app.
  out,

  /// Sent by the terminal.
  input,

  /// Said of the session.
  note,
}

/// An entry of the log: a sequence, a text run, a frame or a note.
final class LogEntry {
  /// An entry.
  const LogEntry({
    required this.id,
    required this.time,
    required this.direction,
    required this.kind,
    required this.name,
    required this.raw,
    required this.bytes,
    this.children,
  });

  /// From 0, in the order they came; a frame's own entries are numbered too.
  final int id;

  /// Milliseconds since the log began.
  final int time;

  /// Which way it went.
  final Direction direction;

  /// A token's kind, `frame` or `note`.
  final String kind;

  /// What it is: `CUP cursor to row 3, column 5`, `key Up`, `frame 12: ...`.
  final String name;

  /// Its bytes as the log shows them (`ESC [3;5H`), cut where long.
  final String raw;

  /// How many bytes it is.
  final int bytes;

  /// A frame's entries, in order.
  final List<LogEntry>? children;

  /// The entry as the golden and the extension hold it: `direction` is
  /// `out`, `in` or `note`.
  Map<String, Object?> toJson() => {
    'id': id,
    'time': time,
    'direction': direction == Direction.input ? 'in' : direction.name,
    'kind': kind,
    'name': name,
    'raw': raw,
    'bytes': bytes,
    if (children != null) 'children': [for (final c in children!) c.toJson()],
  };
}

class _Open {
  _Open(this.time, this.number);
  final int time;
  final int number;
  final entries = <LogEntry>[];
  var bytes = 0;
}

/// Entries made of a terminal's traffic as it comes: what the app wrote cut
/// and named, a synchronized update (DEC mode 2026) held in one frame entry
/// with its entries below it.
final class SequenceLog {
  /// A log keeping at most [limit] entries, a frame at most [frameLimit]
  /// below it.
  SequenceLog({this.limit = 20000, this.frameLimit = 2000});

  /// The most entries kept (the oldest dropped first).
  final int limit;

  /// The most entries a frame keeps below it.
  final int frameLimit;

  final _out = SequenceReader();
  final _kept = <LogEntry>[];
  var _nextId = 0;
  var _frames = 0;
  _Open? _open;
  var _depth = 0;

  /// What the app wrote at [time] (milliseconds).
  void output(int time, List<int> bytes) {
    for (final t in _out.read(bytes)) {
      final change = syncChange(t);
      final e = _entry(time, Direction.out, t.kind, describeOutput(t), t.raw);
      if (change > 0 && _depth <= 0 && _open == null) {
        _open = _Open(time, ++_frames);
      }
      _depth += change;
      final open = _open;
      if (open != null) {
        if (open.entries.length < frameLimit) {
          open.entries.add(e);
        }
        open.bytes += e.bytes;
        if (_depth <= 0) {
          _closeFrame(open, time);
        }
      } else {
        _add(e);
      }
    }
  }

  /// What the terminal sent at [time]: each read whole.
  void input(int time, List<int> bytes) {
    for (final t in SequenceReader(input: true).read(bytes)) {
      _add(_entry(time, Direction.input, t.kind, describeInput(t), t.raw));
    }
  }

  /// Something of the session at [time]: an app came or went, a size.
  void note(int time, String text) => _add(
    LogEntry(
      id: _nextId++,
      time: time,
      direction: Direction.note,
      kind: 'note',
      name: text,
      raw: '',
      bytes: 0,
    ),
  );

  /// Every entry kept, in order.
  List<LogEntry> all() => List.of(_kept);

  LogEntry _entry(
    int time,
    Direction d,
    String kind,
    String name,
    String raw,
  ) => LogEntry(
    id: _nextId++,
    time: time,
    direction: d,
    kind: kind,
    name: name,
    raw: visible(raw),
    bytes: raw.length,
  );

  /// A frame's summary: how many of each name's first word, the most first.
  static String _summary(List<LogEntry> entries) {
    final counts = <String, int>{};
    for (final e in entries) {
      final word = e.kind == 'text' ? 'text' : e.name.split(' ')[0];
      counts[word] = (counts[word] ?? 0) + 1;
    }
    // stable: equal counts keep the order they were first seen in
    final sorted = counts.entries.toList();
    final order = {for (var i = 0; i < sorted.length; i++) sorted[i].key: i};
    sorted.sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : order[a.key]!.compareTo(order[b.key]!);
    });
    return sorted.take(6).map((e) => '${e.value} ${e.key}').join(', ');
  }

  void _closeFrame(_Open open, int time) {
    _open = null;
    final cut = open.entries.length >= frameLimit
        ? ' (the first $frameLimit entries)'
        : '';
    final ms = time - open.time;
    _add(
      LogEntry(
        id: _nextId++,
        time: open.time,
        direction: Direction.out,
        kind: 'frame',
        name:
            'frame ${open.number}: ${_summary(open.entries)}$cut'
            '${ms > 0 ? ', $ms ms' : ''}',
        raw: '${open.bytes} bytes',
        bytes: open.bytes,
        children: open.entries,
      ),
    );
  }

  void _add(LogEntry e) {
    _kept.add(e);
    if (_kept.length > limit) {
      _kept.removeRange(0, _kept.length - limit);
    }
  }
}

/// One thing that happened at `micros`: bytes the app wrote or the terminal
/// sent, or a note of the session.
typedef _Event = ({
  int micros,
  Direction direction,
  List<int> bytes,
  String? note,
});

/// The events of a recording: what it wrote and what was typed, its
/// resizes and markers as notes.
List<_Event> _castEvents(Cast cast) => [
  (
    micros: 0,
    direction: Direction.note,
    bytes: const <int>[],
    note: 'recording ${cast.header.width}x${cast.header.height}',
  ),
  for (final e in cast.events)
    if (e.code == CastEvent.output || e.code == CastEvent.input)
      (
        micros: (e.time * 1e6).round(),
        direction: e.code == CastEvent.output ? Direction.out : Direction.input,
        bytes: utf8.encode(e.data),
        note: null,
      )
    else if (e.size case (final w, final h))
      (
        micros: (e.time * 1e6).round(),
        direction: Direction.note,
        bytes: const <int>[],
        note: 'resized to ${w}x$h',
      )
    else if (e.code == CastEvent.marker)
      (
        micros: (e.time * 1e6).round(),
        direction: Direction.note,
        bytes: const <int>[],
        note: 'marker ${e.data}',
      ),
];

List<_Event> _traceEvents(Trace trace) => [
  (
    micros: 0,
    direction: Direction.note,
    bytes: const <int>[],
    note:
        '${trace.direction.name} trace ${trace.width}x${trace.height}'
        '${trace.truncated ? ', cut short' : ''}',
  ),
  for (final r in trace.records)
    (
      micros: r.micros,
      direction: trace.direction == TraceDirection.output
          ? Direction.out
          : Direction.input,
      bytes: r.bytes,
      note: null,
    ),
];

/// Reads [path] as a recording when it is one (a first line of JSON), else
/// as a byte trace. Throws [FormatException] for neither,
/// [FileSystemException] for a file that can't be read.
List<_Event> _eventsOf(String path) {
  final bytes = File(path).readAsBytesSync();
  if (bytes.length >= Trace.magic.length &&
      latin1.decode(bytes.sublist(0, Trace.magic.length)) == Trace.magic) {
    return _traceEvents(Trace.parse(bytes));
  }
  return _castEvents(Cast.parse(utf8.decode(bytes, allowMalformed: true)));
}

/// The log of [events] in time order, whichever files they came from (the
/// sort is stable: equal times keep the order given).
SequenceLog _logOf(List<_Event> events) {
  final order = {for (var i = 0; i < events.length; i++) i: events[i]};
  final sorted = order.keys.toList()
    ..sort((a, b) {
      final c = order[a]!.micros.compareTo(order[b]!.micros);
      return c != 0 ? c : a.compareTo(b);
    });
  final log = SequenceLog();
  for (final i in sorted) {
    final e = order[i]!;
    final ms = (e.micros / 1000).round();
    switch (e.direction) {
      case Direction.note:
        log.note(ms, e.note!);
      case Direction.out:
        log.output(ms, e.bytes);
      case Direction.input:
        log.input(ms, e.bytes);
    }
  }
  return log;
}

/// `twk decode`: a recording or a byte trace as named sequences.
final class DecodeCommand extends Command<int> with Completes {
  /// The command; `--frames` and `--grep` choose what is shown.
  DecodeCommand() {
    argParser
      ..addFlag(
        'frames',
        negatable: false,
        help:
            'Show each synchronized update (DEC mode 2026) as one row, '
            'not opened.',
      )
      ..addOption(
        'only',
        allowed: ['output', 'input'],
        help: 'Show only what the app wrote, or only what the terminal sent.',
      )
      ..addOption(
        'grep',
        valueHelp: 'regexp',
        help:
            'Show only the rows whose name or bytes match (a frame when any '
            'of its rows does).',
      );
  }

  @override
  Positionals get positionals => const Positionals.files();

  @override
  String get name => 'decode';

  @override
  String get invocation =>
      'twk decode [--frames] [--only=output|input] [--grep=<regexp>] '
      '<file>...';

  @override
  String get description =>
      'Name the sequences of a recording or a byte trace.\n\n'
      'Reads asciicast recordings (.cast) and the files TWK_TRACE_INPUT and '
      'TWK_TRACE_OUTPUT write, and prints a row for each text run, control '
      'character and escape sequence the app wrote, and each key, mouse '
      'event and answer the terminal sent, with its time in seconds, as the '
      "VS Code extension's sequence log names them. Several files (the "
      'input and output traces of one run share a clock) are merged by '
      'time. Ends with 0; 1 when a file cannot be read; 64 for a wrong '
      'command line. See doc/decode.md.';

  @override
  Future<int> run() async {
    final files = argResults!.rest;
    if (files.isEmpty) {
      usageException('At least one recording or trace to decode.');
    }
    final grep = argResults!['grep'] as String?;
    RegExp? pattern;
    if (grep != null) {
      try {
        pattern = RegExp(grep);
      } on FormatException catch (e) {
        usageException('--grep: not a regular expression: ${e.message}');
      }
    }
    final events = <_Event>[];
    for (final file in files) {
      try {
        events.addAll(_eventsOf(file));
      } on FileSystemException catch (e) {
        stderr.writeln(
          'twk decode: cannot read $file: ${e.osError?.message ?? e.message}',
        );
        return 1;
      } on FormatException catch (e) {
        stderr.writeln('twk decode: $file: ${e.message}');
        return 1;
      }
    }
    final only = switch (argResults!['only']) {
      'output' => Direction.out,
      'input' => Direction.input,
      _ => null,
    };
    final frames = argResults!['frames'] as bool;
    for (final e in _logOf(events).all()) {
      for (final line in renderEntry(
        e,
        frames: frames,
        only: only,
        pattern: pattern,
      )) {
        stdout.writeln(line);
      }
    }
    return 0;
  }
}

bool _matches(LogEntry e, RegExp? pattern) =>
    pattern == null ||
    pattern.hasMatch(e.name) ||
    pattern.hasMatch(e.raw) ||
    (e.children?.any((c) => _matches(c, pattern)) ?? false);

String _row(LogEntry e, {int indent = 0}) {
  final seconds = (e.time / 1000).toStringAsFixed(3).padLeft(9);
  final dir = switch (e.direction) {
    Direction.out => 'out',
    Direction.input => 'in ',
    Direction.note => '-- ',
  };
  final name = '${' ' * indent}${e.name}';
  final raw = e.raw;
  return raw.isEmpty
      ? '$seconds  $dir  $name'
      : '$seconds  $dir  ${name.length < 56 ? name.padRight(56) : name}  $raw';
}

/// The rows [e] is shown as: one, or a frame's and then its entries below
/// it when [frames] is false. Nothing for an entry the other way of
/// [only], or that [pattern] does not match (an entry of a frame that does,
/// when the frame is opened).
List<String> renderEntry(
  LogEntry e, {
  bool frames = false,
  Direction? only,
  RegExp? pattern,
}) {
  if (e.direction != Direction.note && only != null && e.direction != only) {
    return const [];
  }
  if (e.direction == Direction.note && only != null) {
    return const [];
  }
  if (!_matches(e, pattern)) {
    return const [];
  }
  final children = e.children;
  if (children == null || frames) {
    return [_row(e)];
  }
  return [
    _row(e),
    for (final c in children)
      if (pattern == null ||
          pattern.hasMatch(c.name) ||
          pattern.hasMatch(c.raw) ||
          pattern.hasMatch(e.name))
        _row(c, indent: 2),
  ];
}
