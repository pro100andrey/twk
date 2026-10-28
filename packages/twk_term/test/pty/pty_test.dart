// Real programs run in a pseudo-terminal: what they print, what they read,
// their terminal (controlling, in the foreground, its size and modes) and
// their end. Every program a test starts is killed and waited for in its
// tear-down.
@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_term/twk_term.dart';
import 'package:twk_test/twk_test.dart'
    show runProcess, startProcess, waitUntil;

const _timeout = Duration(seconds: 10);

/// A descriptor without FD_CLOEXEC, as native code may leave one.
@Native<Int Function(Int)>(isLeaf: true)
external int dup(int fd);

@Native<Int Function(Int)>(isLeaf: true)
external int close(int fd);

/// Linux 6.15 and later tell how a program ended also when the VM waited
/// for it first, which it does for any child while a `Process` runs (the
/// test runner's compiler does throughout).
final bool _endsKnown = () {
  final version = RegExp(
    r'(\d+)\.(\d+)',
  ).firstMatch(Platform.operatingSystemVersion);
  if (!Platform.isLinux || version == null) {
    return false;
  }
  final [major, minor] = [
    for (final i in [1, 2]) int.parse(version[i]!),
  ];
  return major > 6 || major == 6 && minor >= 15;
}();

/// The exit code [code], or null where the VM may have taken it.
Matcher exits(int code) => _endsKnown ? equals(code) : anyOf(code, isNull);

/// A [Pty] whose output is gathered.
final class Run {
  Run(
    String executable,
    List<String> arguments, {
    int width = 80,
    int height = 24,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) : pty = Pty.start(
         executable,
         arguments,
         width: width,
         height: height,
         workingDirectory: workingDirectory,
         environment: environment,
         includeParentEnvironment: includeParentEnvironment,
       ) {
    subscription = pty.output.listen(
      bytes.addAll,
      onDone: () => outputDone = true,
    );
    unawaited(pty.exitCode.then((code) => exited = true));
    addTearDown(() async {
      pty.kill(ProcessSignal.sigkill);
      await pty.exitCode.timeout(_timeout);
      pty.close();
      await subscription.cancel();
    });
  }

  final Pty pty;
  late final StreamSubscription<Uint8List> subscription;
  final bytes = <int>[];
  var outputDone = false;
  var exited = false;

  String get text => utf8.decode(bytes, allowMalformed: true);

  /// Waits until the output has [s] after [from].
  Future<void> waitFor(String s, {int from = 0}) =>
      until(() => text.indexOf(s, from) >= 0, 'output with "$s"');

  /// The exit code once the program ended and the output did.
  Future<int?> ended() async {
    final code = await pty.exitCode.timeout(_timeout);
    await until(() => outputDone, 'the output to end');
    return code;
  }

  /// Waits until [done], failing with what was waited for and the output
  /// so far after 10 s.
  Future<void> until(bool Function() done, String what) async {
    try {
      await waitUntil(done, what);
    } on TestFailure catch (e) {
      fail('${e.message}; output: ${jsonEncode(text)}');
    }
  }
}

/// [script] run by `sh -c`.
Run sh(
  String script, {
  int width = 80,
  int height = 24,
  String? workingDirectory,
}) => Run(
  'sh',
  ['-c', script],
  width: width,
  height: height,
  workingDirectory: workingDirectory,
);

void main() {
  test('prints through the terminal, which adds CR, and exits', () async {
    final run = sh('echo hello; exit 3');
    expect(await run.ended(), exits(3));
    expect(run.text, 'hello\r\n');
  });

  test(
    'stdin, stdout and stderr are the terminal, the controlling one',
    () async {
      final run = sh('tty; tty <&1; tty <&2');
      expect(await run.ended(), exits(0));
      final name = run.pty.ttyName;
      expect(name, startsWith('/dev/'));
      expect(run.text, '$name\r\n$name\r\n$name\r\n');
      // /dev/tty opens only in a process with a controlling terminal; not
      // in a shell, which would make the terminal its own.
      final head = Run('head', ['-c', '0', '/dev/tty']);
      expect(await head.ended(), exits(0));
      expect(head.text, isEmpty);
    },
  );

  test('Ctrl+C is SIGINT to the foreground process group', () async {
    final run = Run('cat', []);
    run.pty.write(utf8.encode('ping\r'));
    await run.waitFor('ping\r\nping\r\n'); // echoed, then cat's
    run.pty.write([0x03]);
    expect(await run.ended(), exits(-ProcessSignal.sigint.signalNumber));
  });

  test('a shell runs jobs: Ctrl+Z stops one, fg continues it', () async {
    final bash = ['/bin/bash', '/usr/bin/bash'].where(
      (path) => File(path).existsSync(),
    );
    if (bash.isEmpty) {
      markTestSkipped('no bash');
      return;
    }
    final run = Run(
      bash.first,
      ['--norc', '--noprofile', '-i'],
      environment: {'PS1': r'$ '},
    );
    await run.waitFor(r'$ ');
    run.pty.write(utf8.encode('echo started; sleep 30\r'));
    await run.waitFor('started\r\n');
    // Again until it is the job that gets it, not bash before the job runs.
    var at = run.text.length;
    await run.until(() {
      run.pty.write([0x1a]);
      return run.text.contains('Stopped', at);
    }, 'the job to stop');
    expect(run.text, isNot(contains('no job control')));
    await run.waitFor(r'$ ', from: run.text.indexOf('Stopped'));
    at = run.text.length;
    run.pty.write(utf8.encode('fg\r'));
    await run.waitFor('sleep 30\r\n', from: at);
    at = run.text.length;
    await run.until(() {
      run.pty.write([0x03]);
      return run.text.contains(r'$ ', at);
    }, 'the job to end');
    run.pty.write(
      utf8.encode(
        r'jobs; echo "jobs: $(jobs | wc -l)"; exit 0'
        '\r',
      ),
    );
    expect(await run.ended(), exits(0));
    expect(run.text, contains('jobs: 0'));
  });

  test('resize sets the size the program reads and sends SIGWINCH', () async {
    final run = sh(
      'trap "stty size; tput cols" WINCH; stty size; tput cols; '
      'while :; do sleep 0.05; done',
    );
    await run.waitFor('24 80\r\n80\r\n');
    final at = run.text.length;
    run.pty.resize(100, 30);
    expect((run.pty.width, run.pty.height), (100, 30));
    await run.waitFor('30 100\r\n100\r\n', from: at);
    expect(run.pty.kill(), isTrue);
    expect(await run.ended(), exits(-ProcessSignal.sigterm.signalNumber));
    expect(run.pty.kill(), isFalse);
  });

  test('the program starts with every signal at its default', () async {
    // SIGPIPE, which the VM ignores, ends `yes` quietly.
    final run = sh(
      'yes | head -n 1; '
      'if [ -r /proc/self/status ]; then grep -E "^Sig(Ign|Blk)" /proc/self/status; fi',
    );
    expect(await run.ended(), exits(0));
    expect(run.text, isNot(contains('Broken pipe')));
    final lines = const LineSplitter().convert(run.text);
    expect(lines.first, 'y');
    if (Platform.isLinux) {
      expect(lines.skip(1), [
        'SigBlk:\t0000000000000000',
        'SigIgn:\t0000000000000000',
      ]);
    }
  });

  test('the environment, TERM and the working directory', () async {
    final dir = Directory.systemTemp.createTempSync('pty_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = dir.resolveSymbolicLinksSync();
    final inherited = Run(
      'sh',
      ['-c', r'pwd; echo "$TERM $FOO"'],
      workingDirectory: path,
      environment: {'FOO': 'bar'},
    );
    expect(await inherited.ended(), exits(0));
    expect(inherited.text, '$path\r\nxterm-256color bar\r\n');

    final own = Run(
      'env',
      [],
      includeParentEnvironment: false,
      environment: {'PATH': '/usr/bin:/bin', 'TERM': 'vt100'},
    );
    expect(await own.ended(), exits(0));
    expect(const LineSplitter().convert(own.text).toSet(), {
      'PATH=/usr/bin:/bin',
      'TERM=vt100',
    });
  });

  test('IUTF8: erasing takes a UTF-8 character whole', () async {
    final run = sh('head -n 1 | od -An -tx1');
    run.pty.write(utf8.encode('aé\x7fx\r'));
    expect(await run.ended(), exits(0));
    expect(run.text, contains(' 61 78 0a'));
  });

  test(
    'input the terminal does not take at once waits for the program',
    () async {
      final run = sh('stty raw -echo; echo ready; head -c 300000 | wc -c');
      await run.waitFor('ready');
      run.pty.write(Uint8List(300000)..fillRange(0, 300000, 0x61));
      expect(await run.ended(), exits(0));
      expect(run.text, contains('300000'));
    },
  );

  test('input written while earlier input waits follows it', () async {
    final run = sh('stty raw -echo; echo ready; head -c 300003 | tail -c 3');
    await run.waitFor('ready');
    run.pty
      ..write(Uint8List(300000)..fillRange(0, 300000, 0x61))
      ..write(utf8.encode('x'))
      ..write(utf8.encode('yz'));
    expect(await run.ended(), exits(0));
    expect(run.text, endsWith('xyz'));
  });

  test('output is read no faster than it is listened to', () async {
    final run = sh(r'head -c 4000000 /dev/zero | tr "\0" x; echo; echo end');
    run.subscription.pause();
    // Real time on purpose: that the program does not end while nobody
    // listens is an absence, which no event tells; half a second of it
    // ignore: twk_lints/wall_time_in_tests
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(run.exited, isFalse, reason: 'blocked writing to its terminal');
    run.subscription.resume();
    expect(await run.ended(), exits(0));
    expect(run.text, '${'x' * 4000000}\r\nend\r\n');
  });

  test('close hangs up: SIGHUP for the program, the output ends', () async {
    // A program that neither reads nor writes the terminal: one that does,
    // cat, may see EIO and exit before the kernel sends the hang-up's
    // SIGHUP, which a loaded machine shows.
    final run = sh('echo ready; while :; do sleep 0.05; done');
    await run.waitFor('ready\r\n');
    run.pty
      ..close()
      ..write(utf8.encode('dropped\r'));
    expect(await run.ended(), exits(-ProcessSignal.sighup.signalNumber));
    expect(run.text, 'ready\r\n');
  });

  test('a program that closed its terminal is not hung up before it ends: '
      'the output ends, the exit code is its own', () async {
    // What cat does at the end of its input, slowed down: every descriptor
    // of the terminal closed, then the exit. The terminal hung up as the
    // last was closed killed it with SIGHUP before it got there, which a
    // loaded machine showed with cat in `twk record` (exit 129 for 0).
    final run = sh('echo bye; exec 0<&- 1>&- 2>&-; sleep 0.3; exit 3');
    expect(await run.ended(), exits(3));
    expect(run.text, 'bye\r\n');
  });

  test(
    'close hangs up a program that closed its terminal and runs on',
    () async {
      final run = sh('echo bye; exec 0<&- 1>&- 2>&-; sleep 30');
      await run.until(() => run.outputDone, 'the output to end');
      run.pty.close();
      expect(await run.ended(), exits(-ProcessSignal.sighup.signalNumber));
    },
  );

  test(
    'the output goes on while what the program left running writes',
    () async {
      // The writer waits while hold is there: until the test saw the exit
      // or the tear-down removed the directory, 20 s at most. It ignores
      // the SIGHUP the shell's end sends to their process group from its
      // first instruction on, as the shell ignores it before starting it.
      final dir = Directory.systemTemp.createTempSync('pty_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final hold = File('${dir.path}/hold')..createSync();
      final run = sh(
        r'trap "" HUP; (i=0; while [ -e hold ] && [ $i -lt 400 ]; do '
        r'i=$((i + 1)); sleep 0.05; done; echo late) & echo early',
        workingDirectory: dir.path,
      );
      expect(await run.pty.exitCode.timeout(_timeout), exits(0));
      expect(run.text, isNot(contains('late')));
      hold.deleteSync();
      expect(await run.ended(), exits(0));
      expect(run.text, 'early\r\nlate\r\n');
    },
  );

  test('feeds the emulator, which answers through it', () async {
    final term = TerminalEmulator(width: 40, height: 6);
    final run = sh(
      r'stty -echo -icanon; printf "\033[2J\033[Hhello\033[3;5H\033[6n"; '
      'head -c 6 | od -An -tx1; stty size',
      width: 40,
      height: 6,
    );
    term.onOutput = run.pty.write;
    run.subscription.onData((bytes) {
      run.bytes.addAll(bytes);
      term.feed(bytes);
    });
    expect(await run.ended(), exits(0));
    // CSI 6 n answered CSI 3 ; 5 R.
    expect(
      [for (var y = 0; y < 4; y++) term.lineText(y).trim()],
      ['hello', '', '1b 5b 33 3b 35 52', '6 40'],
    );
  });

  test(
    'the exit code also when the VM waited for the program first',
    () async {
      // a process of dart:io's running, which has the VM reap children
      await startProcess('sleep', ['30']);
      for (var i = 0; i < 5; i++) {
        expect(await sh('exit 7').ended(), 7);
        expect(
          await sh(r'kill -TERM $$').ended(),
          -ProcessSignal.sigterm.signalNumber,
        );
      }
    },
    skip: _endsKnown ? null : 'needs Linux 6.15 (PIDFD_INFO_EXIT)',
  );

  test('no descriptor but 0, 1 and 2 is inherited', () async {
    final leaked = dup(2);
    addTearDown(() => close(leaked));
    // Not the last command, so the shell runs ls in a child and stays.
    final run = sh(r'ls -1 /proc/$$/fd; true');
    expect(await run.ended(), exits(0));
    expect(const LineSplitter().convert(run.text), ['0', '1', '2']);
  }, testOn: 'linux');

  test('an argument, a variable or a directory with a NUL is an '
      'ArgumentError', () {
    for (final start in [
      () => Pty.start('sh', ['-c', 'true\x00']),
      () => Pty.start('sh', const [], environment: {'A': 'b\x00'}),
      () => Pty.start('sh', const [], workingDirectory: '/\x00'),
    ]) {
      expect(start, throwsArgumentError);
    }
  });

  test('with no descriptor to spare, Pty.start throws a ProcessException '
      'naming the call that failed, and keeps none it opened', () async {
    // fixture's own process, as it takes every descriptor there is. Run
    // from source, not compiled once (compiledProgram): its compile is a
    // fraction of a second, in which the coverage tool's VM service, when
    // there is one, comes up and is connected to; a kernel's main takes the
    // descriptors while the tool connects, which then counts (4 runs in 40
    // under the tool's watch, none of 40 from source)
    final run = await runProcess('sh', [
      '-c',
      r'ulimit -n 256 && exec "$0" run test/pty/no_descriptors.dart',
      Platform.resolvedExecutable,
    ], group: true);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    Map<String, Object?> fails(int free, Matcher call) => {
      'free': free,
      'thrown': {
        'message': allOf(call, endsWith('(errno 24)')),
        'errorCode': 24,
      },
      'kept': isEmpty,
    };
    expect(
      [
        for (final line in LineSplitter.split('${run.stdout}'))
          jsonDecode(line),
      ],
      [
        fails(0, startsWith('pipe: ')),
        fails(2, startsWith('posix_openpt: ')),
        fails(3, matches(RegExp(r'^open /dev/pts/\d+: '))),
        fails(4, startsWith('posix_spawn /bin/true: ')),
      ],
    );
  }, testOn: 'linux');

  test('a program that is not there or a directory that is not', () {
    expect(
      () => Pty.start('no-such-program-anywhere', []),
      throwsA(isA<ProcessException>()),
    );
    expect(
      () => Pty.start('sh', ['-c', 'true'], workingDirectory: '/no/such/dir'),
      throwsA(
        isA<ProcessException>().having((e) => e.errorCode, 'errorCode', 2),
      ),
    );
  });
}
