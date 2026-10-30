// Real programs in a TerminalView, each in a pseudo-terminal of its own:
// sh, less, nano and htop, each skipped where it is not installed, and
// small scripts that read the keys and the mouse raw. Every program is
// killed and waited for in its tear-down, and at the end none of the
// test's children is left.
@TestOn('linux || mac-os')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_term/twk_term.dart';
import 'package:twk_test/twk_test.dart';

const _timeout = Timeout(Duration(seconds: 30));

/// [executable] run in a session started at the view's size, or at once
/// at [width] x [height] where given, killed and waited for when the test
/// ends.
TerminalSession run(
  TwkTester t,
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  int? width,
  int? height,
}) {
  final session = t.clock.run(
    () => TerminalSession.start(
      executable,
      arguments,
      width: width,
      height: height,
      environment: {'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8', ...?environment},
    ),
  );
  addTearDown(() async {
    final pty = session.pty;
    if (pty == null) {
      return;
    }
    _started.add(pty.pid);
    pty
      ..kill(ProcessSignal.sigkill)
      ..close();
    await waitUntil(
      () => !_alive(pty.pid),
      'program ${pty.pid} to be reaped',
      timeout: const Duration(seconds: 5),
    );
  });
  return session;
}

/// The programs the tests started.
final _started = <int>{};

/// Whether process [pid] is there, a zombie not reaped too; not for a pid
/// that is not positive, a program that ended before its id was read.
bool _alive(int pid) =>
    pid > 0 &&
    (File('/proc/$pid/stat').existsSync() ||
        (!Platform.isLinux && Process.killPid(pid, ProcessSignal.sigcont)));

/// Why a test of [program] is skipped: it is not on the PATH; null where it
/// is.
String? _missing(String program) =>
    Process.runSync('sh', ['-c', 'command -v $program']).exitCode == 0
    ? null
    : '$program is not installed';

/// Pumps until [done] holds, the program running in real time meanwhile;
/// fails with the screen after 10 s.
Future<void> until(
  TwkTester t,
  bool Function() done, {
  required String reason,
}) async {
  await t.pump();
  try {
    await waitUntil(done, reason, between: t.pump);
  } on TestFailure catch (e) {
    fail('${e.message}; the screen:\n${t.lines.join('\n')}');
  }
}

/// Until a row of the screen contains [text].
Future<void> showing(TwkTester t, String text) =>
    until(t, () => t.lines.any((l) => l.contains(text)), reason: '"$text"');

/// Until the shell's prompt, `$`, is the last row with text: its line
/// editor reads the keys again. What is typed before goes to what ran
/// before it, or to the shell between the two, which may drop it.
Future<void> prompt(TwkTester t) => until(
  t,
  () => t.lines.lastWhere((l) => l.isNotEmpty, orElse: () => '') == r'$',
  reason: 'the prompt',
);

/// Whether [command] holds the terminal of [shell], which started it: its
/// process group is the terminal's foreground one, the group Ctrl+C sends
/// SIGINT to. Read from /proc on Linux, as running ps there would have the
/// VM wait for any child, the programs of other tests too.
bool holds(int shell, String command) {
  if (!Platform.isLinux) {
    String ps(String field, String pid) =>
        (Process.runSync('ps', ['-o', '$field=', '-p', pid]).stdout as String)
            .trim();
    final group = ps('tpgid', '$shell');
    return group != '$shell' && ps('comm', group).split('/').last == command;
  }
  try {
    final stat = File('/proc/$shell/stat').readAsStringSync();
    // tpgid, the sixth field after the name in parentheses
    final group = stat.substring(stat.lastIndexOf(')') + 2).split(' ')[5];
    return group != '$shell' &&
        File('/proc/$group/comm').readAsStringSync().trim() == command;
  } on FileSystemException {
    return false;
  }
}

/// The hex of the bytes a raw script read, as `od -An -tx1` prints them.
Future<void> read(TwkTester t, String hex) => until(
  t,
  () => t.lines.join(' ').replaceAll(RegExp(' +'), ' ').contains(hex),
  reason: 'bytes $hex',
);

/// A script that sets [modes], reads [count] bytes raw and prints their
/// hex.
List<String> rawReader(String modes, int count) {
  final script =
      "printf '$modes'; stty raw -echo; printf 'ready\\r\\n'; "
      r'x=$(dd bs=1 count='
      '$count'
      // BSD's od pads the row with blanks, which wrap
      r' 2>/dev/null | od -An -v -tx1 | tr -s " "); stty sane; echo "$x"; '
      'sleep 29.9';
  return ['-c', script];
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('twk_term_view'));
  tearDown(() => dir.deleteSync(recursive: true));

  tearDownAll(() async {
    // the programs started here, and what their scripts ran, by commands
    // of their own (other test files of this process start programs too);
    // what a program left running goes on its hang-up, a moment later
    Future<List<String>> left() async {
      final ps = await runProcess('ps', ['-eo', 'pid=,comm=,args=']);
      return [
        for (final line in (ps.stdout as String).split('\n'))
          if (line.trim().split(RegExp(r'\s+')) case [
            final p,
            final command,
            ...final args,
          ])
            if (_started.contains(int.parse(p)) ||
                const {'sleep', 'od', 'dd', 'less', 'nano'}.contains(command) &&
                    (args.join(' ') == 'sleep 29.9' ||
                        args.join(' ') == 'od -An -v -tx1' ||
                        args.join(' ').startsWith('dd bs=1 count=') ||
                        args.any((a) => a.contains('twk_term_view'))))
              line.trim(),
      ];
    }

    var programs = const <String>[];
    try {
      await waitUntil(
        () async => (programs = await left()).isEmpty,
        'the programs the tests started to end',
        timeout: const Duration(seconds: 5),
      );
    } on TestFailure catch (e) {
      fail('${e.message}: ${programs.join('\n')}');
    }
  });

  testTwk('sh: a command, its size, Ctrl+C, a paste and exit', (t) async {
    final s = run(t, 'sh', const [], environment: {'PS1': r'$ ', 'ENV': ''});
    await t.pumpWidget(
      TerminalView(session: s, autofocus: true),
      size: (40, 10),
    );
    await prompt(t);
    await t.type('echo hi');
    await t.press('enter');
    await until(t, () => t.lines.contains('hi'), reason: 'hi');
    await prompt(t);
    await t.type('stty size');
    await t.press('enter');
    await showing(t, '10 40');
    await prompt(t);
    await t.resize(50, 12);
    await t.pump();
    await t.type('stty size');
    await t.press('enter');
    await showing(t, '12 50');
    await prompt(t);
    await t.type('sleep 20');
    await t.press('enter');
    // Ctrl+C before sleep has the terminal interrupts the shell instead,
    // which drops input it has not read: the line, a key typed after
    await until(
      t,
      () => holds(s.pty!.pid, 'sleep'),
      reason: 'sleep in the foreground',
    );
    await t.press('ctrl+c');
    await prompt(t);
    await t.type('echo back');
    await t.press('enter');
    await until(t, () => t.lines.contains('back'), reason: 'back');
    // bracketed paste, off while a command runs, is on again at the prompt
    await prompt(t);
    await t.paste('echo pasted');
    await t.press('enter');
    await until(t, () => t.lines.contains('pasted'), reason: 'pasted');
    await prompt(t);
    await t.type('exit 3');
    await t.press('enter');
    await until(t, () => s.ended, reason: 'the end of sh');
    int? code;
    var told = false;
    unawaited(
      s.exitCode.then((c) {
        code = c;
        told = true;
      }),
    );
    await until(t, () => told, reason: 'the exit code');
    // without a pidfd (macOS) the VM, which waits for any child while a
    // Process runs (holds' ps here), may take it first ([Pty.exitCode])
    expect(code, Platform.isLinux ? 3 : anyOf(3, isNull));
  }, timeout: _timeout);

  testTwk("a program started with the session sees the view's size", (
    t,
  ) async {
    final s = run(t, 'sh', ['-c', 'stty size; sleep 29.9']);
    await t.pumpWidget(TerminalView(session: s), size: (33, 7));
    await until(t, () => t.lines.first == '7 33', reason: 'its size');
  }, timeout: _timeout);

  testTwk('a program given a size starts at once, in a terminal of that '
      'size', (t) async {
    final s = run(
      t,
      'sh',
      ['-c', 'stty size; sleep 29.9'],
      width: 50,
      height: 7,
    );
    expect(s.pty, isNotNull, reason: 'started before any view');
    expect((s.pty!.width, s.pty!.height), (50, 7));
    await t.pumpWidget(TerminalView(session: s), size: (50, 7));
    await until(t, () => t.lines.first == '7 50', reason: 'its size');
  }, timeout: _timeout);

  testTwk(
    'less: pages, cursor keys, the wheel, a search and q',
    (t) async {
      final file = File(
        '${dir.path}/lines.txt',
      )..writeAsStringSync([for (var i = 1; i <= 100; i++) 'line $i\n'].join());
      final s = run(
        t,
        'less',
        [file.path],
        environment: {'LESS': '', 'LESSHISTFILE': '-'},
      );
      await t.pumpWidget(
        TerminalView(session: s, autofocus: true),
        size: (30, 10),
      );
      await showing(t, 'line 9');
      expect(s.emulator.alternateScreen, isTrue);
      expect(t.lines.first, 'line 1');
      await t.press('space');
      await until(t, () => t.lines.first == 'line 10', reason: 'a page on');
      // less asks for application cursor keys (smkx)
      expect(s.emulator.mode(TerminalMode.cursorKeys), isTrue);
      await t.press('down');
      await until(t, () => t.lines.first == 'line 11', reason: 'a line on');
      await t.mouse(MouseKind.wheelDown, 3, 3);
      await until(t, () => t.lines.first == 'line 14', reason: 'three on');
      await t.type('/line 50');
      await t.press('enter');
      await until(t, () => t.lines.first == 'line 50', reason: 'the search');
      await t.type('q');
      await until(t, () => s.ended, reason: 'the end of less');
      expect(s.emulator.alternateScreen, isFalse);
    },
    timeout: _timeout,
    skip: _missing('less'),
  );

  testTwk(
    'nano: types, saves with Ctrl+O and quits with Ctrl+X',
    (t) async {
      final file = File('${dir.path}/note.txt');
      final s = run(t, 'nano', ['--ignorercfiles', file.path]);
      await t.pumpWidget(
        TerminalView(session: s, autofocus: true),
        size: (60, 12),
      );
      await showing(t, 'note.txt');
      await t.type('hello');
      await t.press('enter');
      await t.type('world');
      await showing(t, 'world');
      await t.press('ctrl+o');
      // GNU nano's prompt, or pico's, which macOS has for nano
      await until(
        t,
        () => t.lines.any(
          (l) =>
              l.contains('Write to File') || l.contains('File Name to write'),
        ),
        reason: 'the prompt for the file name',
      );
      await t.press('enter');
      await showing(t, 'Wrote 2 lines');
      await t.press('ctrl+x');
      await until(t, () => s.ended, reason: 'the end of nano');
      expect(file.readAsStringSync(), 'hello\nworld\n');
    },
    timeout: _timeout,
    skip: _missing('nano'),
  );

  testTwk(
    'htop: its meters, the mouse it takes, and q',
    (t) async {
      final s = run(
        t,
        'htop',
        const [],
        environment: {'HOME': dir.path, 'XDG_CONFIG_HOME': dir.path},
      );
      await t.pumpWidget(
        TerminalView(session: s, autofocus: true),
        size: (100, 30),
      );
      await showing(t, 'Mem');
      await showing(t, 'PID');
      expect(s.emulator.alternateScreen, isTrue);
      expect(s.emulator.mouseProtocol, isNot(MouseProtocol.off));
      await t.type('q');
      await until(t, () => s.ended, reason: 'the end of htop');
    },
    timeout: _timeout,
    skip: _missing('htop'),
  );

  testTwk('a program reading raw gets the keys in its modes', (t) async {
    // application cursor keys, then the kitty protocol pushed over them
    final s = run(t, 'sh', rawReader(r'\033[?1h', 4));
    await t.pumpWidget(
      TerminalView(session: s, autofocus: true),
      size: (40, 5),
    );
    await showing(t, 'ready');
    await t.press('up escape');
    // Escape is ESC, which Up's bytes follow
    await read(t, '1b 4f 41 1b');
    final kitty = run(t, 'sh', rawReader(r'\033[?1h\033[>1u', 15));
    await t.pumpWidget(
      TerminalView(session: kitty, autofocus: true),
      size: (40, 5),
    );
    await showing(t, 'ready');
    await t.press('up escape ctrl+a');
    await read(t, '1b 5b 41 1b 5b 32 37 75 1b 5b 39 37 3b 35 75');
  }, timeout: _timeout);

  testTwk('a program that tracks the mouse reads its reports', (t) async {
    final s = run(t, 'sh', rawReader(r'\033[?1002h\033[?1006h', 28));
    await t.pumpWidget(
      Padding(
        padding: const EdgeInsets.only(left: 1, top: 1),
        child: TerminalView(session: s),
      ),
      size: (60, 6),
    );
    await showing(t, 'ready');
    await t.mouse(MouseKind.down, 3, 2);
    await t.mouse(MouseKind.drag, 4, 2);
    await t.mouse(MouseKind.up, 4, 2);
    // ESC [ < 0 ; 3 ; 2 M, ESC [ < 32 ; 4 ; 2 M, ESC [ < 0 ; 4 ; 2 m
    await read(
      t,
      '1b 5b 3c 30 3b 33 3b 32 4d 1b 5b 3c 33 32 3b 34 3b 32 4d '
      '1b 5b 3c 30 3b 34 3b 32 6d',
    );
  }, timeout: _timeout);
}
