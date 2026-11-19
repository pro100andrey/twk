// The pointer's shape (OSC 22) and the progress in the tab (OSC 9;4): the
// sequences, wrapped for a multiplexer, and the terminals known to show
// them, or to draw the block sextants, by their environment; GNU screen's
// pieces of a sequence passed on.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/src/terminal/sequences.dart'
    show pointerNamesFor, progressReportsFor, sextantsFor;
import 'package:twk_core/twk_core.dart';

void main() {
  group('pointer shape', () {
    test("OSC 22 with the CSS name, empty for the terminal's own", () {
      expect(pointerShapeSequence(PointerShape.text), '\x1b]22;text\x1b\\');
      expect(
        pointerShapeSequence(PointerShape.arrow),
        '\x1b]22;default\x1b\\',
      );
      expect(
        pointerShapeSequence(PointerShape.nwseResize),
        '\x1b]22;nwse-resize\x1b\\',
      );
      expect(pointerShapeSequence(null), '\x1b]22;\x1b\\');
    });

    test("OSC 22 with the X cursor font's name, empty where it has none", () {
      String x11(PointerShape? shape) =>
          pointerShapeSequence(shape, PointerNames.x11);
      expect(x11(PointerShape.ewResize), '\x1b]22;sb_h_double_arrow\x1b\\');
      expect(x11(PointerShape.nsResize), '\x1b]22;sb_v_double_arrow\x1b\\');
      expect(x11(PointerShape.text), '\x1b]22;xterm\x1b\\');
      expect(x11(PointerShape.pointer), '\x1b]22;hand2\x1b\\');
      expect(x11(PointerShape.grabbing), '\x1b]22;fleur\x1b\\');
      expect(x11(PointerShape.nwseResize), '\x1b]22;\x1b\\');
      expect(x11(null), '\x1b]22;\x1b\\');
    });

    test("the names of kitty's protocol, each once", () {
      expect(PointerShape.values.map((s) => s.css), [
        'alias',
        'cell',
        'copy',
        'crosshair',
        'default',
        'e-resize',
        'ew-resize',
        'grab',
        'grabbing',
        'help',
        'move',
        'n-resize',
        'ne-resize',
        'nesw-resize',
        'no-drop',
        'not-allowed',
        'ns-resize',
        'nw-resize',
        'nwse-resize',
        'pointer',
        'progress',
        's-resize',
        'se-resize',
        'sw-resize',
        'text',
        'vertical-text',
        'w-resize',
        'wait',
        'zoom-in',
        'zoom-out',
      ]);
    });
  });

  group('progress', () {
    test('OSC 9;4 with the state and the percent, cut to 0…100', () {
      expect(
        progressSequence(ProgressState.normal, percent: 40),
        '\x1b]9;4;1;40\x1b\\',
      );
      expect(
        progressSequence(ProgressState.error, percent: 140),
        '\x1b]9;4;2;100\x1b\\',
      );
      expect(
        progressSequence(ProgressState.paused, percent: -3),
        '\x1b]9;4;4;0\x1b\\',
      );
      expect(progressSequence(ProgressState.error), '\x1b]9;4;2\x1b\\');
    });

    test('none and indeterminate without a percent', () {
      expect(
        progressSequence(ProgressState.none, percent: 50),
        '\x1b]9;4;0\x1b\\',
      );
      expect(
        progressSequence(ProgressState.indeterminate, percent: 50),
        '\x1b]9;4;3\x1b\\',
      );
    });
  });

  group('known to show the pointer shape', () {
    test('by CSS names: by its own TERM, its TERM_PROGRAM or the variables '
        'it sets', () {
      for (final env in const [
        {'TERM': 'xterm-kitty'},
        {'TERM': 'xterm-ghostty'},
        {'TERM': 'foot'},
        {'TERM': 'foot-extra'},
        {'TERM_PROGRAM': 'ghostty'},
        {'TERM_PROGRAM': 'rio'},
        {'TERM': 'xterm-256color', 'KITTY_WINDOW_ID': '1'},
        {'GHOSTTY_RESOURCES_DIR': '/usr/share/ghostty'},
        {'KONSOLE_VERSION': '260400'},
      ]) {
        expect(pointerNamesFor(env), PointerNames.css, reason: '$env');
      }
    });

    test("by the X cursor font's: iTerm2 3.7 on by its TERM_PROGRAM or "
        'XTVERSION, xterm 367 on by XTVERSION over what it was started '
        'from, or by XTERM_VERSION where it told no name', () {
      for (final (env, version) in const [
        ({'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.7.0'}, ''),
        ({'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.7.7'}, ''),
        (<String, String>{}, 'iTerm2 3.7.2'),
        ({'TERM': 'xterm-256color'}, 'XTerm(367)'),
        ({'KONSOLE_VERSION': '260400'}, 'XTerm(390)'),
        // XTVERSION not asked
        ({'TERM': 'xterm-256color', 'XTERM_VERSION': 'XTerm(390)'}, ''),
      ]) {
        expect(
          pointerNamesFor(env, version: version),
          PointerNames.x11,
          reason: '$env $version',
        );
      }
    });

    test('not by other names, an earlier Konsole, iTerm2 or xterm, another '
        'TERM_PROGRAM, or inside tmux or screen', () {
      for (final (env, version) in const [
        (<String, String>{}, ''),
        ({'TERM': 'xterm-256color'}, ''),
        ({'TERM_PROGRAM': 'iTerm.app'}, ''),
        ({'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.6.11'}, ''),
        (<String, String>{}, 'iTerm2 3.6.11'),
        ({'XTERM_VERSION': 'XTerm(366)'}, ''),
        // another terminal, which told its name, started from xterm
        ({'XTERM_VERSION': 'XTerm(390)'}, 'mlterm(3.9.3)'),
        (<String, String>{}, 'XTerm(366)'),
        ({'TERM_PROGRAM': 'Apple_Terminal'}, ''),
        ({'TERM_PROGRAM': 'mintty'}, ''),
        ({'TERM_PROGRAM': 'contour'}, ''),
        ({'TERM_PROGRAM': 'WezTerm', 'WEZTERM_PANE': '0'}, ''),
        ({'VTE_VERSION': '8200'}, ''),
        ({'WT_SESSION': 'x'}, ''),
        ({'KONSOLE_VERSION': '251200'}, ''),
        ({'TERM_PROGRAM': 'vscode', 'KITTY_WINDOW_ID': '1'}, ''),
        (
          {
            'TERM': 'tmux-256color',
            'TMUX': '/tmp/t,1,0',
            'KITTY_WINDOW_ID': '1',
          },
          '',
        ),
        ({'TERM_PROGRAM': 'tmux', 'TMUX': '/tmp/t,1,0'}, 'iTerm2 3.7.2'),
        (
          {
            'TERM': 'screen.xterm-256color',
            'STY': '1.pts',
            'KITTY_WINDOW_ID': '1',
          },
          '',
        ),
      ]) {
        expect(
          pointerNamesFor(env, version: version),
          isNull,
          reason: '$env $version',
        );
      }
    });
  });

  group('known to show the progress', () {
    test('by its environment, its version where an earlier one takes it '
        'for a notification', () {
      for (final (env, version) in const [
        ({'WT_SESSION': 'x'}, ''),
        ({'ConEmuPID': '42'}, ''),
        ({'ConEmuANSI': 'ON'}, ''),
        ({'TERM': 'xterm-ghostty'}, ''),
        ({'TERM_PROGRAM': 'ghostty'}, ''),
        ({'GHOSTTY_RESOURCES_DIR': '/usr/share/ghostty'}, ''),
        ({'VTE_VERSION': '8000'}, ''),
        ({'KONSOLE_VERSION': '260400'}, ''),
        ({'TERM': 'xterm-kitty'}, 'kitty(0.38.0)'),
        ({'KITTY_WINDOW_ID': '1'}, 'kitty(0.44.1)'),
        ({'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.6.6'}, ''),
        (
          {'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.7.0beta1'},
          '',
        ),
        ({'TERM_PROGRAM': 'mintty', 'TERM_PROGRAM_VERSION': '3.4.2'}, ''),
        ({'TERM_PROGRAM': 'rio', 'TERM_PROGRAM_VERSION': '0.3.1'}, ''),
        ({'TERM_PROGRAM': 'contour', 'TERM_PROGRAM_VERSION': '0.7.0'}, ''),
        (
          {
            'TERM': 'tmux-256color',
            'TMUX': 'x',
            'TERM_PROGRAM': 'tmux',
            'TERM_PROGRAM_VERSION': '3.7',
          },
          '',
        ),
      ]) {
        expect(
          progressReportsFor(env, version: version),
          isTrue,
          reason: '$env $version',
        );
      }
    });

    test('not where its version is earlier or not known, nor where it '
        'shows none', () {
      for (final (env, version) in const [
        (<String, String>{}, ''),
        ({'TERM': 'xterm-256color'}, ''),
        ({'TERM': 'xterm-kitty'}, ''),
        ({'TERM': 'xterm-kitty'}, 'kitty(0.37.0)'),
        ({'KITTY_WINDOW_ID': '1'}, ''),
        ({'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.6.5'}, ''),
        ({'TERM_PROGRAM': 'iTerm.app'}, ''),
        ({'TERM': 'foot'}, ''),
        ({'TERM_PROGRAM': 'WezTerm', 'WEZTERM_PANE': '0'}, ''),
        ({'TERM_PROGRAM': 'mintty', 'TERM_PROGRAM_VERSION': '3.4.1'}, ''),
        ({'TERM_PROGRAM': 'contour', 'TERM_PROGRAM_VERSION': '0.6.2'}, ''),
        ({'VTE_VERSION': '7800'}, ''),
        ({'KONSOLE_VERSION': '251200'}, ''),
        ({'TERM_PROGRAM': 'Apple_Terminal', 'WT_SESSION': 'x'}, ''),
        (
          {
            'TERM': 'tmux-256color',
            'TMUX': 'x',
            'TERM_PROGRAM': 'tmux',
            'TERM_PROGRAM_VERSION': '3.6a',
          },
          '',
        ),
        ({'TERM': 'tmux-256color', 'WT_SESSION': 'x'}, ''),
        ({'TERM': 'screen', 'STY': '1.pts', 'WT_SESSION': 'x'}, ''),
        ({'TERM': 'dumb', 'WT_SESSION': 'x'}, ''),
      ]) {
        expect(
          progressReportsFor(env, version: version),
          isFalse,
          reason: '$env $version',
        );
      }
    });
  });

  group('known to draw the block sextants', () {
    test('by its TERM, its TERM_PROGRAM and version, or the variables it '
        'sets', () {
      for (final env in const [
        {'TERM': 'xterm-kitty'},
        {'TERM': 'xterm-ghostty'},
        {'TERM': 'foot'},
        {'TERM': 'foot-extra'},
        {'TERM_PROGRAM': 'ghostty'},
        {'TERM_PROGRAM': 'WezTerm', 'TERM_PROGRAM_VERSION': '20210814-124438'},
        {'TERM_PROGRAM': 'WezTerm', 'TERM_PROGRAM_VERSION': '20240203-110809'},
        {'TERM_PROGRAM': 'contour', 'TERM_PROGRAM_VERSION': '0.3.1'},
        {'TERM_PROGRAM': 'contour', 'TERM_PROGRAM_VERSION': '0.6.1.7494'},
        {'TERM_PROGRAM': 'rio', 'TERM_PROGRAM_VERSION': '0.4.6'},
        {'TERM': 'xterm-256color', 'KITTY_WINDOW_ID': '1'},
        {'GHOSTTY_RESOURCES_DIR': '/usr/share/ghostty'},
        {'VTE_VERSION': '7800'},
        {'VTE_VERSION': '8200'},
        {'KONSOLE_VERSION': '220400'},
        {'KONSOLE_VERSION': '260400'},
      ]) {
        expect(sextantsFor(env), isTrue, reason: '$env');
      }
    });

    test('by the name and version it tells (XTVERSION)', () {
      for (final version in const [
        'kitty(0.19.3)',
        'kitty(0.35.2)',
        'foot(1.16.2)',
        'ghostty 1.0.0',
        'WezTerm 20210814-124438-54e29167',
        'WezTerm 20240203-110809-5046fc22',
        'VTE(7800)',
        'VTE(8200)',
      ]) {
        expect(
          sextantsFor(const {}, version: version),
          isTrue,
          reason: version,
        );
      }
      // the name it tells over the environment of the one it was started from
      expect(
        sextantsFor(const {'KITTY_WINDOW_ID': '1'}, version: 'kitty(0.35.2)'),
        isTrue,
      );
      expect(
        sextantsFor(const {'TERM': 'xterm-256color'}, version: 'foot(1.16.2)'),
        isTrue,
      );
    });

    test('not by an earlier one, one not known to, another TERM_PROGRAM, '
        'or inside tmux or screen', () {
      for (final (env, version) in const [
        (<String, String>{}, ''),
        ({'TERM': 'xterm-256color'}, ''),
        ({'TERM': 'alacritty'}, ''),
        // Ghostty before 1.0, over its own TERM
        ({'TERM': 'xterm-ghostty'}, 'ghostty 0.9.1'),
        ({'TERM': 'xterm'}, 'XTerm(390)'),
        ({'TERM_PROGRAM': 'Apple_Terminal'}, ''),
        ({'TERM_PROGRAM': 'iTerm.app', 'TERM_PROGRAM_VERSION': '3.6.6'}, ''),
        (<String, String>{}, 'iTerm2 3.6.6'),
        ({'TERM_PROGRAM': 'mintty', 'TERM_PROGRAM_VERSION': '3.7.8'}, ''),
        ({'TERM_PROGRAM': 'vscode'}, ''),
        ({'WT_SESSION': 'x'}, ''),
        ({'TERM_PROGRAM': 'WezTerm', 'TERM_PROGRAM_VERSION': '20210813'}, ''),
        ({'TERM_PROGRAM': 'WezTerm'}, ''),
        ({'TERM_PROGRAM': 'contour', 'TERM_PROGRAM_VERSION': '0.3.0'}, ''),
        ({'TERM_PROGRAM': 'rio', 'TERM_PROGRAM_VERSION': '0.4.5'}, ''),
        ({'TERM_PROGRAM': 'rio'}, ''),
        ({'VTE_VERSION': '7600'}, ''),
        ({'KONSOLE_VERSION': '211200'}, ''),
        (<String, String>{}, 'kitty(0.19.2)'),
        (<String, String>{}, 'WezTerm 20210813-000000-abc'),
        (<String, String>{}, 'VTE(7600)'),
        ({'TERM_PROGRAM': 'vscode', 'KITTY_WINDOW_ID': '1'}, ''),
        (
          {
            'TERM': 'tmux-256color',
            'TMUX': '/tmp/t,1,0',
            'KITTY_WINDOW_ID': '1',
          },
          '',
        ),
        ({'TERM_PROGRAM': 'tmux', 'TMUX': '/tmp/t,1,0'}, 'kitty(0.35.2)'),
        (
          {'TERM': 'screen.xterm-256color', 'STY': '1.pts', 'TERM_PROGRAM': ''},
          'foot(1.16.2)',
        ),
      ]) {
        expect(
          sextantsFor(env, version: version),
          isFalse,
          reason: '$env $version',
        );
      }
    });
  });

  test("screen's pieces hold whole characters, counted in UTF-8 bytes", () {
    final title = '${'x' * 245}🧪é🧪';
    final s = passthroughSequence('\x1b]2;$title\x1b\\', Multiplexer.screen);
    final pieces = [
      for (final m in RegExp('\x1bP(.*?)\x1b\\\\').allMatches(s)) m[1]!,
    ];
    expect(pieces.map((p) => '\x1bP$p\x1b\\').join(), s);
    expect(pieces.join(), '\x1b]2;$title\x07');
    // ESC ] 2 ; and 245 x leave 3 bytes of the first: the emoji's 4 go
    // on
    expect(pieces.map((p) => utf8.encode(p).length), [249, 11]);
  });
}
