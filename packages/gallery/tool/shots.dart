// Draws the gallery's golden screens (test/goldens/) as SVGs, into
// doc/shots/: each page's stage, the widget as the page shows it, in the
// dark and the light theme (doc/shots/<group>/<page>.<theme>.svg), and a
// few whole screens (doc/shots/screens/<name>.svg) for the READMEs. Run
// from this package's directory after the goldens changed:
//
//   dart run tool/shots.dart
//
// It reads the goldens alone, so what it writes changes only with them;
// `xtask gallery-shots` runs it and fails where that changed a file.
//
// With `--png <directory>` it also makes a PNG of each whole screen there,
// with rsvg-convert (librsvg), for pub.dev's screenshots: PNGs, drawn in
// the fonts this machine has, so not held to anything.
//
//   dart run tool/shots.dart --png ../twk/doc/screenshots
import 'dart:io';

import 'package:gallery/src/shell/tokens.dart' show galleryThemes;
import 'package:path/path.dart' as p;

import 'shots/svg.dart';

/// The whole screens drawn, by the name of their file: the golden each
/// is, under test/goldens/.
const screens = {
  'table-dark': 'data/table.dark',
  'text-light': 'text/text.light',
  'dialog-dark': 'overlays/dialog.open',
  'palette-dark': 'text/text.palette',
};

/// The themes each page's stage is drawn in.
const themes = ['dark', 'light'];

Future<void> main(List<String> args) async {
  final png = switch (args) {
    ['--png', final dir] => dir,
    [] => null,
    _ => throw ArgumentError('usage: shots.dart [--png <directory>]'),
  };
  final package = p.dirname(p.dirname(p.fromUri(Platform.script)));
  final goldens = p.join(package, 'test', 'goldens');
  final out = Directory(p.join(package, 'doc', 'shots'));
  if (out.existsSync()) {
    out.deleteSync(recursive: true);
  }
  var written = 0;
  void write(String path, String svg) {
    File(p.join(out.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(svg);
    written++;
  }

  for (final group in Directory(goldens).listSync().whereType<Directory>()) {
    for (final theme in themes) {
      final suffix = '.$theme.txt';
      for (final file in group.listSync().whereType<File>()) {
        if (!file.path.endsWith(suffix)) {
          continue;
        }
        final shot = Shot.parse(file.readAsStringSync());
        final page = p.basename(file.path).replaceFirst(suffix, '');
        write(
          p.join(p.basename(group.path), '$page.$theme.svg'),
          svgOf(widgetOf(stageOf(shot)), paletteOf(theme)),
        );
      }
    }
  }
  for (final MapEntry(key: name, value: golden) in screens.entries) {
    final shot = Shot.parse(
      File(p.join(goldens, '$golden.txt')).readAsStringSync(),
    );
    final theme = name.endsWith('-light') ? 'light' : 'dark';
    write(p.join('screens', '$name.svg'), svgOf(shot, paletteOf(theme)));
  }
  stdout.writeln('${p.relative(out.path)}: $written SVGs');
  if (png != null) {
    Directory(png).createSync(recursive: true);
    for (final name in screens.keys) {
      final to = p.join(png, '$name.png');
      final result = await Process.run('rsvg-convert', [
        p.join(out.path, 'screens', '$name.svg'),
        '-o',
        to,
      ]);
      if (result.exitCode != 0) {
        throw ProcessException('rsvg-convert', [], '${result.stderr}');
      }
      stdout.writeln(to);
    }
  }
}

/// The palette of the gallery's [theme]: its background and its text.
ShotPalette paletteOf(String theme) {
  final data = galleryThemes[theme]!.$2;
  return ShotPalette(
    foreground: data.text.fg!.value & 0xFFFFFF,
    background: data.background.bg!.value & 0xFFFFFF,
  );
}

/// The page's stage in [shot], a screen of the gallery: below the rule
/// under the Preview and Code tabs, from where the rule starts to the
/// options' divider (`┬`) or the screen's edge, down to the row above the
/// key hints. A [StateError] where the screen has no such rule.
Shot stageOf(Shot shot) {
  for (final (y, row) in shot.rows.indexed) {
    final texts = [for (final c in row) c.text];
    if (!texts.contains('━')) {
      continue;
    }
    final left = texts.indexOf('─');
    final divider = texts.indexOf('┬');
    final right = divider < 0 ? shot.width : divider;
    return shot.crop(left, y + 1, right - left, shot.height - 2 - y);
  }
  throw StateError('no rule under the tabs');
}

/// The widget in [stage], a page's stage: the marks the gallery puts at
/// its corners (`┌ ┐ └ ┘`), the size under them (`26 × 3`) and [margin]
/// cells around, as far as the stage goes; the whole stage where it shows
/// no size.
Shot widgetOf(Shot stage, {int margin = 2}) {
  // a character a cell, so that an index is a column
  final rows = [
    for (final row in stage.rows)
      [
        for (final c in row)
          if (c.text.length == 1) c.text else '?',
      ].join(),
  ];
  for (var y = rows.length - 1; y > 0; y--) {
    final size = RegExp(r'\d+ × \d+').firstMatch(rows[y]);
    if (size == null) {
      continue;
    }
    // the bottom marks, on the row above the size, the right one over its
    // end or just after it
    final bottom = y - 1;
    final right = rows[bottom].lastIndexOf('┘', size.end);
    final left = right < 0 ? -1 : rows[bottom].lastIndexOf('└', right);
    var top = bottom - 1;
    while (top >= 0 && (right < 0 || rows[top][right] != '┐')) {
      top--;
    }
    if (left < 0 || top < 0 || rows[top][left] != '┌') {
      return stage;
    }
    final x0 = (left - margin).clamp(0, stage.width);
    final x1 = (right + 1 + margin).clamp(0, stage.width);
    final y0 = (top - margin ~/ 2).clamp(0, stage.height);
    final y1 = (y + 1 + margin ~/ 2).clamp(0, stage.height);
    return stage.crop(x0, y0, x1 - x0, y1 - y0);
  }
  return stage;
}
