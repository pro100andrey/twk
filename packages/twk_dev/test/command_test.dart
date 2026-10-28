// The `twk` command line: its usage, what each command says of arguments
// it cannot take, and what those that want a terminal do without one. Run
// in this process (`twkHere`), as in one started without a terminal.
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/twk_dev.dart';

import 'twk.dart';

/// The subcommands `twk --help` lists, by name.
const subcommands = [
  'create',
  'inspect',
  'logs',
  'play',
  'record',
  'run',
  'shell',
  'tape',
];

/// The names in the "Available commands:" section of [usage]: the lines
/// indented by two spaces after the heading, up to the first blank line.
List<String> commandsIn(String usage) {
  final lines = const LineSplitter().convert(usage);
  final heading = lines.indexOf('Available commands:');
  if (heading < 0) {
    return const [];
  }
  final name = RegExp(r'^  (\S+)');
  return [
    for (final line in lines.skip(heading + 1).takeWhile((l) => l.isNotEmpty))
      ?name.firstMatch(line)?.group(1),
  ];
}

void main() {
  test('twk --help lists the subcommands and exits with 0', () async {
    final result = await twkHere(['--help']);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(commandsIn(result.stdout as String), subcommands);
  });

  test(
    'twk inspect with more than one address exits with $usageExitCode, '
    'with one nothing answers at with 1, without a terminal with 1',
    () async {
      final two = await twkHere(['inspect', 'ws://127.0.0.1:1/ws', 'x']);
      expect(two.exitCode, usageExitCode);
      expect(two.stderr, contains('One VM service address at most.'));

      final malformed = await twkHere(['inspect', 'nowhere']);
      expect(malformed.exitCode, usageExitCode);
      expect(malformed.stderr, contains('Not a VM service address: nowhere'));

      final nothing = await twkHere(['inspect', 'ws://127.0.0.1:1/ws']);
      expect(nothing.exitCode, 1);
      expect(nothing.stderr, startsWith('twk inspect: no VM service at '));

      final waiting = await twkHere(['inspect']);
      expect(waiting.exitCode, 1);
      expect(waiting.stderr, 'twk inspect: not a terminal\n');
    },
  );

  test('twk inspect connected to a VM service without a terminal exits '
      'with 1', () async {
    // this process's VM service, which it may have on already
    final on = (await Service.getInfo()).serverUri != null;
    final info = await Service.controlWebServer(
      enable: true,
      silenceOutput: true,
    );
    if (!on) {
      addTearDown(() => Service.controlWebServer(silenceOutput: true));
    }

    final result = await twkHere(['inspect', '${info.serverWebSocketUri}']);
    expect(result.exitCode, 1);
    expect(result.stderr, 'twk inspect: not a terminal\n');
  });

  test('twk run without a file exits with $usageExitCode, with a file that '
      'is not there with 1', () async {
    final none = await twkHere(['run']);
    expect(none.exitCode, usageExitCode);
    expect(none.stderr, contains('No file to run.'));

    final missing = await twkHere(['run', 'missing.dart', '--seconds=1']);
    expect(missing.exitCode, 1);
    expect(missing.stderr, 'twk run: no file missing.dart\n');
  });

  test('twk shell without a terminal says so and exits with 1', () async {
    final result = await twkHere(['shell']);

    expect(result.exitCode, 1);
    expect(result.stderr, 'twk shell: not a terminal\n');
  });

  test('twk record without a command or with a bad idle limit exits with '
      '$usageExitCode, with a recording it cannot write or a command it '
      'cannot run with 1 and 127, leaving no recording', () async {
    final temp = await Directory.systemTemp.createTemp('twk_record_');
    addTearDown(() => temp.delete(recursive: true));
    final cast = p.join(temp.path, 's.cast');

    final none = await twkHere(['record', '--out=$cast']);
    expect(none.exitCode, usageExitCode);
    expect(none.stderr, contains('No command to record.'));

    final limit = await twkHere([
      'record',
      '--idle-limit=soon',
      '--',
      'true',
    ]);
    expect(limit.exitCode, usageExitCode);
    expect(limit.stderr, contains('--idle-limit takes a number of seconds'));

    final nowhere = p.join(temp.path, 'none', 's.cast');
    final unwritable = await twkHere([
      'record',
      '--out=$nowhere',
      '--',
      'true',
    ]);
    expect(unwritable.exitCode, 1);
    expect(
      unwritable.stderr,
      startsWith('twk record: cannot write $nowhere: '),
    );

    final missing = await twkHere(['record', '--out=$cast', 'no-such-program']);
    expect(missing.exitCode, 127);
    expect(
      missing.stderr,
      startsWith('twk record: cannot run no-such-program: '),
    );
    expect(File(cast).existsSync(), isFalse);
  });

  test('twk record without a terminal records at 80 by 24, writing what '
      'the command wrote to stdout', () async {
    final temp = await Directory.systemTemp.createTemp('twk_record_');
    addTearDown(() => temp.delete(recursive: true));
    final cast = p.join(temp.path, 's.cast');

    final result = await twkHere(['record', '--out=$cast', 'echo', 'hi']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, 'hi\r\n');
    final recording = Cast.read(cast);
    expect((recording.header.width, recording.header.height), (80, 24));
    expect(recording.events.map((e) => e.data).join(), 'hi\r\n');
  });

  test('the header of a recording has the idle limit (2 s, --idle-limit, '
      'none at 0), the command, and the title, the command when no '
      '--title', () async {
    final temp = await Directory.systemTemp.createTemp('twk_record_');
    addTearDown(() => temp.delete(recursive: true));
    final cast = p.join(temp.path, 's.cast');

    final result = await twkHere(['record', '--out=$cast', 'echo', 'hi']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final header = Cast.read(cast).header;
    expect(
      (header.idleTimeLimit, header.command, header.title),
      (2.0, 'echo hi', 'echo hi'),
    );

    final titled = await twkHere([
      'record',
      '--out=$cast',
      '--idle-limit=0.5',
      '--title=greeting',
      '--keys',
      '--',
      'echo',
      'a b',
    ]);
    expect(titled.exitCode, 0, reason: '${titled.stderr}');
    final again = Cast.read(cast).header;
    expect(
      (again.idleTimeLimit, again.command, again.title),
      (0.5, "echo 'a b'", 'greeting'),
    );

    final unlimited = await twkHere([
      'record',
      '--out=$cast',
      '--idle-limit=0',
      'true',
    ]);
    expect(unlimited.exitCode, 0, reason: '${unlimited.stderr}');
    expect(Cast.read(cast).header.idleTimeLimit, isNull);
  });

  test('twk play without a terminal writes what the program wrote to '
      'stdout, a pause divided by --speed and cut to the idle limit: the '
      "recording's, --idle-limit's, or none with 0", () async {
    final temp = await Directory.systemTemp.createTemp('twk_play_');
    addTearDown(() => temp.delete(recursive: true));
    final cast = p.join(temp.path, 's.cast');
    // a pause of a minute, which a test gets through only cut or sped up
    File(cast).writeAsStringSync(
      '{"version": 2, "width": 40, "height": 6, "idle_time_limit": 0.05}\n'
      '[0.0, "o", "first "]\n'
      '[0.1, "i", "typed"]\n'
      '[60.0, "o", "second"]\n',
    );
    // the time it took to play, at most 20 s. Real time on purpose: the
    // pauses of playback are what is measured
    Future<Duration> play(List<String> options) async {
      final took = Stopwatch()..start();
      final result = await twkHere([
        'play',
        ...options,
        cast,
      ]).timeout(const Duration(seconds: 20));
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'first second');
      return took.elapsed;
    }

    // the recording's limit: 0.05 s
    await play([]);
    // --idle-limit's: 1 s
    expect(
      await play(['--idle-limit=1']),
      greaterThanOrEqualTo(const Duration(seconds: 1)),
    );
    // none: the minute, by 100
    expect(
      await play(['--idle-limit=0', '--speed=100']),
      greaterThanOrEqualTo(const Duration(milliseconds: 600)),
    );
  });

  test('twk play with no recording, a bad speed or idle limit exits with '
      '$usageExitCode, with one it cannot read or that is no asciicast v2 '
      'with 1', () async {
    final temp = await Directory.systemTemp.createTemp('twk_play_');
    addTearDown(() => temp.delete(recursive: true));
    final cast = p.join(temp.path, 's.cast');

    final none = await twkHere(['play']);
    expect(none.exitCode, usageExitCode);
    expect(none.stderr, contains('One recording to play.'));

    final speed = await twkHere(['play', '--speed=0', cast]);
    expect(speed.exitCode, usageExitCode);
    expect(speed.stderr, contains('--speed takes a number above 0.'));

    final limit = await twkHere(['play', '--idle-limit=-1', cast]);
    expect(limit.exitCode, usageExitCode);
    expect(
      limit.stderr,
      contains('--idle-limit takes a number of seconds, 0 or more.'),
    );

    final missing = await twkHere(['play', cast]);
    expect(missing.exitCode, 1);
    expect(missing.stderr, startsWith('twk play: cannot read $cast: '));

    File(cast).writeAsStringSync('{"version": 1, "width": 80, "height": 24}');
    final old = await twkHere(['play', cast]);
    expect(old.exitCode, 1);
    expect(
      old.stderr,
      'twk play: $cast: asciicast version 1; this reads version 2\n',
    );
  });

  test('twk tape with no tape exits with $usageExitCode, with one it '
      'cannot read or that is wrong with 1, saying where', () async {
    final temp = await Directory.systemTemp.createTemp('twk_tape_');
    addTearDown(() => temp.delete(recursive: true));
    final tape = p.join(temp.path, 'demo.tape');

    final none = await twkHere(['tape']);
    expect(none.exitCode, usageExitCode);
    expect(none.stderr, contains('One tape to run.'));

    final missing = await twkHere(['tape', tape]);
    expect(missing.exitCode, 1);
    expect(missing.stderr, startsWith('twk tape: cannot read $tape: '));

    File(tape).writeAsStringSync('Output demo.svg\nTipe "hi"\n');
    final wrong = await twkHere(['tape', tape]);
    expect(wrong.exitCode, 1);
    expect(wrong.stderr, 'twk tape: $tape:2: no statement "Tipe"\n');

    File(tape).writeAsStringSync('Run no-such-program\n');
    final program = await twkHere(['tape', tape]);
    expect(program.exitCode, 127);
    expect(
      program.stderr,
      startsWith('twk tape: cannot run no-such-program: '),
    );
  });

  test('an unknown subcommand exits with $usageExitCode', () async {
    final result = await twkHere(['frobnicate']);

    expect(result.exitCode, usageExitCode);
    expect(result.stderr, contains('Could not find a command named'));
  });
}
