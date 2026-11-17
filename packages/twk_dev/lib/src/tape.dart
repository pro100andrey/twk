/// `twk tape`: [TapeCommand], [TapeRunner], which runs a tape, and
/// [TapeClock], the time it runs by. Exports the tape's language, its
/// themes and its SVGs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:twk/twk.dart' show KeyCombo;
import 'package:twk_core/twk_core.dart'
    show Attr, Clock, Color, StyleId, StyleTable, kCont;
import 'package:twk_driver/twk_driver.dart';
import 'package:twk_term/twk_term.dart';

import 'completion.dart';
import 'tape/recording.dart';
import 'tape/script.dart';
import 'tape/svg.dart';

export 'tape/script.dart';
export 'tape/svg.dart';
export 'tape/theme.dart';

/// `twk tape`: runs a tape, a script of what to type into a program, and
/// writes the session as asciicast v2 and SVG ([TapeRunner]).
final class TapeCommand extends Command<int> with Completes {
  /// Adds `--check`.
  TapeCommand() {
    argParser.addFlag(
      'check',
      negatable: false,
      help:
          'Run the tape as a test: write no Output or Screenshot, say on '
          'stdout whether each statement passed, and fail on the first '
          'Wait that times out.',
    );
  }

  @override
  Positionals get positionals => const Positionals.files(glob: '*.tape');

  @override
  String get name => 'tape';

  @override
  String get invocation => 'twk tape [--check] <file.tape>';

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
      'that stopped it. With --check nothing is written: each statement is '
      'reported on stdout (`<tape>:<line>: ok <statement>`, then a line '
      'saying how many passed), the first Wait that times out fails the '
      'tape (exit 1, the screen then on stderr). See doc/tape.md for the '
      'statements.';

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
      check: argResults!.flag('check'),
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

/// A [tape] run: its program in a pseudo-terminal of the tape's size, run
/// as twk_driver's [Session] of ports of the tape's own: a recording
/// [TerminalPort] around the program's pty ([RecordingProcessPort]),
/// twk_term's emulators answering the program's queries as a terminal of the
/// tape's theme does, and the tape's [TapeClock]. What the tape types goes
/// through the session (`type`, `press`), encoded as the program's modes
/// want it (application cursor keys, the kitty keyboard protocol); a Wait
/// on the screen is the session's wait on its output; for a program that
/// is a twk app (`Run dart app.dart`, when the tape has a `Wait Widget`,
/// `Wait Text` or `Click`) the session is connected to the app's VM
/// service, and the tape finds and clicks its widgets.
///
/// What the program writes is recorded, its time that of the tape's clock
/// from the start without what lay between a Hide and its Show: as
/// asciicast v2 (each piece an `o` event; at a Show one that draws the
/// screen as it is then) and as the frames of an animated SVG (the screen
/// after each piece that leaves no synchronized update open, at most
/// `Framerate` a second). When the steps are done, the recording ends, the
/// program is ended through its terminal ([Session.close]: killed, its
/// terminal hung up); then the outputs are written.
final class TapeRunner {
  /// A run of [tape]: [title] in the recording's header, what goes wrong
  /// told to `log` (by default a line of stderr each), its time that of
  /// `clock` (by default the real time).
  TapeRunner(
    this.tape, {
    this.title,
    void Function(String line)? log,
    TapeClock? clock,
    this.check = false,
    void Function(String line)? report,
    this.program,
    Future<AppServicePort> Function(Uri uri)? connect,
  }) : _connectTo = connect ?? _connect,
       _log = log ?? stderr.writeln,
       _report = report ?? stdout.writeln,
       _clock = clock ?? TapeClock();

  /// Whether the tape is run as a test: nothing is recorded or written
  /// (no Output, no Screenshot), each statement is told to `report` (by
  /// default a line of stdout) as it passes, then a last line.
  final bool check;

  final void Function(String line) _report;

  /// The tape run.
  final Tape tape;

  /// The title in the recording's header.
  final String? title;

  final void Function(String line) _log;

  /// What starts the program in place of a pseudo-terminal, a port a test
  /// gives for a fake; null for the pty. What connects to its VM service
  /// is the other (`connect`).
  final ProcessPort? program;
  final Future<AppServicePort> Function(Uri uri) _connectTo;

  late Session _session;

  /// The session's answering emulator, which every chunk of the program's
  /// output is fed to as it arrives: the screen of the recording.
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

  final _stop = Completer<void>();
  late int _stopCode;

  /// The time of the recording: the tape's time since the start, but for
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
    final code = await _run();
    if (check) {
      final n = tape.steps.length;
      _report(
        code == 0
            ? '${tape.name}: passed, $n statement${n == 1 ? '' : 's'}'
            : '${tape.name}: failed, $_passed of $n statement'
                  '${n == 1 ? '' : 's'} passed',
      );
    }
    return code;
  }

  var _passed = 0;

  /// The file and arguments of `dart <file> <args>`, a Dart program the
  /// driver can attach the VM service to; null for any other command.
  static (String, List<String>)? _dartProgram(List<String> command) {
    if (command.length < 2 ||
        p.basenameWithoutExtension(command.first) != 'dart') {
      return null;
    }
    final file = command[1];
    return file.endsWith('.dart') || file.endsWith('.dill')
        ? (file, command.sublist(2))
        : null;
  }

  Future<int> _run() async {
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
    final emulators = <TerminalEmulator>[];
    final screens = EmulatorScreen(
      width: settings.width,
      height: settings.height,
      emulator: (width, height) {
        final emulator = TerminalEmulator(width: width, height: height)
          ..defaultForeground = theme.foreground
          ..defaultBackground = theme.background
          ..defaultCursorColor = theme.cursor;
        emulator.palette.setAll(0, theme.ansi);
        emulators.add(emulator);
        return emulator;
      },
    );
    // the first the screens make is the answering one, which takes every
    // chunk as it comes
    _screen = emulators.first;
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
    final environment = {
      'COLORTERM': 'truecolor',
      // a terminal, the recording's, also in CI, where an app that
      // inherited CI=true would write plain text only
      'CI': 'false',
      // the shell's prompt, not the user's
      if (tape.command == null) ...{'PS1': r'$ ', 'HISTFILE': '/dev/null'},
      ...tape.environment,
    };
    // a twk app is attached to when the tape finds or clicks its widgets
    final dart = _dartProgram(command);
    final app =
        dart != null &&
        tape.steps.any((s) => s is WaitNodeStep || s is ClickStep);
    final spec = app
        ? ProcessSpec(
            dart.$1,
            arguments: dart.$2,
            environment: environment,
            width: settings.width,
            height: settings.height,
          )
        : ProcessSpec(
            command.first,
            arguments: command.sublist(1),
            environment: environment,
            width: settings.width,
            height: settings.height,
          );
    _film.add(Duration.zero, _screen);
    _clock.start();
    try {
      _session = await Session.compose(
        spec,
        process: RecordingProcessPort(
          program ??
              (app
                  ? PtyProcessPort(dart: command.first)
                  : const PtyCommandPort()),
          now: () => _now,
          recorded: _recorded,
        ),
        screen: screens,
        connect: app ? _connectTo : null,
        clock: _clock,
        // the first frame of an app, which may be compiled first
        timeout: const Duration(minutes: 1),
      );
    } on ProcessException catch (e) {
      _log('twk tape: cannot run ${command.first}: ${e.message}');
      return 127;
    } on DriverError catch (e) {
      _log('twk tape: cannot run ${command.first}: ${e.message}');
      return 1;
    }
    Duration end;
    try {
      for (final step in tape.steps) {
        await _step(step);
        if (check) {
          _passed++;
          _report('${tape.name}:${step.line}: ok ${_label(step)}');
        }
      }
      end = _now;
    } on _Failed catch (e) {
      if (check) {
        _report('${tape.name}:${e.line}: FAIL ${e.label}');
      }
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
      await _session.close();
    }
    _cast.close(end);
    if (check) {
      return 0;
    }
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

  static Future<AppServicePort> _connect(Uri uri) async {
    final service = await VmAppClient.connect(uri);
    return VmAppClient.attach(service, '$uri');
  }

  /// What the program wrote, at [at], now on the screen: recorded unless
  /// hidden.
  void _recorded(Duration at, Uint8List bytes) {
    if (!_recording || check || _hiddenAt != null) {
      return;
    }
    _cast.output(at, bytes);
    if (!_screen.mode(TerminalMode.synchronizedOutput)) {
      _film.add(at, _screen);
    }
  }

  Future<void> _step(TapeStep step) async {
    switch (step) {
      case TypeStep(:final text, :final delay):
        for (final rune in text.runes) {
          final char = String.fromCharCode(rune);
          await _input(
            step,
            () => char == '\t' ? _session.press('tab') : _session.type(char),
          );
          await _pause(delay ?? _typing);
        }
      case KeyStep(:final key, :final count, :final delay):
        final keys = KeyCombo.fromEvent(key).toString();
        for (var i = 0; i < count; i++) {
          await _input(step, () => _session.press(keys));
          await _pause(delay ?? _typing);
        }
      case ClickStep(:final finder, :final delay):
        await _input(step, () => _session.tap(finder));
        await _pause(delay ?? _typing);
      case SleepStep(:final duration):
        await _pause(duration);
      case WaitStep():
        await _wait(step);
      case WaitNodeStep():
        await _waitNode(step);
      case HideStep(hide: true):
        // hidden before anything was recorded: from the start
        _hiddenAt ??= _cast.count == 0 ? Duration.zero : _clock.elapsed;
      case HideStep(hide: false):
        if (_hiddenAt case final hidden?) {
          // the recording goes on from the time it was hidden at
          final elapsed = _clock.elapsed;
          _cut += elapsed - hidden;
          _hiddenAt = null;
          if (!check) {
            final now = elapsed - _cut;
            _cast.output(now, utf8.encode(redraw(_screen)));
            _film.add(now, _screen);
          }
        }
      case ScreenshotStep(:final path):
        if (!check) {
          _write(path, screenSvg(_screen, _look));
        }
      case DelayStep(:final delay, :final timeout):
        _typing = delay ?? _typing;
        _timeout = timeout ?? _timeout;
    }
  }

  /// Does [act], an input of [step] to the session. A program that has
  /// ended takes no more input, as before; anything else the session says
  /// fails the step.
  Future<void> _input(TapeStep step, Future<Object?> Function() act) async {
    try {
      await act();
    } on AppEnded {
      // nothing is listening
    } on DriverError catch (e) {
      throw _failed(step, e.message);
    } on FormatException catch (e) {
      throw _failed(step, e.message);
    }
  }

  _Failed _failed(TapeStep step, String why) => _Failed(
    step.line,
    _label(step),
    '${tape.name}:${step.line}: ${_label(step)}: $why',
  );

  /// Waits [duration], unless stopped.
  Future<void> _pause(Duration duration) async {
    await _clock.pause(duration, _stop.future);
    if (_stop.isCompleted) {
      throw const _Stopped();
    }
  }

  /// Waits until the screen shows what [step] waits for, but no longer
  /// than its timeout: the session's wait on the screen after each piece
  /// of output.
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
    final where = step.scope == WaitScope.line ? ' on the line' : '';
    final timeout = step.timeout ?? _timeout;
    var ended = false;
    var found = true;
    try {
      await Future.any([
        _session.waitForScreen(
          (_) => shows(),
          timeout: timeout,
          what: step.source,
        ),
        _stop.future,
      ]);
    } on AppEnded {
      ended = true;
    } on DriverError {
      found = false;
    }
    if (_stop.isCompleted) {
      throw const _Stopped();
    }
    if (ended || !found) {
      throw _timedOut(step, step.source + where, timeout, ended: ended);
    }
  }

  /// Waits until the app's tree has what [step] looks for, but no longer
  /// than its timeout on the tape's clock: the tree is asked once, and again
  /// after each frame the app draws, as twk_test's `waitForFinder` does.
  Future<void> _waitNode(WaitNodeStep step) async {
    final timeout = step.timeout ?? _timeout;
    final end = _clock.elapsed + timeout;
    try {
      while (true) {
        final seen = _session.frame;
        final found = await _find(step);
        if (found.isNotEmpty) {
          return;
        }
        final left = end - _clock.elapsed;
        if (left <= Duration.zero) {
          throw _timedOut(step, step.source, timeout, ended: false);
        }
        try {
          // a frame after the one the tree was read at, its screen not
          // looked at: only that the app drew
          await Future.any([
            _session.waitForScreen(
              (_) => _session.frame != seen,
              timeout: left,
              what: step.source,
            ),
            _stop.future,
          ]);
        } on AppEnded {
          rethrow;
        } on DriverError {
          throw _timedOut(step, step.source, timeout, ended: false);
        }
        if (_stop.isCompleted) {
          throw const _Stopped();
        }
      }
    } on AppEnded {
      throw _timedOut(step, step.source, timeout, ended: true);
    }
  }

  Future<List<Found>> _find(WaitNodeStep step) async {
    try {
      return await _session.find(step.finder);
    } on AppEnded {
      rethrow;
    } on DriverError catch (e) {
      throw _failed(step, e.message);
    }
  }

  /// The failure of a Wait for [what] that was not answered.
  _Failed _timedOut(
    TapeStep step,
    String what,
    Duration timeout, {
    required bool ended,
  }) {
    final seconds = timeout.inMicroseconds / 1e6;
    final rows = [
      for (var y = 0; y < _screen.height; y++) '│${_screen.lineText(y)}',
    ];
    final why = ended
        ? 'Wait for $what failed, the program having ended'
        : 'Wait timed out after ${seconds}s for $what';
    return _Failed(
      step.line,
      _label(step),
      '${tape.name}:${step.line}: $why; the screen:\n${rows.join('\n')}',
    );
  }

  /// [step] as a line of a check says it.
  String _label(TapeStep step) {
    String q(String text) => '"${text.replaceAll('"', "'")}"';
    String at(Duration? d) => d == null ? '' : '@${_time(d)}';
    String times(int n) => n == 1 ? '' : ' $n';
    return switch (step) {
      TypeStep(:final text, :final delay) => 'Type${at(delay)} ${q(text)}',
      KeyStep(:final name, :final count, :final delay) =>
        '$name${at(delay)}${times(count)}',
      SleepStep(:final duration) => 'Sleep ${_time(duration)}',
      WaitStep(:final source, :final scope, :final timeout) =>
        'Wait${scope == WaitScope.line ? '+Line' : ''}${at(timeout)} '
            '$source',
      WaitNodeStep(:final source, :final timeout) =>
        'Wait${at(timeout)} $source',
      ClickStep(:final source, :final delay) => 'Click${at(delay)} $source',
      HideStep(:final hide) => hide ? 'Hide' : 'Show',
      ScreenshotStep(:final path) => 'Screenshot $path (not written)',
      DelayStep(:final delay, :final timeout) =>
        delay != null
            ? 'Set TypingSpeed ${_time(delay)}'
            : 'Set WaitTimeout ${_time(timeout!)}',
    };
  }

  static String _time(Duration d) => d.inMilliseconds % 1000 == 0
      ? '${d.inSeconds}s'
      : '${d.inMilliseconds}ms';

  /// Writes [text] to [path], making its directory.
  void _write(String path, String text) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
    _log('twk tape: wrote $path');
  }

  /// [word] as a shell takes it.
  static String _quoted(String word) =>
      RegExp(r'^[\w@%+=:,./-]+$').hasMatch(word)
      ? word
      : "'${word.replaceAll("'", r"'\''")}'";
}

/// The time a tape runs by: the real time since [start], which a pause
/// (the typing speed, Sleep) waits out and the session's timeouts run on.
/// A test gives the runner one it moves: [elapsed], [pause] and [timer]
/// are what it overrides.
class TapeClock implements Clock {
  final _watch = Stopwatch();

  /// The time since [start].
  Duration get elapsed => _watch.elapsed;

  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;

  /// Starts the time, at zero.
  void start() => _watch.start();

  @override
  Timer timer(Duration after, void Function() callback) =>
      Timer(after, callback);

  @override
  Timer periodic(Duration every, void Function(Timer) callback) =>
      Timer.periodic(every, callback);

  /// Waits [duration], or until [stop] completes.
  Future<void> pause(Duration duration, Future<void> stop) async {
    final done = Completer<void>();
    final alarm = timer(duration, done.complete);
    await Future.any([done.future, stop]);
    alarm.cancel();
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
    var style = StyleId.base;
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
    if (style != StyleId.base) {
      out.write('\x1b[0m');
    }
  }
  out
    ..write('\x1b[${screen.cursorY + 1};${screen.cursorX + 1}H')
    ..write(screen.cursorVisible ? '\x1b[?25h' : '\x1b[?25l');
  return out.toString();
}

/// Style [id] looks as an erased cell does.
bool _plain(StyleTable styles, StyleId id) =>
    styles.bgOf(id).isDefault && styles.attrsOf(id) & Attr.visibleOnBlank == 0;

/// The SGR sequence of style [id], from the default.
String _sgr(StyleTable styles, StyleId id) {
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
  const _Failed(this.line, this.label, this.message);

  /// The line of the statement, and how a check names it.
  final int line;
  final String label;

  final String message;
}

/// The tape was stopped.
final class _Stopped implements Exception {
  const _Stopped();
}
