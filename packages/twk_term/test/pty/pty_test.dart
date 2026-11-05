// Real programs run in a pseudo-terminal: what they print, what they read,
// their terminal (controlling, in the foreground, its size and modes) and
// their end. Every program a test starts is killed and waited for in its
// tear-down.
@Tags(['process'])
@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_term/src/pty/pty.dart' show ptyEnvironment;
import 'package:twk_term/twk_term.dart';
import 'package:twk_test/twk_test.dart'
    show compiledProgram, runProcess, startProcess, waitFor, waitUntil;

/// The exit code of [pty]'s program ([waitFor], which [Run] has one of its own
/// beside).
Future<int?> _exit(Pty pty, {String Function()? state}) =>
    waitFor(pty.exitCode, 'the program to end', state: state);

/// A descriptor without FD_CLOEXEC, as native code may leave one.
@Native<Int Function(Int)>(isLeaf: true)
external int dup(int fd);

@Native<Int Function(Int)>(isLeaf: true)
external int close(int fd);

/// The exit code [code], or null where the VM may have taken it.
Matcher exits(int code) =>
    Pty.tellsExitCode ? equals(code) : anyOf(code, isNull);

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
      await _exit(pty);
      pty.close();
      await subscription.cancel();
    });
  }

  final Pty pty;
  late final StreamSubscription<Uint8List> subscription;
  final bytes = <int>[];
  var outputDone = false;
  var exited = false;

  // what [type] handed the terminal: the writes and their bytes
  var _typed = 0;
  var _typedBytes = 0;

  /// Hands [input] to the program, counted for a failure's report.
  void type(List<int> input) {
    _typed++;
    _typedBytes += input.length;
    pty.write(input);
  }

  String get text => utf8.decode(bytes, allowMalformed: true);

  /// Waits until the output has [s] after [from].
  Future<void> waitFor(String s, {int from = 0}) =>
      until(() => text.indexOf(s, from) >= 0, 'output with "$s"');

  /// The exit code once the program ended and the output did.
  Future<int?> ended() async {
    final code = await _exit(pty, state: _state);
    await until(() => outputDone, 'the output to end');
    return code;
  }

  /// Waits until [done], failing after 10 s with what was waited for, the
  /// output so far, what [type] handed the terminal, the output the master
  /// holds unread (`Pty.debugUnreadOutput`), and the program's
  /// processes as they were then ([_processes]): where a wait that has no
  /// cause found yet stopped.
  Future<void> until(bool Function() done, String what) =>
      waitUntil(done, what, state: _state);

  String _state() =>
      'output: ${jsonEncode(text)}; '
      'typed: $_typed writes, $_typedBytes bytes; '
      'unread on the master: ${pty.debugUnreadOutput} bytes; '
      'processes:\n${_processes()}';

  /// The program and the processes under it, a line each (`ps`: pid,
  /// parent, group, the terminal's foreground group, state, what it
  /// waits in, name), or why they could not be listed.
  String _processes() {
    try {
      final ps = Process.runSync('ps', [
        '-A',
        '-o',
        'pid=,ppid=,pgid=,tpgid=,stat=,wchan=,comm=',
      ]);
      final rows = [
        for (final line in (ps.stdout as String).split('\n'))
          if (line.trim().split(RegExp(r'\s+')) case [
            final pid,
            final ppid,
            ...,
          ])
            (int.tryParse(pid), int.tryParse(ppid), line.trim()),
      ];
      final ours = {pty.pid};
      for (var grew = true; grew;) {
        grew = false;
        for (final (pid, ppid, _) in rows) {
          if (pid != null && ours.contains(ppid) && ours.add(pid)) {
            grew = true;
          }
        }
      }
      return [
        '  pid ppid pgid tpgid stat wchan comm',
        for (final (pid, _, line) in rows)
          if (ours.contains(pid)) '  $line',
      ].join('\n');
    } on Object catch (e) {
      return '  not listed: $e';
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
  test('tells the code of programs that end at once while a Process runs, '
      'which reaps them', () async {
    // a Process of the test's own, so that the VM waits for any child
    final reaper = await Process.start('sleep', ['30']);
    addTearDown(reaper.kill);
    final codes = await Future.wait([
      for (var i = 0; i < 64; i++) sh('exit ${i % 7 + 1}').ended(),
    ]);
    expect(codes, [
      for (var i = 0; i < 64; i++) exits(i % 7 + 1),
    ]);
  });

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
      // each line ended by the terminal's CR LF, or by nothing where tty
      // writes the name alone (uutils', Ubuntu 26.04's coreutils)
      expect(run.text.replaceAll('\r\n', ''), '$name$name$name');
      // /dev/tty opens only in a process with a controlling terminal; not
      // in a shell, which would make the terminal its own. dd reads nothing
      // of it (BSD's head takes no -c 0) and says how much it copied.
      final dd = Run('dd', ['if=/dev/tty', 'of=/dev/null', 'count=0']);
      expect(await dd.ended(), exits(0));
      expect(dd.text, isNot(contains('dd:')));
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
    // The job says that it runs: bash makes a foreground job the terminal's
    // foreground group in its child, before the exec, so once it has printed
    // the one Ctrl+Z reaches it. None is typed again: each signal character
    // drops the output the terminal has not passed on yet (no NOFLSH), which
    // took bash's job line and prompt on a busy CI runner, 3 runs in 100,
    // when one was typed a millisecond until the prompt showed.
    run.pty.write(
      utf8.encode("sh -c 'echo started; read x; echo \"got \$x\"'\r"),
    );
    await run.waitFor('started\r\n');
    // the prompt is back once the job stopped (bash's own line saying so may
    // come later or not at all), and `jobs` lists it stopped
    var at = run.text.length;
    run.type([0x1a]);
    await run.until(() => run.text.contains(r'$ ', at), 'the job to stop');
    expect(run.text, isNot(contains('no job control')));
    at = run.text.length;
    run.pty.write(utf8.encode('jobs\r'));
    await run.waitFor('Stopped', from: at);
    await run.waitFor(r'$ ', from: run.text.indexOf('Stopped', at));
    at = run.text.length;
    run.pty.write(utf8.encode('fg\r'));
    // fg names the job, then gives it the terminal and continues it; the
    // line typed waits for its read, which ends it
    await run.waitFor('got \$x"\'\r\n', from: at);
    at = run.text.length;
    run.type(utf8.encode('line\r'));
    await run.waitFor('got line\r\n', from: at);
    await run.until(
      () => run.text.contains(r'$ ', run.text.indexOf('got line', at)),
      'the job to end',
    );
    run.pty.write(
      utf8.encode(
        // BSD's wc pads the count
        r'jobs; echo "jobs: $(jobs | wc -l | tr -d " ")"; exit 0'
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
      'COLORTERM=truecolor',
    });
  });

  test("the terminal this process runs in isn't the program's: its "
      'variables left out, those given kept', () {
    final env = ptyEnvironment(
      {
        'HOME': '/home/a',
        'TERM': 'xterm-kitty',
        'TERM_PROGRAM': 'Apple_Terminal',
        'TERM_PROGRAM_VERSION': '466',
        'LC_TERMINAL': 'iTerm2',
        'KITTY_WINDOW_ID': '1',
        'TMUX': '/tmp/t,1,0',
        'COLORTERM': '24bit',
      },
      {'TERM_PROGRAM': 'mine'},
    );
    expect(env, {
      'HOME': '/home/a',
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
      'TERM_PROGRAM': 'mine',
    });
  });

  test("CI isn't the program's: a twk app in the emulator would write plain "
      'text for a log; given, it is kept', () {
    final parent = {
      'HOME': '/home/a',
      'CI': 'true',
      'CONTINUOUS_INTEGRATION': 'true',
      'BUILD_NUMBER': '12',
      'RUN_ID': '3',
    };
    expect(ptyEnvironment(parent, null), {
      'HOME': '/home/a',
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
    });
    expect(ptyEnvironment(parent, {'CI': '1'}), containsPair('CI', '1'));
  });

  test('IUTF8: erasing takes a UTF-8 character whole', () async {
    // BSD's od puts two blanks between bytes
    final run = sh('head -n 1 | od -An -tx1 | tr -s " "');
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

  test('a program that ignores the hang-up is killed a second after '
      'close', () async {
    final run = sh('trap "" HUP; echo ready; while :; do sleep 0.05; done');
    await run.waitFor('ready\r\n');
    run.pty.close();
    expect(await run.ended(), exits(-ProcessSignal.sigkill.signalNumber));
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
      if (Platform.isLinux) {
        await run.until(() => run.outputDone, 'the output to end');
      } else {
        // macOS keeps a session's controlling terminal open for it, its
        // output going on while the leader runs
        await run.waitFor('bye\r\n');
      }
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
      expect(await _exit(run.pty), exits(0));
      expect(run.text, isNot(contains('late')));
      hold.deleteSync();
      expect(await run.ended(), exits(0));
      expect(run.text, 'early\r\nlate\r\n');
    },
    // macOS revokes the controlling terminal of a session whose leader
    // ended: what it left running writes to it no more
    testOn: 'linux',
  );

  test('the modes the program left its terminal in, read at its end', () {
    // c_lflag: the fourth field, 32 bits on Linux and 64 on macOS
    int lflag(Uint8List termios) => Platform.isMacOS
        ? ByteData.sublistView(termios).getUint64(24, Endian.host)
        : ByteData.sublistView(termios).getUint32(12, Endian.host);
    final icanon = Platform.isMacOS ? 0x100 : 0x2;
    Future<Uint8List?> left(String script) async {
      final run = sh(script);
      expect(await run.ended(), exits(0));
      return run.pty.modesAtEnd;
    }

    return Future.wait([
      left('stty raw -echo').then((m) {
        expect(m, isNotNull);
        expect(lflag(m!) & icanon, 0);
      }),
      left('stty sane').then((m) {
        expect(m, isNotNull);
        expect(lflag(m!) & icanon, icanon);
      }),
    ]);
  });

  test('feeds the emulator, which answers through it', () async {
    final term = TerminalEmulator(width: 40, height: 6);
    final run = sh(
      r'stty -echo -icanon; printf "\033[2J\033[Hhello\033[3;5H\033[6n"; '
      // BSD's od pads the row to 16 bytes and adds an empty one
      'head -c 6 | od -An -tx1 | tr -s " " | grep .; stty size',
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
    skip: Pty.tellsExitCode
        ? null
        : 'needs macOS or Linux 6.15 (PIDFD_INFO_EXIT)',
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

  test('SIGTSTP is caught only while the terminal is raw, and the stdout it '
      'shares with the shell stays blocking', () async {
    final app = await compiledProgram(
      'test/pty/stop_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
    final pty = Pty.start(Platform.resolvedExecutable, [app]);
    addTearDown(pty.close);
    final out = StringBuffer();
    final reading = pty.output.listen((b) => out.write(latin1.decode(b)));
    addTearDown(reading.cancel);
    await waitFor(pty.exitCode, 'the end of the app');
    await waitUntil(() => '$out'.contains(']'), 'what it says');
    expect('$out', contains('[false,true,false,true,false,true]'));
  }, testOn: 'linux');

  test('a SIGHUP the process was started ignoring stays ignored', () async {
    final app = await compiledProgram(
      'test/pty/stalled_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    );
    final dir = Directory.systemTemp.createTempSync('nohup');
    addTearDown(() => dir.deleteSync(recursive: true));
    final writing = File('${dir.path}/writing');
    final pty = Pty.start('/bin/sh', [
      '-c',
      r'trap "" HUP; exec "$0" "$@"',
      Platform.resolvedExecutable,
      app,
      writing.path,
    ]);
    addTearDown(pty.close);
    final out = StringBuffer();
    final opened = Completer<void>();
    final reading = pty.output.listen((bytes) {
      out.write(latin1.decode(bytes));
      if (!opened.isCompleted && '$out'.contains('opened')) {
        opened.complete();
      }
    });
    addTearDown(reading.cancel);
    await waitFor(opened.future, 'the terminal to open');
    pty
      ..kill(ProcessSignal.sighup)
      ..write(const [0x67]);
    await waitUntil(writing.existsSync, 'the app to take the key after it');
    pty.kill();
    expect(await waitFor(pty.exitCode, 'the end of the app'), 143);
  });

  group('an app on a terminal that stops reading', () {
    late String app;
    setUpAll(
      () async => app = await compiledProgram(
        'test/pty/stalled_app.dart',
        packages: (await Isolate.packageConfig)!.toFilePath(),
        cache: '.dart_tool/twk_test/programs',
      ),
    );

    for (final (name, signal, code) in [
      ('SIGTERM', ProcessSignal.sigterm, 143),
      ('SIGHUP', ProcessSignal.sighup, 129),
      ('SIGINT', ProcessSignal.sigint, 0),
    ]) {
      test('ends on $name, the output blocking nothing', () async {
        final dir = Directory.systemTemp.createTempSync('stalled');
        addTearDown(() => dir.deleteSync(recursive: true));
        final writing = File('${dir.path}/writing');
        final pty = Pty.start(
          Platform.resolvedExecutable,
          [app, writing.path],
          width: 120,
          height: 40,
        );
        addTearDown(pty.close);
        final out = StringBuffer();
        final opened = Completer<void>();
        final reading = pty.output.listen((bytes) {
          out.write(latin1.decode(bytes));
          if (!opened.isCompleted && '$out'.contains('opened')) {
            opened.complete();
          }
        });
        addTearDown(reading.cancel);
        await waitFor(opened.future, 'the terminal to open');
        reading.pause();
        // a megabyte: the app has far more to write than the terminal holds
        pty.write(const [0x67]);
        await waitUntil(writing.existsSync, 'the app to start writing');
        pty.kill(signal);
        expect(await waitFor(pty.exitCode, 'the end of the app'), code);
      });
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
