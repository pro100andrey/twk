/// The colours a tape's terminal has: its default text and background,
/// its cursor and the 16 colours of its palette (`Set Theme`).
library;

import 'dart:convert';

/// A terminal's colours, each 0xRRGGBB: the default [foreground] and
/// [background], the [cursor] and [ansi], palette colours 0 to 15 (black,
/// red, green, yellow, blue, magenta, cyan, white, then their bright
/// ones).
final class TapeTheme {
  /// A theme named [name] of these colours.
  const TapeTheme({
    required this.name,
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.ansi,
  });

  /// The theme [value] names, case aside ([builtIn]), or a JSON object
  /// of one: `background`, `foreground` and `cursor`, `black` to `white`
  /// and `brightBlack` to `brightWhite` (`purple` for `magenta`, as VHS
  /// and iTerm2's schemes have it), each `#rrggbb`, a colour it leaves
  /// out [dark]'s. A [FormatException] for a name there is not, a colour
  /// that is not `#rrggbb` and a key no theme has.
  factory TapeTheme.parse(String value) {
    final text = value.trim();
    if (!text.startsWith('{')) {
      final theme = builtIn[text.toLowerCase()];
      if (theme == null) {
        throw FormatException(
          'no theme "$text"; there are ${builtIn.keys.join(', ')} '
          'and a JSON object of colours',
        );
      }
      return theme;
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw FormatException('the theme is no JSON object: ${e.message}');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('the theme is no JSON object');
    }
    final colors = json;
    int? color(String key) {
      final v = colors[key];
      if (v == null) {
        return null;
      }
      final m = v is String ? _hex.firstMatch(v) : null;
      if (m == null) {
        throw FormatException("the theme's $key is no #rrggbb: $v");
      }
      return int.parse(m[1]!, radix: 16);
    }

    for (final key in json.keys) {
      if (!_keys.contains(key)) {
        throw FormatException('a theme has no colour "$key"');
      }
    }
    final ansi = [
      for (final (i, key) in _ansiKeys.indexed)
        color(key) ?? color(_aliases[key] ?? key) ?? dark.ansi[i],
    ];
    final foreground = color('foreground') ?? dark.foreground;
    return TapeTheme(
      name: switch (json['name']) {
        final String name => name,
        _ => 'custom',
      },
      foreground: foreground,
      background: color('background') ?? dark.background,
      cursor: color('cursor') ?? foreground,
      ansi: List.unmodifiable(ansi),
    );
  }

  /// What `Set Theme` names, or `custom`.
  final String name;

  /// The default text colour, 0xRRGGBB.
  final int foreground;

  /// The default background colour, 0xRRGGBB.
  final int background;

  /// The cursor's colour, 0xRRGGBB.
  final int cursor;

  /// Palette colours 0 to 15.
  final List<int> ansi;

  /// The theme a tape has when it sets none: a dark grey background.
  static const dark = TapeTheme(
    name: 'dark',
    foreground: 0xcccccc,
    background: 0x1e1e1e,
    cursor: 0xaeafad,
    ansi: [
      0x000000, 0xcd3131, 0x0dbc79, 0xe5e510, 0x2472c8, 0xbc3fbc, 0x11a8cd, //
      0xe5e5e5, 0x666666, 0xf14c4c, 0x23d18b, 0xf5f543, 0x3b8eea, 0xd670d6,
      0x29b8db, 0xffffff,
    ],
  );

  /// Dark text on white.
  static const light = TapeTheme(
    name: 'light',
    foreground: 0x333333,
    background: 0xffffff,
    cursor: 0x333333,
    ansi: [
      0x000000, 0xcd3131, 0x00bc00, 0x949800, 0x0451a5, 0xbc05bc, 0x0598bc, //
      0x555555, 0x666666, 0xcd3131, 0x14ce14, 0xb5ba00, 0x0451a5, 0xbc05bc,
      0x0598bc, 0xa5a5a5,
    ],
  );

  /// xterm's colours, on black: what twk_term's emulator has by default.
  static const xterm = TapeTheme(
    name: 'xterm',
    foreground: 0xe5e5e5,
    background: 0x000000,
    cursor: 0xe5e5e5,
    ansi: [
      0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, //
      0xe5e5e5, 0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff,
      0x00ffff, 0xffffff,
    ],
  );

  /// The themes `Set Theme` names, by their names.
  static const Map<String, TapeTheme> builtIn = {
    'dark': dark,
    'light': light,
    'xterm': xterm,
  };

  static final _hex = RegExp(r'^#([0-9a-fA-F]{6})$');

  static const _ansiKeys = [
    'black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white', //
    'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue',
    'brightMagenta', 'brightCyan', 'brightWhite',
  ];

  static const _aliases = {
    'magenta': 'purple',
    'brightMagenta': 'brightPurple',
  };

  static const Set<String> _keys = {
    ..._ansiKeys,
    'purple',
    'brightPurple',
    'background',
    'foreground',
    'cursor',
    'selection',
    'name',
  };
}
