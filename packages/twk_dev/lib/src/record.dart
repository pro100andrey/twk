/// `twk record`: [RecordCommand], and [Recorder], which records a session.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:twk_term/twk_term.dart';

import 'cast.dart';
import 'modes.dart';

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
    return Recorder(
      command,
      out: results.option('out')!,
      idleLimit: limit == 0
          ? null
          : Duration(microseconds: (limit * 1e6).round()),
      title: results.option('title'),
      keys: results.flag('keys'),
    ).run();
  }
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
    final RandomAccessFile file;
    try {
      file = File(out).openSync(mode: FileMode.writeOnly);
    } on FileSystemException catch (e) {
      stderr.writeln('twk record: cannot write $out: ${_reason(e)}');
      return 1;
    }
    final env = Platform.environment;
    final line = command.map(_quoted).join(' ');
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
      _pty = Pty.start(
        command.first,
        command.sublist(1),
        width: width,
        height: height,
        // a terminal, the recording's: not plain, CI or not
        environment: {'TERM': ?env['TERM'], 'CI': 'false'},
      );
    } on Object catch (e) {
      file.closeSync();
      if (FileSystemEntity.isFileSync(out)) {
        File(out).deleteSync();
      }
      stderr.writeln(switch (e) {
        FileSystemException() => 'twk record: cannot write $out: ${_reason(e)}',
        ProcessException(:final message) =>
          'twk record: cannot run ${command.first}: $message',
        _ => 'twk record: $e',
      });
      return e is ProcessException ? 127 : 1;
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
    final input = stdin.listen((bytes) {
      _pty.write(bytes);
      if (keys) {
        _cast.input(_clock.elapsed, bytes);
      }
    }, onError: (Object _) {});
    late final StreamSubscription<Uint8List> output;
    output = _pty.output.listen(
      (bytes) {
        _modes.add(_cast.output(_clock.elapsed, bytes));
        stdout.add(bytes);
        output.pause(stdout.flush().catchError(_fail));
      },
      onError: _fail,
      onDone: _outputDone.complete,
    );
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
