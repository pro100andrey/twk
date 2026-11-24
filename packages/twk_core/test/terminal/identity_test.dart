// The terminal as twk tells it (identifyTerminal): by the name it tells,
// else its environment, a name of another terminal coming before the
// variables of the one it was started from; and what the table of known
// terminals says it does without answering a query, as from DEC 2026 on
// Konsole 26.04, which answers no DECRQM.
import 'package:test/test.dart';
import 'package:twk_core/src/terminal/identity.dart';
import 'package:twk_core/src/terminal/sequences.dart'
    show bidiReorderingFor, pointerNamesFor, progressReportsFor, sextantsFor;
import 'package:twk_core/src/terminal/terminal.dart'
    show
        colorModeFor,
        graphicsProtocolFor,
        konsoleLinesFor,
        notificationProtocolFor,
        styledUnderlinesFor;
import 'package:twk_core/twk_core.dart';

import 'fake_link.dart';

/// The terminal [env] names, as `identifyTerminal` writes it.
String named(Map<String, String> env) => '${identifyTerminal(env)}';

void main() {
  group('identifyTerminal', () {
    test('by the name and version the terminal tells', () {
      expect(
        '${identifyTerminal(const {}, version: 'Konsole 26.08.3')}',
        'konsole 26.8.3',
      );
      expect(
        '${identifyTerminal(const {}, version: 'VTE(7802)')}',
        'vte 0.78.2',
      );
      expect(
        '${identifyTerminal(const {}, version: 'kitty(0.39)')}',
        'kitty 0.39',
      );
      expect(
        '${identifyTerminal(const {}, version: 'WezTerm 20240203-110809-5')}',
        'wezterm 20240203',
      );
      expect(
        '${identifyTerminal(const {}, version: 'Alacritty 0.15')}',
        'unknown',
      );
    });

    test('else by the variables a terminal sets for its programs', () {
      expect(
        named(const {'KONSOLE_VERSION': '260803'}),
        'konsole 26.8.3',
      );
      expect(
        named(const {'VTE_VERSION': '8002'}),
        'vte 0.80.2',
      );
      expect(named(const {'TERM': 'xterm'}), 'unknown');
      expect(
        '${identifyTerminal(const {}, version: 'Konsole')}',
        'konsole',
      );
    });

    test('not by those variables under a TERM of another terminal, which '
        'was started from theirs', () {
      for (final term in ['st-256color', 'linux']) {
        expect(
          identifyTerminal({
            'TERM': term,
            'KONSOLE_VERSION': '260803',
            'VTE_VERSION': '8002',
          }).terminal,
          isNull,
          reason: term,
        );
      }
      for (final term in ['xterm-256color', 'konsole-256color', 'tmux']) {
        expect(
          identifyTerminal({
            'TERM': term,
            'KONSOLE_VERSION': '260803',
          }).terminal,
          KnownTerminal.konsole,
          reason: term,
        );
      }
    });

    test('a name told, a TERM or a TERM_PROGRAM of another terminal comes '
        'before the variables of the one it was started from', () {
      const konsole = {'KONSOLE_VERSION': '260803'};
      for (final (env, version, terminal) in [
        (konsole, 'XTerm(397)', 'xterm 397'),
        ({...konsole, 'TERM': 'xterm-kitty'}, '', 'kitty'),
        ({...konsole, 'TERM_PROGRAM': 'vscode'}, '', 'unknown'),
        (
          {
            ...konsole,
            'TERM': 'contour',
            'TERM_PROGRAM': 'contour',
            'TERM_PROGRAM_VERSION': '0.6.1.7494',
          },
          '',
          'contour 0.6.1.7494',
        ),
        ({...konsole, 'TERM': 'dumb'}, '', 'unknown'),
      ]) {
        expect(
          '${identifyTerminal(env, version: version)}',
          terminal,
          reason: '$env $version',
        );
      }
    });

    test("a multiplexer's name says nothing of the terminal outside it", () {
      expect(
        identifyTerminal(const {
          'TMUX': '/tmp/tmux-1000/default,1,0',
          'TERM_PROGRAM': 'tmux',
          'KONSOLE_VERSION': '260803',
        }, version: 'tmux 3.5a').terminal,
        KnownTerminal.konsole,
      );
    });
  });

  test('what a known terminal does is known from its version on; a version '
      'not told has only what every version has', () {
    const sync = TerminalFeature.synchronizedOutput;
    expect(
      const TerminalIdentity(KnownTerminal.konsole, [26, 4]).has(sync),
      isTrue,
    );
    expect(
      const TerminalIdentity(KnownTerminal.konsole, [26, 3, 90]).has(sync),
      isFalse,
    );
    expect(const TerminalIdentity(KnownTerminal.konsole).has(sync), isFalse);
    expect(
      const TerminalIdentity(
        KnownTerminal.konsole,
      ).has(TerminalFeature.konsoleLines),
      isTrue,
    );
    expect(
      const TerminalIdentity(KnownTerminal.vte, [0, 80]).has(sync),
      isFalse,
    );
    expect(TerminalIdentity.unknown.has(TerminalFeature.konsoleLines), isFalse);
  });

  test('the rules of Konsole ask its identity: told by its name over ssh, '
      'where KONSOLE_VERSION is not passed on, or by the variable where no '
      'other terminal is named', () {
    const told = {'TERM': 'xterm-256color'};
    const version = 'Konsole 26.08.3';
    expect(pointerNamesFor(told, version: version), PointerNames.css);
    expect(progressReportsFor(told, version: version), isTrue);
    expect(sextantsFor(told, version: version), isTrue);
    expect(konsoleLinesFor(told, version: version), isTrue);
    expect(
      bidiReorderingFor(told, version: version),
      BidiReordering.terminal,
    );
    // VS Code started from Konsole keeps its KONSOLE_VERSION
    const vscode = {
      'TERM': 'xterm-256color',
      'TERM_PROGRAM': 'vscode',
      'KONSOLE_VERSION': '260803',
    };
    expect(konsoleLinesFor(vscode), isFalse);
    expect(pointerNamesFor(vscode), isNull);
    expect(notificationProtocolFor(vscode), NotificationProtocol.none);
  });

  group('the other terminals on the table', () {
    test('by the name and version they tell', () {
      for (final (version, terminal) in const [
        ('foot(1.18.0)', 'foot 1.18.0'),
        ('ghostty 1.0.1', 'ghostty 1.0.1'),
        ('iTerm2 3.5.0', 'iterm2 3.5.0'),
        ('mintty 3.7.8', 'mintty 3.7.8'),
        ('Rio 0.4.6', 'rio 0.4.6'),
        ('contour 0.6.1.7494', 'contour 0.6.1.7494'),
        ('mlterm(3.9.3)', 'mlterm 3.9.3'),
      ]) {
        expect('${identifyTerminal(const {}, version: version)}', terminal);
      }
    });

    test('by their TERM_PROGRAM and its version; GNOME Console by its '
        "VTE's", () {
      expect(
        named(const {
          'TERM_PROGRAM': 'iTerm.app',
          'TERM_PROGRAM_VERSION': '3.6.6',
        }),
        'iterm2 3.6.6',
      );
      expect(
        named(const {
          'TERM_PROGRAM': 'kgx',
          'TERM_PROGRAM_VERSION': '48.0',
          'VTE_VERSION': '7802',
        }),
        'vte 0.78.2',
      );
    });

    test('by the variables they set, under a TERM they set only; iTerm2 '
        'over ssh by LC_TERMINAL, at LC_TERMINAL_VERSION', () {
      expect(
        named(const {'LC_TERMINAL': 'iTerm2', 'LC_TERMINAL_VERSION': '3.7.1'}),
        'iterm2 3.7.1',
      );
      for (final env in const [
        {'WT_SESSION': 'x'},
        {'KITTY_WINDOW_ID': '1'},
        {'GHOSTTY_RESOURCES_DIR': '/usr/share/ghostty'},
        {'WEZTERM_PANE': '0'},
        {'ITERM_SESSION_ID': 'w0t0p0'},
        {'ConEmuPID': '1'},
      ]) {
        expect(
          identifyTerminal({'TERM': 'xterm-256color', ...env}).terminal,
          isNotNull,
          reason: '$env',
        );
        expect(
          identifyTerminal({'TERM': 'st-256color', ...env}).terminal,
          isNull,
          reason: '$env',
        );
      }
    });

    test('a fact from a version on: one not told has it where the table '
        'takes it to, as of kitty under its own TERM', () {
      const kitty = {'TERM': 'xterm-kitty'};
      expect(pointerNamesFor(kitty), PointerNames.css);
      expect(pointerNamesFor(kitty, version: 'kitty(0.30.1)'), isNull);
      expect(
        pointerNamesFor(kitty, version: 'kitty(0.31.0)'),
        PointerNames.css,
      );
      expect(sextantsFor(kitty), isTrue);
      expect(progressReportsFor(kitty), isFalse);
      expect(progressReportsFor(kitty, version: 'kitty(0.38.0)'), isTrue);
      // foot's OSC 99 only from 1.18, told by its name
      expect(
        notificationProtocolFor(const {'TERM': 'foot'}),
        NotificationProtocol.osc777,
      );
      expect(
        notificationProtocolFor(const {}, version: 'foot(1.18.0)'),
        NotificationProtocol.osc99,
      );
    });

    test('every rule asks the same identity: what a terminal started from '
        'another inherited counts for none of them', () {
      // st started from Windows Terminal
      const st = {'TERM': 'st-256color', 'WT_SESSION': 'x'};
      expect(colorModeFor(st), ColorMode.ansi256);
      expect(notificationProtocolFor(st), NotificationProtocol.none);
      expect(progressReportsFor(st), isFalse);
      const wt = {'TERM': 'xterm-256color', 'WT_SESSION': 'x'};
      expect(colorModeFor(wt), ColorMode.trueColor);
      expect(notificationProtocolFor(wt), NotificationProtocol.osc777);
      expect(progressReportsFor(wt), isTrue);
      // xterm started from kitty, which tells its own name
      const fromKitty = {'TERM': 'xterm-256color', 'KITTY_WINDOW_ID': '1'};
      expect(
        notificationProtocolFor(fromKitty, version: 'XTerm(397)'),
        NotificationProtocol.none,
      );
      expect(
        pointerNamesFor(fromKitty, version: 'XTerm(397)'),
        PointerNames.x11,
      );
      expect(
        notificationProtocolFor(fromKitty),
        NotificationProtocol.osc99,
      );
      // an editor's dumb TERM, started from Terminal.app
      const dumb = {'TERM': 'dumb', 'TERM_PROGRAM': 'Apple_Terminal'};
      expect(notificationProtocolFor(dumb), NotificationProtocol.none);
      expect(styledUnderlinesFor(dumb), isTrue);
      expect(
        styledUnderlinesFor(const {'TERM_PROGRAM': 'Apple_Terminal'}),
        isFalse,
      );
      // iTerm2's images through tmux, by the variables it set
      expect(
        graphicsProtocolFor(const {
          'TERM': 'tmux-256color',
          'TMUX': '/tmp/tmux-1000/default,1,0',
          'TERM_PROGRAM': 'tmux',
          'ITERM_SESSION_ID': 'w0t0p0',
        }),
        GraphicsProtocol.iterm2,
      );
    });
  });

  group('the probe', () {
    /// The info of a terminal of [env] that tells [version] and answers no
    /// DECRQM, as Konsole, or answers 2026 with [mode].
    Future<TerminalInfo> probe(
      Map<String, String> env, {
      String? version,
      int? mode,
      String reply = '',
      TerminalDeclaration declaration = const TerminalDeclaration(),
    }) async {
      final link = FakeLink(environment: env, declaration: declaration)
        ..type(
          '${version == null ? '' : '\x1bP>|$version\x1b\\'}'
          '${mode == null ? '' : '\x1b[?2026;$mode\$y'}'
          '$reply'
          '\x1b[?62;22c',
        );
      final term = await Terminal.overLink(
        link,
        const TerminalOptions(probeTimeout: Duration(seconds: 5)),
      );
      final info = term.info;
      await term.close();
      return info;
    }

    test('synchronized output for Konsole 26.04 on, which answers no DECRQM, '
        'by the name it tells or its environment', () async {
      for (final info in [
        await probe(const {
          'TERM': 'xterm-256color',
        }, version: 'Konsole 26.08.3'),
        await probe(const {
          'TERM': 'xterm-256color',
        }, version: 'Konsole 26.04.0'),
        await probe(const {
          'TERM': 'xterm-256color',
          'KONSOLE_VERSION': '260803',
        }),
      ]) {
        expect(info.caps.synchronizedOutput, isTrue);
      }
    });

    test('none for an earlier Konsole, for a terminal started from Konsole '
        'that tells its own name, or inside tmux that answers not', () async {
      for (final info in [
        await probe(const {
          'TERM': 'xterm-256color',
        }, version: 'Konsole 25.12.3'),
        await probe(const {
          'TERM': 'xterm-256color',
          'KONSOLE_VERSION': '260803',
        }, version: 'XTerm(397)'),
        await probe(const {
          'TERM': 'tmux-256color',
          'TMUX': '/tmp/tmux-1000/default,1,0',
          'TERM_PROGRAM': 'tmux',
          'KONSOLE_VERSION': '260803',
        }, version: 'tmux 3.5a'),
      ]) {
        expect(info.caps.synchronizedOutput, isFalse);
      }
    });

    test('a terminal that answers DECRQM 2026 no has none, though its '
        'variables name Konsole 26.04 on', () async {
      final info = await probe(const {
        'TERM': 'xterm-256color',
        'KONSOLE_VERSION': '260803',
      }, mode: 0);
      expect(info.caps.synchronizedOutput, isFalse);
      expect(info.sources['synchronizedOutput'], CapabilitySource.answered);
    });

    test('a terminal that answers DECRQM has what it answers', () async {
      expect(
        (await probe(const {'TERM': 'xterm'}, mode: 2)).caps.synchronizedOutput,
        isTrue,
      );
      expect(
        (await probe(const {'TERM': 'xterm'}, mode: 0)).caps.synchronizedOutput,
        isFalse,
      );
    });

    test('the info says which terminal it is and where its synchronized '
        'output came from', () async {
      final konsole = await probe(const {
        'TERM': 'xterm-256color',
      }, version: 'Konsole 26.08.3');
      expect(konsole.terminal, 'konsole 26.8.3');
      expect(konsole.sources['synchronizedOutput'], CapabilitySource.known);
      expect(konsole.sources['konsoleLines'], CapabilitySource.known);
      expect(
        '$konsole',
        allOf(
          contains('terminal=konsole 26.8.3'),
          contains('synchronizedOutput:known'),
        ),
      );
      final xterm = await probe(const {'TERM': 'xterm'}, mode: 2);
      expect(xterm.terminal, 'unknown');
      expect(xterm.sources['synchronizedOutput'], CapabilitySource.answered);
      final refused = await probe(const {'TERM': 'xterm'}, mode: 0);
      expect(refused.sources['synchronizedOutput'], CapabilitySource.answered);
      final silent = await probe(const {'TERM': 'xterm'});
      expect(silent.sources['synchronizedOutput'], CapabilitySource.assumed);
      expect(silent.sources['leftRightMargins'], CapabilitySource.assumed);
      expect(silent.sources['insertDelete'], CapabilitySource.assumed);
    });

    test('what the terminal declares comes before what it answers and what '
        'twk knows of it', () async {
      final declared = await probe(
        const {'TERM': 'xterm'},
        declaration: const TerminalDeclaration(
          synchronizedOutput: true,
          leftRightMargins: true,
          graphemes: true,
          insertDelete: false,
        ),
      );
      expect(declared.caps.synchronizedOutput, isTrue);
      expect(declared.caps.leftRightMargins, isTrue);
      expect(declared.textMode, TextMode.graphemes);
      expect(declared.caps.insertDelete, isFalse);
      for (final name in [
        'synchronizedOutput',
        'leftRightMargins',
        'graphemes',
        'insertDelete',
      ]) {
        expect(declared.sources[name], CapabilitySource.declared, reason: name);
      }
      final denied = await probe(
        const {'TERM': 'xterm-256color'},
        version: 'Konsole 26.08.3',
        declaration: const TerminalDeclaration(synchronizedOutput: false),
      );
      expect(denied.caps.synchronizedOutput, isFalse);
      expect(denied.sources['synchronizedOutput'], CapabilitySource.declared);
    });

    test("OSC 99 where its query is answered, kitty's form or Konsole's, "
        'which comes before the name', () async {
      final kitty = await probe(
        const {'TERM': 'xterm-256color'},
        reply:
            '\x1b]99;i=twk:p=?;p=title,body,?:a=focus,report:'
            'o=always,unfocused,invisible:u=0,1,2:c=1:w=1\x1b\\',
      );
      expect(kitty.notifications, NotificationProtocol.osc99);
      expect(kitty.sources['notifications'], CapabilitySource.answered);
      expect(kitty.notificationKeys['p'], {'title', 'body', '?'});
      expect(kitty.notificationKeys['o'], {
        'always',
        'unfocused',
        'invisible',
      });
      expect(kitty.notificationKeys['w'], {'1'});
      final konsole = await probe(
        const {'TERM': 'xterm-256color'},
        version: 'Konsole 23.08.5',
        reply:
            '\x1b]99;i=twk;p=?;p=title,body,buttons:a=report,focus:'
            'o=always,unfocus,invisible:u=0,1,2:c=1\x1b\\',
      );
      expect(konsole.notifications, NotificationProtocol.osc99);
      expect(konsole.notificationKeys, {
        'p': {'title', 'body', 'buttons'},
        'a': {'report', 'focus'},
        'o': {'always', 'unfocused', 'invisible'},
        'u': {'0', '1', '2'},
        'c': {'1'},
      });
    });

    test('without an answer by the name and version, else the environment; '
        'what the terminal declares first', () async {
      final known = await probe(const {
        'TERM': 'xterm-256color',
      }, version: 'Konsole 26.08.3');
      expect(known.notifications, NotificationProtocol.osc99);
      expect(known.notificationKeys, isEmpty);
      expect(known.sources['notifications'], CapabilitySource.environment);
      final none = await probe(const {'TERM': 'xterm-256color'});
      expect(none.notifications, NotificationProtocol.none);
      expect(none.sources['notifications'], CapabilitySource.assumed);
      final declared = await probe(
        const {'TERM': 'xterm-256color'},
        reply: '\x1b]99;i=twk:p=?;p=title,body\x1b\\',
        declaration: const TerminalDeclaration(
          notifications: NotificationProtocol.osc777,
        ),
      );
      expect(declared.notifications, NotificationProtocol.osc777);
      expect(declared.sources['notifications'], CapabilitySource.declared);
    });

    test('a declaration of them goes over the wire and back', () {
      const declaration = TerminalDeclaration(
        synchronizedOutput: true,
        leftRightMargins: false,
        graphemes: true,
        insertDelete: false,
      );
      expect(declaration.toJson(), {
        'synchronizedOutput': true,
        'leftRightMargins': false,
        'graphemes': true,
        'insertDelete': false,
      });
      expect(
        TerminalDeclaration.fromJson(declaration.toJson()),
        declaration,
      );
    });
  });
}
