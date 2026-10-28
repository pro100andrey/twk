/// A fake bash for a terminal view: [ScriptedShell] writes what bash would,
/// in VT sequences, and answers the keys it is sent, as far as the
/// gallery's TerminalView page needs: a prompt, a line edited, history,
/// `ls`, `git log`, `dart test`, `htop` on the alternate screen, `echo`,
/// `clear`, `help` and `exit`. With autoplay it types a script of
/// commands itself until a key takes it over. Nothing of the machine it
/// runs on shows: the files, the commits and the processes are its own.
///
/// It needs nothing but the Dart core libraries, so that a program can
/// copy it beside its own code:
///
/// ```dart
/// final shell = ScriptedShell(autoplay: true);
/// final session = TerminalSession(
///   output: shell.output,
///   input: shell.input,
///   onResize: shell.resize,
/// );
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

// Examples can assume:
// import 'package:twk_term/twk_term.dart';

/// bash at the other end of a byte link, on a clock of its own: its own
/// timers, or, made `manual`, the times [runTo] is called with, so that a
/// view that stops time (a gallery's `t=`) shows the screen of that
/// moment. Its [output] ends when it exits.
final class ScriptedShell {
  /// A shell of a terminal of [width] × [height] cells, the script typed
  /// from its start where [autoplay] is true. Unless [manual], it runs on
  /// timers from now, each set for the next thing it does; [manual], it
  /// stands at time 0 until [runTo].
  ScriptedShell({
    this.autoplay = false,
    int width = 80,
    int height = 24,
    bool manual = false,
  }) : _cols = width,
       _rows = height,
       _manual = manual {
    _at(0, (_) => _prompt());
    if (autoplay) {
      for (final e in _played.keys) {
        _at(e.at, (_) => _key(e.name, e.char), auto: true);
      }
    }
    if (!manual) {
      _clock = Stopwatch()..start();
      scheduleMicrotask(() => _pump(0));
    }
  }

  /// Whether it types its script; false once a key took it over.
  bool autoplay;

  final bool _manual;
  Stopwatch? _clock;
  Timer? _timer;
  int _cols;
  int _rows;

  final _out = StreamController<List<int>>(sync: true);

  /// What it writes to its terminal.
  Stream<List<int>> get output => _out.stream;

  /// Called after a key or a step of time changed what it does next.
  void Function()? onChange;

  /// The time now, in milliseconds from its start, for a `manual` shell:
  /// when a key comes. Without it, the time it was last run to.
  int Function()? clock;

  /// The time it is at, in milliseconds from its start.
  int get now => _now;
  var _now = 0;

  /// When it exited, in milliseconds from its start; null while it runs.
  int? get endedAt => _endedAt;
  int? _endedAt;

  /// The time of the next thing it does by itself, null for none.
  int? get next {
    int? t;
    for (final e in _queue) {
      if (t == null || e.at < t) {
        t = e.at;
      }
    }
    return t;
  }

  /// How long the script takes, the clear at its end included, and a pause
  /// after it.
  static final int cycle = _played.cycle;

  /// Does what comes by [ms], in order: the script's keys, the output of
  /// what runs.
  void runTo(int ms) {
    for (;;) {
      _Event? first;
      for (final e in _queue) {
        if (e.at > ms) {
          continue;
        }
        if (first == null ||
            e.at < first.at ||
            e.at == first.at && e.seq < first.seq) {
          first = e;
        }
      }
      if (first == null) {
        break;
      }
      _queue.remove(first);
      _now = math.max(_now, first.at);
      first.run(first.at);
    }
    _now = math.max(_now, ms);
    _flush();
  }

  /// What its terminal sends it: keys, a paste, as bytes.
  void input(Uint8List bytes) {
    if (_endedAt != null) {
      return;
    }
    final keys = _keysOf(utf8.decode(bytes, allowMalformed: true));
    if (keys.isEmpty) {
      return;
    }
    if (autoplay) {
      // a key takes the shell over: the typist stops
      autoplay = false;
      _queue.removeWhere((e) => e.auto);
    }
    final time = _clock?.elapsedMilliseconds ?? clock?.call() ?? _now;
    runTo(math.max(_now, time));
    for (final (name, char) in keys) {
      _key(name, char);
    }
    _flush();
    _changed();
  }

  /// Its terminal's new size.
  void resize(int width, int height) {
    _cols = width;
    _rows = height;
  }

  /// Stops its timers; its output ends.
  void close() {
    _timer?.cancel();
    if (!_out.isClosed) {
      unawaited(_out.close());
    }
  }

  /// Runs to [at], the time a timer was set for: the time it is, by the
  /// timers' clock, whatever clock that is (a test's fake one too).
  void _pump(int at) {
    if (_out.isClosed) {
      return;
    }
    runTo(at);
    _changed();
  }

  void _changed() {
    onChange?.call();
    if (_manual || _out.isClosed) {
      return;
    }
    _timer?.cancel();
    final at = next;
    if (_endedAt != null) {
      close();
    } else if (at != null) {
      _timer = Timer(
        Duration(milliseconds: math.max(0, at - _now)),
        () => _pump(at),
      );
    }
  }

  // ------------------------------------------------------------ the queue

  final _queue = <_Event>[];
  var _seq = 0;

  void _at(int at, void Function(int at) run, {bool auto = false}) =>
      _queue.add(_Event(at, _seq++, run, auto: auto));

  // ------------------------------------------------------------ writing

  final _buf = StringBuffer();

  void _flush() {
    if (_buf.isEmpty || _out.isClosed) {
      return;
    }
    _out.add(utf8.encode(_buf.toString()));
    _buf.clear();
  }

  /// [text] in [style], `\n` as the tty makes it (CR LF).
  void _write(String text, [_Style style = _Style.plain]) {
    if (text.isEmpty) {
      return;
    }
    _buf
      ..write(style.sgr)
      ..write(text.replaceAll('\n', '\r\n'));
    if (style != _Style.plain) {
      _buf.write('\x1B[0m');
    }
  }

  /// [text] at [x], [y] in [style], as a full-screen program puts it: cut
  /// at the edge.
  int _put(int x, int y, String text, [_Style style = _Style.plain]) {
    if (y < 0 || y >= _rows || x >= _cols) {
      return 0;
    }
    final shown = text.length > _cols - x ? text.substring(0, _cols - x) : text;
    _buf.write('\x1B[${y + 1};${x + 1}H');
    _write(shown, style);
    return shown.length;
  }

  /// [w] blanks at [x], [y] on [style]'s background.
  void _fill(int x, int y, int w, _Style style) {
    final from = math.max(0, x);
    final to = math.min(_cols, x + w);
    if (y < 0 || y >= _rows || to <= from) {
      return;
    }
    _buf.write('\x1B[${y + 1};${from + 1}H');
    _write(' ' * (to - from), _Style(bg: style.bg));
  }

  void _title(String title) => _buf.write('\x1B]0;$title\x07');

  void _cursor({required bool visible}) =>
      _buf.write(visible ? '\x1B[?25h' : '\x1B[?25l');

  void _clear() => _buf.write('\x1B[0m\x1B[H\x1B[2J');

  // ------------------------------------------------------------ the shell

  var _line = '';
  final _history = <String>[];
  int? _historyAt;
  var _job = 0;

  /// What runs in the foreground: the keys it is given.
  void Function(String name, String? char)? _program;

  /// The name of what runs in the foreground (`htop`, `dart test`); null
  /// at the prompt.
  String? get running => _program == null ? null : _programName;
  var _programName = '';

  void _prompt() {
    _write('$_user@$_host', const _Style(fg: _green, bold: true));
    _write(':');
    _write(_dir, const _Style(fg: _blue, bold: true));
    _write(r'$ ');
    _title('$_user@$_host: $_dir');
    _cursor(visible: true);
    // a paste comes bracketed, as bash's readline asks
    _buf.write('\x1B[?2004h');
  }

  void _key(String name, String? char) {
    if (_endedAt != null) {
      return;
    }
    final program = _program;
    if (program != null) {
      program(name, char);
      return;
    }
    switch (name) {
      case 'paste':
        // inserted, not run, its line breaks and tabs as blanks
        final text = char!.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
        _line += text;
        _write(text);
        return;
      case 'enter':
        final command = _line;
        _line = '';
        _historyAt = null;
        _write('\n');
        if (command.trim().isNotEmpty) {
          _history.add(command);
        }
        _run(command.trim());
        return;
      case 'backspace':
        if (_line.isNotEmpty) {
          final chars = _line.runes.toList()..removeLast();
          _line = String.fromCharCodes(chars);
          _rubout(1);
        }
        return;
      case 'ctrl+u':
        _rubout(_line.runes.length);
        _line = '';
        return;
      case 'ctrl+c':
        _write('^C\n');
        _line = '';
        _prompt();
        return;
      case 'ctrl+l':
        _clear();
        _prompt();
        _write(_line);
        return;
      case 'ctrl+d':
        if (_line.isEmpty) {
          _write('exit\n');
          _exit();
        }
        return;
      case 'up' || 'down':
        if (_history.isEmpty) {
          return;
        }
        final i = _clamp(
          (_historyAt ?? _history.length) + (name == 'up' ? -1 : 1),
          0,
          _history.length,
        );
        _historyAt = i;
        _rubout(_line.runes.length);
        _line = i < _history.length ? _history[i] : '';
        _write(_line);
        return;
    }
    if (char != null && char.codeUnitAt(0) >= 0x20) {
      _line += char;
      _write(char);
    }
  }

  void _rubout(int n) {
    for (var i = 0; i < n; i++) {
      _buf.write('\b \b');
    }
  }

  void _exit() {
    _endedAt = _now;
    _title('');
    _cursor(visible: false);
    _flush();
  }

  void _run(String command) {
    final words = command.split(RegExp(r'\s+'));
    final name = words.first;
    final args = words.skip(1).toList();
    switch (name) {
      case '':
        break;
      case 'ls':
        _ls();
      case 'git':
        if (args.firstOrNull == 'log') {
          _gitLog();
        } else {
          _write(
            "git: '${args.firstOrNull ?? ''}' is not a git command here. "
            "Try 'git log'.\n",
          );
        }
      case 'dart':
        if (args.firstOrNull == 'test') {
          return _dartTest();
        }
        _write("Try 'dart test'.\n");
      case 'htop' || 'top':
        return _htop();
      case 'clear':
        _clear();
      case 'echo':
        _write('${_echo(args.join(' '))}\n');
      case 'pwd':
        _write('/home/user/twk\n');
      case 'whoami':
        _write('$_user\n');
      case 'help':
        for (final (c, what) in _help) {
          _write(c.padRight(11), const _Style(bold: true));
          _write('$what\n');
        }
      case 'exit':
        _exit();
        return;
      default:
        _write('bash: $name: command not found\n');
    }
    _prompt();
  }

  void _ls() {
    final n = _entries.length;
    final colw = _entries.map((e) => e.$1.length).reduce(math.max) + 2;
    var columns = math.max(1, (_cols + 2) ~/ colw);
    final rows = (n + columns - 1) ~/ columns;
    columns = (n + rows - 1) ~/ rows;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final i = c * rows + r;
        if (i >= n) {
          continue;
        }
        final (entry, kind) = _entries[i];
        _write(entry, switch (kind) {
          'dir' => const _Style(fg: _blue, bold: true),
          'exe' => const _Style(fg: _green, bold: true),
          _ => _Style.plain,
        });
        if (c < columns - 1 && (c + 1) * rows + r < n) {
          _write(' ' * (colw - entry.length));
        }
      }
      _write('\n');
    }
  }

  void _gitLog() {
    for (final (i, (hash, message)) in _commits.indexed) {
      _write(hash, const _Style(fg: _yellow));
      _write(' ');
      if (i == 0) {
        _write('(', const _Style(fg: _yellow));
        _write('HEAD -> ', const _Style(fg: _cyan, bold: true));
        _write('main', const _Style(fg: _green, bold: true));
        _write(') ', const _Style(fg: _yellow));
      }
      _write('$message\n');
    }
  }

  void _dartTest() {
    final job = ++_job;
    final start = _now;
    _title('dart test -r expanded');
    String stamp(int ms) => '00:${'${ms ~/ 1000}'.padLeft(2, '0')} ';
    _write('${stamp(0)}+0: loading test/view_test.dart\n');
    for (final (i, name) in _tests.indexed) {
      _at(start + 300 + i * _testStep, (at) {
        if (job != _job) {
          return;
        }
        _write(stamp(at - start));
        _write('+${i + 1}', const _Style(fg: _green));
        _write(': $name\n');
      });
    }
    _at(start + 300 + _tests.length * _testStep, (at) {
      if (job != _job) {
        return;
      }
      _write(stamp(at - start));
      _write('+${_tests.length}', const _Style(fg: _green));
      _write(': All tests passed!\n');
      _program = null;
      _prompt();
    });
    _programName = 'dart test';
    _program = (name, _) {
      if (name != 'ctrl+c') {
        return;
      }
      _job++;
      _write('^C\n');
      _program = null;
      _prompt();
    };
  }

  void _htop() {
    final job = ++_job;
    var selected = 0;
    _buf.write('\x1B[?1049h');
    _clear();
    _cursor(visible: false);
    _title('htop');
    void frame(int at) {
      if (job != _job) {
        return;
      }
      _drawHtop(selected, at);
      _at(at + _htopStep, frame);
    }

    frame(_now);
    void quit() {
      _job++;
      _buf.write('\x1B[0m\x1B[?1049l');
      _program = null;
      _prompt();
    }

    _programName = 'htop';
    _program = (name, char) {
      if (char == 'q' || name == 'f10' || name == 'ctrl+c') {
        return quit();
      }
      final step = switch (name) {
        'up' => -1,
        'down' => 1,
        'pageup' => -5,
        'pagedown' => 5,
        'home' => -99,
        'end' => 99,
        _ => null,
      };
      if (step == null) {
        return;
      }
      selected = _clamp(selected + step, 0, _procs.length - 1);
      _drawHtop(selected, _now);
    };
  }

  /// htop's screen at [now]: meters, then its processes, then its keys.
  void _drawHtop(int selected, int now) {
    final w = _cols;
    final h = _rows;
    _clear();
    final f = now ~/ _htopStep;
    final cores = h >= 18 ? 4 : 2;
    final lw = w >= 60 ? w ~/ 2 - 1 : math.max(20, w ~/ 2);
    // a meter: its label, a bar of |s in its parts' colours, its value
    void meter(int y, String label, List<(double, int)> parts, String value) {
      var x = _put(0, y, label.padLeft(3), const _Style(fg: _cyan));
      x += _put(x, y, '[', const _Style(bold: true));
      final bw = lw - x - 1;
      final shown = value.substring(
        0,
        math.min(value.length, math.max(0, bw - 1)),
      );
      var n = 0;
      for (final (k, color) in parts) {
        final m = _round(k * bw);
        for (var i = 0; i < m && n < bw; i++, n++) {
          _put(x + n, y, '|', _Style(fg: color));
        }
      }
      _put(x + bw - shown.length, y, shown, const _Style(dim: true));
      _put(x + bw, y, ']', const _Style(bold: true));
    }

    var y = 0;
    for (var c = 0; c < cores; c++, y++) {
      final user = 0.08 + 0.55 * _noise(c * 7 + f);
      final sys = 0.04 + 0.12 * _noise(c * 13 + f + 5);
      meter(y, '$c', [
        (sys * 0.4, _blue),
        (user, _green),
        (sys, _red),
      ], '${((user + sys * 1.4) * 100).toStringAsFixed(1)}%');
    }
    final used = 0.38 + 0.02 * _noise(f);
    meter(y++, 'Mem', [
      (used, _green),
      (0.06, _blue),
      (0.22, _yellow),
    ], '${(15.5 * used).toStringAsFixed(2)}G/15.5G');
    meter(y++, 'Swp', [(0.02, _red)], '12.0M/2.00G');
    // the right column: tasks, load, uptime
    final rx = lw + 2;
    final rw = w - rx;
    void right(int yy, List<(String, _Style)> parts) {
      var x = rx;
      for (final (s, style) in parts) {
        x += _put(
          x,
          yy,
          s.substring(0, math.min(s.length, math.max(0, w - x))),
          style,
        );
      }
    }

    if (rw >= 14) {
      const bold = _Style(bold: true);
      const label = _Style(fg: _cyan);
      String load(int k) => (0.3 + 0.4 * _noise(f * 3 + k)).toStringAsFixed(2);
      final up = 3 * 86400 + 4 * 3600 + 12 * 60 + 9 + now ~/ 1000;
      final hms = [
        up ~/ 3600 % 24,
        up ~/ 60 % 60,
        up % 60,
      ].map((v) => '$v'.padLeft(2, '0')).join(':');
      if (rw >= 28) {
        right(0, [
          ('Tasks: ', label),
          ('87', bold),
          (', ', _Style.plain),
          ('312', bold),
          (' thr; ', _Style.plain),
          ('2', const _Style(fg: _green, bold: true)),
          (' running', _Style.plain),
        ]);
        right(1, [
          ('Load average: ', label),
          (load(0), bold),
          (' ', _Style.plain),
          (load(1), _Style.plain),
          (' ', _Style.plain),
          (load(2), _Style.plain),
        ]);
        right(2, [('Uptime: ', label), ('3 days, $hms', bold)]);
      } else {
        right(0, [('Tasks: ', label), ('87', bold)]);
        right(1, [('Load: ', label), (load(0), bold)]);
        right(2, [('Up: ', label), (hms, bold)]);
      }
    }
    y = math.max(y, 3) + 1;
    // the processes, the busiest first
    final wide = w >= 70;
    final head = wide
        ? '    PID USER       PRI  NI   RES S  CPU% MEM%   TIME+  Command'
        : '  PID USER     S  CPU% MEM% Command';
    const headStyle = _Style(fg: _black, bg: _green, bold: true);
    _fill(0, y, w, headStyle);
    _put(0, y, head, headStyle);
    _put(
      head.indexOf('CPU%'),
      y,
      'CPU%',
      const _Style(fg: _black, bg: _cyan, bold: true),
    );
    y++;
    final rows = [
      for (final (i, p) in _procs.indexed)
        (i, p, p.$4 * (0.6 + 0.8 * _noise(i * 17 + f))),
    ]..sort((a, b) => a.$3 == b.$3 ? a.$1 - b.$1 : b.$3.compareTo(a.$3));
    final listH = h - 1 - y;
    final top = _clamp(selected - listH + 1, 0, rows.length - listH);
    for (var k = 0; k < listH; k++) {
      if (k + top >= rows.length) {
        break;
      }
      final (_, (pid, user, command, share, mem, res), cpu) = rows[k + top];
      final isSelected = k + top == selected;
      const selectedStyle = _Style(fg: _black, bg: _cyan, bold: true);
      if (isSelected) {
        _fill(0, y + k, w, selectedStyle);
      }
      final running = cpu > 8;
      final secs = ((pid % 97) * 3.7 + share * now / 1000).floor();
      final time =
          '${secs ~/ 60}:${'${secs % 60}'.padLeft(2, '0')}.'
          '${'${pid % 100}'.padLeft(2, '0')}';
      var x = 0;
      void cell(String s, [_Style more = _Style.plain]) =>
          x += _put(x, y + k, s, isSelected ? selectedStyle : more);
      final runStyle = running
          ? const _Style(fg: _green, bold: true)
          : _Style.plain;
      if (wide) {
        cell('${'$pid'.padLeft(7)} ');
        cell('${user.padRight(9).substring(0, 9)} ');
        cell(' 20   0 ');
        cell(
          '${res.padLeft(5)} ',
          res.endsWith('G') ? const _Style(fg: _cyan) : _Style.plain,
        );
        cell(running ? 'R' : 'S', runStyle);
        cell(' ${cpu.toStringAsFixed(1).padLeft(5)}');
        cell(' ${mem.toStringAsFixed(1).padLeft(4)}');
        cell(' ${time.padLeft(7)}  ');
      } else {
        cell('${'$pid'.padLeft(5)} ');
        cell('${user.padRight(8).substring(0, 8)} ');
        cell(running ? 'R' : 'S', runStyle);
        cell(' ${cpu.toStringAsFixed(1).padLeft(5)}');
        cell(' ${mem.toStringAsFixed(1).padLeft(4)} ');
      }
      final base = command.split(' ').first;
      final slash = base.lastIndexOf('/');
      if (slash >= 0) {
        cell(base.substring(0, slash + 1), const _Style(dim: true));
      }
      cell(base.substring(slash + 1), const _Style(bold: true));
      cell(command.substring(base.length));
    }
    // the keys
    var x = 0;
    for (final (k, what) in _fkeys) {
      if (x >= w) {
        break;
      }
      x += _put(x, h - 1, k);
      x += _put(
        x,
        h - 1,
        what.padRight(6),
        const _Style(fg: _black, bg: _cyan, bold: true),
      );
    }
    if (x < w) {
      _fill(x, h - 1, w - x, const _Style(bg: _cyan));
    }
  }
}

// ------------------------------------------------------------ the keys

/// The keys in [s] as the shell names them, (name, the character typed):
/// a paste whole, as `paste` with its text.
List<(String, String?)> _keysOf(String s) {
  final keys = <(String, String?)>[];
  var i = 0;
  while (i < s.length) {
    if (s.startsWith('\x1B[200~', i)) {
      final end = s.indexOf('\x1B[201~', i);
      final stop = end < 0 ? s.length : end;
      keys.add(('paste', s.substring(i + 6, stop)));
      i = end < 0 ? s.length : end + 6;
      continue;
    }
    final c = s.codeUnitAt(i);
    if (c == 0x1B) {
      final m = _escape.matchAsPrefix(s, i);
      if (m == null) {
        keys.add(('escape', null));
        i++;
        continue;
      }
      final name = _escapes[m[0]!.substring(1)];
      if (name != null) {
        keys.add((name, null));
      }
      i = m.end;
      continue;
    }
    final name = switch (c) {
      0x0D || 0x0A => 'enter',
      0x7F || 0x08 => 'backspace',
      0x09 => 'tab',
      0x03 => 'ctrl+c',
      0x04 => 'ctrl+d',
      0x0C => 'ctrl+l',
      0x15 => 'ctrl+u',
      _ => null,
    };
    if (name != null) {
      keys.add((name, null));
      i++;
      continue;
    }
    final rune = s.runes.elementAt(s.substring(0, i).runes.length);
    final char = String.fromCharCode(rune);
    if (rune >= 0x20) {
      keys.add((char == ' ' ? 'space' : char, char));
    }
    i += char.length;
  }
  return keys;
}

/// A sequence a key sends: CSI or SS3, its parameters and its final.
final _escape = RegExp(r'\x1B(\[[0-9;]*[A-Za-z~]|O[A-Za-z])');

const _escapes = {
  '[A': 'up',
  'OA': 'up',
  '[B': 'down',
  'OB': 'down',
  '[C': 'right',
  'OC': 'right',
  '[D': 'left',
  'OD': 'left',
  '[H': 'home',
  'OH': 'home',
  '[1~': 'home',
  '[F': 'end',
  'OF': 'end',
  '[4~': 'end',
  '[5~': 'pageup',
  '[6~': 'pagedown',
  '[3~': 'delete',
  '[21~': 'f10',
};

// ------------------------------------------------------------ styles

const _black = 0;
const _red = 1;
const _green = 2;
const _yellow = 3;
const _blue = 4;
const _cyan = 6;

/// What SGR sets: a colour of the palette for the text and the
/// background, bold and dim.
final class _Style {
  const _Style({this.fg, this.bg, this.bold = false, this.dim = false});

  static const plain = _Style();

  final int? fg;
  final int? bg;
  final bool bold;
  final bool dim;

  String get sgr {
    final codes = [
      if (bold) '1',
      if (dim) '2',
      if (fg case final c?) '${30 + c}',
      if (bg case final c?) '${40 + c}',
    ];
    return codes.isEmpty ? '' : '\x1B[${codes.join(';')}m';
  }

  @override
  bool operator ==(Object other) =>
      other is _Style &&
      other.fg == fg &&
      other.bg == bg &&
      other.bold == bold &&
      other.dim == dim;

  @override
  int get hashCode => Object.hash(fg, bg, bold, dim);
}

// ------------------------------------------------------------ the queue

final class _Event {
  _Event(this.at, this.seq, this.run, {required this.auto});

  final int at;
  final int seq;
  final void Function(int at) run;

  /// The script's: dropped when a key takes the shell over.
  final bool auto;
}

/// A value from 0 to 1 that looks random and is the same for the same [i].
double _noise(int i) {
  final s = math.sin(i * 91.345 + 3.1) * 43758.5453;
  return s - s.floorToDouble();
}

/// [v] within [low] and [high]; [low] where [high] is below it.
int _clamp(int v, int low, int high) => math.max(low, math.min(high, v));

/// [words] as echo prints them: the variables it knows set, the quotes
/// gone.
String _echo(String words) => words
    .replaceAll(RegExp(r'\$TERM\b'), 'xterm-256color')
    .replaceAll(RegExp(r'\$SHELL\b'), '/bin/bash')
    .replaceAll(RegExp('["\']'), '');

/// [v] rounded as JavaScript's Math.round does: halves up.
int _round(double v) => (v + 0.5).floor();

// ------------------------------------------------------------ the script

/// What the typist does: (the pause before, what): a string typed a key
/// at a time, or a key's name.
const _script = [
  (700, 'ls'),
  (380, 'enter'),
  (1000, 'git log --oneline -8'),
  (380, 'enter'),
  (1300, 'dart test -r expanded'),
  (380, 'enter'),
  (3200, 'htop'),
  (380, 'enter'),
  (1700, 'down'),
  (450, 'down'),
  (450, 'down'),
  (1800, 'up'),
  (2000, 'q'),
  (900, r'echo $TERM'),
  (380, 'enter'),
  (1800, 'clear'),
  (420, 'enter'),
];

typedef _Key = ({int at, String name, String? char});

/// The script's keys and when they come, and the time of a whole run of
/// it: its last key and a pause.
final ({List<_Key> keys, int cycle}) _played = () {
  final out = <_Key>[];
  var at = 0;
  var n = 0;
  for (final (pause, what) in _script) {
    at += pause;
    if (const {'enter', 'down', 'up', 'q'}.contains(what)) {
      out.add((at: at, name: what, char: what == 'q' ? 'q' : null));
      continue;
    }
    for (final ch in what.split('')) {
      out.add((at: at, name: ch == ' ' ? 'space' : ch, char: ch));
      at += 55 + _round(_noise(n++) * 70);
    }
  }
  return (keys: out, cycle: at + 1400);
}();

// ------------------------------------------------------------ its world

const _user = 'user';
const _host = 'twk';
const _dir = '~/twk';

const _entries = [
  ('analysis_options.yaml', 'file'),
  ('CHANGELOG.md', 'file'),
  ('design', 'dir'),
  ('example', 'dir'),
  ('lib', 'dir'),
  ('LICENSE', 'file'),
  ('packages', 'dir'),
  ('pubspec.yaml', 'file'),
  ('README.md', 'file'),
  ('run.sh', 'exe'),
  ('test', 'dir'),
  ('tool', 'dir'),
];

const _commits = [
  ('c1586ef', 'Give every gallery group a page'),
  ('348d284', 'Design the gallery in cells'),
  ('f4842e7', 'Pin the type Dart infers for a Table'),
  ('a585dc5', 'Show the debug keys over the bottom row'),
  ('e3bfa34', 'Clear the row flags in a plain loop'),
  ('9b1c2d0', 'Stream Markdown answers block by block'),
  ('7d03aa1', 'Highlight Go, Rust and Python'),
  ('52e9f4b', 'Draw images in quadrants'),
];

final List<String> _tests = [
  for (final (file, names) in const [
    (
      'view_test',
      [
        'headings',
        'paragraphs wrap by words',
        'lists and their markers',
        'task items',
        'block quotes',
        'tables',
        'links as OSC 8',
        'code highlighted',
        'a document streamed in',
      ],
    ),
    (
      'stream_test',
      [
        'pieces of any size',
        'a block settled once',
        'definitions after use',
        'close settles all',
      ],
    ),
    (
      'code_test',
      [
        'dart',
        'rust',
        'go',
        'python',
        'tabs',
        'wrapped lines',
        'numbers in a gutter',
      ],
    ),
    (
      'diff_test',
      ['unified', 'side by side', 'changed words', 'a gap row', '50 000 lines'],
    ),
    ('big_test', ['large', 'block', 'thin', 'small']),
  ])
    for (final n in names) 'test/$file.dart: $n',
];

const _testStep = 70;
const _htopStep = 1000;

const _help = [
  ('ls', 'the files here'),
  ('git log', 'the last commits'),
  ('dart test', 'the tests, a line each'),
  ('htop', 'processes, full screen (q quits)'),
  ('echo …', 'its words'),
  ('clear', 'the screen (Ctrl+L)'),
  ('exit', 'a new shell'),
];

/// pid, user, command, its CPU share, MEM %, RES.
const _procs = [
  (4211, 'user', 'dart test', 31.0, 2.1, '334M'),
  (3920, 'user', 'dart run example/widgets', 14.0, 1.6, '251M'),
  (2817, 'user', 'firefox', 9.0, 6.4, '1.0G'),
  (1834, 'user', 'kitty', 6.0, 1.2, '190M'),
  (3302, 'user', 'code', 5.0, 4.8, '760M'),
  (1102, 'root', '/usr/lib/Xorg', 3.5, 0.9, '142M'),
  (4400, 'user', 'htop', 1.6, 0.1, '6M'),
  (1500, 'user', 'pipewire', 1.1, 0.3, '27M'),
  (812, 'postgres', 'postgres: checkpointer', 0.6, 0.4, '61M'),
  (401, 'root', 'systemd-journald', 0.3, 0.2, '34M'),
  (3990, 'user', 'bash', 0.1, 0.1, '8M'),
  (623, 'root', 'sshd: /usr/bin/sshd -D', 0.0, 0.1, '11M'),
  (1, 'root', '/sbin/init', 0.0, 0.1, '13M'),
];

const _fkeys = [
  ('F1', 'Help'),
  ('F2', 'Setup'),
  ('F3', 'Search'),
  ('F4', 'Filter'),
  ('F5', 'Tree'),
  ('F6', 'SortBy'),
  ('F7', 'Nice -'),
  ('F8', 'Nice +'),
  ('F9', 'Kill'),
  ('F10', 'Quit'),
];
