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
      'Ctrl+C stops; what the recording left turned on in the terminal '
      '(the alternate screen, mouse reports, a hidden cursor) is turned '
      'off then.';

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

/// Plays [cast] back on stdout: what the program wrote (its `o` events),
/// each at its time divided by [speed], every pause longer than
/// [idleLimit] seconds cut to it.
///
/// A terminal on stdin is put in raw mode meanwhile, and what is typed is
/// dropped but for Ctrl+C, which stops; so is what the terminal answers
/// to the queries the program sent, which the recording has too. Stopped
/// (Ctrl+C, SIGINT, SIGTERM, SIGHUP), what the recording left turned on
/// is turned off. At the end, input not read yet is dropped as the
/// terminal is put back, after [grace] for answers still on their way.
final class Player {
  /// A player of [cast] at its own pace, every pause kept.
  Player(this.cast, {this.speed = 1, this.idleLimit});

  /// The recording played.
  final Cast cast;

  /// How many times faster than recorded it is played.
  final double speed;

  /// The longest pause played, in seconds; null plays each as it was.
  final double? idleLimit;

  /// How long answers to the last queries are waited for at the end.
  static const grace = Duration(milliseconds: 100);

  /// Plays [cast]; returns 0, or 130 when Ctrl+C stopped it, 128 and the
  /// signal's number when a signal did.
  Future<int> run() async {
    final stopped = Completer<int>();
    void stop(int code) {
      if (!stopped.isCompleted) {
        stopped.complete(code);
      }
    }

    final tty = RawTty.enter();
    final input = tty == null
        ? null
        : stdin.listen((bytes) {
            if (bytes.contains(0x03)) {
              stop(130);
            }
          }, onError: (Object _) {});
    final signals = [
      for (final (signal, number) in [
        (ProcessSignal.sigint, 2),
        (ProcessSignal.sigterm, 15),
        (ProcessSignal.sighup, 1),
      ])
        signal.watch().listen((_) => stop(128 + number)),
    ];
    final modes = ModeTracker();
    final clock = Stopwatch()..start();
    try {
      var last = 0.0;
      var at = 0.0;
      for (final event in cast.events) {
        final gap = math.max<double>(event.time - last, 0);
        last = event.time;
        at += idleLimit == null ? gap : math.min(gap, idleLimit!);
        if (event.code != CastEvent.output) {
          continue;
        }
        final due = Duration(microseconds: (at / speed * 1e6).round());
        final wait = due - clock.elapsed;
        if (wait > Duration.zero) {
          final due = Completer<void>();
          // cancelled when stopped: a timer left would keep the VM running
          final timer = Timer(wait, due.complete);
          await Future.any([due.future, stopped.future]);
          timer.cancel();
        }
        if (stopped.isCompleted) {
          break;
        }
        modes.add(event.data);
        stdout.add(utf8.encode(event.data));
        await stdout.flush();
      }
      if (stopped.isCompleted) {
        stdout.write(modes.off);
      }
      await stdout.flush();
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
