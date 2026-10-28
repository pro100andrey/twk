import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show ColorMode, TerminalCaps, TerminalInfo;

import '../framework/harness.dart';

const Map<String, ThemeData> presets = {
  'dark': ThemeData.dark,
  'light': ThemeData.light,
  'nord': ThemeData.nord,
  'catppuccinMocha': ThemeData.catppuccinMocha,
  'catppuccinLatte': ThemeData.catppuccinLatte,
};

/// The slots of [theme] by name.
Map<String, Style> slots(ThemeData theme) => {
  'background': theme.background,
  'surface': theme.surface,
  'text': theme.text,
  'muted': theme.muted,
  'primary': theme.primary,
  'accent': theme.accent,
  'border': theme.border,
  'selection': theme.selection,
  'error': theme.error,
  'warning': theme.warning,
  'success': theme.success,
  'info': theme.info,
};

/// The slots that are backgrounds; the others are text colors.
const backgrounds = {'background', 'surface', 'selection'};

/// A [Probe] named [name] that logs the theme it reads, by its name.
Probe reader(String name, List<String> log) => Probe(
  name,
  log,
  builder: (state) {
    final theme = Theme.of(state.context);
    log.add('$name reads ${presetName(theme)}');
    return Leaf(name);
  },
);

/// The name of [theme] among the presets.
String presetName(ThemeData theme) => {
  ...presets,
  'terminal dark': const ThemeData.terminal(Brightness.dark),
  'terminal light': const ThemeData.terminal(Brightness.light),
}.entries.firstWhere((e) => e.value == theme).key;

/// What the probe found on a terminal with [background].
TerminalInfo probed(int? background) => TerminalInfo(
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

void main() {
  group('ThemeData', () {
    test('a preset is as dark or light as its background, and has a color '
        'in every slot', () {
      for (final MapEntry(key: name, value: theme) in presets.entries) {
        final background = theme.background.bg!;
        expect(background.isRgb, isTrue, reason: name);
        expect(
          theme.brightness,
          Brightness.ofRgb(background.value & 0xFFFFFF),
          reason: name,
        );
        for (final MapEntry(key: slot, value: style) in slots(theme).entries) {
          final color = backgrounds.contains(slot) ? style.bg : style.fg;
          expect(color?.isRgb, isTrue, reason: '$name $slot');
        }
      }
      expect(presets.values.toSet(), hasLength(presets.length));
    });

    test('the terminal preset keeps to the terminal default colors and '
        'its palette', () {
      for (final brightness in Brightness.values) {
        final theme = ThemeData.terminal(brightness);
        expect(theme.brightness, brightness);
        for (final MapEntry(key: slot, value: style) in slots(theme).entries) {
          for (final color in [style.fg, style.bg]) {
            expect(
              color == null || color.isDefault || color.isIndexed,
              isTrue,
              reason: slot,
            );
          }
        }
      }
      const theme = ThemeData.terminal(Brightness.dark);
      expect(theme.background, const Style(bg: Color.defaultColor));
      expect(theme.text, const Style(fg: Color.defaultColor));
      // a grey of the 256 colors, which no color scheme changes
      expect(theme.selection, const Style(bg: Color.indexed(237)));
      expect(
        const ThemeData.terminal(Brightness.light).selection,
        const Style(bg: Color.indexed(252)),
      );
      expect(theme.error, const Style(fg: Color.red));
    });

    test('copyWith replaces the slots given and keeps the others', () {
      const green = Style(fg: Color.green);
      final theme = ThemeData.dark.copyWith(primary: green);
      expect(theme.primary, green);
      expect(theme, isNot(ThemeData.dark));
      expect(theme.copyWith(primary: ThemeData.dark.primary), ThemeData.dark);
      expect(
        ThemeData.dark.copyWith(brightness: Brightness.light).brightness,
        Brightness.light,
      );
      final all = <String, Style>{
        for (final slot in slots(theme).keys) slot: Style(link: slot),
      };
      expect(
        slots(
          ThemeData.light.copyWith(
            background: all['background'],
            surface: all['surface'],
            text: all['text'],
            muted: all['muted'],
            primary: all['primary'],
            accent: all['accent'],
            border: all['border'],
            selection: all['selection'],
            error: all['error'],
            warning: all['warning'],
            success: all['success'],
            info: all['info'],
          ),
        ),
        all,
      );
    });

    test('is equal to another with the same slots', () {
      final copy = ThemeData.nord.copyWith();
      expect(identical(copy, ThemeData.nord), isFalse);
      expect(copy, ThemeData.nord);
      expect(copy.hashCode, ThemeData.nord.hashCode);
      expect(ThemeData.nord, isNot(ThemeData.dark));
    });
  });

  group('Theme', () {
    test('gives the widgets below its data, the nearest one hiding those '
        'above', () {
      final log = <String>[];
      Tree().pump(
        Theme(
          data: ThemeData.light,
          child: Multi([
            reader('a', log),
            Theme(data: ThemeData.nord, child: reader('b', log)),
          ]),
        ),
      );
      expect(log, containsAll(['a reads light', 'b reads nord']));
    });

    test("without one, the widgets get twk's own theme of the terminal's "
        "brightness; the terminal's own colors where it did not say it", () {
      final log = <String>[];
      Tree().pump(
        Multi([
          TerminalBrightness(
            brightness: Brightness.dark,
            child: reader('a', log),
          ),
          TerminalBrightness(
            brightness: Brightness.light,
            child: reader('b', log),
          ),
          TerminalBrightness(
            brightness: Brightness.dark,
            known: false,
            child: reader('c', log),
          ),
          reader('d', log),
        ]),
      );
      expect(
        log,
        containsAll([
          'a reads dark',
          'b reads light',
          'c reads terminal dark',
          'd reads terminal dark',
        ]),
      );
    });

    test("Theme.terminal gives the terminal's own colors, of its "
        'brightness', () {
      final log = <String>[];
      Tree().pump(
        Multi([
          Theme.terminal(child: reader('a', log)),
          TerminalBrightness(
            brightness: Brightness.light,
            child: Theme.terminal(child: reader('b', log)),
          ),
        ]),
      );
      expect(
        log,
        containsAll(['a reads terminal dark', 'b reads terminal light']),
      );
    });

    test('a theme switched rebuilds the widgets that read it and no '
        'others', () {
      final log = <String>[];
      final a = reader('a', log);
      final other = Probe('other', log);
      Widget app(ThemeData data) => Theme(
        data: data,
        child: Multi([a, other]),
      );
      final tree = Tree()..pump(app(ThemeData.dark));
      log.clear();
      tree.pump(app(ThemeData.light));
      expect(log, ['a didChangeDependencies', 'a build', 'a reads light']);
      log.clear();
      tree
        ..pump(app(ThemeData.light.copyWith()))
        ..pump(app(ThemeData.light));
      expect(log, isEmpty, reason: 'the same theme again');
    });

    test("adaptive, it is the dark or the light theme by the terminal's "
        'brightness, and switches with it', () {
      final log = <String>[];
      final a = reader('a', log);
      final b = reader('b', log);
      final c = Probe(
        'c',
        log,
        builder: (state) {
          log.add('c sees ${TerminalBrightness.of(state.context).name}');
          return const Leaf('c');
        },
      );
      final other = Probe('other', log);
      Widget app(Brightness brightness) => TerminalBrightness(
        brightness: brightness,
        child: Multi([
          Theme.adaptive(child: Multi([a, other])),
          c,
          Theme.adaptive(
            dark: ThemeData.catppuccinMocha,
            light: ThemeData.catppuccinLatte,
            child: b,
          ),
        ]),
      );
      final tree = Tree()..pump(app(Brightness.dark));
      expect(log, containsAll(['a reads dark', 'b reads catppuccinMocha']));
      log.clear();
      tree.pump(app(Brightness.light));
      expect(
        log,
        unorderedEquals([
          'a didChangeDependencies',
          'a build',
          'a reads light',
          'b didChangeDependencies',
          'b build',
          'b reads catppuccinLatte',
          'c didChangeDependencies',
          'c build',
          'c sees light',
        ]),
      );
      log.clear();
      tree.pump(app(Brightness.light));
      expect(log, isEmpty, reason: 'the same brightness again');
    });

    test("the probe's background picks the preset", () {
      final log = <String>[];
      for (final background in [0x101218, 0xeff1f5]) {
        Tree().pump(
          TerminalBrightness(
            brightness: probed(background).brightness!,
            child: Theme.adaptive(child: reader('$background', log)),
          ),
        );
      }
      expect(
        log,
        containsAll(['${0x101218} reads dark', '${0xeff1f5} reads light']),
      );
    });

    test('a color scheme report switches it live', () {
      final log = <String>[];
      final tree = Tree()..pump(_App(Theme.adaptive(child: reader('a', log))));
      final app = tree.stateOf<_AppState>();
      log.clear();
      app.deliver(const ColorSchemeReport(Brightness.light));
      tree.frame();
      expect(log, ['a didChangeDependencies', 'a build', 'a reads light']);
      log.clear();
      app.deliver(const ColorSchemeReport(Brightness.dark));
      tree.frame();
      expect(log, ['a didChangeDependencies', 'a build', 'a reads dark']);
    });
  });
}

/// An app that keeps the terminal's brightness as a binding does: from the
/// color scheme reports delivered to it.
final class _App extends StatefulWidget {
  const _App(this.child);

  final Widget child;

  @override
  State<_App> createState() => _AppState();
}

final class _AppState extends State<_App> {
  Brightness _brightness = Brightness.dark;

  void deliver(InputEvent event) {
    if (event case ColorSchemeReport(:final brightness)) {
      setState(() => _brightness = brightness);
    }
  }

  @override
  Widget build(BuildContext context) =>
      TerminalBrightness(brightness: _brightness, child: widget.child);
}
