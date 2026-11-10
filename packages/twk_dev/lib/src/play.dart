/// `twk play`: [PlayCommand], and [Player], which plays a recording back.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:args/command_runner.dart';
import 'package:twk_term/twk_term.dart' show RawTty;

import 'cast.dart';
import 'modes.dart';

/// `twk play`: plays a recording back in this terminal ([Player]).
final class PlayCommand extends Command<int> {
  /// Sets up `twk play`'s options: `--speed` and `--idle-limit`.
  PlayCommand() {
    argParser
      ..addOption(
        'speed',
        abbr: 's',
        valueHelp: 'factor',
        defaultsTo: '1',
        help: 'How many times faster than recorded.',
      )
      ..addOption(
        'idle-limit',
        valueHelp: 'seconds',
        help:
            'The longest pause played; 0 plays each (default: the '
            "recording's idle_time_limit).",
      );
  }

  @override
  String get name => 'play';

  @override
  String get invocation => 'twk play [<options>] <file>';

  @override
  String get description =>
      'Play a recording back in this terminal.\n\n'
      'Writes what the program recorded in <file> (asciicast v2, as `twk '
      'record` writes it) wrote, at the times it wrote it, divided by '
      '--speed, a pause longer than the idle limit cut to it. This '
      'terminal is not resized: play a recording in one of its size. '
      'Space pauses and plays, Right goes a frame on and Left a frame back '
      '(a frame is a screen the recording showed: the output up to where '
      'no synchronized update is open), Home plays from the start, q '
      'quits. Paused, a status line (frame n/m, the time) shows under '
      'the recording, where this terminal has a row for it. '
      'Ctrl+C stops; what the recording left turned on in the terminal '
      '(the alternate screen, mouse reports, a hidden cursor) is turned '
      'off then, after q too.';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.length != 1) {
      usageException('One recording to play.');
    }
    final speed = double.tryParse(results.option('speed')!);
    if (speed == null || speed <= 0 || !speed.isFinite) {
      usageException('--speed takes a number above 0.');
    }
    final limitOption = results.option('idle-limit');
    final limit = limitOption == null ? null : double.tryParse(limitOption);
    if (limitOption != null && (limit == null || limit < 0)) {
      usageException('--idle-limit takes a number of seconds, 0 or more.');
    }
    final path = results.rest.single;
    final Cast cast;
    try {
      cast = Cast.read(path);
    } on FileSystemException catch (e) {
      stderr.writeln(
        'twk play: cannot read $path: ${e.osError?.message ?? e.message}',
      );
      return 1;
    } on FormatException catch (e) {
      stderr.writeln('twk play: $path: ${e.message}');
      return 1;
    }
    return Player(
      cast,
      speed: speed,
      idleLimit: switch (limit) {
        null => cast.header.idleTimeLimit,
        0 => null,
        _ => limit,
      },
    ).run();
  }
}

/// What a key typed while a recording plays asks.
enum PlayKey {
  /// Space: pauses, or plays on (from the start once it ended).
  toggle,

  /// Right: paused, the next frame shown.
  next,

  /// Left: paused, the frame before the one shown.
  previous,

  /// Home: played from the start.
  start,

  /// `q`: stops, exit 0.
  quit,

  /// Ctrl+C: stops, exit 130.
  interrupt,
}

/// The keys in [typed], and what of it is not a whole key yet (the start
/// of an escape sequence, to be put in front of the next piece). The
/// terminal's answers to the queries of the recording are whole escape
/// sequences, and give no key.
(List<PlayKey>, String) readPlayKeys(String typed) {
  final keys = <PlayKey>[];
  var i = 0;
  while (i < typed.length) {
    final c = typed.codeUnitAt(i);
    if (c != 0x1b) {
      switch (c) {
        case 0x03:
          keys.add(PlayKey.interrupt);
        case 0x20:
          keys.add(PlayKey.toggle);
        case 0x71:
          keys.add(PlayKey.quit);
      }
      i++;
      continue;
    }
    if (i + 1 == typed.length) {
      return (keys, typed.substring(i));
    }
    switch (typed[i + 1]) {
      case '[':
        var j = i + 2;
        while (j < typed.length && typed.codeUnitAt(j) < 0x40) {
          j++;
        }
        if (j == typed.length) {
          return (keys, typed.substring(i));
        }
        if (typed.codeUnitAt(j) > 0x7e) {
          i = j;
          continue;
        }
        if (_csiKey(typed.substring(i + 2, j), typed[j]) case final key?) {
          keys.add(key);
        }
        i = j + 1;
      case 'O':
        if (i + 2 == typed.length) {
          return (keys, typed.substring(i));
        }
        if (_csiKey('', typed[i + 2]) case final key?) {
          keys.add(key);
        }
        i += 3;
      case ']' || 'P' || '_' || '^' || 'X':
        // a string: ended by ST, an OSC also by BEL
        final st = typed.indexOf('\x1b\\', i + 2);
        final bel = typed[i + 1] == ']' ? typed.indexOf('\x07', i + 2) : -1;
        final end = switch ((st, bel)) {
          (-1, -1) => -1,
          (-1, _) => bel + 1,
          (_, -1) => st + 2,
          _ => math.min(st + 2, bel + 1),
        };
        if (end == -1) {
          return (keys, typed.length - i > 4096 ? '' : typed.substring(i));
        }
        i = end;
      default:
        i += 2;
    }
  }
  return (keys, '');
}

/// The key a CSI sequence with [params] and [final], or an SS3 with
/// [final], is: the arrows and Home as a terminal sends them, and, where
/// the recording turned the kitty keyboard flags on, Space, `q` and
/// Ctrl+C as CSI u (a release is no key).
PlayKey? _csiKey(String params, String final_) {
  switch (final_) {
    case 'C':
      return PlayKey.next;
    case 'D':
      return PlayKey.previous;
    case 'H':
      return PlayKey.start;
    case '~':
      return const {'1', '7'}.contains(params.split(';').first)
          ? PlayKey.start
          : null;
    case 'u':
      final parts = params.split(';');
      if (params.contains(':3') || parts.first.contains(':')) {
        return null;
      }
      final modifiers = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
      return switch (int.tryParse(parts.first)) {
        32 when modifiers == 1 => PlayKey.toggle,
        113 when modifiers == 1 => PlayKey.quit,
        99 when modifiers == 5 => PlayKey.interrupt,
        _ => null,
      };
  }
  return null;
}

/// The time [Player] plays by, which a test moves.
class PlayClock {
  final _watch = Stopwatch()..start();

  /// The time since it was made.
  Duration get elapsed => _watch.elapsed;

  /// Waits [duration], or until [stop] completes.
  Future<void> pause(Duration duration, Future<void> stop) async {
    final done = Completer<void>();
    // cancelled when stopped: a timer left would keep the VM running
    final timer = Timer(duration, done.complete);
    await Future.any([done.future, stop]);
    timer.cancel();
  }
}

/// What [Player] writes at one time: the output up to a frame, or, with
/// `frame` 0, what follows the last one inside an update never ended.
typedef _Step = ({String output, double at, double time, int frame});

/// Plays [cast] back on stdout: what the program wrote (its `o` events),
/// each frame at its time divided by [speed], every pause longer than
/// [idleLimit] seconds cut to it. A frame is what twk_test's `screenFrames`
/// takes for one: the output up to where no synchronized update (DEC mode
/// 2026) is open, written in one piece.
///
/// A terminal on stdin is put in raw mode meanwhile; Space pauses and
/// plays, Right goes a frame on, Left a frame back (the terminal reset
/// and the frames before it written at once), Home plays from the start,
/// `q` stops, and Ctrl+C stops with 130. Other keys are dropped, and so
/// is what the terminal answers to the queries the program sent, which
/// the recording has too. Paused, a status line (`frame 3/12`, the time)
/// shows on the row under the recording where the terminal has one; it is
/// not written into what is played, and is wiped when playing goes on. It
/// is drawn with the cursor saved (`ESC 7`) and put back (`ESC 8`): the
/// terminal has one saved cursor, so a recording that saved its own
/// before a pause and restores it after finds the status line's. Stopped
/// (q, Ctrl+C, SIGINT, SIGTERM, SIGHUP), what the recording left turned on
/// is turned off. At the end, input not read yet is dropped as the
/// terminal is put back, after [grace] for answers still on their way.
final class Player {
  /// A player of [cast] at its own pace, every pause kept. `output`,
  /// `keys`, `rows` and `clock` are the terminal's, stdin's and the
  /// time's, unless a test gives its own (then no signal is watched, and
  /// no terminal put in raw mode).
  Player(
    this.cast, {
    this.speed = 1,
    this.idleLimit,
    this._output,
    this._keys,
    this._rows,
    PlayClock? clock,
  }) : _clock = clock ?? PlayClock();

  /// The recording played.
  final Cast cast;

  /// How many times faster than recorded it is played.
  final double speed;

  /// The longest pause played, in seconds; null plays each as it was.
  final double? idleLimit;

  /// How long answers to the last queries are waited for at the end.
  static const grace = Duration(milliseconds: 100);

  final Future<void> Function(String text)? _output;
  final Stream<List<int>>? _keys;
  final int? _rows;
  final PlayClock _clock;

  /// Resets the terminal: what the recording left on, the screen and its
  /// modes (RIS).
  static const _reset = '\x1bc';

  static final _sync = RegExp(r'\x1b\[\?([0-9;]*)([hl])');
  static final _cut = RegExp(r'\x1b(?:\[[0-?]*[ -/]*)?$');

  List<_Step> _steps() {
    final steps = <_Step>[];
    var depth = 0;
    var tail = '';
    var output = StringBuffer();
    var last = 0.0;
    var at = 0.0;
    var time = 0.0;
    var pending = false;
    var frames = 0;
    for (final event in cast.events) {
      final gap = math.max<double>(event.time - last, 0);
      last = event.time;
      at += idleLimit == null ? gap : math.min(gap, idleLimit!);
      if (event.code != CastEvent.output) {
        continue;
      }
      output.write(event.data);
      pending = true;
      time = event.time;
      final s = '$tail${event.data}';
      for (final m in _sync.allMatches(s)) {
        final n = m[1]!.split(';').where((p) => p == '2026').length;
        depth += m[2] == 'h' ? n : -n;
      }
      final cut = _cut.firstMatch(
        s.length > 64 ? s.substring(s.length - 64) : s,
      );
      tail = cut == null ? '' : cut[0]!;
      if (depth > 0) {
        continue;
      }
      steps.add((
        output: '$output',
        at: at,
        time: time,
        frame: ++frames,
      ));
      output = StringBuffer();
      pending = false;
    }
    if (pending) {
      steps.add((output: '$output', at: at, time: time, frame: 0));
    }
    return steps;
  }

  /// Plays [cast]; returns 0, or 130 when Ctrl+C stopped it, 128 and the
  /// signal's number when a signal did, 0 when `q` did.
  Future<int> run() async {
    final stopped = Completer<int>();
    void stop(int code) {
      if (!stopped.isCompleted) {
        stopped.complete(code);
      }
    }

    final injected = _keys != null;
    final tty = injected ? null : RawTty.enter();
    final queue = <PlayKey>[];
    var wake = Completer<void>();
    var typed = '';
    void onKeys(List<int> bytes) {
      final (keys, rest) = readPlayKeys('$typed${latin1.decode(bytes)}');
      typed = rest;
      for (final key in keys) {
        if (key == PlayKey.interrupt) {
          stop(130);
        } else if (key == PlayKey.quit) {
          stop(0);
        } else {
          queue.add(key);
        }
      }
      if (keys.isNotEmpty && !wake.isCompleted) {
        wake.complete();
      }
    }

    final input = injected
        ? _keys.listen(onKeys)
        : tty == null
        ? null
        : stdin.listen(onKeys, onError: (Object _) {});
    final signals = injected
        ? const <StreamSubscription<ProcessSignal>>[]
        : [
            for (final (signal, number) in [
              (ProcessSignal.sigint, 2),
              (ProcessSignal.sigterm, 15),
              (ProcessSignal.sighup, 1),
            ])
              signal.watch().listen((_) => stop(128 + number)),
          ];
    final output =
        _output ??
        (String text) async {
          stdout.add(utf8.encode(text));
          await stdout.flush();
        };
    final rows = _rows ?? (stdout.hasTerminal ? stdout.terminalLines : null);
    final room = rows != null && rows > cast.header.height;
    final steps = _steps();
    final frames = steps.where((s) => s.frame > 0).length;
    final duration = cast.duration;
    var modes = ModeTracker();
    var shown = 0;
    var playing = true;
    var statusUp = false;
    var anchor = Duration.zero;

    Duration play(double at) =>
        Duration(microseconds: (at / speed * 1e6).round());
    // where the playing is with [n] steps shown, and when the next is due
    Duration reached(int n) => play(n == 0 ? 0 : steps[n - 1].at);
    void anchorHere() => anchor = _clock.elapsed - reached(shown);

    String line(String text) =>
        '\x1b7\x1b[${cast.header.height + 1};1H\x1b[2K$text\x1b8';
    Future<void> wipeStatus() async {
      if (statusUp) {
        statusUp = false;
        await output(line(''));
      }
    }

    Future<void> drawStatus() async {
      if (!room) {
        return;
      }
      final n = steps.take(shown).where((s) => s.frame > 0).length;
      final time = shown == 0 ? 0.0 : steps[shown - 1].time;
      statusUp = true;
      await output(
        line(
          '\x1b[7m paused  frame $n/$frames  '
          '${time.toStringAsFixed(3)} s / ${duration.toStringAsFixed(3)} s '
          '\x1b[0m',
        ),
      );
    }

    Future<void> seek(int n) async {
      modes = ModeTracker();
      final out = StringBuffer();
      for (final step in steps.take(n)) {
        modes.add(step.output);
        out.write(step.output);
      }
      statusUp = false;
      shown = n;
      await output('$_reset$out');
    }

    Future<void> show() async {
      final step = steps[shown++];
      modes.add(step.output);
      await output(step.output);
    }

    try {
      anchorHere();
      while (!stopped.isCompleted) {
        if (queue.isNotEmpty) {
          final key = queue.removeAt(0);
          if (queue.isEmpty) {
            wake = Completer<void>();
          }
          switch (key) {
            case PlayKey.toggle:
              if (playing) {
                playing = false;
                await drawStatus();
              } else {
                await wipeStatus();
                if (shown >= steps.length) {
                  await seek(0);
                }
                playing = true;
                anchorHere();
              }
            case PlayKey.next:
              playing = false;
              await wipeStatus();
              if (shown < steps.length) {
                await show();
              }
              await drawStatus();
            case PlayKey.previous:
              playing = false;
              await wipeStatus();
              if (shown > 0) {
                await seek(shown - 1);
              }
              await drawStatus();
            case PlayKey.start:
              await wipeStatus();
              await seek(0);
              playing = true;
              anchorHere();
            case PlayKey.quit || PlayKey.interrupt:
              break;
          }
          continue;
        }
        final woken = Future.any([wake.future, stopped.future]);
        if (!playing) {
          await woken;
          continue;
        }
        if (shown >= steps.length) {
          break;
        }
        final wait = play(steps[shown].at) - (_clock.elapsed - anchor);
        if (wait > Duration.zero) {
          await _clock.pause(wait, woken);
          continue;
        }
        await show();
      }
      if (stopped.isCompleted) {
        await wipeStatus();
        await output(modes.off);
      }
      if (tty != null) {
        await Future<void>.delayed(grace);
      }
    } finally {
      for (final s in signals) {
        await s.cancel();
      }
      tty?.restore(discardInput: true);
      await input?.cancel();
    }
    return stopped.isCompleted ? await stopped.future : 0;
  }
}
