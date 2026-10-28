// Output that takes plain text only (a pipe, a file, CI): how it is
// chosen, a Terminal over a PlainLink in memory, an app on one, and the
// demo run with its stdout piped.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/terminal/plain.dart';
import 'package:twk_core/src/terminal/terminal.dart' show openForProcess;
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart'
    show FakeClock, compiledProgram, runProcess;

import 'fake_link.dart';
import 'on_clock.dart';

/// Plain output in memory: everything written to it, in order.
final class Output {
  final _bytes = BytesBuilder();

  Uint8List get bytes => _bytes.toBytes();
  String get text => utf8.decode(bytes);

  /// A link writing here, with [env] and [input].
  PlainLink link([
    Map<String, String> env = const {},
    Stream<List<int>>? input,
  ]) => PlainLink(
    env,
    add: _bytes.add,
    flush: () async {},
    input: input,
  );
}

/// [link], keeping what it is told puts the terminal back if the process
/// goes away (what a `twk shell` would write then).
final class Told implements TerminalLink {
  Told(this.link);
  final FakeLink link;
  final told = <List<int>>[];

  @override
  void restoreWith(List<int> bytes) {
    if (bytes.isNotEmpty) {
      told.add(bytes);
    }
  }

  @override
  Map<String, String> get environment => link.environment;
  @override
  bool get windows => link.windows;
  @override
  int get columns => link.columns;
  @override
  int get lines => link.lines;
  @override
  int? get eraseChar => link.eraseChar;
  @override
  void enterRaw() => link.enterRaw();
  @override
  void restore() => link.restore();
  @override
  Stream<List<int>> get input => link.input;
  @override
  void add(List<int> bytes) => link.add(bytes);
  @override
  Future<void> flush() => link.flush();
  @override
  Stream<void> get resizes => link.resizes;
  @override
  Future<void> close() => link.close();
}

const _esc = 0x1b;

void main() {
  // The terminals and apps run on a clock of the test's: their frames are
  // timers that fire as it moves on ([settle]), what their input is given
  // comes in as it flushes.
  late FakeClock clock;
  setUp(() => clock = FakeClock());

  /// Moves the clock on by [ms]: the frames due by then run.
  Future<void> settle([int ms = 30]) =>
      clock.elapse(Duration(milliseconds: ms));

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('plain');
    // a project no twk shell serves
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('TWK_PLAIN asks for plain output with 1 or true, against it with 0 '
      'or false', () {
    bool? asked(String? value) => plainAsked({'TWK_PLAIN': ?value});
    expect(
      [
        for (final v in ['1', 'true', '0', 'false', '', 'yes', null]) asked(v),
      ],
      [true, true, false, false, null, null, null],
    );
  });

  test('CI is told by CI, CONTINUOUS_INTEGRATION, BUILD_NUMBER or RUN_ID, '
      'unless CI is 0 or false', () {
    expect(runsInCi({}), isFalse);
    for (final name in ['CI', 'CONTINUOUS_INTEGRATION', 'BUILD_NUMBER']) {
      expect(runsInCi({name: '1'}), isTrue, reason: name);
      expect(runsInCi({name: ''}), isFalse, reason: name);
      expect(runsInCi({name: 'false'}), isFalse, reason: name);
    }
    expect(runsInCi({'CI': 'true'}), isTrue);
    expect(runsInCi({'RUN_ID': '42'}), isTrue);
    expect(runsInCi({'RUN_ID': '0'}), isFalse);
    expect(runsInCi({'CI': '0', 'BUILD_NUMBER': '7'}), isFalse);
    expect(runsInCi({'CI': 'false', 'RUN_ID': '7'}), isFalse);
  });

  group('Terminal.open', () {
    const fast = Duration(milliseconds: 20);

    /// What [openForProcess] opens in a process of [env] whose own
    /// terminal is [own], with [plain] as TerminalOptions.plain; how
    /// [out], its plain output, was written to.
    Future<Terminal> open(
      Map<String, String> env, {
      FakeLink? own,
      bool? plain,
      bool outputIsTerminal = true,
      Output? out,
    }) async {
      final term = await openForProcess(
        own,
        (out ?? Output()).link,
        TerminalOptions(plain: plain, probeTimeout: fast),
        env: env,
        outputIsTerminal: outputIsTerminal,
        directory: dir.path,
      );
      addTearDown(term.close);
      return term;
    }

    test("opens the process's own terminal, plain or not, as the "
        'environment and the options say', () async {
      Future<bool> plain(Map<String, String> env, {bool? plain}) async {
        final own = FakeLink();
        final term = await open(env, own: own, plain: plain);
        expect(term.info.plain, own.rawChanges.isEmpty);
        expect(term.info.plain, own.output.isEmpty);
        return term.info.plain;
      }

      expect(await plain({}), isFalse);
      expect(await plain({'CI': 'true'}), isTrue);
      expect(await plain({'CI': 'true', 'TWK_PLAIN': '0'}), isFalse);
      expect(await plain({'TWK_PLAIN': '1'}), isTrue);
      expect(await plain({}, plain: true), isTrue);
      expect(await plain({'CI': 'true'}, plain: false), isFalse);
      expect(await plain({'TWK_PLAIN': '0'}, plain: true), isFalse);
      expect(await plain({'TWK_PLAIN': '1'}, plain: false), isTrue);
    });

    test('is plain where stdout is not a terminal, unless told not to; '
        'without stdin a terminal it is none', () async {
      final term = await open({}, outputIsTerminal: false);
      expect(term.info.plain, isTrue);
      final notTerminal = throwsA(
        isA<TerminalException>().having(
          (e) => e.message,
          'message',
          'not a terminal',
        ),
      );
      await expectLater(
        open({}, outputIsTerminal: false, plain: false),
        notTerminal,
      );
      await expectLater(
        open({'TWK_PLAIN': '0'}, outputIsTerminal: false),
        notTerminal,
      );
      await expectLater(open({}), notTerminal);
    });

    test("where stdout is not a terminal, gives way to the project's "
        'twk shell', () async {
      final link = FakeLink(columns: 33, lines: 7);
      final file = LocalAddress.fileOf('shell', dir.path);
      final (server, address) = await LocalAddress.bind(
        LocalAddress.directoryOf(dir.path),
        'shell',
      );
      address.write(file);
      final shell = TerminalShell.serve(link, server, address, file: file);
      addTearDown(shell.stop);
      final out = Output();
      final term = await open({}, outputIsTerminal: false, out: out);
      expect(term.info.plain, isFalse);
      expect((term.width, term.height), (33, 7));
      await term.close();
      expect(out.bytes, isEmpty);
    });
  });

  group('a terminal over plain output', () {
    test('asks nothing and writes nothing of its own, only what it is '
        'given, at the size COLUMNS and LINES give', () async {
      final out = Output();
      final term = await Terminal.overLink(
        out.link({'COLUMNS': '100', 'LINES': '30', 'TERM': 'xterm-kitty'}),
        const TerminalOptions(plain: true),
      );
      expect(term.info.plain, isTrue);
      expect((term.width, term.height), (100, 30));
      expect(term.info.colorMode, ColorMode.none);
      expect(term.info.alternateScreen, isTrue);
      expect(term.mouseTracking, MouseTracking.off);
      term
        ..setTitle('a title')
        ..copyToClipboard('copied')
        ..mouseTracking = MouseTracking.motion;
      expect(term.mouseTracking, MouseTracking.off);
      expect(out.bytes, isEmpty);
      term.write(utf8.encode('text\n'));
      await term.close();
      expect(out.text, 'text\n');
    });

    test("over a terminal's link (SSH without a pseudo-terminal) sets no "
        'console mode, and has its size', () async {
      final link = FakeLink();
      final term = await Terminal.overLink(
        link,
        const TerminalOptions(plain: true),
      );
      expect((term.width, term.height), (20, 4));
      term.write(utf8.encode('text\n'));
      await term.close();
      expect(link.rawChanges, isEmpty);
      expect(link.text, 'text\n');
      expect(link.closed, isTrue);
    });

    test('handed to another program and back, sets no console mode and '
        'writes nothing, nor tells its link anything to write', () async {
      final link = FakeLink();
      final told = Told(link);
      final term = await openForProcess(
        null,
        () => told,
        const TerminalOptions(plain: true, alternateScreen: false),
        env: const {},
        outputIsTerminal: false,
      );
      term.setTitle('a title');
      await term.suspend();
      await term.resume();
      await term.close();
      expect(link.rawChanges, isEmpty);
      expect(link.output.isEmpty, isTrue);
      expect(told.told, isEmpty);
    });

    test('is 80 x 24 without COLUMNS and LINES, or with ones that are no '
        'size', () {
      expect((Output().link().columns, Output().link().lines), (80, 24));
      final odd = Output().link({'COLUMNS': 'wide', 'LINES': '0'});
      expect((odd.columns, odd.lines), (80, 24));
    });

    test('reads keys from its input when it has one, none otherwise', () async {
      final keys = StreamController<List<int>>();
      addTearDown(keys.close);
      final term = await clock.open(
        Output().link({}, keys.stream),
        const TerminalOptions(plain: true),
      );
      final events = <InputEvent>[];
      term.events.listen(events.add);
      keys.add(utf8.encode('q'));
      await settle();
      expect(events, [isA<KeyEvent>().having((e) => e.char, 'char', 'q')]);
      await clock.runUntil(term.close);

      events.clear();
      final none = await clock.open(
        Output().link(),
        const TerminalOptions(plain: true),
      );
      none.events.listen(events.add);
      await settle();
      await clock.runUntil(none.close);
      expect(events, isEmpty);
    });
  });

  group('an app on plain output', () {
    Future<(TwkApp, Output)> start({
      bool inline = false,
      bool clearInlineOnExit = false,
      bool? framesInRow,
    }) async {
      final out = Output();
      final term = await clock.open(
        out.link({'COLUMNS': '20', 'LINES': '6'}),
        TerminalOptions(plain: true, alternateScreen: !inline),
      );
      final app = TwkApp(
        term,
        maxFps: 1000,
        clearInlineOnExit: clearInlineOnExit,
        framesInRow: framesInRow,
        clock: clock.stopwatch,
        environment: const {},
      );
      return (app, out);
    }

    /// [TwkApp.run] in the clock's zone.
    Future<void> run(TwkApp app, RenderObject root) =>
        clock.run(() => app.run(root, (_) {}));

    test('writes no frame as it comes, only the last as text when it ends: '
        'styles left out, a wide glyph once, no blanks at the end of a row '
        'or of the frame', () async {
      final (app, out) = await start(framesInRow: true);
      expect(app.framesInRow, isFalse);
      final t = app.screen.styles;
      final bold = t.pen(
        const Pen(fg: Color.rgb(255, 0, 0), attrs: Attr.bold),
      );
      final top = RenderText('first', bold);
      final root = RenderBox(
        pen: t.pen(const Pen(bg: Color.rgb(0, 0, 90))),
        child: RenderColumn(<(RenderObject, int?)>[
          (top, 1),
          (RenderText('', bold), 1),
          (RenderText('你好 wide', bold), 1),
          (RenderText('', bold), null),
        ]),
      );
      final done = run(app, root);
      await settle();
      top.text = 'last';
      await settle();
      expect(app.stats.frames, 2);
      expect(out.bytes, isEmpty);
      app.quit();
      await clock.elapseUntil(done);
      expect(out.bytes, isNot(contains(_esc)));
      expect(out.text, 'last\n\n你好 wide\n');
    });

    test('in the inline mode writes what is committed as it is, and the '
        "region's last frame when it ends", () async {
      final (app, out) = await start(inline: true);
      final status = RenderText('status', 0);
      app.commit(
        RenderParagraph([('committed  ', const Pen(attrs: Attr.bold))]),
      );
      final done = run(app, status);
      await settle();
      expect(out.text, 'committed\n');
      app.commit(
        RenderParagraph([('a line long enough to wrap', const Pen())]),
      );
      await settle();
      expect(out.text, 'committed\na line long enough\nto wrap\n');
      status.text = 'done';
      await settle();
      app.quit();
      await clock.elapseUntil(done);
      expect(out.bytes, isNot(contains(_esc)));
      expect(out.text, 'committed\na line long enough\nto wrap\ndone\n');
    });

    test('in the inline mode with clearInlineOnExit leaves the last frame '
        'out', () async {
      final (app, out) = await start(inline: true, clearInlineOnExit: true);
      app.commit(RenderParagraph([('committed', const Pen())]));
      final done = run(app, RenderText('status', 0));
      await settle();
      app.quit();
      await clock.elapseUntil(done);
      expect(out.text, 'committed\n');
    });
  });

  group('the demo with its stdout piped', () {
    late String demo;
    setUpAll(
      () async => demo = await compiledProgram(
        'example/chat_demo.dart',
        packages: (await Isolate.packageConfig)!.toFilePath(),
        cache: '.dart_tool/twk_test/programs',
      ),
    );

    /// The demo's stdout, run with [args] outside any project (no twk
    /// shell to give way to).
    Future<Uint8List> run(List<String> args) async {
      final res = await runProcess(
        Platform.resolvedExecutable,
        [demo, ...args],
        workingDirectory: Directory.systemTemp.path,
        environment: {'TWK_PLAIN': ''},
        stdoutEncoding: null,
      );
      expect(res.exitCode, 0, reason: '${res.stderr}');
      return res.stdout as Uint8List;
    }

    test('writes no escape sequence, and its last frame as text', () async {
      final out = await run(['--seconds=1']);
      expect(out, isNot(contains(_esc)));
      final lines = utf8.decode(out).split('\n');
      expect(lines.first, startsWith(' twk_core · chat demo'));
      expect(lines, contains('>'));
      expect(lines, contains(startsWith(' frame ')));
    });

    test('in the inline mode, the lines it commits first', () async {
      final out = await run(['--inline', '--seconds=1']);
      expect(out, isNot(contains(_esc)));
      final lines = utf8.decode(out).split('\n');
      expect(lines.first, 'tool: ran 412 tests ✓ all passed');
      expect(lines, contains(startsWith(' twk_core · chat demo')));
    });
  });
}
