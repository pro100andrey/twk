// Konsole's lines (TerminalCaps.konsoleLines): each as long as what was
// written on it, ICH padding it with blanks in the default colours and DCH
// ending it with blanks at that length rather than at the right margin;
// known by the name the terminal tells or else its environment, never
// inside a multiplexer (konsoleLinesFor).
import 'package:test/test.dart';
import 'package:twk_core/src/terminal/terminal.dart' show konsoleLinesFor;
import 'package:twk_core/twk_core.dart';

import 'fake_link.dart';

const _konsole = {'TERM': 'xterm-256color', 'KONSOLE_VERSION': '260802'};

void main() {
  test('Konsole holds its lines so; xterm, kitty and multiplexers not', () {
    expect(konsoleLinesFor(_konsole), isTrue);
    expect(konsoleLinesFor(const {}, version: 'Konsole 26.08.2'), isTrue);
    // the name told wins over a variable left by the terminal it ran from
    expect(konsoleLinesFor(_konsole, version: 'XTerm(397)'), isFalse);
    expect(konsoleLinesFor({..._konsole, 'TMUX': '/tmp/tmux'}), isFalse);
    expect(konsoleLinesFor({..._konsole, 'STY': '1.pts-0'}), isFalse);
    expect(konsoleLinesFor({..._konsole, 'TERM': 'screen-256color'}), isFalse);
    expect(konsoleLinesFor({..._konsole, 'TERM': 'tmux-256color'}), isFalse);
    expect(konsoleLinesFor(const {'TERM': 'xterm-kitty'}), isFalse);
    expect(konsoleLinesFor(const {'TERM': 'xterm-256color'}), isFalse);
  });

  group('the probe', () {
    Future<TerminalInfo> probe(
      Map<String, String> env, {
      String? version,
    }) async {
      final link = FakeLink(environment: env)
        ..type(
          '${version == null ? '' : '\x1bP>|$version\x1b\\'}'
          '\x1b[?2026;2\$y\x1b[?62;22c',
        );
      final term = await Terminal.overLink(
        link,
        const TerminalOptions(probeTimeout: Duration(seconds: 5)),
      );
      final info = term.info;
      await term.close();
      return info;
    }

    test("gives the presenter Konsole's lines by its environment or the "
        'name it tells, and says so', () async {
      for (final info in [
        await probe(_konsole),
        await probe(
          const {'TERM': 'xterm-256color'},
          version: 'Konsole 26.08.2',
        ),
      ]) {
        expect(info.caps.konsoleLines, isTrue);
        expect('$info', contains('konsoleLines=true'));
      }
    });

    test(
      'not on xterm, a name told over a Konsole started from, tmux',
      () async {
        for (final info in [
          await probe(const {'TERM': 'xterm-256color'}),
          await probe(_konsole, version: 'XTerm(397)'),
          await probe({..._konsole, 'TMUX': '/tmp/tmux-1000/default,1,0'}),
        ]) {
          expect(info.caps.konsoleLines, isFalse);
          expect('$info', contains('konsoleLines=false'));
        }
      },
    );
  });
}
