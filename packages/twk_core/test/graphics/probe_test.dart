// The protocol images are shown with: what the probe asks and is told
// (kitty's graphics query, XTVERSION, DA1's sixel attribute, the cell size
// in pixels), the environment, and what TWK_GRAPHICS or the options say.
import 'package:test/test.dart';
import 'package:twk_core/src/terminal/terminal.dart';
import 'package:twk_core/twk_core.dart';

import '../terminal/fake_link.dart';

/// Opens a terminal on a link of [env] that answers the probe with
/// [answers] and DA1 [da1]; returns what it found and what it asked.
Future<(TerminalCaps, String)> probe(
  Map<String, String> env, {
  String answers = '',
  String da1 = '\x1b[?62;22c',
  GraphicsProtocol? graphics,
}) async {
  final link = FakeLink(environment: env)..type('$answers$da1');
  final term = await openOwnOrShell(
    link,
    TerminalOptions(
      probeTimeout: const Duration(seconds: 5),
      graphics: graphics,
    ),
  );
  final asked = link.text;
  await term.close();
  return (term.info.caps, asked);
}

void main() {
  const kittyOk = '\x1b_Gi=31;OK\x1b\\';
  const cellSize = '\x1b[6;20;9t';

  test('kitty answers its graphics query: kitty, and the cell size', () async {
    final (caps, asked) = await probe(const {
      'TERM': 'xterm-kitty',
    }, answers: '$kittyOk${'\x1bP>|kitty(0.39.1)\x1b\\'}$cellSize');
    expect(asked, contains('\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\'));
    expect(asked, contains('\x1b[16t'));
    expect(asked, contains('\x1b[>0q'));
    expect(caps.graphics, GraphicsProtocol.kitty);
    expect(caps.graphicsMultiplexer, Multiplexer.none);
    expect((caps.cellPixelWidth, caps.cellPixelHeight), (9, 20));
  });

  test(
    "Konsole answers kitty's graphics query: kitty, and Konsole's images",
    () async {
      const konsole = {'TERM': 'xterm-256color', 'KONSOLE_VERSION': '260802'};
      final (caps, _) = await probe(
        konsole,
        answers: '$kittyOk${'\x1bP>|Konsole 26.08.2\x1b\\'}$cellSize',
        da1: '\x1b[?62;1;4c',
      );
      expect(caps.graphics, GraphicsProtocol.kitty);
      expect(caps.konsoleImages, isTrue);
      expect((caps.cellPixelWidth, caps.cellPixelHeight), (9, 20));
      // told sixel, it is still Konsole that shows the images
      final (sixel, _) = await probe(
        konsole,
        answers: '\x1bP>|Konsole 26.08.2\x1b\\',
        graphics: GraphicsProtocol.sixel,
      );
      expect(sixel.konsoleImages, isTrue);
      final (kitty, _) = await probe(const {
        'TERM': 'xterm-kitty',
      }, answers: '$kittyOk${'\x1bP>|kitty(0.39.1)\x1b\\'}');
      expect(kitty.konsoleImages, isFalse);
    },
  );

  test('sixel by the device attributes, iTerm2 by the name the terminal '
      'tells', () async {
    final (sixel, _) = await probe(const {
      'TERM': 'xterm-256color',
    }, da1: '\x1b[?65;4;22c');
    expect(sixel.graphics, GraphicsProtocol.sixel);
    final (iterm, _) = await probe(const {
      'TERM': 'xterm-256color',
    }, answers: '\x1bP>|iTerm2 3.5.4\x1b\\');
    expect(iterm.graphics, GraphicsProtocol.iterm2);
    final (none, _) = await probe(const {'TERM': 'xterm-256color'});
    expect(none.graphics, GraphicsProtocol.none);
    expect((none.cellPixelWidth, none.cellPixelHeight), (0, 0));
  });

  test(
    'given by the options or TWK_GRAPHICS: nothing asked about it',
    () async {
      final (given, asked) = await probe(
        const {'TERM': 'xterm-kitty'},
        answers: kittyOk,
        graphics: GraphicsProtocol.sixel,
      );
      expect(given.graphics, GraphicsProtocol.sixel);
      expect(asked, isNot(contains('\x1b_G')));
      final (named, asked2) = await probe(const {
        'TERM': 'xterm-kitty',
        'TWK_GRAPHICS': 'none',
      }, answers: kittyOk);
      expect(named.graphics, GraphicsProtocol.none);
      expect(asked2, isNot(contains('\x1b_G')));
    },
  );

  test("inside tmux: tmux's own sixel, kitty's through it", () async {
    final (sixel, asked) = await probe(const {
      'TERM': 'tmux-256color',
      'TMUX': '/tmp/tmux-1000/default,1,0',
    }, da1: '\x1b[?62;4c');
    expect(asked, isNot(contains('\x1b_G')));
    expect(sixel.graphics, GraphicsProtocol.sixel);
    expect(sixel.graphicsMultiplexer, Multiplexer.none);
    final (kitty, _) = await probe(const {
      'TERM': 'tmux-256color',
      'TMUX': '/tmp/tmux-1000/default,1,0',
      'KITTY_WINDOW_ID': '1',
    });
    expect(kitty.graphics, GraphicsProtocol.kitty);
    expect(kitty.graphicsMultiplexer, Multiplexer.tmux);
  });

  test('from the environment', () {
    GraphicsProtocol of(Map<String, String> env) => graphicsProtocolFor(env);
    expect(of({'TERM_PROGRAM': 'iTerm.app'}), GraphicsProtocol.iterm2);
    expect(of({'TERM_PROGRAM': 'WezTerm'}), GraphicsProtocol.iterm2);
    expect(of({'LC_TERMINAL': 'iTerm2'}), GraphicsProtocol.iterm2);
    expect(of({'TERM': 'xterm-kitty'}), GraphicsProtocol.none);
    expect(of({'TWK_GRAPHICS': 'kitty'}), GraphicsProtocol.kitty);
    expect(of({'TWK_GRAPHICS': 'pixels'}), GraphicsProtocol.none);
    expect(
      graphicsProtocolFor({'STY': '1.pts'}, kittyGraphics: true, sixel: true),
      GraphicsProtocol.none,
      reason: 'screen passes no images on',
    );
    expect(
      graphicsProtocolFor({}, kittyGraphics: true, version: 'WezTerm 2024'),
      GraphicsProtocol.kitty,
    );
  });
}
