import 'package:test/test.dart';
import 'package:twk_core/src/input/events.dart';
import 'package:twk_core/src/presenter.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_core/src/terminal/sequences.dart';
import 'package:twk_core/src/terminal/terminal.dart';
import 'package:twk_core/src/unicode/unicode.dart';

void main() {
  test('the brightness COLORFGBG declares, by its last field, the '
      'background', () {
    expect(brightnessFor({'COLORFGBG': '15;0'}), Brightness.dark);
    expect(brightnessFor({'COLORFGBG': '7;8'}), Brightness.dark);
    expect(brightnessFor({'COLORFGBG': '0;15'}), Brightness.light);
    expect(brightnessFor({'COLORFGBG': '0;default;7'}), Brightness.light);
    expect(brightnessFor({'COLORFGBG': '15;default'}), isNull);
    expect(brightnessFor({'COLORFGBG': ''}), isNull);
    expect(brightnessFor({}), isNull);
    // declared, not told: no brightness of the terminal's
    TerminalInfo info(int? bg) => TerminalInfo(
      caps: const TerminalCaps(),
      textMode: TextMode.graphemes,
      ambiguousWidth: 1,
      colorMode: ColorMode.trueColor,
      foregroundRgb: null,
      backgroundRgb: bg,
      inBandResize: false,
      graphemeMode: false,
      kittyKeyboard: false,
      answeredQueries: true,
      declaredBrightness: Brightness.light,
    );
    expect(info(null).brightness, isNull);
    expect(info(null).declaredBrightness, Brightness.light);
    expect(info(0x000000).brightness, Brightness.dark);
  });

  test('colors from the environment', () {
    expect(
      colorModeFor({'NO_COLOR': '1', 'COLORTERM': 'truecolor'}),
      ColorMode.none,
    );
    // no-color.org: an empty NO_COLOR doesn't turn colors off
    expect(
      colorModeFor({'NO_COLOR': '', 'COLORTERM': 'truecolor'}),
      ColorMode.trueColor,
    );
    expect(colorModeFor({'TERM': 'xterm-256color'}), ColorMode.ansi256);
    expect(colorModeFor({'TERM': 'dumb'}), ColorMode.none);
    // a dumb terminal started from a 24-bit one (a shell inside an
    // editor): what it inherited of the other says nothing of it
    expect(
      colorModeFor({'TERM': 'dumb', 'COLORTERM': 'truecolor'}),
      ColorMode.none,
    );
    expect(
      colorModeFor({'TERM': 'dumb', 'TERM_PROGRAM': 'WezTerm'}),
      ColorMode.none,
    );
    expect(colorModeFor({'TERM': 'xterm'}), ColorMode.ansi16);
    expect(colorModeFor({}, windows: true), ColorMode.trueColor);
  });

  test('styled underlines on all but Terminal.app', () {
    expect(styledUnderlinesFor({'TERM_PROGRAM': 'Apple_Terminal'}), isFalse);
    expect(styledUnderlinesFor({'TERM_PROGRAM': 'iTerm.app'}), isTrue);
    expect(styledUnderlinesFor({'TERM': 'xterm-kitty'}), isTrue);
    expect(styledUnderlinesFor({}), isTrue);
    // TERM_PROGRAM inherited from the Terminal.app it was started in
    for (final term in [
      'alacritty',
      'xterm-kitty',
      'foot-extra',
      'contour',
      'wezterm',
    ]) {
      expect(
        styledUnderlinesFor({'TERM': term, 'TERM_PROGRAM': 'Apple_Terminal'}),
        isTrue,
        reason: term,
      );
    }
    expect(
      styledUnderlinesFor({
        'TERM': 'xterm-256color',
        'TERM_PROGRAM': 'Apple_Terminal',
      }),
      isFalse,
    );
  });

  test('notifications by the terminal the environment names', () {
    const kitty = NotificationProtocol.osc99;
    const iterm = NotificationProtocol.osc9;
    const notify = NotificationProtocol.osc777;
    const none = NotificationProtocol.none;
    final terminals = <Map<String, String>, NotificationProtocol>{
      {'TERM': 'xterm-kitty'}: kitty,
      {'TERM': 'xterm-256color', 'TERM_PROGRAM': 'iTerm.app'}: iterm,
      {'TERM': 'xterm-256color', 'TERM_PROGRAM': 'WezTerm'}: notify,
      {'TERM': 'xterm-ghostty'}: notify,
      {'TERM': 'xterm-256color', 'TERM_PROGRAM': 'ghostty'}: notify,
      {'TERM': 'foot'}: notify,
      {'TERM': 'foot-extra'}: notify,
      {'TERM': 'rxvt-unicode-256color'}: notify,
      {'TERM': 'xterm-256color', 'WT_SESSION': 'b5c8'}: notify,
      {'TERM': 'xterm-256color', 'KONSOLE_VERSION': '221200'}: notify,
      {'TERM': 'xterm-256color', 'KONSOLE_VERSION': '220803'}: none,
      {'TERM': 'xterm-256color', 'VTE_VERSION': '7800'}: notify,
      {'TERM': 'xterm-256color', 'VTE_VERSION': '5003'}: none,
      {'TERM': 'alacritty'}: none,
      {'TERM': 'xterm-256color'}: none,
      {'TERM': 'xterm-256color', 'TERM_PROGRAM': 'Apple_Terminal'}: none,
      {'TERM': 'linux'}: none,
      {}: none,
      // the terminal's own TERM and TERM_PROGRAM come before variables
      // inherited from the one it was started in
      {'TERM': 'xterm-kitty', 'TERM_PROGRAM': 'iTerm.app'}: kitty,
      {'TERM_PROGRAM': 'WezTerm', 'KITTY_WINDOW_ID': '1'}: notify,
      {'TERM_PROGRAM': 'vscode', 'KITTY_WINDOW_ID': '1'}: none,
      {'TERM': 'dumb', 'VTE_VERSION': '7800'}: none,
    };
    for (final MapEntry(key: env, value: protocol) in terminals.entries) {
      expect(notificationProtocolFor(env), protocol, reason: '$env');
    }
  });

  test('notifications inside tmux or screen, by what the terminal outside '
      'set', () {
    const tmux = {
      'TERM': 'tmux-256color',
      'TERM_PROGRAM': 'tmux',
      'TMUX': '/tmp/tmux-1000/default,4242,0',
    };
    const screen = {'TERM': 'screen.xterm-256color', 'STY': '4242.pts-0.host'};
    final terminals = <Map<String, String>, NotificationProtocol>{
      {...tmux, 'KITTY_WINDOW_ID': '1'}: NotificationProtocol.osc99,
      {...tmux, 'WEZTERM_PANE': '0'}: NotificationProtocol.osc777,
      {...tmux, 'GHOSTTY_RESOURCES_DIR': '/usr/share/ghostty'}:
          NotificationProtocol.osc777,
      {...tmux, 'ITERM_SESSION_ID': 'w0t0p0:5E3B'}: NotificationProtocol.osc9,
      // passed on by ssh too
      {...tmux, 'LC_TERMINAL': 'iTerm2'}: NotificationProtocol.osc9,
      {...tmux, 'KONSOLE_VERSION': '250401'}: NotificationProtocol.osc777,
      {...tmux, 'VTE_VERSION': '8002'}: NotificationProtocol.osc777,
      tmux: NotificationProtocol.none,
      {...screen, 'TERM_PROGRAM': 'iTerm.app'}: NotificationProtocol.osc9,
      {...screen, 'WT_SESSION': 'b5c8'}: NotificationProtocol.osc777,
      screen: NotificationProtocol.none,
    };
    for (final MapEntry(key: env, value: protocol) in terminals.entries) {
      expect(notificationProtocolFor(env), protocol, reason: '$env');
    }
  });

  test('the multiplexer from the environment, also from a TERM passed on '
      'by ssh', () {
    expect(
      multiplexerFor({'TERM': 'screen-256color', 'TMUX': '/tmp/t,1,0'}),
      Multiplexer.tmux,
    );
    expect(
      multiplexerFor({'TERM': 'screen', 'STY': '4242.pts-0.host'}),
      Multiplexer.screen,
    );
    expect(multiplexerFor({'TERM': 'tmux-256color'}), Multiplexer.tmux);
    expect(
      multiplexerFor({'TERM': 'screen.xterm-256color'}),
      Multiplexer.screen,
    );
    expect(multiplexerFor({'TERM': 'xterm-kitty'}), Multiplexer.none);
    expect(multiplexerFor({}), Multiplexer.none);
  });

  test('a color is dark or light by its luma', () {
    const dark = [0x000000, 0x101218, 0x1e1e2e, 0x002b36, 0x7f7f7f, 0x0000ff];
    const light = [0xffffff, 0xeff1f5, 0xfdf6e3, 0x808080, 0x00ff00];
    expect(dark.map(Brightness.ofRgb), everyElement(Brightness.dark));
    expect(light.map(Brightness.ofRgb), everyElement(Brightness.light));
  });

  test('the terminal is dark or light by the background the probe got', () {
    TerminalInfo info(int? background) => TerminalInfo(
      caps: const TerminalCaps(),
      textMode: TextMode.graphemes,
      ambiguousWidth: 1,
      colorMode: ColorMode.trueColor,
      foregroundRgb: null,
      backgroundRgb: background,
      inBandResize: false,
      graphemeMode: false,
      kittyKeyboard: false,
      answeredQueries: true,
    );
    expect(info(0x101218).brightness, Brightness.dark);
    expect(info(0xeff1f5).brightness, Brightness.light);
    expect(info(null).brightness, isNull);
    expect(info(null).colorSchemeReports, isFalse);
  });
}
