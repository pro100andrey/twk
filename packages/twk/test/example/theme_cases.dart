// The themes the example apps are tested in: each of their tests runs once
// in each, checking the cells against the theme it runs in.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// The color the terminal of the tests tells as its background: a dark one.
const terminalBackground = 0x16181d;

/// A theme the examples run in: how the app is wrapped, what the terminal
/// tells, and the [theme] the app then takes.
final class ThemeCase {
  /// The terminal's own colors, with no [Theme] around the app: those of a
  /// terminal that told its background, or of one that told nothing.
  ThemeCase.terminal(this.name, {required this.told})
    : preset = null,
      theme = told
          ? ThemeData.terminalOn(terminalBackground)
          : const ThemeData.terminal(Brightness.dark);

  /// [preset] under a [Theme].
  ThemeCase.preset(this.name, ThemeData this.preset)
    : told = true,
      theme = preset;

  /// What the group of the tests is called.
  final String name;

  /// The [Theme] the app is in; null for none.
  final ThemeData? preset;

  /// Whether the terminal tells its background.
  final bool told;

  /// The theme the app takes.
  final ThemeData theme;

  /// The background the terminal tells, null where it tells none.
  int? get background => told ? terminalBackground : null;

  /// [app] in the theme.
  Widget wrap(Widget app) =>
      preset == null ? app : Theme(data: preset!, child: app);
}

/// The themes twk provides: the terminal's own colors (the default) where
/// it told its background and where it told nothing, and the presets.
final themeCases = [
  ThemeCase.terminal('terminal colors', told: true),
  ThemeCase.terminal('terminal colors, none told', told: false),
  ThemeCase.preset('dark', ThemeData.dark),
  ThemeCase.preset('light', ThemeData.light),
  ThemeCase.preset('nord', ThemeData.nord),
  ThemeCase.preset('catppuccin mocha', ThemeData.catppuccinMocha),
  ThemeCase.preset('catppuccin latte', ThemeData.catppuccinLatte),
];

/// The case the running test is in, set before each.
late ThemeCase current;

/// The theme the app takes in the running test.
ThemeData get theme => current.theme;

/// Runs [tests] once in each of [themeCases], in a group of its name.
void forEachTheme(void Function() tests) {
  for (final c in themeCases) {
    group(c.name, () {
      setUp(() => current = c);
      tests();
    });
  }
}
