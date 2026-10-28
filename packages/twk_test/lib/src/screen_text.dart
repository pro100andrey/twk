/// The screen as text, for snapshots and failure messages: rows of the
/// emulator, plain or with the style of each run of cells marked.
library;

import 'package:twk_core/twk_core.dart' show Attr, Color, RenderObject;

import '../vt.dart';

// Examples can assume:
// import 'dart:convert';
// import 'package:twk_core/twk_core.dart' show Attr, Color;

/// [color], a number as [Color] makes one, as styles name it: `red` and
/// the other names of [Color] for the 16 colors of the palette (`brightRed`
/// for 9), `indexed(n)` for the rest of the palette, `#rrggbb` for a color
/// of 24 bits, `default` for the terminal's own.
///
/// ```dart
/// assert(colorName(const Color.indexed(9).value) == 'brightRed');
/// assert(colorName(const Color.rgb(16, 32, 48).value) == '#102030');
/// ```
String colorName(int color) {
  if (color == 0) {
    return 'default';
  }
  if (color & 0x1000000 != 0) {
    return '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
  final index = color & 0xFF;
  return index < 16 ? _colorNames[index] : 'indexed($index)';
}

/// The [Color] that [color], a number as [Color] makes one, is: as [VtCell]
/// keeps its colors, `0` being [Color.defaultColor].
///
/// ```dart
/// assert(colorOf(Color.red.value) == Color.red);
/// assert(colorOf(0) == Color.defaultColor);
/// ```
Color colorOf(int color) => switch (color) {
  0 => Color.defaultColor,
  _ when color & 0x2000000 != 0 => Color.indexed(color & 0xFF),
  _ => Color.rgb((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF),
};

const _colorNames = [
  'black',
  'red',
  'green',
  'yellow',
  'blue',
  'magenta',
  'cyan',
  'white',
  'brightBlack',
  'brightRed',
  'brightGreen',
  'brightYellow',
  'brightBlue',
  'brightMagenta',
  'brightCyan',
  'brightWhite',
];

/// The attributes of [attrs], a set of [Attr]'s bits, by the names of
/// [Attr]'s constants, in the order of the bits.
List<String> attrNames(int attrs) {
  final underline = (attrs & Attr.underlineMask) >> 3;
  return [
    if (attrs & Attr.bold != 0) 'bold',
    if (attrs & Attr.dim != 0) 'dim',
    if (attrs & Attr.italic != 0) 'italic',
    if (underline >= _underlines.length)
      'underline($underline)'
    else if (underline != 0)
      _underlines[underline],
    if (attrs & Attr.blink != 0) 'blink',
    if (attrs & Attr.reverse != 0) 'reverse',
    if (attrs & Attr.hidden != 0) 'hidden',
    if (attrs & Attr.strike != 0) 'strike',
    if (attrs & Attr.overline != 0) 'overline',
  ];
}

const _underlines = [
  '',
  'underline',
  'doubleUnderline',
  'curlyUnderline',
  'dottedUnderline',
  'dashedUnderline',
];

/// The style of [cell]: its attributes ([attrNames]), its color, `on` and
/// its background, `ul=` and the color of its underline, each left out
/// when it is the default ([colorName]) — `bold red on #102030`; `''` for
/// none.
///
/// ```dart
/// final vt = Vt(2, 1)..feed(utf8.encode('\x1b[1;31ma'));
/// assert(styleOf(vt.cell(0, 0)) == 'bold red');
/// ```
String styleOf(VtCell cell) => [
  ...attrNames(cell.attrs),
  if (cell.fg != 0) colorName(cell.fg),
  if (cell.bg != 0) 'on ${colorName(cell.bg)}',
  if (cell.ul != 0) 'ul=${colorName(cell.ul)}',
].join(' ');

/// [cell] as a snapshot with styles shows it: its text, `[` doubled, in
/// `[style]…[/]` when it has a style ([styleOf]).
String markedCell(VtCell cell) {
  final text = cell.text.replaceAll('[', '[[');
  final style = styleOf(cell);
  return style.isEmpty ? text : '[$style]$text[/]';
}

/// Row [y] of [vt]'s screen as text: the text of its cells, a wide glyph
/// once, without the blanks that end it. With [styles] each run of cells of
/// one style is in `[style]…[/]` ([styleOf]), and a `[` of the text is
/// doubled. A space without an attribute that shows on a blank
/// ([Attr.visibleOnBlank]) shows its background alone: between two cells
/// of one style with that background it is in their run, elsewhere its
/// style is its background. The cells that end the row are left out while
/// they show nothing.
///
/// ```dart
/// final vt = Vt(10, 1)..feed(utf8.encode('a\x1b[1mbc\x1b[0m d'));
/// assert(rowText(vt, 0) == 'abc d');
/// assert(rowText(vt, 0, styles: true) == 'a[bold]bc[/] d');
/// ```
String rowText(Vt vt, int y, {bool styles = false}) {
  final cells = [
    for (var x = 0; x < vt.width; x++)
      // the right half of a wide glyph is written with the left
      if (vt.cell(x, y) case final cell when cell.role != -1) cell,
  ];
  if (!styles) {
    return cells.map((c) => c.text).join().trimRight();
  }
  while (cells.isNotEmpty && _blank(cells.last) && cells.last.bg == 0) {
    cells.removeLast();
  }
  final keys = [
    for (final c in cells)
      if (!_blank(c))
        styleOf(c)
      else if (c.bg != 0)
        'on ${colorName(c.bg)}'
      else
        '',
  ];
  for (var i = 0; i < cells.length; i++) {
    if (!_blank(cells[i])) {
      continue;
    }
    var j = i;
    while (j < cells.length && _blank(cells[j])) {
      j++;
    }
    if (i > 0 && j < cells.length && keys[i - 1] == keys[j]) {
      final around = cells[i - 1];
      for (var k = i; k < j; k++) {
        if (cells[k].bg == around.bg &&
            around.attrs & Attr.visibleOnBlank == 0) {
          keys[k] = keys[j];
        }
      }
    }
    i = j;
  }
  final out = StringBuffer();
  var style = '';
  for (final (i, cell) in cells.indexed) {
    final next = keys[i];
    if (next != style) {
      if (style.isNotEmpty) {
        out.write('[/]');
      }
      if (next.isNotEmpty) {
        out.write('[$next]');
      }
      style = next;
    }
    out.write(cell.text.replaceAll('[', '[['));
  }
  if (style.isNotEmpty) {
    out.write('[/]');
  }
  return out.toString();
}

/// Whether [cell] is a space that shows only its background.
bool _blank(VtCell cell) =>
    cell.text == ' ' && cell.attrs & Attr.visibleOnBlank == 0;

/// The rows of [vt]'s screen as [rowText] gives each, without the empty
/// rows that end the screen.
List<String> screenRows(Vt vt, {bool styles = false}) {
  final rows = [
    for (var y = 0; y < vt.height; y++) rowText(vt, y, styles: styles),
  ];
  while (rows.isNotEmpty && rows.last.isEmpty) {
    rows.removeLast();
  }
  return rows;
}

/// [vt]'s screen as a failure message shows it: the rows numbered, styles
/// marked ([rowText]), the empty rows that end the screen summed up.
///
/// ```dart
/// final vt = Vt(10, 3)..feed(utf8.encode('ok'));
/// assert(describeScreen(vt) == '0│ok\n(rows 1–2 blank)');
/// ```
String describeScreen(Vt vt) {
  final rows = screenRows(vt, styles: true);
  final digits = '${vt.height - 1}'.length;
  final out = [
    for (final (y, row) in rows.indexed) '${'$y'.padLeft(digits)}│$row',
  ];
  final blank = rows.length;
  if (blank == vt.height - 1) {
    out.add('(row $blank blank)');
  } else if (blank < vt.height) {
    out.add('(rows $blank–${vt.height - 1} blank)');
  }
  return out.join('\n');
}

/// [vt]'s screen ([describeScreen]) and the render tree from [root] down,
/// as a failure message shows them, the tree as `describe().toStringDeep()`
/// gives it; without the screen with [screen] false.
String describeApp(Vt vt, RenderObject? root, {bool screen = true}) => [
  if (screen) ...['screen ${vt.width}×${vt.height}:', describeScreen(vt), ''],
  'render tree:',
  root?.describe().toStringDeep() ?? 'none',
].join('\n');
