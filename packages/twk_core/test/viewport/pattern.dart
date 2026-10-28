/// A screen that showed something everywhere before a viewport was drawn
/// on it, to tell whether a cell outside the viewport was touched.
library;

import 'dart:convert';

import 'package:twk_test/vt.dart';

/// Puts a letter on every cell of [vt], in its row's colors, and the
/// cursor at [cursor] with SGR reset.
void paintPattern(Vt vt, (int, int) cursor) {
  final b = StringBuffer();
  for (var y = 0; y < vt.height; y++) {
    b.write('\x1b[${y + 1}H\x1b[38;5;${1 + y % 7};48;5;${16 + y}m');
    for (var x = 0; x < vt.width; x++) {
      b.writeCharCode(0x61 + (x + y) % 26);
    }
  }
  b.write('\x1b[m\x1b[${cursor.$2 + 1};${cursor.$1 + 1}H');
  vt.feed(utf8.encode(b.toString()));
}

/// What [cell] shows: its text and style, which half of a glyph it is,
/// its hyperlink.
String shown(VtCell cell) => '$cell ${cell.role} ${cell.link}';

/// What each cell of [vt] for which [inside] is false shows, by its
/// column and row.
Map<(int, int), String> shownOutside(
  Vt vt,
  bool Function(int x, int y) inside,
) => {
  for (var y = 0; y < vt.height; y++)
    for (var x = 0; x < vt.width; x++)
      if (!inside(x, y)) (x, y): shown(vt.cell(x, y)),
};

/// The cells of [now] that don't show what they did in [was]; a cell
/// [was] doesn't have (the screen grew) must be blank.
List<String> changes(Map<(int, int), String> was, Map<(int, int), String> now) {
  final blank = shown(VtCell());
  return [
    for (final MapEntry(:key, :value) in now.entries)
      if (value != (was[key] ?? blank))
        '$key was ${was[key] ?? blank}, now $value',
  ].take(5).toList();
}
