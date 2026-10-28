// Bidi on a terminal: the probe asks for BDSM (DECRQM CSI 8 $ p), a
// terminal that honours it is put in explicit mode while open and back in
// its own on the way out, one that doesn't answer is known by its identity,
// and an app draws text in visual order where the app orders it, in
// logical order where the terminal does.
import 'package:test/test.dart';
import 'package:twk_core/src/terminal/sequences.dart'
    show
        bidiModeQuery,
        bidiModeSequences,
        bidiReorderingFor,
        explicitBidiSequence,
        implicitBidiSequence;
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;
import 'package:twk_test/vt.dart';
import 'package:twk_test/vt_terminal.dart';

import 'fake_link.dart';
import 'on_clock.dart';

const _options = TerminalOptions(probeTimeout: Duration(seconds: 5));

/// DA1, the probe's last answer.
const _da1 = '\x1b[?62;22c';

/// The answer about BDSM, [mode] its Ps; none for null.
String _bdsm(int? mode) => mode == null ? '' : '\x1b[8;$mode\$y';

const BidiReordering app = BidiReordering.app;
const BidiReordering terminal = BidiReordering.terminal;

/// Konsole's environment: it doesn't answer about BDSM.
const _konsole = {'TERM': 'xterm-256color', 'KONSOLE_VERSION': '240802'};

/// kitty's, started from Konsole.
const _kitty = {'TERM': 'xterm-kitty', 'KONSOLE_VERSION': '240802'};

/// A terminal over a link in [env] whose probe gets [answers].
Future<(Terminal, FakeLink)> _open(
  String answers, {
  Map<String, String> env = _kitty,
  TerminalOptions options = _options,
}) async {
  final link = FakeLink(environment: env)..type(answers);
  return (await Terminal.overLink(link, options), link);
}

const _plain = Pen();

/// The rows the emulator shows after an app on [term] drew [text] once,
/// on a clock of its own: its frame is a timer that fires as the clock
/// moves on.
Future<List<String>> _drawn(HeadlessTerminal term, String text) async {
  final clock = FakeClock();
  final ui = TwkApp(
    term,
    maxFps: 1000,
    clock: clock.stopwatch,
    environment: const {},
  );
  final done = clock.run(
    () => ui.run(RenderParagraph([(text, _plain)]), (_) {}),
  );
  await clock.elapse(const Duration(milliseconds: 30));
  ui.quit();
  await clock.elapseUntil(done);
  final vt = Vt(term.width, term.height);
  term.frames.forEach(vt.feed);
  expect(vt.errors, isEmpty);
  return [for (final r in vt.dump().split('\n')) r.trimRight()];
}

void main() {
  group('who orders right-to-left text', () {
    test('a terminal that honours BDSM leaves it to the app, one that '
        'keeps it set orders it itself', () {
      for (final env in [_konsole, _kitty, const <String, String>{}]) {
        expect(bidiReorderingFor(env, mode: 1), app, reason: '$env');
        expect(bidiReorderingFor(env, mode: 2), app, reason: '$env');
        expect(bidiReorderingFor(env, mode: 3), terminal, reason: '$env');
      }
    });

    test('without an answer that settles it, by identity: Konsole, '
        'mlterm, Terminal.app and PuTTY order it themselves', () {
      const reorders = <(Map<String, String>, String)>[
        (_konsole, ''),
        ({'TERM': 'xterm-256color'}, 'Konsole 24.08.2'),
        ({'TERM': 'xterm', 'MLTERM': '3.9.3'}, ''),
        ({'TERM': 'xterm'}, 'mlterm(3.9.5)'),
        ({'TERM': 'mlterm'}, ''),
        ({'TERM': 'xterm-256color', 'TERM_PROGRAM': 'Apple_Terminal'}, ''),
        ({'TERM': 'putty-256color'}, ''),
        ({'TERM': 'putty'}, ''),
      ];
      for (final (env, version) in reorders) {
        for (final mode in [null, 0, 4]) {
          expect(
            bidiReorderingFor(env, mode: mode, version: version),
            terminal,
            reason: '$env $version $mode',
          );
        }
      }
    });

    test('the app elsewhere: terminals that do no bidi, a name or TERM of '
        'its own over a Konsole it was started from, tmux and screen', () {
      const ordersNot = <(Map<String, String>, String)>[
        ({}, ''),
        ({'TERM': 'xterm-256color', 'XTERM_VERSION': 'XTerm(390)'}, ''),
        (_kitty, ''),
        ({'TERM': 'xterm-256color'}, 'kitty(0.39.1)'),
        (_konsole, 'kitty(0.39.1)'),
        ({'TERM': 'xterm-ghostty', 'MLTERM': '3.9.3'}, ''),
        ({'TERM': 'foot', 'KONSOLE_VERSION': '240802'}, ''),
        ({'TERM': 'alacritty', 'KONSOLE_VERSION': '240802'}, ''),
        ({..._konsole, 'TERM_PROGRAM': 'WezTerm'}, ''),
        ({'TERM_PROGRAM': 'iTerm.app'}, ''),
        ({'TERM': 'xterm-256color', 'VTE_VERSION': '7600'}, ''),
        ({'WT_SESSION': 'x'}, ''),
        ({'TERM': 'linux'}, ''),
        ({..._konsole, 'TMUX': '/tmp/tmux-1000/default,1,0'}, ''),
        ({'TERM': 'tmux-256color', 'KONSOLE_VERSION': '240802'}, ''),
        ({'TERM': 'screen', 'TERM_PROGRAM': 'Apple_Terminal'}, ''),
        ({'STY': '1.pts-0', 'MLTERM': '3.9.3'}, ''),
      ];
      for (final (env, version) in ordersNot) {
        for (final mode in [null, 0, 4]) {
          expect(
            bidiReorderingFor(env, mode: mode, version: version),
            app,
            reason: '$env $version $mode',
          );
        }
      }
    });

    test('BDSM is switched only where it is honoured and in the other '
        'mode, and put back', () {
      expect(bidiModeSequences(1, app), (
        explicitBidiSequence,
        implicitBidiSequence,
      ));
      expect(bidiModeSequences(2, terminal), (
        implicitBidiSequence,
        explicitBidiSequence,
      ));
      for (final mode in [null, 0, 3, 4]) {
        for (final bidi in BidiReordering.values) {
          expect(bidiModeSequences(mode, bidi), isNull, reason: '$mode');
        }
      }
      expect(bidiModeSequences(2, app), isNull);
      expect(bidiModeSequences(1, terminal), isNull);
      expect(
        (explicitBidiSequence, implicitBidiSequence),
        (
          '\x1b[8l',
          '\x1b[8h',
        ),
      );
    });
  });

  group('the probe', () {
    test('asks for BDSM before DA1', () async {
      final (term, link) = await _open(_da1);
      final asked = link.text.indexOf(bidiModeQuery);
      expect(bidiModeQuery, '\x1b[8\$p');
      expect(asked, greaterThan(0));
      expect(asked, lessThan(link.text.indexOf('\x1b[c')));
      await term.close();
    });

    test('reads each answer: 1 and 2 leave it to the app, 3 to the '
        'terminal, 0, 4 and none to its identity', () async {
      final cases = <(int?, Map<String, String>, BidiReordering)>[
        (1, _konsole, app),
        (2, _konsole, app),
        (3, _kitty, terminal),
        for (final mode in [0, 4, null]) ...[
          (mode, _konsole, terminal),
          (mode, _kitty, app),
        ],
      ];
      for (final (mode, env, bidi) in cases) {
        final (term, link) = await _open('${_bdsm(mode)}$_da1', env: env);
        expect(term.info.bidi, bidi, reason: '$mode $env');
        expect(term.info.toString(), contains('bidi=${bidi.name}'));
        await term.close();
        final written = link.text;
        expect(
          written.contains(explicitBidiSequence),
          mode == 1,
          reason: '$mode $env',
        );
        expect(
          written.contains(implicitBidiSequence),
          mode == 1,
          reason: '$mode $env',
        );
      }
    });

    test('an answer that comes after the probe gave up is no input', () async {
      // on a clock of the test's: the probe gives up as it reaches 20 ms
      final clock = FakeClock();
      final link = FakeLink(environment: _kitty);
      final term = await clock.open(
        link,
        const TerminalOptions(probeTimeout: Duration(milliseconds: 20)),
      );
      expect(clock.elapsed, const Duration(milliseconds: 20));
      expect(term.info.answeredQueries, isFalse);
      final events = <InputEvent>[];
      term.events.listen(events.add);
      link.type('${_bdsm(1)}${_da1}a');
      await clock.elapse(const Duration(milliseconds: 20));
      expect(events, const [KeyEvent(KeyCode.char, char: 'a')]);
      await clock.runUntil(term.close);
    });
  });

  group('BDSM on the terminal', () {
    test('set (implicit): reset while open, set again on close and for a '
        'death, as the emulator follows it', () async {
      final (term, link) = await _open('${_bdsm(1)}$_da1');
      final opened = link.output.toBytes();
      final vt = Vt(20, 4, strict: false)..feed(opened);
      expect(vt.bidiExplicit, isTrue);
      expect(link.text.indexOf(explicitBidiSequence), greaterThan(0));
      expect(link.restoring, startsWith(implicitBidiSequence));
      await term.close();
      vt.feed(link.output.toBytes().sublist(opened.length));
      expect(vt.bidiExplicit, isFalse);
      expect(vt.errors, isEmpty);
      expect(
        link.text.substring(opened.length),
        contains(implicitBidiSequence),
      );
    });

    test('reset (explicit) already: nothing written', () async {
      final (term, link) = await _open('${_bdsm(2)}$_da1');
      expect(term.info.bidi, app);
      await term.close();
      expect(link.text, isNot(contains('\x1b[8l')));
      expect(link.text, isNot(contains('\x1b[8h')));
    });

    test('TerminalOptions.bidi overrides: terminal sets a reset BDSM and '
        'resets it again, app leaves one set for good alone', () async {
      final (term, link) = await _open(
        '${_bdsm(2)}$_da1',
        options: const TerminalOptions(
          probeTimeout: Duration(seconds: 5),
          bidi: terminal,
        ),
      );
      expect(term.info.bidi, terminal);
      final opened = link.text.length;
      expect(link.text, contains(implicitBidiSequence));
      expect(link.restoring, startsWith(explicitBidiSequence));
      await term.close();
      expect(link.text.substring(opened), contains(explicitBidiSequence));

      final (forced, other) = await _open(
        '${_bdsm(3)}$_da1',
        env: _konsole,
        options: const TerminalOptions(
          probeTimeout: Duration(seconds: 5),
          bidi: app,
        ),
      );
      expect(forced.info.bidi, app);
      await forced.close();
      expect(other.text, isNot(contains('\x1b[8l')));
      expect(other.text, isNot(contains('\x1b[8h')));
    });

    test('plain output leaves it to its reader, unless the options say '
        'otherwise', () async {
      final link = FakeLink(environment: _kitty);
      final term = await Terminal.overLink(
        link,
        const TerminalOptions(plain: true),
      );
      expect(term.info.bidi, terminal);
      await term.close();
      final forced = await Terminal.overLink(
        FakeLink(environment: _kitty),
        const TerminalOptions(plain: true, bidi: app),
      );
      expect(forced.info.bidi, app);
      await forced.close();
      expect(link.text, isEmpty);
    });
  });

  group('the app', () {
    test('draws in visual order where the app orders the text, the '
        'headless default', () async {
      final term = HeadlessTerminal(width: 12, height: 1);
      expect(term.info.bidi, app);
      expect(
        TwkApp(term, environment: const {}).owner.textOrder,
        TextOrder.visual,
      );
      expect(await _drawn(term, 'abc אבג'), ['abc גבא']);
    });

    test('in logical order where the terminal does', () async {
      final term = HeadlessTerminal(width: 12, height: 1, bidi: terminal);
      expect(
        TwkApp(term, environment: const {}).owner.textOrder,
        TextOrder.logical,
      );
      expect(await _drawn(term, 'abc אבג'), ['abc אבג']);
    });

    test("commits in the order the app's owner has", () async {
      // on a clock of the test's: the frames are timers that fire as it
      // moves on
      final clock = FakeClock();
      Future<void> frame() => clock.elapse(const Duration(milliseconds: 30));
      final term = VtTerminal(width: 12, height: 4);
      final ui = TwkApp(
        term,
        maxFps: 1000,
        clock: clock.stopwatch,
        environment: const {},
      );
      final done = clock.run(
        () => ui.run(RenderParagraph([('live', _plain)]), (_) {}),
      );
      await frame();
      ui.commit(RenderParagraph([('abc אבג', _plain)]));
      await frame();
      ui.owner.textOrder = TextOrder.logical;
      ui.commit(RenderParagraph([('abc אבג', _plain)]));
      await frame();
      ui.quit();
      await clock.elapseUntil(done);
      expect(term.vt.errors, isEmpty);
      expect(term.lines.take(3), ['abc גבא', 'abc אבג', 'live']);
    });
  });
}
