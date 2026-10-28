// What startProcess and runProcess end, and what they never touch: the
// guard every signal goes through, and the tests of fixtures/processes.dart
// and fixtures/holder.dart run with `dart test` in processes of their own,
// alone, as two isolates of one runner, and in two runners at once, while
// processes these tests started themselves look on.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/src/process.dart';
import 'package:twk_test/twk_test.dart';

/// The state of process [pid] and when it started, null when there is
/// none.
({String state, int startTime})? stat(int pid) {
  final String text;
  try {
    text = File('/proc/$pid/stat').readAsStringSync();
  } on FileSystemException {
    return null;
  }
  final fields = text.substring(text.lastIndexOf(')') + 2).split(' ');
  return (state: fields[0], startTime: int.parse(fields[19]));
}

/// The group and session of process [pid], as `ps` lists them.
Future<(int, int)> groupOf(int pid) async {
  final ps = await Process.run('ps', ['-o', 'pgid=,sid=', '-p', '$pid']);
  final [group, session] = '${ps.stdout}'.trim().split(RegExp(r'\s+'));
  return (int.parse(group), int.parse(session));
}

/// The result of each test of a `dart test --reporter=json` run's output.
Map<String, String> results(String output) {
  final names = <int, String>{};
  final results = <String, String>{};
  for (final line in LineSplitter.split(output)) {
    if (!line.startsWith('{')) {
      continue;
    }
    switch (jsonDecode(line) as Map<String, Object?>) {
      case {
        'type': 'testStart',
        'test': {'id': final int id, 'name': final String name},
      }:
        names[id] = name;
      case {
        'type': 'testDone',
        'testID': final int id,
        'result': final String result,
        'hidden': false,
      }:
        results[names[id]!] = result;
    }
  }
  return results;
}

const _endings = {
  'returns, a process left running': 'success',
  'fails, a process left running': 'failure',
  'throws, a process left running': 'error',
  'times out, a process left running': 'error',
  'fails, a shell and what it started running': 'failure',
  'returns, the shell ended and what it started running': 'success',
  'times out in runProcess, a shell and what it started running': 'error',
};

const _held = {
  'what it started runs while the other suite ends its own': 'success',
};

void main() {
  group('the guard', () {
    final sent = <(int, ProcessSignal)>[];
    setUp(sent.clear);

    void signal(int target, {int started = 4242, int? group, int runner = 7}) =>
        guardedSignal(
          target,
          ProcessSignal.sigkill,
          started: started,
          group: group,
          runnerGroup: runner,
          send: (t, s) => sent.add((t, s)),
        );

    test('sends to the process started, and to the group made for it', () {
      signal(4242);
      signal(-4242, group: 4242);
      expect(sent, [
        (4242, ProcessSignal.sigkill),
        (-4242, ProcessSignal.sigkill),
      ]);
    });

    test('refuses 0, 1, -1 and any pid not the process started', () {
      for (final target in [0, 1, -1, 4243, 2, 7]) {
        expect(() => signal(target), throwsStateError, reason: '$target');
        expect(
          () => signal(target, group: 4242),
          throwsStateError,
          reason: '$target, with a group',
        );
      }
      expect(sent, isEmpty);
    });

    test('refuses a group when none was made, another group, and one not '
        'the own of the process started', () {
      expect(() => signal(-4242), throwsStateError);
      expect(() => signal(-4243, group: 4242), throwsStateError);
      expect(() => signal(-4243, group: 4243), throwsStateError);
      expect(() => signal(-1, group: 1, started: 1), throwsStateError);
      expect(() => signal(-7, group: 7, started: 7), throwsStateError);
      expect(sent, isEmpty);
    });

    test("refuses the runner's group, even as the own of the process", () {
      expect(() => signal(-4242, group: 4242, runner: 4242), throwsStateError);
      expect(() => signal(-4242, group: 4242, runner: 1), throwsStateError);
      expect(() => signal(-4242, group: 4242, runner: 0), throwsStateError);
      expect(sent, isEmpty);
    });

    test('refuses any target when the process started is not above 1', () {
      for (final started in [1, 0, -1]) {
        expect(() => signal(started, started: started), throwsStateError);
      }
      expect(sent, isEmpty);
    });
  });

  test("the runner's group is the one ps lists", () async {
    expect(runnerGroup, (await groupOf(pid)).$1);
    expect(runnerGroup, greaterThan(1));
  });

  test('a process started in a group leads it and a session, its pid '
      'their id, and gets what it is sent only', () async {
    final cat = await startProcess('cat', [], group: true);
    expect(await groupOf(cat.pid), (cat.pid, cat.pid));
    expect(cat.pid, isNot(runnerGroup));
    cat.stdin.writeln('said');
    await cat.stdin.close();
    expect(await cat.stdout.transform(utf8.decoder).join(), 'said\n');
    expect(await cat.exitCode, 0);
  });

  test('a process started alone is in the group of the runner', () async {
    final cat = await startProcess('cat', []);
    expect((await groupOf(cat.pid)).$1, runnerGroup);
  });

  test('runProcess is Process.run: exit code, output, as text or bytes; a '
      'group too', () async {
    final text = await runProcess('sh', [
      '-c',
      'echo out; echo err >&2; exit 3',
    ]);
    expect((text.exitCode, text.stdout, text.stderr), (3, 'out\n', 'err\n'));
    final bytes = await runProcess(
      'printf',
      ['a'],
      stdoutEncoding: null,
      group: true,
    );
    expect(bytes.stdout, [0x61]);
  });

  group('run in processes of their own', () {
    final dir = Directory.systemTemp.createTempSync('twk_process_test');
    // processes these tests start themselves, outside startProcess: in
    // this runner's group, and in a session of their own
    late Process inGroup;
    late Process inSession;
    setUpAll(() async {
      inGroup = await Process.start('sleep', ['300']);
      inSession = await Process.start('setsid', ['sleep', '300']);
    });
    tearDownAll(() async {
      inGroup.kill(ProcessSignal.sigkill);
      inSession.kill(ProcessSignal.sigkill);
      await waitFor(inGroup.exitCode, 'the sleep of this runner to end');
      await waitFor(inSession.exitCode, 'the sleep of its session to end');
      dir.deleteSync(recursive: true);
    });

    var runs = 0;

    /// The files a run reads its environment from.
    ({String log, String held, String done}) files() {
      final run = Directory('${dir.path}/${runs++}')..createSync();
      return (
        log: '${run.path}/log',
        held: '${run.path}/held',
        done: '${run.path}/done',
      );
    }

    /// `dart test` of [suites] with [files], and the result of each test.
    Future<Map<String, String>> dartTest(
      List<String> suites,
      ({String log, String held, String done}) files, {
      List<String> options = const [],
    }) async {
      final run = await runProcess(
        Platform.resolvedExecutable,
        ['test', '--reporter=json', ...options, ...suites],
        environment: {
          'TWK_PROCESS_LOG': files.log,
          'TWK_HOLDER_LOG': files.held,
          'TWK_PROCESS_DONE': files.done,
        },
        group: true,
      );
      return results('${run.stdout}');
    }

    /// Expects every process in [log] gone (or a pid used again since).
    Future<void> gone(String log, {required int count}) async {
      final lines = File(log).readAsLinesSync();
      expect(lines, hasLength(count), reason: 'the processes of $log');
      for (final line in lines) {
        final [pid, startTime] = line.split(' ').map(int.parse).toList();
        await waitUntil(() {
          final now = stat(pid);
          return now == null || now.startTime != startTime || now.state == 'Z';
        }, 'process $pid to be gone');
      }
    }

    /// Expects the processes these tests started themselves running.
    void survived() {
      for (final p in [inGroup, inSession]) {
        expect(
          stat(p.pid)?.state,
          isNot(anyOf(isNull, 'Z')),
          reason: '${p.pid}',
        );
      }
    }

    test('what a test started ends with it, however it ends', () async {
      final f = files();
      expect(
        await dartTest(['test/fixtures/processes.dart'], f),
        {..._endings},
      );
      await gone(f.log, count: 9);
      survived();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'two suites in two isolates of one runner end their own only',
      () async {
        final f = files();
        expect(
          await dartTest(
            ['test/fixtures/holder.dart', 'test/fixtures/processes.dart'],
            f,
            options: ['--concurrency=2'],
          ),
          {
            ..._endings,
            ..._held,
          },
        );
        await gone(f.log, count: 9);
        await gone(f.held, count: 3);
        survived();
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test('two runners at once end their own only', () async {
      final f = files();
      final (held, ended) = await (
        dartTest(['test/fixtures/holder.dart'], f),
        dartTest(['test/fixtures/processes.dart'], f),
      ).wait;
      expect(held, {..._held});
      expect(ended, {
        ..._endings,
      });
      await gone(f.log, count: 9);
      await gone(f.held, count: 3);
      survived();
    }, timeout: const Timeout(Duration(minutes: 4)));
  });
}
