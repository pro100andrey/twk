// A Terminal over a link of the program's own (Terminal.overLink): an
// in-memory one, and link_app.dart in a process of its own for what
// belongs to the process (its signals, the trace its environment asks
// for), which such a terminal leaves alone.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/terminal/link.dart' show TerminalDeclaration;
import 'package:twk_core/src/terminal/terminal.dart' show openOwnOrShell;
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart'
    show FakeClock, compiledProgram, startProcess;

import 'fake_link.dart';
import 'on_clock.dart';

/// What the terminal answers to the probe: synchronized output, the kitty
/// keyboard protocol, then DA1.
const _answers = '\x1b[?2026;2\$y\x1b[?0u\x1b[?62;22c';

const _options = TerminalOptions(probeTimeout: Duration(seconds: 5));

/// link_app.dart, compiled to [kernel], in a process of its own, with
/// [args] and `TWK_TRACE_OUTPUT` naming a file: the lines it printed, its
/// exit code and whether the trace was written. Killed if the test ends
/// first.
Future<(List<String>, int, bool)> _signalled(
  String kernel,
  List<String> args,
) async {
  final dir = Directory.systemTemp.createTempSync('link');
  addTearDown(() => dir.deleteSync(recursive: true));
  final trace = File('${dir.path}/output.trace');
  final process = await startProcess(
    Platform.resolvedExecutable,
    [kernel, ...args],
    environment: {'TWK_TRACE_OUTPUT': trace.path},
  );
  final lines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();
  final errors = process.stderr.transform(utf8.decoder).join();
  // the test's timeout is the bound
  final code = await process.exitCode;
  expect(await errors, isEmpty);
  return (await lines, code, trace.existsSync());
}

void main() {
  // The terminals run on a clock of the test's: their timers fire as it
  // moves on, and what their link is given comes in as it flushes.
  late FakeClock clock;
  setUp(() => clock = FakeClock());

  test('the probe is answered, keys and resizes come in, and close puts '
      'the modes back', () async {
    final link = FakeLink()..type(_answers);
    final term = await clock.open(link, _options);
    // asked on the alternate screen, which takes what they show
    expect(link.text, startsWith('\x1b[?2026h\x1b[?1049h\x1b[?2026\$p'));
    expect(term.info.answeredQueries, isTrue);
    expect(term.info.caps.synchronizedOutput, isTrue);
    expect(term.info.kittyKeyboard, isTrue);
    // no shell of this process has it: Ctrl+Z stops nothing
    expect(term.stopsForShell, isFalse);
    expect(link.text, contains('\x1b[?1049h'));
    expect(link.text, contains('\x1b[>1u'));
    expect(link.raw, isTrue);

    final events = <InputEvent>[];
    term.events.listen(events.add);
    link.type('a\x03');
    await clock.flushMicrotasks();
    expect(events, const [
      KeyEvent(KeyCode.char, char: 'a'),
      KeyEvent(KeyCode.char, char: 'c', modifiers: Mod.ctrl),
    ]);
    link.resize(30, 10);
    await clock.flushMicrotasks();
    expect(events, hasLength(3));
    expect(events.last, const ResizeEvent(30, 10));
    expect((term.width, term.height), (30, 10));

    final open = link.text.length;
    await clock.runUntil(term.close);
    final exit = link.text.substring(open);
    expect(exit, contains('\x1b[<u'));
    expect(exit, contains('\x1b[?2004l'));
    expect(exit, contains('\x1b[?25h'));
    expect(exit, endsWith('\x1b[?1049l'));
    expect(link.rawChanges, [true, false]);
    expect(link.closed, isTrue);
  });

  test(
    'inline, the probe is asked in one write on the alternate screen, '
    'where the cursor is asked before it and after, nothing erased where '
    'it did not move',
    () async {
      final link = FakeLink(
        columns: 80,
        environment: const {'TERM': 'xterm-256color'},
      )..type('\x1b[5;1R\x1b[?2026;2\$y\x1b[?0u\x1b[5;1R\x1b[?62;22c');
      final term = await clock.open(
        link,
        const TerminalOptions(
          probeTimeout: Duration(seconds: 5),
          alternateScreen: false,
        ),
      );
      // a terminal that doesn't know a query may print it: on the
      // alternate screen, let go in the same write
      expect(
        link.text,
        startsWith('\x1b[6n\x1b7\x1b[?2026h\x1b[?1049h\x1b[?2026\$p'),
      );
      expect(
        link.text,
        contains('\x1b[>c\x1b[?1049l\x1b[?2026l\x1b[6n\x1b[c\x1b8\x1b[?25l'),
      );
      expect('\x1b[c'.allMatches(link.text), hasLength(1), reason: 'one round');
      expect(link.text, isNot(contains('\x1b[J')));
      expect(link.text, isNot(contains('\x1b[K')));
      expect(link.text, contains('\x1b_Gi=31'));
      expect(term.info.answeredQueries, isTrue);
      expect(term.info.caps.synchronizedOutput, isTrue);
      expect(term.info.kittyKeyboard, isTrue);
      expect(term.info.cursorColumn, 0);
      await clock.runUntil(term.close);
    },
  );

  test('Terminal.app is asked every query on the alternate screen, which '
      'takes what it prints of them', () async {
    for (final alternateScreen in [true, false]) {
      final link = FakeLink(
        columns: 80,
        environment: const {
          'TERM': 'xterm-256color',
          'TERM_PROGRAM': 'Apple_Terminal',
        },
      )..type('\x1b[5;1R\x1b[>1;95;0c\x1b[5;1R\x1b[?1;2c');
      final term = await clock.open(
        link,
        TerminalOptions(
          probeTimeout: const Duration(seconds: 5),
          alternateScreen: alternateScreen,
        ),
      );
      final text = link.text;
      final between = text.substring(
        text.indexOf('\x1b[?1049h'),
        text.indexOf('\x1b[?1049l'),
      );
      expect(between, contains(r'$p'), reason: '$alternateScreen');
      expect(between, contains('\x1b_G'), reason: '$alternateScreen');
      expect(term.info.caps.styledUnderlines, isFalse);
      // its DCH shifts a line only as far as it was written in one go
      expect(term.info.caps.insertDelete, isFalse);
      await clock.runUntil(term.close);
    }
  });

  test('a terminal started from Terminal.app, which keeps its '
      "TERM_PROGRAM, is told apart by its DA2: xterm's", () async {
    final term = await clock.open(
      FakeLink(
        columns: 80,
        environment: const {
          'TERM': 'xterm',
          'TERM_PROGRAM': 'Apple_Terminal',
          'XTERM_VERSION': 'XTerm(390)',
        },
      )..type('\x1b[5;1R\x1b[?2026;2\$y\x1b[>41;390;0c\x1b[5;1R\x1b[?64c'),
      const TerminalOptions(
        probeTimeout: Duration(seconds: 5),
        alternateScreen: false,
      ),
    );
    expect(term.info.caps.synchronizedOutput, isTrue);
    expect(term.info.caps.styledUnderlines, isTrue);
    expect(term.info.caps.insertDelete, isTrue);
    expect(term.info.notifications, NotificationProtocol.none);
    expect(term.info.bidi, BidiReordering.app);
    await clock.runUntil(term.close);
  });

  test("inline, what the queries showed is erased on the cursor's line, "
      'only where it moved: a terminal without the alternate screen', () async {
    final link = FakeLink(
      columns: 80,
      environment: const {'TERM': 'xterm-256color'},
    )..type('\x1b[5;1R\x1b[5;7R\x1b[?62c');
    final term = await clock.open(
      link,
      const TerminalOptions(
        probeTimeout: Duration(seconds: 5),
        alternateScreen: false,
      ),
    );
    expect(term.info.cursorColumn, 0);
    expect(link.text, contains('\x1b[6n\x1b[c\x1b8\x1b[K'));
    await clock.runUntil(term.close);
  });

  test(
    'inline, every query is asked wherever the cursor is on its line',
    () async {
      final link = FakeLink(
        columns: 80,
        environment: const {'TERM': 'xterm-kitty'},
      )..type('\x1b[5;79R\x1b[?2026;2\$y\x1b[5;79R\x1b[?62c');
      final term = await clock.open(
        link,
        const TerminalOptions(
          probeTimeout: Duration(seconds: 5),
          alternateScreen: false,
        ),
      );
      expect(term.info.cursorColumn, 78);
      expect(term.info.caps.synchronizedOutput, isTrue);
      expect(link.text, contains(r'$p'));
      expect(link.text, contains('\x1b_Gi=31'));
      await clock.runUntil(term.close);
    },
  );

  test('inside GNU screen, which prints a DECRQM, none is asked', () async {
    for (final env in const [
      {'TERM': 'screen-256color', 'STY': '1.pts-0.host'},
      {'TERM': 'screen.xterm-256color'},
    ]) {
      final link = FakeLink(columns: 80, environment: env)
        ..type('\x1b[5;1R\x1b[>83;40903;0c\x1b[5;1R\x1b[?1;2c');
      final term = await clock.open(
        link,
        const TerminalOptions(
          probeTimeout: Duration(seconds: 5),
          alternateScreen: false,
        ),
      );
      expect(link.text, isNot(contains(r'$p')), reason: '$env');
      // its ICH and DCH are what they should be
      expect(term.info.caps.insertDelete, isTrue, reason: '$env');
      await clock.runUntil(term.close);
    }
  });

  test('Terminal.app is told by its secondary device attributes, over ssh '
      'too: no underline styles, no ICH nor DCH; another terminal that '
      'answers no DECRQM keeps them', () async {
    for (final alternateScreen in [true, false]) {
      Future<Terminal> open(String secondary) => clock.open(
        FakeLink(columns: 80, environment: const {'TERM': 'xterm-256color'})
          ..type('\x1b[5;1R$secondary\x1b[5;1R\x1b[?1;2c'),
        TerminalOptions(
          probeTimeout: const Duration(seconds: 5),
          alternateScreen: alternateScreen,
        ),
      );
      final apple = await open('\x1b[>1;95;0c');
      expect(apple.info.answeredQueries, isTrue);
      expect(
        apple.info.caps.styledUnderlines,
        isFalse,
        reason: '$alternateScreen',
      );
      expect(apple.info.caps.insertDelete, isFalse);
      // what its TERM_PROGRAM would give: its bell, its own bidi
      expect(apple.info.notifications, NotificationProtocol.bell);
      expect(apple.info.bidi, BidiReordering.terminal);
      await clock.runUntil(apple.close);
      // iTerm2's, and none at all (PuTTY, the Linux console)
      for (final other in ['\x1b[>0;95;0c', '']) {
        final term = await open(other);
        expect(
          term.info.caps.styledUnderlines,
          isTrue,
          reason: '$alternateScreen $other',
        );
        expect(term.info.caps.insertDelete, isTrue);
        expect(term.info.notifications, NotificationProtocol.none);
        expect(term.info.bidi, BidiReordering.app);
        await clock.runUntil(term.close);
      }
    }
  });

  test("through tmux, which answers DA2 itself, Terminal.app's is taken "
      'for nothing', () async {
    final term = await clock.open(
      FakeLink(
        columns: 80,
        environment: const {
          'TERM': 'tmux-256color',
          'TMUX': '/tmp/tmux-1000/default,1,0',
        },
      )..type('\x1b[5;1R\x1b[>1;95;0c\x1b[5;1R\x1b[?1;2c'),
      const TerminalOptions(
        probeTimeout: Duration(seconds: 5),
        alternateScreen: false,
      ),
    );
    expect(term.info.notifications, NotificationProtocol.none);
    expect(term.info.bidi, BidiReordering.app);
    expect(term.info.caps.insertDelete, isTrue);
    await clock.runUntil(term.close);
  });

  test('writes what a terminal opened as Terminal.open opens one writes '
      'over the same link', () async {
    Future<String> session(Future<Terminal> Function(FakeLink) open) async {
      final link = FakeLink()..type(_answers);
      final term = await open(link);
      term
        ..setTitle('title')
        ..write(Uint8List.fromList('frame'.codeUnits))
        ..mouseTracking = MouseTracking.off;
      await term.flush();
      await term.close();
      return link.text;
    }

    final own = await session((link) => openOwnOrShell(link, _options));
    expect(own, contains('frame'));
    expect(await session((link) => Terminal.overLink(link, _options)), own);
  });

  test("a terminal of the process's gives the app TWK_SCREEN_READER and "
      "TWK_DEBUG of its link's environment, an empty one too, and nothing "
      'else of it; one over a link (overLink) none of it', () async {
    Future<Map<String, String>> settings(
      Future<Terminal> Function(FakeLink) open,
      Map<String, String> environment,
    ) async {
      final link = FakeLink(environment: environment)..type(_answers);
      final term = await open(link);
      await term.close();
      return term.info.settings;
    }

    const asks = {
      'TERM': 'xterm-256color',
      'TWK_SCREEN_READER': '1',
      'TWK_DEBUG': 'overlay,frames',
      'TWK_LOG': '/tmp/app.log',
      'TWK_EDITOR': 'vi {file}',
    };
    Future<Terminal> own(FakeLink link) => openOwnOrShell(link, _options);
    expect(await settings(own, asks), {
      'TWK_SCREEN_READER': '1',
      'TWK_DEBUG': 'overlay,frames',
    });
    expect(
      await settings(own, const {'TERM': 'xterm', 'TWK_DEBUG': ''}),
      {'TWK_DEBUG': ''},
      reason: 'set empty: none of the debug aids, whatever the process says',
    );
    expect(await settings(own, const {'TERM': 'xterm'}), isEmpty);
    expect(
      await settings((link) => Terminal.overLink(link, _options), asks),
      isEmpty,
      reason: "a link's far end is not to switch the app's debug aids",
    );
    expect(TerminalInfo.settingNames, {'TWK_SCREEN_READER', 'TWK_DEBUG'});
  });

  group('a terminal that declares what it does', () {
    // kitty by its name: OSC 99, pointer shapes, REP; no progress (no
    // version told), no images (kitty's graphics query not answered)
    const kitty = {'TERM': 'xterm-kitty'};

    Future<Terminal> open(TerminalDeclaration declaration) {
      final link = FakeLink(environment: kitty, declaration: declaration)
        ..type(_answers);
      return clock.open(link, _options);
    }

    test('is taken at its word over the guess by its name', () async {
      final guessed = (await open(const TerminalDeclaration())).info;
      expect(guessed.notifications, NotificationProtocol.osc99);
      expect(guessed.pointerShapes, isTrue);
      expect(guessed.caps.repeatChar, isTrue);
      expect(guessed.progressReports, isFalse);
      expect(guessed.caps.graphics, GraphicsProtocol.none);

      final declared = (await open(
        const TerminalDeclaration(
          notifications: NotificationProtocol.osc777,
          progressReports: true,
          pointerShapes: false,
          repeatChar: false,
          graphics: GraphicsProtocol.sixel,
          styledUnderlines: false,
        ),
      )).info;
      expect(declared.notifications, NotificationProtocol.osc777);
      expect(declared.progressReports, isTrue);
      expect(declared.pointerShapes, isFalse);
      expect(declared.caps.repeatChar, isFalse);
      expect(declared.caps.graphics, GraphicsProtocol.sixel);
      expect(guessed.caps.styledUnderlines, isTrue);
      expect(declared.caps.styledUnderlines, isFalse);
    });

    test("iTerm2's pointer shapes are named by the X cursor font, a "
        "declaring terminal's by CSS", () async {
      const iTerm = {
        'TERM_PROGRAM': 'iTerm.app',
        'TERM_PROGRAM_VERSION': '3.7.2',
      };
      Future<TerminalInfo> info(TerminalDeclaration declaration) async {
        final link = FakeLink(environment: iTerm, declaration: declaration)
          ..type(_answers);
        return (await clock.open(link, _options)).info;
      }

      final guessed = await info(const TerminalDeclaration());
      expect(guessed.pointerShapes, isTrue);
      expect(guessed.pointerNames, PointerNames.x11);
      final declared = await info(
        const TerminalDeclaration(pointerShapes: true),
      );
      expect(declared.pointerShapes, isTrue);
      expect(declared.pointerNames, PointerNames.css);
    });

    test('declaring some, the rest is guessed', () async {
      final info = (await open(
        const TerminalDeclaration(progressReports: true),
      )).info;
      expect(info.progressReports, isTrue);
      expect(info.notifications, NotificationProtocol.osc99);
      expect(info.pointerShapes, isTrue);
      expect(info.caps.repeatChar, isTrue);
    });

    test('declaring its images, it is not asked about them', () async {
      final link = FakeLink(
        environment: kitty,
        declaration: const TerminalDeclaration(graphics: GraphicsProtocol.none),
      )..type(_answers);
      final term = await clock.open(link, _options);
      await clock.runUntil(term.close);
      expect(link.text, isNot(contains('\x1b_G')), reason: "kitty's query");
      expect(link.text, isNot(contains('\x1b[>0q')), reason: 'XTVERSION');
      final asked = FakeLink(environment: kitty)..type(_answers);
      final other = await clock.open(asked, _options);
      await clock.runUntil(other.close);
      expect(asked.text, contains('\x1b_G'), reason: 'undeclared: asked');
    });

    test('options of the app come before it', () async {
      final link = FakeLink(
        environment: kitty,
        declaration: const TerminalDeclaration(
          graphics: GraphicsProtocol.sixel,
        ),
      )..type(_answers);
      final term = await clock.open(
        link,
        const TerminalOptions(
          probeTimeout: Duration(seconds: 5),
          graphics: GraphicsProtocol.kitty,
        ),
      );
      await clock.runUntil(term.close);
      expect(term.info.caps.graphics, GraphicsProtocol.kitty);
    });
  });

  group('TerminalDeclaration', () {
    test('as JSON: what it declares, in order, the protocols by name', () {
      const all = TerminalDeclaration(
        notifications: NotificationProtocol.none,
        progressReports: false,
        pointerShapes: true,
        repeatChar: true,
        graphics: GraphicsProtocol.iterm2,
      );
      expect(
        jsonEncode(all.toJson()),
        '{"notifications":"none",'
        '"progressReports":false,"pointerShapes":true,"repeatChar":true,'
        '"graphics":"iterm2"}',
      );
      expect(TerminalDeclaration.fromJson(all.toJson()), all);
      expect(const TerminalDeclaration().toJson(), isEmpty);
      expect(const TerminalDeclaration().isEmpty, isTrue);
      expect(all.isEmpty, isFalse);
    });

    test('from JSON: a field of another type or value declares nothing, '
        'nor does what is no object', () {
      expect(
        TerminalDeclaration.fromJson({
          'notifications': 'beep',
          'progressReports': 'yes',
          'pointerShapes': 1,
          'repeatChar': null,
          'graphics': 'png',
          'unknown': true,
        }),
        const TerminalDeclaration(),
      );
      expect(
        TerminalDeclaration.fromJson({'repeatChar': true, 'graphics': 7}),
        const TerminalDeclaration(repeatChar: true),
      );
      for (final json in [
        null,
        1,
        'osc9',
        <Object?>[true],
      ]) {
        expect(TerminalDeclaration.fromJson(json), const TerminalDeclaration());
      }
    });
  });

  test('is not suspended: nothing is written, raw mode stays', () async {
    final link = FakeLink()..type(_answers);
    final term = await Terminal.overLink(link, _options);
    final open = link.text.length;
    await expectLater(term.suspend(), throwsUnsupportedError);
    await term.resume();
    expect(link.text.length, open);
    expect(link.rawChanges, [true]);
    await term.close();
  });

  test(
    'puts the states set on it back, the last first, as it closes, '
    'and tells the link so for a death; writes one again on refresh',
    () async {
      final link = FakeLink()..type(_answers);
      final term = (await clock.open(link, _options))
        ..setTerminalState(#a, '<A>', '<a>')
        ..setTerminalState(#b, '<B>', '<b>')
        ..setTerminalState(#c, '<C>', '<c>')
        ..setTerminalState(#a, '<A2>', '<a2>')
        ..restoreTerminalState(#c)
        ..restoreTerminalState(#d);
      expect(link.text, endsWith('<A><B><C><A2><c>'));
      expect(link.restoring, startsWith('<b><a2>\x1b[0m'));
      // the refresh is a timer of the clock's
      clock.run(
        () => term.setTerminalState(
          #r,
          '<R>',
          '<r>',
          refresh: const Duration(milliseconds: 20),
        ),
      );
      await clock.elapse(const Duration(milliseconds: 70));
      // as set, then at 20, 40 and 60 ms
      expect('<R>'.allMatches(link.text).length, 4);
      term.restoreTerminalState(#r);
      expect(link.text, endsWith('<r>'));
      final restored = link.text.length;
      await clock.elapse(const Duration(milliseconds: 50));
      expect(link.text.length, restored);
      clock.run(
        () => term.setTerminalState(
          #s,
          '<S>',
          '<s>',
          refresh: const Duration(milliseconds: 20),
        ),
      );
      final open = link.text.length;
      await clock.runUntil(term.close);
      final exit = link.text.substring(open);
      expect(exit, startsWith('<s><b><a2>\x1b[0m'));
      await clock.elapse(const Duration(milliseconds: 50));
      expect(link.text.substring(open), exit);
      expect(clock.pendingTimers, 0, reason: 'no refresh left');
      term.setTerminalState(#e, '<E>', '<e>');
      expect(link.text.substring(open), exit);
    },
  );

  test('over plain output keeps no state, writes none and starts no '
      'timer to refresh it', () async {
    final link = FakeLink();
    final term = await Terminal.overLink(
      link,
      const TerminalOptions(plain: true),
    );
    var timers = 0;
    runZoned(
      () => term.setTerminalState(
        #p,
        '<P>',
        '<p>',
        refresh: const Duration(milliseconds: 10),
      ),
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, period, f) {
          timers++;
          return parent.createPeriodicTimer(zone, period, f);
        },
      ),
    );
    term.restoreTerminalState(#p);
    await term.close();
    expect(timers, 0);
    expect(link.text, isEmpty);
    expect(link.restoring, isEmpty);
  });

  group("the process's signals and trace", () {
    late String app;
    setUpAll(
      () async => app = await compiledProgram(
        'test/terminal/link_app.dart',
        packages: (await Isolate.packageConfig)!.toFilePath(),
        cache: '.dart_tool/twk_test/programs',
      ),
    );

    test('are left alone over a link: SIGINT is no key, SIGTERM ends the '
        'process, nothing is traced', () async {
      final (lines, code, traced) = await _signalled(app, []);
      expect(lines, ['sigterm']);
      expect(code, -ProcessSignal.sigterm.signalNumber);
      expect(traced, isFalse);
    });

    test('are taken as Terminal.open opens one: SIGINT is Ctrl+C, SIGTERM '
        'restores and exits, the output is traced', () async {
      final (lines, code, traced) = await _signalled(app, ['own']);
      expect(lines, ['event Key("c" mod=${Mod.ctrl})', 'sigterm']);
      expect(code, 143);
      expect(traced, isTrue);
    });
  }, testOn: 'linux || mac-os');
}
