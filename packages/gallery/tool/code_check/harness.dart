/// Renders the widgets the Code check built from the gallery's Code tabs
/// in twk's tester ([testTwk]), one test each, and writes their cells.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// One widget to render: what [build] returns, in the theme named
/// [theme] (`dark`, `light`, `nord`, `mocha`, `latte`), on a stage of
/// [width] × [height] cells, at [ms] milliseconds; [keys] pressed and
/// [type] typed after its first frame, as a route's `keys=` and `type=`;
/// with [terminal], the widget in the terminal's own colors.
final class Entry {
  const Entry(
    this.id,
    this.build, {
    required this.theme,
    required this.width,
    required this.height,
    required this.ms,
    this.keys = const [],
    this.type = '',
    this.terminal = false,
  });

  /// Names the entry in the output.
  final String id;

  /// The widget, built in the test.
  final Widget Function() build;

  /// The gallery's name of the theme (a route's `theme=`).
  final String theme;

  /// The room the stage gives the widget.
  final int width;

  /// The room the stage gives the widget.
  final int height;

  /// The time on the clock when the cells are read.
  final int ms;

  /// Keys pressed after the first frame, named as `TwkTester.press` names
  /// them.
  final List<String> keys;

  /// Text typed after [keys].
  final String type;

  /// Whether the widget is under [ThemeData.terminal] of the theme's
  /// brightness, as `runApp` gives an app, where the page's stage draws
  /// the app in the terminal's colors (its `codeTheme: 'terminal'`).
  final bool terminal;
}

/// twk's preset of each of the gallery's themes.
const themes = <String, ThemeData>{
  'dark': ThemeData.dark,
  'light': ThemeData.light,
  'nord': ThemeData.nord,
  'mocha': ThemeData.catppuccinMocha,
  'latte': ThemeData.catppuccinLatte,
};

const ValueKey<String> _stage = ValueKey('code-stage');

/// Declares a test for each of [entries]; when all have run, writes what
/// each showed to the file at [outPath] as JSON: by id, the widget's
/// rectangle and its cells (`[text, fg, bg, attrs, role]`, colors and
/// attributes numbered as [Color] and [Attr] number them), or the error
/// it ended with.
void renderAll(List<Entry> entries, String outPath) {
  final results = <String, Object?>{};
  for (final e in entries) {
    testTwk(e.id, (t) async {
      final r = results[e.id] = <String, Object?>{};
      try {
        await _render(t, e, r);
      } on Object catch (error, stack) {
        r['error'] = '$error';
        r['stack'] = '$stack'.split('\n').take(12).join('\n');
      }
      final logs = [
        for (final l in t.logs.records)
          if (l.level.index >= LogLevel.warning.index)
            [
              [l.level.name, l.message, ?l.error].join(': '),
              ...'${l.stack ?? ''}'.split('\n').take(8),
            ].join('\n').trimRight(),
      ];
      if (logs.isNotEmpty) {
        r['logs'] = logs.take(20).toList();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }
  tearDownAll(() {
    File(outPath).writeAsStringSync(jsonEncode(results));
  });
}

Future<void> _render(TwkTester t, Entry e, Map<String, Object?> r) async {
  final theme = themes[e.theme] ?? (throw ArgumentError.value(e.theme));
  final bg = theme.background.bg!;
  await t.pumpWidget(
    Theme(
      data: theme,
      child: Overlay(
        child: Box(
          style: theme.background.merge(theme.text),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: _stage,
              child: e.terminal
                  ? Theme(
                      data: ThemeData.terminal(theme.brightness),
                      child: e.build(),
                    )
                  : e.build(),
            ),
          ),
        ),
      ),
    ),
    size: (e.width, e.height),
    duration: Duration.zero,
    backgroundRgb: bg.value & 0xFFFFFF,
  );
  for (final key in e.keys) {
    await t.press(key);
    await t.pump();
  }
  if (e.type.isNotEmpty) {
    await t.type(e.type);
    await t.pump();
  }
  final rest = Duration(milliseconds: e.ms) - t.clock.elapsed;
  await t.pump(rest.isNegative ? Duration.zero : rest);
  final errors = [
    for (final e in find.byType(ErrorWidget).evaluate())
      if (e.widget case final ErrorWidget w) w.message,
  ];
  if (errors.isNotEmpty) {
    r['errorWidgets'] = errors;
  }
  final rect = t.rect(find.byKey(_stage));
  r['rect'] = {
    'x': rect.x,
    'y': rect.y,
    'w': rect.width,
    'h': rect.height,
  };
  final vt = t.vt;
  final x1 = rect.x + rect.width < vt.width ? rect.x + rect.width : vt.width;
  final y1 = rect.y + rect.height < vt.height
      ? rect.y + rect.height
      : vt.height;
  r['cells'] = [
    for (var y = rect.y < 0 ? 0 : rect.y; y < y1; y++)
      [
        for (var x = rect.x < 0 ? 0 : rect.x; x < x1; x++) _cell(vt.cell(x, y)),
      ],
  ];
  r['cursor'] = t.cursorVisible ? [t.cursor.$1, t.cursor.$2] : null;
}

List<Object> _cell(VtCell c) => [c.text, c.fg, c.bg, c.attrs, c.role];
