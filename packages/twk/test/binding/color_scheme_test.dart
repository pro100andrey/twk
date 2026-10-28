// The terminal's color scheme under runApp: the app in the brightness of
// the terminal's background, switched live by its color scheme reports,
// and blended with the default colors the terminal reports after them;
// last in a pseudo-terminal (tool/pty_run.py --scheme) running
// color_scheme_app.dart.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, runProcess;

import 'harness.dart';

/// `theme` and the brightness of the theme at [state], on its background.
Widget showTheme(ProbeState state) {
  final theme = Theme.of(state.context);
  return Box(
    style: theme.background,
    child: Text('theme ${theme.brightness.name}', style: theme.text),
  );
}

void main() {
  // the app run in a pseudo-terminal, compiled once
  late String app;
  setUpAll(
    () async => app = await compiledProgram(
      'test/binding/color_scheme_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  test("the app is in the brightness of the terminal's background, dark "
      'when the terminal did not tell it', () async {
    for (final (background, brightness) in [
      (null, 'dark'),
      (0x101218, 'dark'),
      (0xeff1f5, 'light'),
    ]) {
      final key = GlobalKey<ProbeState>();
      final run = Run(
        Probe(
          key: key,
          (s) => Label(TerminalBrightness.of(s.context).name),
        ),
        backgroundRgb: background,
      );
      await run.settle();
      expect(run.rows.first, brightness, reason: 'background $background');
      AppBinding.of(key.currentContext!).quit();
      await run.ended();
    }
  });

  test('a color scheme report switches Theme.adaptive live: what reads the '
      'theme is rebuilt and nothing else, and the listeners get the '
      'report', () async {
    final reader = GlobalKey<ProbeState>();
    final other = GlobalKey<ProbeState>();
    final reports = <InputEvent>[];
    final run = Run(
      InputListener(
        onEvent: (e) {
          if (e is ColorSchemeReport) {
            reports.add(e);
          }
          return false;
        },
        child: Theme.adaptive(
          child: column([
            Probe(key: reader, showTheme),
            Probe(key: other, (_) => const Label('other')),
          ]),
        ),
      ),
      backgroundRgb: 0x101218,
    );
    await run.settle();
    (int, int) builds() =>
        (reader.currentState!.builds, other.currentState!.builds);
    expect(run.rows.take(2), ['theme dark', 'other']);
    expect(run.cell(0, 0).bg, ThemeData.dark.background.bg!.value);
    expect(builds(), (1, 1));

    run.term.type('\x1b[?997;2n');
    await run.settle();
    expect(run.rows.take(2), ['theme light', 'other']);
    expect(run.cell(0, 0).bg, ThemeData.light.background.bg!.value);
    expect(builds(), (2, 1));

    final frames = run.term.frames.length;
    run.term.type('\x1b[?997;2n');
    await run.settle();
    expect(builds(), (2, 1), reason: 'light already: nothing rebuilt');
    expect(run.term.frames, hasLength(frames));

    run.term.type('\x1b[?997;1n');
    await run.settle();
    expect(run.rows.first, 'theme dark');
    expect(builds(), (3, 1));
    expect(reports, const [
      ColorSchemeReport(Brightness.light),
      ColorSchemeReport(Brightness.light),
      ColorSchemeReport(Brightness.dark),
    ]);
    AppBinding.of(reader.currentContext!).quit();
    await run.ended();
  });

  test('what is translucent over the default background is blended with '
      'the background the terminal reports after a switch', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(
        key: key,
        (_) => const Box(
          style: Style(bg: Color.rgb(255, 255, 255), bgAlpha: 128),
          child: Label('x'),
        ),
      ),
      backgroundRgb: 0x000000,
    );
    await run.settle();
    expect(run.cell(0, 0).bg, const Color.rgb(128, 128, 128).value);
    run.term.type('\x1b[?997;2n\x1b]11;rgb:ffff/ffff/ffff\x1b\\');
    await run.settle();
    expect(run.cell(0, 0).bg, const Color.rgb(255, 255, 255).value);
    expect(run.cell(5, 2).bg, const Color.rgb(255, 255, 255).value);
    AppBinding.of(key.currentContext!).quit();
    await run.ended();
  });

  test(
    'in a pseudo-terminal that switches to its light color scheme, the '
    'app switches with it and blends with its light background',
    () async {
      final dir = Directory.systemTemp.createTempSync('color_scheme');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = '${dir.path}/out.bin';
      final res = await runProcess(
        'python3',
        [
          '../../tool/pty_run.py',
          '--input',
          'none',
          '--scheme',
          '0.5:light',
          '--out',
          out,
          '--',
          Platform.resolvedExecutable,
          app,
          // a bound: the app quits once it has shown the light background
          '--seconds=30',
        ],
        // the colours looked for below are 24-bit, whatever the terminal
        // the test runs from says
        environment: const {'COLORTERM': 'truecolor'},
        group: true,
      );
      expect(res.stdout, endsWith('terminal restored\n'));
      expect(res.exitCode, 0);
      final written = String.fromCharCodes(File(out).readAsBytesSync());
      // the dark theme, half white over the dark background, 0x101218
      final dark = written.indexOf('48;2;22;24;29mtheme dark');
      expect(dark, isNot(-1));
      expect(written.indexOf('48;2;76;77;82mhalf white', dark), isNot(-1));
      // the light one, half white over the light background, 0xeff1f5
      final light = written.indexOf('48;2;250;250;251mtheme light', dark);
      expect(light, greaterThan(dark));
      expect(written.indexOf('48;2;243;245;248mhalf white', light), isNot(-1));
    },
    testOn: 'linux || mac-os',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
