// The theme's colors as the shell paints with them, and the gallery's
// spacing (doc/design.md, "Colour").
import 'package:twk/twk.dart';

/// The colors of a [ThemeData], each slot and token as one color: the
/// background slots' backgrounds, the others' text colors, and the
/// tokens derived from them (doc/design.md, "Colour").
final class Tokens {
  Tokens(this.theme)
    : dark = theme.brightness == Brightness.dark,
      background = theme.background.bg ?? Color.defaultColor,
      surface = theme.surface.bg ?? Color.defaultColor,
      text = theme.text.fg ?? Color.defaultColor,
      muted = theme.muted.fg ?? Color.defaultColor,
      primary = theme.primary.fg ?? Color.defaultColor,
      accent = theme.accent.fg ?? Color.defaultColor,
      border = theme.border.fg ?? Color.defaultColor,
      selection = theme.selection.bg ?? Color.defaultColor,
      error = theme.error.fg ?? Color.defaultColor,
      warning = theme.warning.fg ?? Color.defaultColor,
      success = theme.success.fg ?? Color.defaultColor,
      info = theme.info.fg ?? Color.defaultColor,
      chrome = theme.chrome.bg ?? Color.defaultColor,
      well = theme.well.bg ?? Color.defaultColor,
      faint = theme.faint.fg ?? Color.defaultColor,
      dim = theme.dim.fg ?? Color.defaultColor,
      selectionIdle = theme.selectionIdle.bg ?? Color.defaultColor,
      hover = theme.hover.bg ?? Color.defaultColor,
      onPrimary = theme.onPrimary.fg ?? Color.defaultColor,
      shade = theme.shade.bg ?? Color.defaultColor,
      shadeAlpha = theme.shadeAlpha;

  /// The theme the colors are of.
  final ThemeData theme;

  final bool dark;
  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
  final Color primary;
  final Color accent;
  final Color border;
  final Color selection;
  final Color error;
  final Color warning;
  final Color success;
  final Color info;
  final Color chrome;
  final Color well;
  final Color faint;
  final Color dim;
  final Color selectionIdle;
  final Color hover;
  final Color onPrimary;
  final Color shade;
  final double shadeAlpha;

  /// [a] [k] of the way to [b], as the design lights a row the mouse is
  /// over; the theme's [hover] where either is not RGB, which
  /// [Color.lerp] would leave [a] below half of the way: no light at all
  /// on the terminal's own colors.
  Color lit(Color a, Color b, double k) =>
      a.isRgb && b.isRgb ? Color.lerp(a, b, k) : hover;

  /// The color of the slot [name]: `primary`, `success`…
  Color named(String name) => switch (name) {
    'primary' => primary,
    'accent' => accent,
    'success' => success,
    'warning' => warning,
    'error' => error,
    'info' => info,
    'muted' => muted,
    'border' => border,
    _ => text,
  };
}

/// The themes the gallery cycles through, by the names a route gives them,
/// in the design's order; the last the terminal's own colors, of the
/// terminal's colors as [galleryTheme] gives it.
const galleryThemes = <String, (String, ThemeData)>{
  'dark': ('Dark', ThemeData.dark),
  'light': ('Light', ThemeData.light),
  'nord': ('Nord', ThemeData.nord),
  'mocha': ('Catppuccin Mocha', ThemeData.catppuccinMocha),
  'latte': ('Catppuccin Latte', ThemeData.catppuccinLatte),
  'terminal': ('Terminal', ThemeData.terminal(Brightness.dark)),
};

/// The theme of [galleryThemes] named [name] at [context]: the terminal's
/// own colors those it told ([ThemeData.terminalOf]).
ThemeData galleryTheme(String name, BuildContext context) => name == 'terminal'
    ? ThemeData.terminalOf(context)
    : galleryThemes[name]!.$2;

/// The page's margin at the left, on a page 70 columns wide or more.
const pagePad = 3;

/// The sidebar's width on a screen [cols] wide.
int sidebarWidth(int cols) => cols >= 150
    ? 32
    : cols >= 110
    ? 28
    : cols >= 96
    ? 26
    : 22;

/// The inspector's width on a screen [cols] wide.
int inspectorWidth(int cols) => cols >= 150 ? 34 : 30;
