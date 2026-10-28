/// `twk tape`: [TapeCommand], [TapeRunner], which runs a tape, and
/// [TapeClock], the time it runs by. Exports the tape's language, its
/// themes and its SVGs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:twk_core/twk_core.dart'
    show Attr, Color, KeyCode, KeyEvent, StyleTable, kCont;
import 'package:twk_term/twk_term.dart';

import 'cast.dart';
import 'tape/script.dart';
import 'tape/svg.dart';

export 'tape/script.dart';
export 'tape/svg.dart';
export 'tape/theme.dart';

/// `twk tape`: runs a tape, a script of what to type into a program, and
/// writes the session as asciicast v2 and SVG ([TapeRunner]).
final class TapeCommand extends Command<int> {
  @override
  String get name => 'tape';

  @override
  String get invocation => 'twk tape <file.tape>';

  @override
  String get description =>
      'Run a tape: record a scripted session as asciicast v2 and SVG.\n\n'
      "Runs the tape's program (Run; sh by default) in a pseudo-terminal "
      'of the size it sets, types what it says (Type, Enter, Ctrl+C, ...), '
      'waits as it says (Sleep, Wait for text on the screen), and writes '
      'the session to each Output: a .cast file, asciicast v2, or an .svg '
      'file, an animated SVG of the screens; Screenshot writes the screen '
      'as it is to a still SVG. Hide and Show cut what lies between from '
      'the recording. When the tape has run, the program is hung up. Ends '
      'with 0; 1 when the tape cannot be read or a Wait timed out, 127 '
      'when the program cannot be started, 128 and the number of a signal '
      'that stopped it. See the README for the statements.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('One tape to run.');
    }
    final path = rest.single;
    final Tape tape;
    try {
      tape = Tape.parse(File(path).readAsStringSync(), name: path);
    } on FileSystemException catch (e) {
      stderr.writeln(
        'twk tape: cannot read $path: ${e.osError?.message ?? e.message}',
      );
      return 1;
    } on FormatException catch (e) {
      stderr.writeln('twk tape: ${e.message}');
      return 1;
    }
    final runner = TapeRunner(
      tape,
      title: p.basenameWithoutExtension(path),
    );
    final signals = [
      for (final (signal, number) in [
        (ProcessSignal.sigint, 2),
        (ProcessSignal.sigterm, 15),
        (ProcessSignal.sighup, 1),
      ])
        signal.watch().listen((_) => runner.stop(128 + number)),
    ];
    try {
      return await runner.run();
    } finally {
      for (final s in signals) {
        await s.cancel();
      }
    }
  }
}

/// A [tape] run: its program in a pseudo-terminal (twk_term's [Pty]) of
/// the tape's size, whose screen twk_term's emulator keeps, answering the
/// program's queries as a terminal of the tape's theme does; what the
/// tape types goes through the emulator too, encoded as the program's
/// modes want it (application cursor keys, the kitty keyboard protocol).
///
/// What the program writes is recorded, its time real time from the
/// start without what lay between a Hide and its Show: as asciicast v2
/// (each piece an `o` event; at a Show one that draws the screen as it is
/// then) and as the frames of an animated SVG (the screen after each
/// piece that leaves no synchronized update open, at most `Framerate` a
/// second). When the steps are done, the recording ends, the program is
/// hung up ([Pty.close]) and, still running [patience] later, killed
/// through its terminal ([Pty.kill]); then the outputs are written.
final class TapeRunner {
  /// A run of [tape]: [title] in the recording's header, what goes wrong
  /// told to `log` (by default a line of stderr each), its time that of
  /// `clock` (by default the real time).
  TapeRunner(
    this.tape, {
    this.title,
    void Function(String line)? log,
    TapeClock? clock,
  }) : _log = log ?? stderr.writeln,
       _clock = clock ?? TapeClock();

  /// The tape run.
  final Tape tape;

  /// The title in the recording's header.
  final String? title;

  final void Function(String line) _log;

  /// How long the program is given to end once hung up.
  static const patience = Duration(seconds: 2);

  late final Pty _pty;
  late final TerminalEmulator _screen;
  late final CastWriter _cast;
  final _castText = StringBuffer();
  late final SvgFilm _film;
  late final SvgLook _look;

  final TapeClock _clock;
  Duration? _hiddenAt;
  Duration _cut = Duration.zero;
  var _recording = true;

  var _typing = const Duration(milliseconds: 50);
  var _timeout = const Duration(seconds: 15);
  void Function()? _waiting;
  var _ended = false;

  final _stop = Completer<void>();
  late int _stopCode;

  /// The time of the recording: the real time since the start, but for
  /// the time hidden.
  Duration get _now => (_hiddenAt ?? _clock.elapsed) - _cut;

  /// Stops the tape where it is, which then ends with [code]; nothing is
  /// written.
  void stop(int code) {
    if (!_stop.isCompleted) {
      _stopCode = code;
      _stop.complete();
    }
  }

  /// Runs the tape; returns 0, 1 when a step failed (a Wait timed out, a
  /// file could not be written), 127 when the program cannot be started
  /// and what [stop] was given when stopped.
  Future<int> run() async {
    final settings = tape.settings;
    final theme = settings.theme;
    final command = tape.command ?? const ['sh'];
    _look = SvgLook(
      theme: theme,
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      padding: settings.padding,
    );
    _film = SvgFilm(
      _look,
      minGap: Duration(microseconds: 1000000 ~/ settings.framerate),
    );
    _screen = TerminalEmulator(width: settings.width, height: settings.height)
      ..defaultForeground = theme.foreground
      ..defaultBackground = theme.background
      ..defaultCursorColor = theme.cursor;
    _screen.palette.setAll(0, theme.ansi);
    final line = command.map(_quoted).join(' ');
    _cast = CastWriter(
      _castText.write,
      CastHeader(
        width: settings.width,
        height: settings.height,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        command: line,
        title: title ?? line,
        env: const {'TERM': 'xterm-256color'},
      ),
    );
    try {
      _pty = Pty.start(
        command.first,
        command.sublist(1),
        width: settings.width,
        height: settings.height,
        environment: {
          'COLORTERM': 'truecolor',
          // the shell's prompt, not the user's
          if (tape.command == null) ...{'PS1': r'$ ', 'HISTFILE': '/dev/null'},
          ...tape.environment,
        },
      );
    } on ProcessException catch (e) {
      _log('twk tape: cannot run ${command.first}: ${e.message}');
      return 127;
    }
    _screen.onOutput = _pty.write;
    _clock.start();
    _film.add(Duration.zero, _screen);
    final output = _pty.output.listen(
      _output,
      onDone: () {
        _ended = true;
        _waiting?.call();
      },
    );
    Duration end;
    try {
      for (final step in tape.steps) {
        await _step(step);
      }
      end = _now;
    } on _Failed catch (e) {
      _log('twk tape: ${e.message}');
      return 1;
    } on _Stopped {
      return _stopCode;
    } on FileSystemException catch (e) {
      _log(
        'twk tape: cannot write ${e.path}: ${e.osError?.message ?? e.message}',
      );
      return 1;
    } finally {
      _recording = false;
      await _hangUp();
      await output.cancel();
    }
    _cast.close(end);
    try {
      for (final path in tape.outputs) {
        _write(
          path,
          path.endsWith('.cast') ? _castText.toString() : _film.render(end),
        );
      }
    } on FileSystemException catch (e) {
      _log(
        'twk tape: cannot write ${e.path}: ${e.osError?.message ?? e.message}',
      );
      return 1;
    }
    return 0;
  }

  /// What the program wrote: on the screen, and recorded unless hidden.
  void _output(List<int> bytes) {
    if (!_recording) {
      return;
    }
    _screen.feed(bytes);
    if (_hiddenAt == null) {
      final now = _now;
      _cast.output(now, bytes);
      if (!_screen.mode(TerminalMode.synchronizedOutput)) {
        _film.add(now, _screen);
      }
    }
    _waiting?.call();
  }

  Future<void> _step(TapeStep step) async {
    switch (step) {
      case TypeStep(:final text, :final delay):
        for (final rune in text.runes) {
          final char = String.fromCharCode(rune);
          _screen.sendKey(
            char == '\t'
                ? const KeyEvent(KeyCode.tab)
                : KeyEvent(KeyCode.char, char: char),
          );
          await _pause(delay ?? _typing);
        }
      case KeyStep(:final key, :final count, :final delay):
        for (var i = 0; i < count; i++) {
          _screen.sendKey(key);
          await _pause(delay ?? _typing);
        }
      case SleepStep(:final duration):
        await _pause(duration);
      case WaitStep():
        await _wait(step);
      case HideStep(hide: true):
        // hidden before anything was recorded: from the start
        _hiddenAt ??= _cast.count == 0 ? Duration.zero : _clock.elapsed;
      case HideStep(hide: false):
        if (_hiddenAt case final hidden?) {
          // the recording goes on from the time it was hidden at
          final elapsed = _clock.elapsed;
          _cut += elapsed - hidden;
          _hiddenAt = null;
          final now = elapsed - _cut;
          _cast.output(now, utf8.encode(redraw(_screen)));
          _film.add(now, _screen);
        }
      case ScreenshotStep(:final path):
        _write(path, screenSvg(_screen, _look));
      case DelayStep(:final delay, :final timeout):
        _typing = delay ?? _typing;
        _timeout = timeout ?? _timeout;
    }
  }

  /// Waits [duration], unless stopped.
  Future<void> _pause(Duration duration) async {
    await _clock.pause(duration, _stop.future);
    if (_stop.isCompleted) {
      throw const _Stopped();
    }
  }

  /// Waits until the screen shows what [step] waits for, but no longer
  /// than its timeout.
  Future<void> _wait(WaitStep step) async {
    String text() => step.scope == WaitScope.line
        ? _screen.lineText(_screen.cursorY)
        : _screen.text;
    // a frame drawn in part is not looked at
    bool shows() =>
        !_screen.mode(TerminalMode.synchronizedOutput) &&
        step.pattern.hasMatch(text());
    if (shows()) {
      return;
    }
    final found = Completer<void>();
    _waiting = () {
      if (!found.isCompleted && shows()) {
        found.complete();
      }
    };
    final timeout = step.timeout ?? _timeout;
    final timedOut = Completer<void>();
    final deadline = Timer(timeout, timedOut.complete);
    try {
      await Future.any([found.future, timedOut.future, _stop.future]);
    } finally {
      deadline.cancel();
      _waiting = null;
    }
    if (_stop.isCompleted) {
      throw const _Stopped();
    }
    if (!found.isCompleted) {
      final seconds = timeout.inMicroseconds / 1e6;
      final where = step.scope == WaitScope.line ? ' on the line' : '';
      final ended = _ended ? ', the program having ended' : '';
      final rows = [
        for (var y = 0; y < _screen.height; y++) '│${_screen.lineText(y)}',
      ];
      throw _Failed(
        '${tape.name}:${step.line}: Wait timed out after ${seconds}s for '
        '${step.source}$where$ended; the screen:\n${rows.join('\n')}',
      );
    }
  }

  /// Writes [text] to [path], making its directory.
  void _write(String path, String text) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
    _log('twk tape: wrote $path');
  }

  /// Hangs the program up; kills it through its terminal when it is still
  /// running [patience] later.
  Future<void> _hangUp() async {
    _pty.close();
    final exited = _pty.exitCode;
    await exited.timeout(
      patience,
      onTimeout: () {
        _pty.kill(ProcessSignal.sigkill);
        return exited.timeout(patience, onTimeout: () => null);
      },
    );
  }

  /// [word] as a shell takes it.
  static String _quoted(String word) =>
      RegExp(r'^[\w@%+=:,./-]+$').hasMatch(word)
      ? word
      : "'${word.replaceAll("'", r"'\''")}'";
}

/// The time a tape runs by: the real time since [start], which a pause
/// (the typing speed, Sleep) waits out.
class TapeClock {
  final _watch = Stopwatch();

  /// The time since [start].
  Duration get elapsed => _watch.elapsed;

  /// Starts the time, at zero.
  void start() => _watch.start();

  /// Waits [duration], or until [stop] completes.
  Future<void> pause(Duration duration, Future<void> stop) async {
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    await Future.any([done.future, stop]);
    timer.cancel();
  }
}

/// What draws [screen] as it shows on a terminal of its size: the
/// alternate screen entered when it is on it, every cell in its style,
/// the cursor where it is and as shown or hidden.
String redraw(TerminalEmulator screen) {
  final out = StringBuffer();
  if (screen.alternateScreen) {
    out.write('\x1b[?1049h');
  }
  out.write('\x1b[0m\x1b[H\x1b[2J');
  final styles = screen.styles;
  for (var y = 0; y < screen.height; y++) {
    var end = screen.width;
    while (end > 0 &&
        screen.cellText(end - 1, y) == ' ' &&
        _plain(styles, screen.styleAt(end - 1, y))) {
      end--;
    }
    if (end == 0) {
      continue;
    }
    out.write('\x1b[${y + 1}H');
    var style = 0;
    for (var x = 0; x < end; x++) {
      if (screen.cellAt(x, y) & kCont != 0) {
        continue;
      }
      final id = screen.styleAt(x, y);
      if (id != style) {
        out.write(_sgr(styles, id));
        style = id;
      }
      out.write(screen.cellText(x, y));
    }
    if (style != 0) {
      out.write('\x1b[0m');
    }
  }
  out
    ..write('\x1b[${screen.cursorY + 1};${screen.cursorX + 1}H')
    ..write(screen.cursorVisible ? '\x1b[?25h' : '\x1b[?25l');
  return out.toString();
}

/// Style [id] looks as an erased cell does.
bool _plain(StyleTable styles, int id) =>
    styles.bgOf(id).isDefault && styles.attrsOf(id) & Attr.visibleOnBlank == 0;

/// The SGR sequence of style [id], from the default.
String _sgr(StyleTable styles, int id) {
  final attrs = styles.attrsOf(id);
  final underline = (attrs & Attr.underlineMask) >> 3;
  String color(Color c, int base) => c.isRgb
      ? '${base + 8};2;${c.r};${c.g};${c.b}'
      : c.index < 8
      ? '${base + c.index}'
      : c.index < 16
      ? '${base + 60 + c.index - 8}'
      : '${base + 8};5;${c.index}';
  final fg = styles.fgOf(id);
  final bg = styles.bgOf(id);
  final codes = [
    '0',
    if (attrs & Attr.bold != 0) '1',
    if (attrs & Attr.dim != 0) '2',
    if (attrs & Attr.italic != 0) '3',
    if (underline == 1) '4' else if (underline > 1) '4:$underline',
    if (attrs & Attr.blink != 0) '5',
    if (attrs & Attr.reverse != 0) '7',
    if (attrs & Attr.hidden != 0) '8',
    if (attrs & Attr.strike != 0) '9',
    if (attrs & Attr.overline != 0) '53',
    if (!fg.isDefault) color(fg, 30),
    if (!bg.isDefault) color(bg, 40),
  ];
  return '\x1b[${codes.join(';')}m';
}

/// A step that failed: [message] says where and why.
final class _Failed implements Exception {
  const _Failed(this.message);

  final String message;
}

/// The tape was stopped.
final class _Stopped implements Exception {
  const _Stopped();
}
