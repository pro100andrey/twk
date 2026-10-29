import 'package:test/test.dart';
import 'package:twk/twk.dart' show ColorMode;
import 'package:twk_cli/twk_cli.dart';
import 'package:twk_core/twk_core.dart' show colorModeFor;

CliCapabilities _detect({
  Map<String, String> env = const {},
  bool input = true,
  bool output = true,
  bool supportsAnsi = true,
  bool? ansi,
  bool? interactive,
  bool? hyperlinks,
  bool windows = false,
}) => CliCapabilities.detect(
  environment: env,
  inputIsTerminal: input,
  outputIsTerminal: output,
  outputSupportsAnsi: supportsAnsi,
  ansi: ansi,
  interactive: interactive,
  hyperlinks: hyperlinks,
  windows: windows,
);

void main() {
  group('ansi', () {
    test('on a terminal that supports escapes', () {
      expect(_detect().ansi, isTrue);
      expect(_detect(supportsAnsi: false).ansi, isFalse);
      expect(_detect(output: false).ansi, isFalse);
    });

    test('off under NO_COLOR and TERM=dumb', () {
      expect(_detect(env: {'NO_COLOR': '1'}).ansi, isFalse);
      expect(_detect(env: {'NO_COLOR': ''}).ansi, isTrue);
      expect(_detect(env: {'TERM': 'dumb'}).ansi, isFalse);
      // what the terminal it was started from left says nothing of it
      expect(
        _detect(env: {'TERM': 'dumb', 'COLORTERM': 'truecolor'}).ansi,
        isFalse,
      );
    });

    test('FORCE_COLOR wins over the rest', () {
      expect(_detect(output: false, env: {'FORCE_COLOR': '1'}).ansi, isTrue);
      expect(_detect(env: {'FORCE_COLOR': '0'}).ansi, isFalse);
      expect(_detect(env: {'FORCE_COLOR': 'false'}).ansi, isFalse);
      expect(
        _detect(env: {'FORCE_COLOR': '1', 'NO_COLOR': '1'}).ansi,
        isTrue,
      );
    });

    test('off where TWK_PLAIN asks for plain text, FORCE_COLOR too', () {
      expect(_detect(env: {'TWK_PLAIN': '1'}).ansi, isFalse);
      expect(_detect(env: {'TWK_PLAIN': 'true'}).ansi, isFalse);
      expect(_detect(env: {'TWK_PLAIN': '0'}).ansi, isTrue);
      expect(
        _detect(env: {'TWK_PLAIN': '1', 'FORCE_COLOR': '1'}).ansi,
        isFalse,
      );
      expect(_detect(env: {'TWK_PLAIN': '1'}, ansi: true).ansi, isTrue);
    });

    test('--no-color wins over FORCE_COLOR', () {
      expect(_detect(env: {'FORCE_COLOR': '1'}, ansi: false).ansi, isFalse);
    });
  });

  group('input', () {
    test('interactive on a terminal outside CI', () {
      expect(_detect().interactiveInput, isTrue);
      expect(_detect(input: false).interactiveInput, isFalse);
      expect(_detect(env: {'CI': 'true'}).interactiveInput, isFalse);
      expect(_detect(env: {'CI': '0'}).interactiveInput, isTrue);
      expect(_detect(env: {'CI': 'false'}).interactiveInput, isTrue);
    });

    test('nobody answers wherever the core sees CI', () {
      for (final name in [
        'CONTINUOUS_INTEGRATION',
        'BUILD_NUMBER',
        'RUN_ID',
      ]) {
        expect(_detect(env: {name: '1'}).interactiveInput, isFalse);
        expect(_detect(env: {name: '0'}).interactiveInput, isTrue);
        expect(
          _detect(env: {name: '1', 'CI': 'false'}).interactiveInput,
          isTrue,
        );
      }
    });

    test('--no-input refuses, true asks under CI but not on a pipe', () {
      expect(_detect(interactive: false).interactiveInput, isFalse);
      expect(
        _detect(env: {'CI': '1'}, interactive: true).interactiveInput,
        isTrue,
      );
      expect(
        _detect(input: false, interactive: true).interactiveInput,
        isFalse,
      );
    });
  });

  group('mode', () {
    test('interactive where somebody answers and output redraws', () {
      expect(_detect().mode, CliMode.interactive);
    });

    test('plain where output takes no ANSI or is a pipe', () {
      expect(_detect(env: {'NO_COLOR': '1'}).mode, CliMode.plain);
      expect(_detect(output: false).mode, CliMode.plain);
      expect(_detect(ansi: false).mode, CliMode.plain);
      expect(_detect(env: {'TWK_PLAIN': '1'}).mode, CliMode.plain);
      // styled, but not on a terminal: it does not redraw
      expect(
        _detect(output: false, env: {'FORCE_COLOR': '1'}).mode,
        CliMode.plain,
      );
    });

    test('nonInteractive where nobody answers', () {
      expect(_detect(env: {'CI': '1'}).mode, CliMode.nonInteractive);
      // Jenkins, TeamCity
      expect(
        _detect(env: {'BUILD_NUMBER': '42'}).mode,
        CliMode.nonInteractive,
      );
      expect(_detect(input: false).mode, CliMode.nonInteractive);
      expect(_detect(interactive: false).mode, CliMode.nonInteractive);
    });
  });

  test('hyperlinks follow styled output on a terminal', () {
    expect(_detect().hyperlinks, isTrue);
    expect(_detect(env: {'NO_COLOR': '1'}).hyperlinks, isFalse);
    expect(_detect(hyperlinks: false).hyperlinks, isFalse);
    expect(_detect(output: false, hyperlinks: true).hyperlinks, isTrue);
  });

  test('colors by COLORTERM and TERM', () {
    expect(
      _detect(env: {'COLORTERM': 'truecolor'}).colorMode,
      ColorMode.trueColor,
    );
    expect(
      _detect(env: {'TERM': 'xterm-256color'}).colorMode,
      ColorMode.ansi256,
    );
    expect(_detect(env: {'TERM': 'xterm'}).colorMode, ColorMode.ansi16);
  });

  test('colors by TERM_PROGRAM and on Windows, as the core tells', () {
    for (final program in ['WezTerm', 'iTerm.app', 'ghostty']) {
      expect(
        _detect(env: {'TERM': 'xterm', 'TERM_PROGRAM': program}).colorMode,
        ColorMode.trueColor,
        reason: program,
      );
    }
    expect(
      _detect(
        env: {'TERM': 'xterm', 'TERM_PROGRAM': 'Apple_Terminal'},
      ).colorMode,
      ColorMode.ansi256,
    );
    expect(_detect(windows: true).colorMode, ColorMode.trueColor);
    for (final env in [
      {'TERM': 'xterm', 'TERM_PROGRAM': 'WezTerm'},
      {'COLORTERM': 'truecolor', 'TERM_PROGRAM': 'Apple_Terminal'},
      {'TERM': 'xterm-256color'},
      {'TERM': 'dumb'},
      {'NO_COLOR': '1', 'TERM': 'xterm-256color'},
    ]) {
      final core = colorModeFor(env);
      expect(
        _detect(env: {...env, 'FORCE_COLOR': '1'}).colorMode,
        core == ColorMode.none ? ColorMode.ansi16 : core,
        reason: '$env',
      );
    }
  });

  test('underline styles on all terminals but Terminal.app', () {
    expect(_detect().styledUnderlines, isTrue);
    expect(
      _detect(env: {'TERM_PROGRAM': 'iTerm.app'}).styledUnderlines,
      isTrue,
    );
    expect(
      _detect(env: {'TERM_PROGRAM': 'Apple_Terminal'}).styledUnderlines,
      isFalse,
    );
  });

  test('the error output is the output by default', () {
    const caps = CliCapabilities(
      ansi: false,
      interactiveInput: false,
      outputIsTerminal: true,
    );
    expect(caps.errorIsTerminal, isTrue);
    expect(caps.hyperlinks, isFalse);
  });
}
