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
    }) async {
      final link = FakeLink(environment: env)
        ..type(
          '${version == null ? '' : '\x1bP>|$version\x1b\\'}'
          '${mode == null ? '' : '\x1b[?2026;$mode\$y'}'
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
  });
}
