/// Themes: the styles of an app by what they are for, presets of them, and
/// the dark or light theme picked by the terminal's brightness.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show Attr, Brightness, Color;

import '../animation/implicit.dart' show StyleTween;
import '../framework/framework.dart';
import 'color_mix.dart';
import 'style.dart';

export 'package:twk_core/twk_core.dart' show Brightness;

/// The styles of an app by what they are for, which widgets draw in: the
/// background slots ([background], [surface], [selection]) set a
/// background, the others a text color. Presets: [dark], [light], [nord],
/// [catppuccinMocha], [catppuccinLatte] and [ThemeData.terminal], the
/// terminal's own colors.
///
/// Besides the twelve slots, the tokens the design draws with, each
/// derived from the slots unless given: [chrome], [well], [faint], [dim],
/// [selectionIdle], [hover], [onPrimary], and a barrier's [shade] and
/// [shadeAlpha]; and [fill], a color filled with text that reads on it.
/// Where the slots they mix are RGB they are mixed as the design does;
/// where one is a palette color (as in [ThemeData.terminal]) a token falls
/// back to the slot it starts from.
///
/// [ThemeData.lerp] blends two themes, [AnimatedTheme] cross-fades from one
/// to the next.
///
/// A preset with another primary color:
///
/// ```dart
/// final data = ThemeData.dark.copyWith(
///   primary: const Style(fg: Color.rgb(0xff, 0x8c, 0x00)),
/// );
/// ```
@immutable
final class ThemeData {
  /// A theme of the twelve slots and [brightness]; each token left out is
  /// derived from the slots, and [shadeAlpha], from 0 to 1 (an assert),
  /// from [brightness]. [selection] must have a background, as a [Theme]
  /// asserts: what is selected is painted on it, and text over it keeps
  /// it.
  const ThemeData({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.primary,
    required this.accent,
    required this.border,
    required this.selection,
    required this.error,
    required this.warning,
    required this.success,
    required this.info,
    this._chrome,
    this._well,
    this._faint,
    this._dim,
    this._selectionIdle,
    this._hover,
    this._onPrimary,
    this._shade,
    this._shadeAlpha,
    this.palette = const {},
  }) : assert(
         _shadeAlpha == null || (_shadeAlpha >= 0 && _shadeAlpha <= 1),
         'shadeAlpha out of 0..1',
       );

  /// The terminal's own colors, so that its color scheme shows through: its
  /// default background and text color and the colors of its palette. For
  /// [surface], [muted], [border], [selection], [selectionIdle] and [hover]
  /// greys of the 256 colors, which no color scheme changes, rather than
  /// the background (a toast, a dialog would not stand out of the page),
  /// dim text, which some terminals ignore, or reverse video, which a text
  /// painted over it would not keep. A ladder from the background: on a
  /// dark terminal [surface] 234 (`#1c1c1c`), [selectionIdle] 235
  /// (`#262626`), [hover] 236 (`#303030`), [selection] 237 (`#3a3a3a`),
  /// [border] 240 (`#585858`), [muted] 245 (`#8a8a8a`); on a light one 255
  /// (`#eeeeee`), 254 (`#e4e4e4`), 253 (`#dadada`), 252 (`#d0d0d0`), 250
  /// (`#bcbcbc`), 243 (`#767676`). What a terminal that told its colors is
  /// in: [ThemeData.terminalOn].
  const ThemeData.terminal(this.brightness)
    : background = const Style(bg: Color.defaultColor),
      surface = brightness == Brightness.dark
          ? const Style(bg: Color.indexed(234))
          : const Style(bg: Color.indexed(255)),
      text = const Style(fg: Color.defaultColor),
      muted = brightness == Brightness.dark
          ? const Style(fg: Color.indexed(245))
          : const Style(fg: Color.indexed(243)),
      primary = const Style(fg: Color.blue),
      accent = const Style(fg: Color.magenta),
      border = brightness == Brightness.dark
          ? const Style(fg: Color.indexed(240))
          : const Style(fg: Color.indexed(250)),
      selection = brightness == Brightness.dark
          ? const Style(bg: Color.indexed(237))
          : const Style(bg: Color.indexed(252)),
      error = const Style(fg: Color.red),
      warning = const Style(fg: Color.yellow),
      success = const Style(fg: Color.green),
      info = const Style(fg: Color.cyan),
      _chrome = null,
      _well = null,
      _faint = null,
      _dim = null,
      _selectionIdle = brightness == Brightness.dark
          ? const Style(bg: Color.indexed(235))
          : const Style(bg: Color.indexed(254)),
      _hover = brightness == Brightness.dark
          ? const Style(bg: Color.indexed(236))
          : const Style(bg: Color.indexed(253)),
      _onPrimary = null,
      _shade = null,
      _shadeAlpha = null,
      palette = const {};

  /// The terminal's own colors on a terminal that told its default
  /// [background] and [foreground] (`0xRRGGBB`; [foreground] white on a
  /// dark background and black on a light one where it did not): as
  /// [ThemeData.terminal] of [background]'s brightness, its greys mixed
  /// from the two instead, so that each is a step from the background
  /// whatever it is: [muted] 0.6 of the way from [background] to
  /// [foreground], [dim] 0.45, [border] 0.3, [selection] and [faint] 0.2,
  /// [hover] 0.13, [selectionIdle] 0.1, [surface] 0.07. A fixed grey can be the
  /// background's own color (the 237 of [ThemeData.terminal] on Breeze's
  /// `#31363b`).
  ///
  /// [primary], [accent] and the colors of [error], [warning], [success]
  /// and [info] are the palette's blue, magenta, red, yellow, green and
  /// cyan, or their bright entries where the [palette] the terminal told
  /// (RGB by index) has the normal one under 4.5 against [background],
  /// and the bright one is of its hue and reads better by more than 0.5:
  /// xterm's blue on black is 2.2, its bright blue 4.4. Solarized's
  /// bright blue is a grey, its blue kept.
  ///
  /// The theme's [ThemeData.palette] is a copy of the map given, which a
  /// change to that map after leaves as it was.
  factory ThemeData.terminalOn(
    int background, {
    int? foreground,
    Map<int, int> palette = const {},
  }) {
    final told = palette.isEmpty
        ? const <int, int>{}
        : Map<int, int>.unmodifiable(palette);
    final brightness = Brightness.ofRgb(background);
    final to =
        foreground ?? (brightness == Brightness.dark ? 0xFFFFFF : 0x000000);
    Color grey(double k) => lerpRgb(background, to, k);
    Style color(Color normal) {
      final rgb = told[normal.index];
      final bright = told[normal.index + 8];
      if (rgb == null || contrastRgb(rgb, background) >= 4.5) {
        return Style(fg: normal);
      }
      return bright != null &&
              _sameHue(rgb, bright) &&
              contrastRgb(bright, background) >
                  contrastRgb(rgb, background) + 0.5
          ? Style(fg: Color.indexed(normal.index + 8))
          : Style(fg: normal);
    }

    return ThemeData.terminal(brightness).copyWith(
      surface: Style(bg: grey(0.07)),
      primary: color(Color.blue),
      accent: color(Color.magenta),
      error: color(Color.red),
      warning: color(Color.yellow),
      success: color(Color.green),
      info: color(Color.cyan),
      muted: Style(fg: grey(0.6)),
      dim: Style(fg: grey(0.45)),
      border: Style(fg: grey(0.3)),
      selection: Style(bg: grey(0.2)),
      faint: Style(fg: grey(0.2)),
      selectionIdle: Style(bg: grey(0.1)),
      hover: Style(bg: grey(0.13)),
      palette: told,
    );
  }

  /// The terminal's own colors as [context] has them: [ThemeData.terminalOn]
  /// where the terminal told its background ([TerminalBrightness]), else
  /// [ThemeData.terminal] of its brightness. [context] depends on them.
  ///
  /// Made once for the colors of the nearest [TerminalBrightness], which
  /// keeps it until they change: [Theme.of] without a [Theme] and
  /// [Theme.terminal] ask at each build, and a theme made anew each time
  /// would read as a change to what compares themes by identity. Kept by
  /// each terminal's own, so that the apps of one isolate on terminals of
  /// their own colors (twk_ssh's, one a client) keep theirs.
  factory ThemeData.terminalOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<TerminalBrightness>();
    if (element is! _TerminalBrightnessElement) {
      return const ThemeData.terminal(Brightness.dark);
    }
    context.dependOnInheritedElement(element);
    return element.theme;
  }

  /// The theme [t] of the way from [a] to [b], for a cross-fade: [a] at 0,
  /// [b] at 1. Each slot and token blends as a [StyleTween] has it (RGB
  /// colors channel by channel, others switching halfway), [shadeAlpha] as
  /// a number; the brightness switches halfway. The tokens are blended as
  /// they are in [a] and [b], not derived again.
  factory ThemeData.lerp(ThemeData a, ThemeData b, double t) {
    if (identical(a, b) || t == 0) {
      return a;
    }
    if (t == 1) {
      return b;
    }
    Style style(Style x, Style y) => StyleTween(begin: x, end: y).transform(t);
    return ThemeData(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      background: style(a.background, b.background),
      surface: style(a.surface, b.surface),
      text: style(a.text, b.text),
      muted: style(a.muted, b.muted),
      primary: style(a.primary, b.primary),
      accent: style(a.accent, b.accent),
      border: style(a.border, b.border),
      selection: style(a.selection, b.selection),
      error: style(a.error, b.error),
      warning: style(a.warning, b.warning),
      success: style(a.success, b.success),
      info: style(a.info, b.info),
      chrome: style(a.chrome, b.chrome),
      well: style(a.well, b.well),
      faint: style(a.faint, b.faint),
      dim: style(a.dim, b.dim),
      selectionIdle: style(a.selectionIdle, b.selectionIdle),
      hover: style(a.hover, b.hover),
      onPrimary: style(a.onPrimary, b.onPrimary),
      shade: style(a.shade, b.shade),
      shadeAlpha: a.shadeAlpha + (b.shadeAlpha - a.shadeAlpha) * t,
      palette: t < 0.5 ? a.palette : b.palette,
    );
  }

  /// Whether the theme is dark (light text on a dark background) or light.
  final Brightness brightness;

  /// The colors the terminal draws the entries of its palette in, RGB by
  /// index, as it told them ([TerminalBrightness.palette]): what [fill]
  /// picks the text on a palette color by, where xterm's own would mislead
  /// (the red of a themed terminal a pink). Empty for none told: xterm's.
  /// [ThemeData.terminalOn] gives it.
  final Map<int, int> palette;

  /// The app's background, under everything else.
  final Style background;

  /// What stands out of the [background]: panels, dialogs, popups.
  final Style surface;

  /// Text.
  final Style text;

  /// Text that matters less: hints, placeholders, what is disabled.
  final Style muted;

  /// The color of what is active: the focused control, buttons, links.
  final Style primary;

  /// A second color for highlights, apart from [primary].
  final Style accent;

  /// Borders of boxes, separators.
  final Style border;

  /// What is selected: rows of a list, text; a background, never null.
  final Style selection;

  /// Errors and what failed.
  final Style error;

  /// Warnings.
  final Style warning;

  /// What succeeded.
  final Style success;

  /// Information, neither good nor bad.
  final Style info;

  // the tokens given; null for those derived from the slots
  final Style? _chrome;
  final Style? _well;
  final Style? _faint;
  final Style? _dim;
  final Style? _selectionIdle;
  final Style? _hover;
  final Style? _onPrimary;
  final Style? _shade;
  final double? _shadeAlpha;

  bool get _isDark => brightness == Brightness.dark;

  /// The app's frame around its content (a header, a sidebar, the key
  /// hints), a background: a step from [background] towards [surface],
  /// half of it on a dark theme, 0.55 on a light one. [surface] where
  /// either is not RGB.
  Style get chrome =>
      _chrome ??
      _bg(mixRgb(background.bg, surface.bg, _isDark ? 0.5 : 0.55), surface);

  /// A well sunk into the [chrome], a background: text fields. [background]
  /// 0.12 of the way to black on a dark theme, 0.7 of the way to white on a
  /// light one; [background] where it is not RGB.
  Style get well =>
      _well ??
      _bg(
        _isDark
            ? mixRgb(background.bg, const Color.rgb(0, 0, 0), 0.12)
            : mixRgb(background.bg, const Color.rgb(0xff, 0xff, 0xff), 0.7),
        background,
      );

  /// Quiet lines, a text color: rules that only separate, dots of a
  /// stage. [background] 0.55 of the way to [border] on a dark theme, 0.6
  /// on a light one; [border] where either is not RGB.
  Style get faint =>
      _faint ??
      _fg(mixRgb(background.bg, border.fg, _isDark ? 0.55 : 0.6), border);

  /// Text that matters least, a text color: counts, line numbers, sizes.
  /// [muted] 0.2 of the way to [background], 3 to 1 against it in every
  /// preset; [muted] where either is not RGB.
  Style get dim => _dim ?? _fg(mixRgb(muted.fg, background.bg, 0.2), muted);

  /// A selection whose list has not the focus, a background: [selection]
  /// 0.35 of the way to [background], apart from both in every preset (a
  /// tint of the selection's on a surface); [selection] where either is
  /// not RGB (a grey of its own in [ThemeData.terminal]).
  Style get selectionIdle =>
      _selectionIdle ??
      _bg(mixRgb(selection.bg, background.bg, 0.35), selection);

  /// What the mouse is over, a background: a row, a header, a button's
  /// chip lit. [background] 0.08 of the way to [text]; [selectionIdle]
  /// where either is not RGB (a grey of its own in [ThemeData.terminal]).
  Style get hover =>
      _hover ?? _bg(mixRgb(background.bg, text.fg, 0.08), selectionIdle);

  /// A fill of [color] with text that reads on it, a background and a
  /// text color: a badge, a focused button, a tab or a cursor lit. Text
  /// [onPrimary] on [primary]'s color, else black or white, whichever
  /// contrasts more (on a dark theme of RGB colors [background]'s color
  /// where it reads, as on [primary]), a palette color measured as the
  /// terminal draws it ([palette]); reverse video where [color] is the
  /// default color, or null and [primary] has none.
  Style fill(Color? color) {
    final c = color ?? primary.fg;
    if (c == null || c.isDefault) {
      return const Style(attrs: Attr.reverse);
    }
    if (c == primary.fg && onPrimary.fg != null) {
      return Style(fg: onPrimary.fg, bg: c);
    }
    final rgb = c.isRgb
        ? c.value & 0xFFFFFF
        : palette[c.index] ?? xtermRgb(c.index);
    final bg = background.bg;
    if (_isDark && bg != null && bg.isRgb) {
      if (contrastRgb(bg.value & 0xFFFFFF, rgb) >= 4.5) {
        return Style(fg: bg, bg: c);
      }
    }
    const black = Color.rgb(0, 0, 0);
    const white = Color.rgb(0xff, 0xff, 0xff);
    return Style(
      fg: contrastRgb(0, rgb) >= contrastRgb(0xFFFFFF, rgb) ? black : white,
      bg: c,
    );
  }

  /// Text on a [primary] fill, a text color: a focused button. On a dark
  /// theme of RGB colors [background]'s color, otherwise white: on the
  /// terminal's palette the blue is the terminal's own, and its black,
  /// bold, many terminals draw bright, a grey that hardly reads on it.
  Style get onPrimary =>
      _onPrimary ??
      Style(
        fg: _isDark && (background.bg?.isRgb ?? false)
            ? background.bg
            : const Color.rgb(0xff, 0xff, 0xff),
      );

  /// What a modal barrier dims what is under it with, a background: black.
  /// [shadeAlpha] says how much of it.
  Style get shade => _shade ?? const Style(bg: Color.rgb(0, 0, 0));

  /// How much of [shade] a modal barrier blends over what is under it,
  /// from 0 (none) to 1 (all of it): 0.5 on a dark theme, 0.28 on a light
  /// one.
  double get shadeAlpha => _shadeAlpha ?? (_isDark ? 0.5 : 0.28);

  /// Neutral greys and muted colors on a near black.
  static const dark = ThemeData(
    brightness: Brightness.dark,
    background: Style(bg: Color.rgb(0x16, 0x18, 0x1d)),
    surface: Style(bg: Color.rgb(0x22, 0x25, 0x2c)),
    text: Style(fg: Color.rgb(0xe6, 0xe8, 0xeb)),
    muted: Style(fg: Color.rgb(0x8b, 0x92, 0x9c)),
    primary: Style(fg: Color.rgb(0x5f, 0xa8, 0xff)),
    accent: Style(fg: Color.rgb(0xc7, 0x92, 0xea)),
    border: Style(fg: Color.rgb(0x3e, 0x44, 0x4f)),
    selection: Style(bg: Color.rgb(0x2b, 0x45, 0x66)),
    error: Style(fg: Color.rgb(0xff, 0x6b, 0x6b)),
    warning: Style(fg: Color.rgb(0xf5, 0xc0, 0x4a)),
    success: Style(fg: Color.rgb(0x5f, 0xd3, 0x8d)),
    info: Style(fg: Color.rgb(0x5c, 0xc8, 0xe6)),
  );

  /// Neutral greys and deep colors on a near white.
  static const light = ThemeData(
    brightness: Brightness.light,
    background: Style(bg: Color.rgb(0xfa, 0xfa, 0xfb)),
    surface: Style(bg: Color.rgb(0xee, 0xf0, 0xf3)),
    text: Style(fg: Color.rgb(0x1f, 0x23, 0x28)),
    muted: Style(fg: Color.rgb(0x65, 0x6d, 0x76)),
    primary: Style(fg: Color.rgb(0x09, 0x69, 0xda)),
    accent: Style(fg: Color.rgb(0x82, 0x50, 0xdf)),
    border: Style(fg: Color.rgb(0xc8, 0xcd, 0xd5)),
    selection: Style(bg: Color.rgb(0xb6, 0xd4, 0xfe)),
    error: Style(fg: Color.rgb(0xcf, 0x22, 0x2e)),
    warning: Style(fg: Color.rgb(0x9a, 0x67, 0x00)),
    success: Style(fg: Color.rgb(0x1a, 0x7f, 0x37)),
    info: Style(fg: Color.rgb(0x0a, 0x7e, 0xa4)),
  );

  /// Nord (nordtheme.com): arctic blues on a dark grey.
  static const nord = ThemeData(
    brightness: Brightness.dark,
    background: Style(bg: Color.rgb(0x2e, 0x34, 0x40)),
    surface: Style(bg: Color.rgb(0x3b, 0x42, 0x52)),
    text: Style(fg: Color.rgb(0xd8, 0xde, 0xe9)),
    // nord4 at 0.6 over nord0: no grey of the palette reads as text
    muted: Style(fg: Color.rgb(0x94, 0x9a, 0xa5)),
    primary: Style(fg: Color.rgb(0x88, 0xc0, 0xd0)),
    accent: Style(fg: Color.rgb(0xb4, 0x8e, 0xad)),
    border: Style(fg: Color.rgb(0x4c, 0x56, 0x6a)),
    // nord3, apart from nord1, the surface
    selection: Style(bg: Color.rgb(0x4c, 0x56, 0x6a)),
    error: Style(fg: Color.rgb(0xbf, 0x61, 0x6a)),
    warning: Style(fg: Color.rgb(0xeb, 0xcb, 0x8b)),
    success: Style(fg: Color.rgb(0xa3, 0xbe, 0x8c)),
    info: Style(fg: Color.rgb(0x81, 0xa1, 0xc1)),
  );

  /// Catppuccin Mocha (catppuccin.com), its dark flavor: pastels on a dark
  /// blue-grey.
  static const catppuccinMocha = ThemeData(
    brightness: Brightness.dark,
    background: Style(bg: Color.rgb(0x1e, 0x1e, 0x2e)),
    surface: Style(bg: Color.rgb(0x31, 0x32, 0x44)),
    text: Style(fg: Color.rgb(0xcd, 0xd6, 0xf4)),
    // overlay2
    muted: Style(fg: Color.rgb(0x93, 0x99, 0xb2)),
    primary: Style(fg: Color.rgb(0x89, 0xb4, 0xfa)),
    accent: Style(fg: Color.rgb(0xcb, 0xa6, 0xf7)),
    border: Style(fg: Color.rgb(0x6c, 0x70, 0x86)),
    // overlay2 at 0.35 over base, as Catppuccin's guide has a selection
    selection: Style(bg: Color.rgb(0x47, 0x49, 0x5c)),
    error: Style(fg: Color.rgb(0xf3, 0x8b, 0xa8)),
    warning: Style(fg: Color.rgb(0xf9, 0xe2, 0xaf)),
    success: Style(fg: Color.rgb(0xa6, 0xe3, 0xa1)),
    info: Style(fg: Color.rgb(0x89, 0xdc, 0xeb)),
  );

  /// Catppuccin Latte (catppuccin.com), its light flavor.
  static const catppuccinLatte = ThemeData(
    brightness: Brightness.light,
    background: Style(bg: Color.rgb(0xef, 0xf1, 0xf5)),
    surface: Style(bg: Color.rgb(0xcc, 0xd0, 0xda)),
    text: Style(fg: Color.rgb(0x4c, 0x4f, 0x69)),
    // subtext0: subtext1 would read 4.5 on base but be all but the text
    muted: Style(fg: Color.rgb(0x6c, 0x6f, 0x85)),
    primary: Style(fg: Color.rgb(0x1e, 0x66, 0xf5)),
    accent: Style(fg: Color.rgb(0x88, 0x39, 0xef)),
    border: Style(fg: Color.rgb(0x9c, 0xa0, 0xb0)),
    // overlay2 at 0.4 over base, as Catppuccin's guide has a selection
    selection: Style(bg: Color.rgb(0xc1, 0xc3, 0xce)),
    error: Style(fg: Color.rgb(0xd2, 0x0f, 0x39)),
    // peach: the palette's yellow does not read on base
    warning: Style(fg: Color.rgb(0xfe, 0x64, 0x0b)),
    success: Style(fg: Color.rgb(0x40, 0xa0, 0x2b)),
    // sapphire: sky reads less on base
    info: Style(fg: Color.rgb(0x20, 0x9f, 0xb5)),
  );

  /// This theme with the fields given replaced.
  ThemeData copyWith({
    Brightness? brightness,
    Style? background,
    Style? surface,
    Style? text,
    Style? muted,
    Style? primary,
    Style? accent,
    Style? border,
    Style? selection,
    Style? error,
    Style? warning,
    Style? success,
    Style? info,
    Style? chrome,
    Style? well,
    Style? faint,
    Style? dim,
    Style? selectionIdle,
    Style? hover,
    Style? onPrimary,
    Style? shade,
    double? shadeAlpha,
    Map<int, int>? palette,
  }) => ThemeData(
    brightness: brightness ?? this.brightness,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    primary: primary ?? this.primary,
    accent: accent ?? this.accent,
    border: border ?? this.border,
    selection: selection ?? this.selection,
    error: error ?? this.error,
    warning: warning ?? this.warning,
    success: success ?? this.success,
    info: info ?? this.info,
    chrome: chrome ?? _chrome,
    well: well ?? _well,
    faint: faint ?? _faint,
    dim: dim ?? _dim,
    selectionIdle: selectionIdle ?? _selectionIdle,
    hover: hover ?? _hover,
    onPrimary: onPrimary ?? _onPrimary,
    shade: shade ?? _shade,
    shadeAlpha: shadeAlpha ?? _shadeAlpha,
    palette: palette ?? this.palette,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeData &&
      other.brightness == brightness &&
      other.background == background &&
      other.surface == surface &&
      other.text == text &&
      other.muted == muted &&
      other.primary == primary &&
      other.accent == accent &&
      other.border == border &&
      other.selection == selection &&
      other.error == error &&
      other.warning == warning &&
      other.success == success &&
      other.info == info &&
      other.chrome == chrome &&
      other.well == well &&
      other.faint == faint &&
      other.dim == dim &&
      other.selectionIdle == selectionIdle &&
      other.hover == hover &&
      other.onPrimary == onPrimary &&
      other.shade == shade &&
      other.shadeAlpha == shadeAlpha &&
      TerminalBrightness._samePalette(other.palette, palette);

  @override
  int get hashCode => Object.hash(
    brightness,
    background,
    surface,
    text,
    muted,
    primary,
    accent,
    border,
    selection,
    error,
    warning,
    success,
    info,
    Object.hash(
      chrome,
      well,
      faint,
      dim,
      selectionIdle,
      hover,
      onPrimary,
      shade,
      shadeAlpha,
      Object.hashAllUnordered([
        for (final e in palette.entries) Object.hash(e.key, e.value),
      ]),
    ),
  );
}

/// Whether [bright] is a color of [normal]'s hue (within 30°), not a
/// grey: a palette's bright entry as the color it brightens, where some
/// schemes (Solarized) put greys.
bool _sameHue(int normal, int bright) {
  (double, double) hueAndChroma(int rgb) {
    final r = (rgb >> 16 & 0xFF) / 255;
    final g = (rgb >> 8 & 0xFF) / 255;
    final b = (rgb & 0xFF) / 255;
    final max = [r, g, b].reduce((x, y) => x > y ? x : y);
    final min = [r, g, b].reduce((x, y) => x < y ? x : y);
    final chroma = max - min;
    if (chroma == 0) {
      return (0, 0);
    }
    final double h;
    if (max == r) {
      h = ((g - b) / chroma) % 6;
    } else if (max == g) {
      h = (b - r) / chroma + 2;
    } else {
      h = (r - g) / chroma + 4;
    }
    return (h * 60, chroma);
  }

  final (h1, c1) = hueAndChroma(normal);
  final (h2, c2) = hueAndChroma(bright);
  final apart = (h1 - h2).abs();
  return c1 >= 0.25 && c2 >= 0.25 && (apart <= 30 || apart >= 330);
}

/// A background of [color]; [fallback] where there is none.
Style _bg(Color? color, Style fallback) =>
    color == null ? fallback : Style(bg: color);

/// A text color of [color]; [fallback] where there is none.
Style _fg(Color? color, Style fallback) =>
    color == null ? fallback : Style(fg: color);

/// The theme of the widgets below it ([Theme.of]): [data], or with
/// [Theme.adaptive] the [dark] or the [light] theme by the brightness of the
/// terminal ([TerminalBrightness]), or with [Theme.terminal] the terminal's
/// own colors. The widgets that read it are rebuilt when it changes, the
/// others are not.
///
/// Without one an app is in twk's own themes, as under a [Theme.adaptive]
/// of the defaults: [ThemeData.dark] on a dark terminal, [ThemeData.light]
/// on a light one; on a terminal that does not say which it is, in its
/// own colors.
///
/// An app in Nord, its text read from the theme:
///
/// ```dart
/// Theme(
///   data: ThemeData.nord,
///   child: Builder(
///     builder: (context) => Text('Ready', style: Theme.of(context).success),
///   ),
/// )
/// ```
///
/// See also:
///
///  * [AnimatedTheme], which cross-fades to a new theme.
///  * `DefaultTextStyle`, the style text below takes where its own is
///    unset.
final class Theme extends StatelessWidget {
  /// Gives the widgets below [data] whatever the terminal's brightness.
  const Theme({required ThemeData this.data, required this.child, super.key})
    : dark = null,
      light = null,
      _terminal = false;

  /// Gives the widgets below the terminal's own colors
  /// ([ThemeData.terminalOf]): its greys from the background and text
  /// color it told, so that its color scheme shows through.
  const Theme.terminal({required this.child, super.key})
    : data = null,
      dark = null,
      light = null,
      _terminal = true;

  /// Gives the widgets below [dark] on a dark terminal and [light] on a
  /// light one, [ThemeData.dark] and [ThemeData.light] by default, switched
  /// when the terminal reports another color scheme.
  const Theme.adaptive({
    required this.child,
    ThemeData this.dark = ThemeData.dark,
    ThemeData this.light = ThemeData.light,
    super.key,
  }) : data = null,
       _terminal = false;

  /// The theme whatever the terminal's brightness; null for [dark] and
  /// [light].
  final ThemeData? data;

  /// The theme on a dark terminal; null for [data].
  final ThemeData? dark;

  /// The theme on a light terminal; null for [data].
  final ThemeData? light;

  /// The widgets the theme is for.
  final Widget child;

  /// Whether it gives the terminal's own colors.
  final bool _terminal;

  /// The theme at [context]: that of the nearest [Theme]; without one
  /// [ThemeData.dark] on a dark terminal and [ThemeData.light] on a light
  /// one, and the terminal's own colors ([ThemeData.terminal]) where the
  /// terminal did not say which it is ([TerminalBrightness.isKnown]): on a
  /// light terminal taken for dark the text of [ThemeData.dark] would be
  /// light grey on white, the terminal's own colors are right on either.
  /// [context] depends on it, as on an [InheritedWidget].
  static ThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ThemeScope>()?.data ??
      (TerminalBrightness.isKnown(context)
          ? switch (TerminalBrightness.of(context)) {
              Brightness.dark => ThemeData.dark,
              Brightness.light => ThemeData.light,
            }
          : ThemeData.terminalOf(context));

  @override
  Widget build(BuildContext context) {
    final theme =
        data ??
        switch (TerminalBrightness.of(context)) {
          _ when _terminal => ThemeData.terminalOf(context),
          Brightness.dark => dark!,
          Brightness.light => light!,
        };
    assert(
      theme.selection.bg != null,
      'ThemeData.selection has no background: what is selected is painted '
      'on it, and text over it keeps only a background',
    );
    return _ThemeScope(data: theme, child: child);
  }
}

/// What [Theme.of] finds.
final class _ThemeScope extends InheritedWidget {
  const _ThemeScope({required this.data, required super.child});

  final ThemeData data;

  @override
  bool updateShouldNotify(_ThemeScope oldWidget) => data != oldWidget.data;
}

/// Whether the terminal's colors are dark or light, for the widgets below
/// it ([TerminalBrightness.of]); [Theme.adaptive] picks its theme by it.
/// An app on a terminal puts it at the top: the brightness of the
/// terminal's background (`TerminalInfo.brightness`) at first, that of each
/// `ColorSchemeReport` after.
///
/// One of its own below the binding's says what the widgets under it see,
/// as a test or a preview of the light theme does:
///
/// ```dart
/// const TerminalBrightness(
///   brightness: Brightness.light,
///   child: Theme.adaptive(child: Text('in ThemeData.light')),
/// )
/// ```
final class TerminalBrightness extends InheritedWidget {
  /// Gives [child]'s subtree [brightness], which the terminal said unless
  /// [known] is false.
  const TerminalBrightness({
    required this.brightness,
    required super.child,
    this.known = true,
    this.background,
    this.foreground,
    this.palette = const {},
    super.key,
  });

  /// Whether the terminal's background is dark or light.
  final Brightness brightness;

  /// Whether the terminal said what its background is: false where it
  /// answered no query of it, [brightness] then a guess, its environment's
  /// (`COLORFGBG`) or dark. A guess picks the greys of the terminal's own
  /// colors ([ThemeData.terminal]), never twk's themes: a stale one would
  /// put a light theme's dark text on a dark terminal.
  final bool known;

  /// The terminal's default background as it told it (OSC 11),
  /// `0xRRGGBB`; null where it did not.
  final int? background;

  /// The terminal's default text color as it told it (OSC 10),
  /// `0xRRGGBB`; null where it did not.
  final int? foreground;

  /// The entries of the terminal's 16 colors it told (OSC 4), RGB
  /// (`0xRRGGBB`) by index; empty where it told none.
  final Map<int, int> palette;

  /// The brightness at [context]: that of the nearest [TerminalBrightness],
  /// dark without one. [context] depends on it.
  static Brightness of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TerminalBrightness>()
          ?.brightness ??
      Brightness.dark;

  /// Whether the brightness at [context] is the terminal's own word: the
  /// nearest [TerminalBrightness]'s [known], false without one. [context]
  /// depends on it.
  static bool isKnown(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TerminalBrightness>()?.known ??
      false;

  /// The terminal's default background at [context], as the nearest
  /// [TerminalBrightness] has it; null without one or where the terminal
  /// did not tell it. [context] depends on it.
  static int? backgroundOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TerminalBrightness>()
      ?.background;

  /// The terminal's default text color at [context], as the nearest
  /// [TerminalBrightness] has it; null without one or where the terminal
  /// did not tell it. [context] depends on it.
  static int? foregroundOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TerminalBrightness>()
      ?.foreground;

  /// The palette the terminal told at [context], as the nearest
  /// [TerminalBrightness] has it; empty without one. [context] depends on
  /// it.
  static Map<int, int> paletteOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TerminalBrightness>()
          ?.palette ??
      const {};

  @override
  InheritedElement createElement() => _TerminalBrightnessElement(this);

  @override
  bool updateShouldNotify(TerminalBrightness oldWidget) =>
      brightness != oldWidget.brightness ||
      known != oldWidget.known ||
      background != oldWidget.background ||
      foreground != oldWidget.foreground ||
      !_samePalette(palette, oldWidget.palette);

  static bool _samePalette(Map<int, int> a, Map<int, int> b) =>
      identical(a, b) ||
      (a.length == b.length && a.entries.every((e) => b[e.key] == e.value));
}

/// Keeps the theme of the terminal's colors ([ThemeData.terminalOf]),
/// made when first asked, until its [TerminalBrightness] has others.
final class _TerminalBrightnessElement extends InheritedElement {
  _TerminalBrightnessElement(TerminalBrightness super.widget);

  ThemeData? _theme;

  ThemeData get theme => _theme ??= switch (widget as TerminalBrightness) {
    TerminalBrightness(:final background?, :final foreground, :final palette) =>
      ThemeData.terminalOn(
        background,
        foreground: foreground,
        palette: palette,
      ),
    final terminal => ThemeData.terminal(terminal.brightness),
  };

  @override
  void updated(TerminalBrightness oldWidget) {
    if ((widget as TerminalBrightness).updateShouldNotify(oldWidget)) {
      _theme = null;
    }
    super.updated(oldWidget);
  }
}
