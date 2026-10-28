// The presets' contrast against the targets of what each color is for;
// the tokens a theme derives from its slots, as the gallery mixes them
// (packages/gallery/doc/design.md, "Colour"), their fallbacks on the
// terminal's palette, ThemeData.lerp and AnimatedTheme's cross-fade.
import 'dart:convert';

import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// The tokens of [theme] by name: colors as 0xRRGGBB, the alpha as is.
Map<String, Object?> tokens(ThemeData theme) => {
  'chrome': theme.chrome.bg?.rgb,
  'well': theme.well.bg?.rgb,
  'faint': theme.faint.fg?.rgb,
  'dim': theme.dim.fg?.rgb,
  'selectionIdle': theme.selectionIdle.bg?.rgb,
  'onPrimary': theme.onPrimary.fg?.rgb,
  'shade': theme.shade.bg?.rgb,
  'shadeAlpha': theme.shadeAlpha,
};

extension on Color {
  int get rgb => (r << 16) | (g << 8) | b;
}

/// What the design derives for the five presets (the gallery's
/// doc/design.md, "Colour"), mixed as `Color.lerp` mixes.
const Map<String, Map<String, Object>> designed = {
  'dark': {
    'chrome': 0x1c1f25,
    'well': 0x13151a,
    'faint': 0x2c3039,
    'dim': 0x747a83,
    'selectionIdle': 0x24354c,
    'onPrimary': 0x16181d,
    'shade': 0x000000,
    'shadeAlpha': 0.5,
  },
  'light': {
    'chrome': 0xf3f5f7,
    'well': 0xfefefe,
    'faint': 0xdcdfe4,
    'dim': 0x838991,
    'selectionIdle': 0xcee1fd,
    'onPrimary': 0xffffff,
    'shade': 0x000000,
    'shadeAlpha': 0.28,
  },
  'nord': {
    'chrome': 0x353b49,
    'well': 0x282e38,
    'faint': 0x3f4757,
    'dim': 0x808691,
    'selectionIdle': 0x424a5b,
    'onPrimary': 0x2e3440,
    'shade': 0x000000,
    'shadeAlpha': 0.5,
  },
  'catppuccinMocha': {
    'chrome': 0x282839,
    'well': 0x1a1a28,
    'faint': 0x494b5e,
    'dim': 0x7c8098,
    'selectionIdle': 0x393a4c,
    'onPrimary': 0x1e1e2e,
    'shade': 0x000000,
    'shadeAlpha': 0.5,
  },
  'catppuccinLatte': {
    'chrome': 0xdcdfe6,
    'well': 0xfafbfc,
    'faint': 0xbdc0cc,
    'dim': 0x86899b,
    'selectionIdle': 0xd1d3dc,
    'onPrimary': 0xffffff,
    'shade': 0x000000,
    'shadeAlpha': 0.28,
  },
};

const Map<String, ThemeData> presets = {
  'dark': ThemeData.dark,
  'light': ThemeData.light,
  'nord': ThemeData.nord,
  'catppuccinMocha': ThemeData.catppuccinMocha,
  'catppuccinLatte': ThemeData.catppuccinLatte,
};

const ms = Duration(milliseconds: 1);

/// Paints the selection slot of the theme it is under over its room.
final class _Selection extends StatelessWidget {
  const _Selection();

  @override
  Widget build(BuildContext context) =>
      Box(style: Theme.of(context).selection, child: const Text('x'));
}

/// Paints the background slot of the theme it is under over its room.
final class _Swatch extends StatelessWidget {
  const _Swatch();

  @override
  Widget build(BuildContext context) =>
      Box(style: Theme.of(context).background, child: const Text('x'));
}

/// The contrast of two RGB colors as WCAG 2 has it, 1 to 21.
double contrast(Color a, Color b) {
  double channel(int c) {
    final v = c / 255;
    return v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final (x, y) = (luminance(a), luminance(b));
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// What a preset's colors are held to, by what each is for: muted text
/// as body text (4.5 to 1 on the background) and apart from the text
/// (1.5), dim text as incidental
/// (3), text on the selection as body text, the selection apart from the
/// background (1.4) and the surface (1.3), the idle selection apart from
/// the background (1.2) and the selection (1.1), the status colors as
/// text (3).
const _targets = <String, double>{
  'muted/background': 4.5,
  // and apart from the text, or a hint reads as text
  'text/muted': 1.5,
  'muted/surface': 3.5,
  'dim/background': 3,
  'text/selection': 4.5,
  'selection/background': 1.4,
  'selection/surface': 1.3,
  'selectionIdle/background': 1.2,
  'selectionIdle/selection': 1.1,
  'warning/background': 3,
  'success/background': 3,
  'info/background': 3,
  'error/background': 3,
};

/// Where a palette of its own has no color that meets a target: its best,
/// as it is.
const _short = <String, Map<String, double>>{
  // no grey of Nord's reads as text: nord4 at 0.6 over nord0
  'nord': {'muted/background': 4.42},
  'catppuccinLatte': {
    // subtext0: its text is near enough base that no color is 4.5 on base
    // and apart from the text both
    'muted/background': 4.37,
    'muted/surface': 3.2,
    // the selection overlay2 at 0.4 over base, which surface0 is near
    'selection/surface': 1.14,
    // no yellow, green or cyan of Latte's reads on base: peach, green,
    // sapphire
    'warning/background': 2.64,
    'success/background': 2.96,
    'info/background': 2.78,
  },
};

void main() {
  test("each preset's colors meet their targets, where its palette has a "
      'color that does', () {
    for (final MapEntry(key: name, value: t) in presets.entries) {
      Color c(Style s) => (s.bg ?? s.fg)!;
      final pairs = <String, (Style, Style)>{
        'muted/background': (t.muted, t.background),
        'text/muted': (t.text, t.muted),
        'muted/surface': (t.muted, t.surface),
        'dim/background': (t.dim, t.background),
        'text/selection': (t.text, t.selection),
        'selection/background': (t.selection, t.background),
        'selection/surface': (t.selection, t.surface),
        'selectionIdle/background': (t.selectionIdle, t.background),
        'selectionIdle/selection': (t.selectionIdle, t.selection),
        'warning/background': (t.warning, t.background),
        'success/background': (t.success, t.background),
        'info/background': (t.info, t.background),
        'error/background': (t.error, t.background),
      };
      for (final MapEntry(key: pair, value: (a, b)) in pairs.entries) {
        final target = _short[name]?[pair] ?? _targets[pair]!;
        expect(
          contrast(c(a), c(b)),
          greaterThanOrEqualTo(target - 0.005),
          reason: '$name $pair',
        );
      }
    }
  });

  group('the derived tokens', () {
    test("of each preset are the design's", () {
      for (final MapEntry(key: name, value: theme) in presets.entries) {
        expect(tokens(theme), designed[name], reason: name);
      }
    });

    test('are the color each of them is: a background or a text color, '
        'and nothing else', () {
      const theme = ThemeData.nord;
      for (final style in [
        theme.chrome,
        theme.well,
        theme.selectionIdle,
        theme.shade,
      ]) {
        expect(style, Style(bg: style.bg));
      }
      for (final style in [theme.faint, theme.dim, theme.onPrimary]) {
        expect(style, Style(fg: style.fg));
      }
    });

    test('follow the slots they come from, a light theme mixing as a '
        'light one', () {
      final theme = ThemeData.dark.copyWith(
        background: const Style(bg: Color.rgb(0, 0, 0)),
        surface: const Style(bg: Color.rgb(100, 200, 50)),
      );
      expect(theme.chrome, const Style(bg: Color.rgb(50, 100, 25)));
      expect(theme.onPrimary, const Style(fg: Color.rgb(0, 0, 0)));
      final light = theme.copyWith(brightness: Brightness.light);
      expect(light.chrome, const Style(bg: Color.rgb(55, 110, 28)));
      expect(light.onPrimary, const Style(fg: Color.rgb(255, 255, 255)));
      expect(light.shadeAlpha, 0.28);
    });

    test("fall back on the terminal's palette to the slot each starts "
        'from', () {
      for (final brightness in Brightness.values) {
        final theme = ThemeData.terminal(brightness);
        expect(theme.chrome, theme.surface);
        expect(theme.well, theme.background);
        expect(theme.faint, theme.border);
        expect(theme.dim, theme.muted);
        expect(theme.shade, const Style(bg: Color.rgb(0, 0, 0)));
      }
      const dark = ThemeData.terminal(Brightness.dark);
      const light = ThemeData.terminal(Brightness.light);
      // an idle selection a grey of its own, nearer the background
      expect(dark.selectionIdle, const Style(bg: Color.indexed(235)));
      expect(light.selectionIdle, const Style(bg: Color.indexed(254)));
      // a surface of its own, a step from the background: a toast, a
      // dialog stands out of the page
      expect(dark.surface, const Style(bg: Color.indexed(234)));
      expect(light.surface, const Style(bg: Color.indexed(255)));
      // not the palette's black, which bold is drawn bright: grey on blue
      expect(dark.onPrimary, const Style(fg: Color.rgb(255, 255, 255)));
      expect(light.onPrimary, const Style(fg: Color.rgb(255, 255, 255)));
      expect(dark.shadeAlpha, 0.5);
      expect(light.shadeAlpha, 0.28);
    });

    test('of a terminal that told its colors are mixed from them: each '
        'grey a step from its background', () {
      // Breeze's dark scheme, on whose background a fixed 237 vanishes
      final dark = ThemeData.terminalOn(0x31363b, foreground: 0xfcfcfc);
      expect(dark.brightness, Brightness.dark);
      expect(dark.background, const Style(bg: Color.defaultColor));
      expect(dark.text, const Style(fg: Color.defaultColor));
      expect(dark.primary, const Style(fg: Color.blue));
      // chrome the surface, well the default background, as the slots they
      // come from
      expect(tokens(dark), {
        'chrome': 0x3f4449,
        'well': 0,
        'faint': 0x5a5e62,
        'dim': 0x8c8f92,
        'selectionIdle': 0x454a4e,
        'onPrimary': 0xffffff,
        'shade': 0x000000,
        'shadeAlpha': 0.5,
      });
      expect(dark.surface, const Style(bg: Color.rgb(0x3f, 0x44, 0x49)));
      expect(dark.muted, const Style(fg: Color.rgb(0xab, 0xad, 0xaf)));
      expect(dark.border, const Style(fg: Color.rgb(0x6e, 0x71, 0x75)));
      expect(dark.selection, const Style(bg: Color.rgb(0x5a, 0x5e, 0x62)));
      // light, the text color black where it was not told
      final light = ThemeData.terminalOn(0xffffff);
      expect(light.brightness, Brightness.light);
      expect(light.selection, const Style(bg: Color.rgb(0xcc, 0xcc, 0xcc)));
      expect(light.selectionIdle, const Style(bg: Color.rgb(0xe6, 0xe6, 0xe6)));
      expect(light.muted, const Style(fg: Color.rgb(0x66, 0x66, 0x66)));
    });

    testTwk('Theme.terminal mixes them from what the terminal told, and '
        'follows what it tells after', (t) async {
      await t.pumpWidget(
        const Theme.terminal(child: _Selection()),
        size: (2, 1),
        backgroundRgb: 0x31363b,
      );
      expect(t, styleAt(0, 0, hasBg(const Color.rgb(0x5a, 0x5e, 0x62))));
      // the terminal's answer to OSC 11, after its scheme changed
      await t.input(utf8.encode('\x1b]11;rgb:0000/0000/0000\x1b\\'));
      await t.pump();
      expect(t, styleAt(0, 0, hasBg(const Color.rgb(0x33, 0x33, 0x33))));
    });

    test("take the palette's bright entry where the normal one does not "
        'read on the background and the bright one, of its hue, does', () {
      // xterm's palette
      const xterm = {
        1: 0xcd0000, 2: 0x00cd00, 3: 0xcdcd00, 4: 0x0000ee, //
        5: 0xcd00cd, 6: 0x00cdcd, 9: 0xff0000, 10: 0x00ff00,
        11: 0xffff00, 12: 0x5c5cff, 13: 0xff00ff, 14: 0x00ffff,
      };
      final black = ThemeData.terminalOn(0x000000, palette: xterm);
      // blue 2.2, red 3.6, magenta 4.48 on black: their bright entries
      expect(black.primary, const Style(fg: Color.indexed(12)));
      expect(black.error, const Style(fg: Color.indexed(9)));
      expect(black.accent, const Style(fg: Color.indexed(13)));
      // green, yellow and cyan read
      expect(black.success, const Style(fg: Color.green));
      expect(black.warning, const Style(fg: Color.yellow));
      expect(black.info, const Style(fg: Color.cyan));
      // on white the bright ones read worse: the normal ones kept
      final white = ThemeData.terminalOn(0xffffff, palette: xterm);
      expect(white.primary, const Style(fg: Color.blue));
      expect(white.success, const Style(fg: Color.green));
      // Solarized dark: its bright blue a grey, its bright red an orange
      // no better than its red
      const solarized = {
        1: 0xdc322f, 9: 0xcb4b16, 4: 0x268bd2, 12: 0x839496, //
      };
      final dark = ThemeData.terminalOn(0x002b36, palette: solarized);
      expect(dark.primary, const Style(fg: Color.blue));
      expect(dark.error, const Style(fg: Color.red));
      // a palette not told: the normal entries
      expect(
        ThemeData.terminalOn(0x000000).primary,
        const Style(fg: Color.blue),
      );
    });

    testTwk('Theme.terminal takes the palette the terminal tells', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Builder(
            builder: (context) => Text('x', style: Theme.of(context).primary),
          ),
        ),
        size: (2, 1),
        backgroundRgb: 0x000000,
      );
      expect(t, styleAt(0, 0, hasFg(Color.blue)));
      // xterm's blue and bright blue, as the terminal answers OSC 4
      await t.input(
        utf8.encode(
          '\x1b]4;4;rgb:0000/0000/eeee\x1b\\'
          '\x1b]4;12;rgb:5c5c/5c5c/ffff\x1b\\',
        ),
      );
      await t.pump();
      expect(t, styleAt(0, 0, hasFg(const Color.indexed(12))));
    });

    testTwk('Theme.terminal on a terminal that told no colors: the fixed '
        'greys', (t) async {
      await t.pumpWidget(
        const Theme.terminal(child: _Selection()),
        size: (2, 1),
      );
      expect(t, styleAt(0, 0, hasBg(const Color.indexed(237))));
    });

    test('fill a color with text that reads on it, never reversed but '
        'where the color is the default', () {
      const white = Color.rgb(255, 255, 255);
      const black = Color.rgb(0, 0, 0);
      const dark = ThemeData.dark;
      // onPrimary on primary; the dark background's color on a light fill
      expect(
        dark.fill(dark.primary.fg),
        Style(fg: dark.onPrimary.fg, bg: dark.primary.fg),
      );
      expect(dark.fill(null), dark.fill(dark.primary.fg));
      expect(
        dark.fill(dark.warning.fg),
        Style(fg: dark.background.bg, bg: dark.warning.fg),
      );
      // light: black or white, whichever contrasts more
      const light = ThemeData.light;
      expect(
        light.fill(light.warning.fg),
        Style(fg: white, bg: light.warning.fg),
      );
      expect(
        light.fill(const Color.rgb(0xff, 0xee, 0x88)),
        const Style(fg: black, bg: Color.rgb(0xff, 0xee, 0x88)),
      );
      // the palette, as xterm shows it
      const terminal = ThemeData.terminal(Brightness.dark);
      expect(terminal.fill(Color.blue), const Style(fg: white, bg: Color.blue));
      expect(
        terminal.fill(Color.yellow),
        const Style(fg: black, bg: Color.yellow),
      );
      expect(terminal.fill(Color.red), const Style(fg: white, bg: Color.red));
      expect(
        terminal.fill(Color.green),
        const Style(fg: black, bg: Color.green),
      );
      expect(
        terminal.fill(Color.defaultColor),
        const Style(attrs: Attr.reverse),
      );
    });

    testTwk('the terminal theme made once for the colors of its '
        'TerminalBrightness: Theme.of without a Theme gives the same theme '
        'at each build, in each of ten trees of their own colors built by '
        'turns, as twk_ssh builds its clients; another when they '
        'change', (t) async {
      const trees = 10;
      final seen = [for (var i = 0; i < trees; i++) <ThemeData>[]];
      final rebuild = ValueNotifier(0);
      addTearDown(rebuild.dispose);
      final first = ValueNotifier(0x101010);
      addTearDown(first.dispose);
      Widget terminal(int i, int background) => TerminalBrightness(
        brightness: Brightness.ofRgb(background),
        known: false,
        background: background,
        palette: const {1: 0xffaaaa},
        child: ValueListenableBuilder<int>(
          valueListenable: rebuild,
          builder: (context, _, _) {
            seen[i].add(Theme.of(context));
            return const SizedBox(width: 1, height: 1);
          },
        ),
      );
      await t.pumpWidget(
        ValueListenableBuilder<int>(
          valueListenable: first,
          builder: (context, background, _) => Row(
            children: [
              terminal(0, background),
              for (var i = 1; i < trees; i++) terminal(i, 0x101010 * (i + 1)),
            ],
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        rebuild.value++;
        await t.pump();
      }
      for (final themes in seen) {
        expect(themes, hasLength(4));
        expect(themes, everyElement(same(themes.first)));
      }
      expect(seen[0].first.surface, isNot(seen[1].first.surface));
      first.value = 0x0c0c0c;
      await t.pump();
      expect(seen[0].last, isNot(same(seen[0].first)));
      expect(seen[0].last.surface, isNot(seen[0].first.surface));
      expect(seen[1].last, same(seen[1].first));
    });

    test("terminalOn's palette a copy, which a change to the map given "
        'after leaves as it was', () {
      final told = {1: 0xffaaaa};
      final theme = ThemeData.terminalOn(0x101010, palette: told);
      told[1] = 0x00ff00;
      expect(theme.palette, {1: 0xffaaaa});
      expect(() => theme.palette[2] = 0, throwsUnsupportedError);
    });

    test('fill a palette color by the color the terminal told it draws it '
        "in, not by xterm's; the palette kept by copyWith and lerp and "
        'compared by ==', () {
      const white = Color.rgb(255, 255, 255);
      const black = Color.rgb(0, 0, 0);
      // a themed terminal whose red is a pink and whose blue a pale one:
      // xterm's would take white text, which does not read on them
      const told = {1: 0xffaaaa, 4: 0xaaccff};
      final themed = ThemeData.terminalOn(0x202020, palette: told);
      expect(themed.palette, told);
      expect(themed.fill(Color.red), const Style(fg: black, bg: Color.red));
      expect(
        ThemeData.terminalOn(0x202020).fill(Color.red),
        const Style(fg: white, bg: Color.red),
      );
      // an entry it did not tell, as xterm's
      expect(themed.fill(Color.green), const Style(fg: black, bg: Color.green));
      expect(themed.copyWith(text: const Style()).palette, told);
      final plain = ThemeData.terminalOn(0x202020);
      expect(ThemeData.lerp(plain, themed, 0.7).palette, told);
      expect(ThemeData.lerp(plain, themed, 0.3).palette, isEmpty);
      expect(
        themed == ThemeData.terminalOn(0x202020, palette: Map.of(told)),
        true,
      );
      expect(
        themed.hashCode,
        ThemeData.terminalOn(0x202020, palette: Map.of(told)).hashCode,
      );
      expect(themed == plain, false);
    });

    test('hover: a step from the background towards the text, a grey of '
        "its own on the terminal's colors", () {
      expect(
        ThemeData.dark.hover,
        const Style(bg: Color.rgb(0x27, 0x29, 0x2d)),
      );
      expect(
        const ThemeData.terminal(Brightness.dark).hover,
        const Style(bg: Color.indexed(236)),
      );
      expect(
        const ThemeData.terminal(Brightness.light).hover,
        const Style(bg: Color.indexed(253)),
      );
      expect(
        ThemeData.terminalOn(0x000000).hover,
        const Style(bg: Color.rgb(0x21, 0x21, 0x21)),
      );
    });

    test('given, are kept through copyWith; not given, are derived again '
        'from the slots copyWith changes', () {
      const red = Style(bg: Color.red);
      final theme = ThemeData.dark.copyWith(
        chrome: red,
        well: red,
        faint: red,
        dim: red,
        selectionIdle: red,
        onPrimary: red,
        shade: red,
        shadeAlpha: 0.75,
      );
      expect(
        [
          theme.chrome,
          theme.well,
          theme.faint,
          theme.dim,
          theme.selectionIdle,
          theme.onPrimary,
          theme.shade,
        ],
        everyElement(red),
      );
      expect(theme.shadeAlpha, 0.75);
      final moved = theme.copyWith(background: ThemeData.nord.background);
      expect(moved.chrome, red, reason: 'given');
      expect(moved.shadeAlpha, 0.75);
      final derived = ThemeData.dark.copyWith(
        background: ThemeData.nord.background,
        surface: ThemeData.nord.surface,
      );
      expect(derived.chrome, ThemeData.nord.chrome);
    });

    test('count in equality: a theme with a token given is another '
        'theme, unless it is the token derived', () {
      expect(
        ThemeData.dark.copyWith(dim: ThemeData.dark.dim),
        ThemeData.dark,
      );
      expect(
        ThemeData.dark.copyWith(dim: ThemeData.dark.dim).hashCode,
        ThemeData.dark.hashCode,
      );
      expect(ThemeData.dark.copyWith(shadeAlpha: 0.4), isNot(ThemeData.dark));
      expect(
        ThemeData.dark.copyWith(well: ThemeData.dark.surface),
        isNot(ThemeData.dark),
      );
    });
  });

  group('ThemeData.lerp', () {
    test('is the first theme at 0 and the second at 1', () {
      expect(
        ThemeData.lerp(ThemeData.dark, ThemeData.light, 0),
        ThemeData.dark,
      );
      expect(
        ThemeData.lerp(ThemeData.dark, ThemeData.light, 1),
        ThemeData.light,
      );
    });

    test('halfway mixes every slot and token, the brightness that of the '
        'second', () {
      final half = ThemeData.lerp(ThemeData.dark, ThemeData.light, 0.5);
      expect(half.brightness, Brightness.light);
      expect(half.background, const Style(bg: Color.rgb(0x88, 0x89, 0x8c)));
      expect(half.text, const Style(fg: Color.rgb(0x83, 0x86, 0x8a)));
      expect(half.selection, const Style(bg: Color.rgb(0x71, 0x8d, 0xb2)));
      // the tokens are mixed as they are, not derived from the mix
      expect(half.chrome, const Style(bg: Color.rgb(0x88, 0x8a, 0x8e)));
      expect(half.well, const Style(bg: Color.rgb(0x89, 0x8a, 0x8c)));
      expect(half.onPrimary, const Style(fg: Color.rgb(0x8b, 0x8c, 0x8e)));
      expect(half.shadeAlpha, closeTo(0.39, 1e-9));
      expect(
        ThemeData.lerp(ThemeData.dark, ThemeData.light, 0.25).brightness,
        Brightness.dark,
      );
    });

    test('switches what is not RGB halfway', () {
      const terminal = ThemeData.terminal(Brightness.dark);
      final before = ThemeData.lerp(terminal, ThemeData.dark, 0.25);
      final after = ThemeData.lerp(terminal, ThemeData.dark, 0.75);
      expect(before.primary.fg, Color.blue);
      expect(after.primary.fg, ThemeData.dark.primary.fg);
      expect(before.selection.bg, const Color.indexed(237));
      expect(after.selection.bg, ThemeData.dark.selection.bg);
    });
  });

  group('AnimatedTheme', () {
    test('cross-fades in 280 ms, easing in and out, by default', () {
      const theme = AnimatedTheme(data: ThemeData.dark, child: Text(''));
      expect(theme.duration, ms * 280);
      expect(theme.curve, Curves.easeInOut);
    });

    testTwk('gives the widgets below it the theme on the way from the one '
        'it had to the new one', (t) async {
      final data = ValueNotifier(ThemeData.dark);
      await t.pumpWidget(
        ValueListenableBuilder<ThemeData>(
          valueListenable: data,
          builder: (_, theme, _) => AnimatedTheme(
            data: theme,
            duration: ms * 20,
            curve: Curves.linear,
            child: const _Swatch(),
          ),
        ),
        size: (2, 1),
        maxFps: 100,
      );
      int background() => t.cell(0, 0).bg;
      expect(background(), ThemeData.dark.background.bg!.value);
      data.value = ThemeData.light;
      final shots = <int>[];
      for (var i = 0; i < 3; i++) {
        await t.pump();
        shots.add(background());
      }
      expect(shots, [
        ThemeData.dark.background.bg!.value,
        ThemeData.lerp(
          ThemeData.dark,
          ThemeData.light,
          0.5,
        ).background.bg!.value,
        ThemeData.light.background.bg!.value,
      ]);
    });
  });
}
