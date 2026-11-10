/// `twk record`: [RecordCommand], and [Recorder], which records a session.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:twk_term/twk_term.dart';

import 'cast.dart';
import 'modes.dart';
import 'replay.dart';

/// `twk record`: runs a command in a pseudo-terminal and records the
/// session as asciicast v2 ([Recorder]).
final class RecordCommand extends Command<int> {
  /// Sets up `twk record`'s options: `--out`, `--idle-limit`, `--title`
  /// and `--keys`.
  RecordCommand() {
    argParser
      ..addOption(
        'out',
        abbr: 'o',
        valueHelp: 'file',
        defaultsTo: 'session.cast',
        help: 'Where the recording goes.',
      )
      ..addOption(
        'idle-limit',
        valueHelp: 'seconds',
        defaultsTo: '2',
        help: 'The longest pause the recording keeps; 0 keeps each.',
      )
      ..addOption(
        'title',
        valueHelp: 'text',
        help: 'The title in the header (default: the command).',
      )
      ..addFlag(
        'keys',
        negatable: false,
        help: 'Record what is typed too ("i" events).',
      )
      ..addOption(
        'marker-key',
        valueHelp: 'ctrl+<letter>',
        help:
            'A key that leaves a marker ("m" event) in the recording, for '
            '`twk play` to go to, instead of reaching the command: ctrl+] '
            r'for one. Any ctrl+<letter> or [ \ ] ^ _ but ctrl+c, h, i, j, '
            'm, d, s, q, z and ctrl+[. Off by default.',
      )
      ..addOption(
        'replay',
        valueHelp: 'file',
        help:
            'Type what this recording typed (its keys, not the '
            "terminal's answers) into the command.",
      )
      ..addOption(
        'replay-speed',
        valueHelp: 'factor|asap',
        defaultsTo: '1',
        help:
            'How many times faster than recorded the keys are typed, or '
            '"asap": each once the command has stopped writing.',
      )
      ..addOption(
        'replay-then',
        allowed: ['handover', 'end'],
        defaultsTo: 'handover',
        help:
            'After the last key: this terminal goes to the command, or the '
            'command is hung up once it has been quiet.',
      );
  }

  // what follows the command is the command's
  @override
  final argParser = ArgParser(allowTrailingOptions: false);

  @override
  String get name => 'record';

  @override
  String get invocation =>
      'twk record [<options>] [--] <command> [<arguments>...]';

  @override
  String get description =>
      'Record a session as asciicast v2.\n\n'
      'Runs <command> in a pseudo-terminal of the size of this one and '
      'passes this terminal through to it, in raw mode, until the command '
      'ends: what it writes, every change of size and, with --keys, what '
      'is typed go to the recording with their times, a pause longer than '
      '--idle-limit cut to it. This terminal is put back as it was at the '
      'end, also when the recording fails or this process is stopped and '
      'continued. Ends with the exit code of the command, or 128 and the '
      'number of the signal that stopped it.';

  @override
  Future<int> run() {
    final results = argResults!;
    final command = results.rest;
    if (command.isEmpty) {
      usageException('No command to record.');
    }
    final limit = double.tryParse(results.option('idle-limit')!);
    if (limit == null || limit < 0 || !limit.isFinite) {
      usageException('--idle-limit takes a number of seconds, 0 or more.');
    }
    int? markerKey;
    if (results.option('marker-key') case final option?) {
      markerKey = markerKeyByte(option);
      if (markerKey == null) {
        usageException(
          r'--marker-key takes ctrl+ and a letter, or one of [ \ ] ^ _ '
          '(not ctrl+c, ctrl+i, ctrl+j, ctrl+m or ctrl+[, which are keys '
          'of the terminal; nor ctrl+h, Backspace on many terminals, ctrl+d, '
          'end of input, ctrl+s and ctrl+q, flow control, or ctrl+z, '
          'suspend).',
        );
      }
    }
    final replayPath = results.option('replay');
    Cast? replay;
    double? speed = 1;
    if (replayPath == null) {
      if (results.wasParsed('replay-speed') ||
          results.wasParsed('replay-then')) {
        usageException('--replay-speed and --replay-then go with --replay.');
      }
    } else {
      try {
        replay = Cast.read(replayPath);
      } on FileSystemException catch (e) {
        usageException(
          'Cannot read $replayPath: ${e.osError?.message ?? e.message}',
        );
      } on FormatException catch (e) {
        usageException('$replayPath: ${e.message}');
      }
      final option = results.option('replay-speed')!;
      speed = option == 'asap' ? null : double.tryParse(option);
      if (option != 'asap' &&
          (speed == null || speed <= 0 || !speed.isFinite)) {
        usageException('--replay-speed takes a number above 0, or asap.');
      }
    }
    return Recorder(
      command,
      out: results.option('out')!,
      idleLimit: limit == 0
          ? null
          : Duration(microseconds: (limit * 1e6).round()),
      title: results.option('title'),
      keys: results.flag('keys'),
      markerKey: markerKey,
      replay: replay,
      replaySpeed: speed,
      replayEnds: results.option('replay-then') == 'end',
    ).run();
  }
}

/// The byte of the key [name] (`ctrl+]`, `ctrl+a`) that `twk record
/// --marker-key` takes, or null for a name that is none or a key the
/// terminal needs (Ctrl+C, Tab, Enter, Escape, Backspace as Ctrl+H, EOF,
/// flow control, suspend).
int? markerKeyByte(String name) {
  final m = RegExp(
    r'^ctrl\+([a-z\[\\\]^_])$',
    caseSensitive: false,
  ).firstMatch(name);
  if (m == null) {
    return null;
  }
  final byte = m[1]!.toLowerCase().codeUnitAt(0) & 0x1f;
  return const {3, 4, 8, 9, 10, 13, 17, 19, 26, 27}.contains(byte)
      ? null
      : byte;
}

/// Runs [command] in a pseudo-terminal of this terminal's size (twk_term's
/// [Pty]) and records the session to [out] as asciicast v2.
///
/// This terminal is put in raw mode and passed through: what is typed
/// goes to the command as it is (Ctrl+C, Ctrl+Z included), what the
/// command writes comes out unchanged, and a change of this terminal's
/// size resizes the command's. The recording gets a header (the size,
/// the time, `TERM` and `SHELL`, the command, [title]), then an event a
/// line: `o` for what the command wrote, `i` for what was typed when
/// [keys], `r` for a change of size, each at its time since the start
/// with every pause longer than [idleLimit] cut to it. The command runs
/// with this terminal's `TERM`, whose bytes it writes.
///
/// It ends when the command does, or when this process gets SIGINT,
/// SIGTERM or SIGHUP, which hang the command's terminal up. Then the
/// terminal is put back: whatever the command left turned on (the
/// alternate screen, mouse reports, a hidden cursor) is turned off, and
/// the modes raw mode changed are restored, also when the recording
/// failed (the file could not be written). SIGCONT can't be watched from
/// Dart: when the terminal's modes were changed while this process was
/// stopped (a shell takes the terminal from a job it stops), raw mode is
/// entered again within [guard].
final class Recorder {
  /// A recorder of [command] to the file [out], each pause cut to 2
  /// seconds.
  Recorder(
    this.command, {
    required this.out,
    this.idleLimit = const Duration(seconds: 2),
    this.title,
    this.keys = false,
    this.markerKey,
    this.replay,
    this.replaySpeed = 1,
    this.replayEnds = false,
  });

  /// The program and its arguments.
  final List<String> command;

  /// The recording's path.
  final String out;

  /// The longest pause the recording keeps; null keeps each.
  final Duration? idleLimit;

  /// The title in the recording's header; null for none.
  final String? title;

  /// Whether what is typed is recorded too (`i` events).
  final bool keys;

  /// The byte of a key that leaves a marker (`m` event, labelled
  /// `marker <n>`) instead of reaching the command, or null for none (see
  /// [markerKeyByte]). Read as the plain byte only: a terminal that has
  /// the kitty keyboard flags on sends it as another sequence, which the
  /// command gets.
  final int? markerKey;

  /// A recording whose keys are typed into the command (see
  /// [replaySteps]), or null.
  ///
  /// They are typed once the command has written: at the recorded times
  /// divided by [replaySpeed] counted from its first output, or, with a
  /// null [replaySpeed], each once the command has been quiet for
  /// [settle]. Meanwhile this terminal's keys are not passed on, except
  /// Ctrl+C and the terminal's answers to the command's queries (the
  /// recording's own are never typed: this terminal answers them again).
  /// After the last, this terminal goes to the command, or with
  /// [replayEnds] the command is hung up once it has been quiet for
  /// [endQuiet].
  final Cast? replay;

  /// How many times faster than recorded [replay] is typed; null for as
  /// soon as the command has settled.
  final double? replaySpeed;

  /// Whether the command is hung up when [replay] has been typed.
  final bool replayEnds;

  /// How long the command writes nothing before the next key of a replay
  /// as soon as possible is typed.
  static const settle = Duration(milliseconds: 100);

  /// How long a replay as soon as possible waits for the command to
  /// answer a key that it answered when it was recorded.
  static const reactionLimit = Duration(seconds: 2);

  /// How long the command writes nothing before a replay that ends hangs
  /// it up.
  static const endQuiet = Duration(seconds: 1);

  /// How often the terminal is checked for the modes it should have.
  static const guard = Duration(milliseconds: 200);

  /// How long the command is given to end once its terminal hung up, and
  /// what it left running to close the terminal once it ended.
  static const patience = Duration(seconds: 2);

  late final Pty _pty;
  late final CastWriter _cast;
  final _clock = Stopwatch();
  final _modes = ModeTracker();
  final _outputDone = Completer<void>();
  final _firstOutput = Completer<void>();
  var _replaying = false;
  Duration _lastOutput = Duration.zero;
  var _outputs = 0;
  var _markers = 0;

  // the exit code a signal set, and what went wrong
  int? _stopped;
  Object? _failure;
  StackTrace? _failureStack;

  /// Records until the command ends; returns its exit code, 128 and the
  /// signal's number when a signal ended it or this process, 1 when the
  /// recording failed, 127 when the command couldn't be started.
  Future<int> run() async {
    final (width, height) = stdout.hasTerminal
        ? (stdout.terminalColumns, stdout.terminalLines)
        : (80, 24);
    final env = Platform.environment;
    final line = command.map(_quoted).join(' ');
    try {
      _pty = Pty.start(
        command.first,
        command.sublist(1),
        width: width,
        height: height,
        // a terminal, the recording's: not plain, CI or not
        environment: {'TERM': ?env['TERM'], 'CI': 'false'},
      );
    } on Object catch (e) {
      // before the recording is opened: one there already is left as it is
      stderr.writeln(switch (e) {
        ProcessException(:final message) =>
          'twk record: cannot run ${command.first}: $message',
        _ => 'twk record: $e',
      });
      return e is ProcessException ? 127 : 1;
    }
    final RandomAccessFile file;
    try {
      file = File(out).openSync(mode: FileMode.writeOnly);
    } on FileSystemException catch (e) {
      // hung up: the command was started for nothing
      _pty.close();
      stderr.writeln('twk record: cannot write $out: ${_reason(e)}');
      return 1;
    }
    try {
      _cast = CastWriter(
        file.writeStringSync,
        CastHeader(
          width: width,
          height: height,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          idleTimeLimit: idleLimit == null
              ? null
              : idleLimit!.inMicroseconds / 1e6,
          command: line,
          title: title ?? line,
          env: {'TERM': ?env['TERM'], 'SHELL': ?env['SHELL']},
        ),
        idleLimit: idleLimit,
      );
    } on FileSystemException catch (e) {
      _pty.close();
      file.closeSync();
      File(out).deleteSync();
      stderr.writeln('twk record: cannot write $out: ${_reason(e)}');
      return 1;
    }
    _clock.start();
    stderr.writeln('twk record: recording $line to $out');
    final result = Completer<int>();
    // an error in a listener, a timer: the recording fails, and ends
    runZonedGuarded(() => unawaited(_guarded(result, file)), _fail);
    return result.future;
  }

  Future<void> _guarded(Completer<int> result, RandomAccessFile file) async {
    try {
      result.complete(await _session());
    } on Object catch (e, s) {
      _fail(e, s);
      result.complete(_report());
    } finally {
      try {
        file.closeSync();
      } on FileSystemException {
        // what could be written was
      }
    }
  }

  /// Passes the terminal through until the command ended, then puts it
  /// back; returns the exit code.
  Future<int> _session() async {
    // watched first: none of them may end this process in raw mode
    final signals = [
      for (final (signal, number) in [
        (ProcessSignal.sigint, 2),
        (ProcessSignal.sigterm, 15),
        (ProcessSignal.sighup, 1),
      ])
        signal.watch().listen((_) => _stop(128 + number)),
      if (stdout.hasTerminal)
        ProcessSignal.sigwinch.watch().listen((_) => _resized()),
    ];
    final tty = RawTty.enter();
    final guarding = tty == null
        ? null
        : Timer.periodic(guard, (_) {
            if (!tty.isRaw) {
              tty.reenter();
            }
          });
    final live = replay == null ? null : InputSplitter();
    _replaying = replay != null;
    final input = stdin.listen((typed) {
      var bytes = typed;
      if (_replaying) {
        // the terminal's answers, and a way out; not the person's keys
        final pieces = live!.add(latin1.decode(bytes));
        final kept = StringBuffer();
        for (final piece in pieces) {
          kept.write(
            piece.isAnswer
                ? piece.text
                : piece.text.replaceAll(RegExp('[^\x03]'), ''),
          );
        }
        bytes = latin1.encode(kept.toString());
        if (bytes.isEmpty) {
          return;
        }
      }
      final mark = markerKey;
      if (mark == null || _replaying || !bytes.contains(mark)) {
        _pty.write(bytes);
        if (keys) {
          _cast.input(_clock.elapsed, bytes);
        }
        return;
      }
      // the marker key is cut out; what is around it goes on in order
      var from = 0;
      for (var i = 0; i <= bytes.length; i++) {
        if (i < bytes.length && bytes[i] != mark) {
          continue;
        }
        final piece = bytes.sublist(from, i);
        if (piece.isNotEmpty) {
          _pty.write(piece);
          if (keys) {
            _cast.input(_clock.elapsed, piece);
          }
        }
        if (i < bytes.length) {
          _cast.marker(_clock.elapsed, 'marker ${++_markers}');
        }
        from = i + 1;
      }
    }, onError: (Object _) {});
    late final StreamSubscription<Uint8List> output;
    output = _pty.output.listen(
      (bytes) {
        _lastOutput = _clock.elapsed;
        _outputs++;
        final text = _cast.output(_lastOutput, bytes);
        live?.sawOutput(text);
        if (!_firstOutput.isCompleted) {
          _firstOutput.complete();
        }
        _modes.add(text);
        stdout.add(bytes);
        output.pause(stdout.flush().catchError(_fail));
      },
      onError: _fail,
      onDone: _outputDone.complete,
    );
    if (replay != null) {
      unawaited(_replay(live!));
    }
    int? code;
    try {
      code = await _ended();
    } finally {
      guarding?.cancel();
      for (final s in signals) {
        await s.cancel();
      }
      await output.cancel();
      try {
        _cast.close(_clock.elapsed);
      } on FileSystemException catch (e, s) {
        _fail(e, s);
      }
      try {
        stdout.write(_modes.off);
        await stdout.flush();
      } on Object {
        // the terminal is gone
      }
      // before stdin is closed, which leaves its modes as they are
      tty?.restore();
      await input.cancel();
    }
    if (_failure != null) {
      return _report();
    }
    final stopped = _stopped;
    stderr.writeln(
      'twk record: $out, ${_cast.time.toStringAsFixed(1)} s, '
      '${_cast.count} events',
    );
    return stopped ?? (code == null ? 0 : (code < 0 ? 128 - code : code));
  }

  /// Types the keys of [replay] into the command, then hands this terminal
  /// over (or ends it); stops when the command ended.
  Future<void> _replay(InputSplitter live) async {
    try {
      await Future.any([_firstOutput.future, _outputDone.future]);
      final steps = replaySteps(replay!);
      final first = replay!.events
          .firstWhere(
            (e) => e.code == CastEvent.output,
            orElse: () => const CastEvent(0, CastEvent.output, ''),
          )
          .time;
      final base = _clock.elapsed;
      stderr.writeln(
        'twk record: replaying ${steps.length} inputs of '
        '${replay!.duration.toStringAsFixed(1)} s',
      );
      var reaction = false;
      var sent = (_outputs, _clock.elapsed);
      for (var k = 0; k < steps.length; k++) {
        final step = steps[k];
        final speed = replaySpeed;
        if (speed == null) {
          if (reaction) {
            // the command answered the last key when it was recorded
            await _wait(() => _outputs > sent.$1, reactionLimit);
          }
          await _quiet(settle, since: sent.$2);
        } else {
          final due =
              base +
              Duration(
                microseconds: ((step.time - first) / speed * 1e6).round(),
              );
          await _waitUntil(due);
        }
        if (_outputDone.isCompleted) {
          return;
        }
        final bytes = utf8.encode(step.keys);
        _pty.write(bytes);
        if (keys) {
          _cast.input(_clock.elapsed, bytes);
        }
        sent = (_outputs, _clock.elapsed);
        reaction = step.reacts;
      }
      if (replayEnds) {
        await _quiet(endQuiet);
        if (!_outputDone.isCompleted) {
          _stop(0);
        }
      }
    } on Object catch (e, s) {
      // an odd recording, a write to the terminal that failed: the recording
      // fails as any other, with the terminal put back
      _fail(e, s);
    } finally {
      _replaying = false;
      // what was kept of a sequence is the person's now
      final rest = live.flush().map((p) => p.text).join();
      if (rest.isNotEmpty && !_outputDone.isCompleted) {
        final bytes = latin1.encode(rest);
        _pty.write(bytes);
        if (keys) {
          _cast.input(_clock.elapsed, bytes);
        }
      }
    }
  }

  /// Waits until the clock reads [due], or the command is gone.
  Future<void> _waitUntil(Duration due) async {
    while (!_outputDone.isCompleted) {
      final left = due - _clock.elapsed;
      if (left <= Duration.zero) {
        return;
      }
      await Future.any([
        Future<void>.delayed(left),
        _outputDone.future,
      ]);
    }
  }

  /// Waits until [done], for [limit] at most, or until the command is gone.
  Future<void> _wait(bool Function() done, Duration limit) async {
    final end = _clock.elapsed + limit;
    while (!_outputDone.isCompleted && !done() && _clock.elapsed < end) {
      await Future.any([
        Future<void>.delayed(const Duration(milliseconds: 5)),
        _outputDone.future,
      ]);
    }
  }

  /// Waits until the command has written nothing for [quiet] (since
  /// [since], when later than its last output), or is gone.
  Future<void> _quiet(Duration quiet, {Duration since = Duration.zero}) async {
    while (!_outputDone.isCompleted) {
      final last = _lastOutput > since ? _lastOutput : since;
      final left = last + quiet - _clock.elapsed;
      if (left <= Duration.zero) {
        return;
      }
      await Future.any([
        Future<void>.delayed(left),
        _outputDone.future,
      ]);
    }
  }

  /// Waits for the command to end and its terminal to hang up, which
  /// whatever it left running may keep open: that is hung up [patience]
  /// after the command ended. Returns the command's exit code.
  Future<int?> _ended() async {
    final exited = _pty.exitCode;
    await Future.any([_outputDone.future, exited]);
    if (!_outputDone.isCompleted) {
      await _outputDone.future.timeout(patience, onTimeout: _pty.close);
      await _outputDone.future;
    }
    return exited.timeout(
      patience,
      onTimeout: () {
        _pty.kill(ProcessSignal.sigkill);
        return exited;
      },
    );
  }

  /// This terminal's size changed: so does the command's.
  void _resized() {
    final (w, h) = (stdout.terminalColumns, stdout.terminalLines);
    if (w < 1 || h < 1 || (w == _pty.width && h == _pty.height)) {
      return;
    }
    _pty.resize(w, h);
    _cast.resize(_clock.elapsed, w, h);
  }

  /// Ends the recording with [code]: hangs the command's terminal up.
  void _stop(int code) {
    _stopped ??= code;
    _pty.close();
  }

  /// The recording failed with [error]: it ends.
  void _fail(Object error, StackTrace stack) {
    _failure ??= error;
    _failureStack ??= stack;
    _pty.close();
  }

  /// Says what went wrong; returns the exit code for it.
  int _report() {
    final failure = _failure;
    if (failure is FileSystemException) {
      stderr.writeln('twk record: cannot write $out: ${_reason(failure)}');
    } else {
      stderr.writeln('twk record: $failure\n$_failureStack');
    }
    return 1;
  }

  static String _reason(FileSystemException e) =>
      e.osError?.message ?? e.message;

  /// [word] as a shell takes it.
  static String _quoted(String word) =>
      RegExp(r'^[\w@%+=:,./-]+$').hasMatch(word)
      ? word
      : "'${word.replaceAll("'", r"'\''")}'";
}
