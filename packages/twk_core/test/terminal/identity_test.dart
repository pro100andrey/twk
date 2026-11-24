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
    show konsoleLinesFor, notificationProtocolFor;
import 'package:twk_core/twk_core.dart';

import 'fake_link.dart';

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
        'unknown',
      );
    });

    test('else by the variables a terminal sets for its programs', () {
      expect(
        '${identifyTerminal(const {'KONSOLE_VERSION': '260803'})}',
        'konsole 26.8.3',
      );
      expect(
        '${identifyTerminal(const {'VTE_VERSION': '8002'})}',
        'vte 0.80.2',
      );
      expect('${identifyTerminal(const {'TERM': 'xterm'})}', 'unknown');
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
      for (final (env, version) in [
        (konsole, 'XTerm(397)'),
        ({...konsole, 'TERM': 'xterm-kitty'}, ''),
        ({...konsole, 'TERM_PROGRAM': 'vscode'}, ''),
      ]) {
        expect(
          identifyTerminal(env, version: version).terminal,
          isNull,
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
