/// A screen kept in a file, as `matchesScreenFile` reads and writes it: a
/// layer of text, a layer of styles of a character a cell, and a legend
/// naming the style of each character.
library;

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show Attr, stringWidth;

import '../vt.dart';
import 'screen_text.dart';

/// The environment variable that makes `matchesScreenFile` write the
/// screen to its file instead of matching it.
const updateScreenFilesVariable = 'TWK_UPDATE_GOLDENS';

/// Whether [updateScreenFilesVariable] is set to something other than `0`
/// or nothing, unless [updateScreenFilesOverride] says.
bool get updatingScreenFiles {
  if (updateScreenFilesOverride case final update?) {
    return update;
  }
  final value = Platform.environment[updateScreenFilesVariable];
  return value != null && value.isNotEmpty && value != '0';
}

/// Whether files are written instead of matched, in place of the
/// environment's say; null to let it say.
@visibleForTesting
bool? updateScreenFilesOverride;

/// A screen as the file holds it: its size, its cursor, the rows of its
/// text and of its styles, and the style each character of the styles
/// stands for.
final class ScreenFile {
  ScreenFile._(
    this.width,
    this.height,
    this.cursor,
    this.text,
    this.styles,
    this.legend,
  );

  /// The screen of [vt] with the cursor at [cursor] (null while hidden),
  /// its styles given the characters [previous] gave them where it had
  /// them, so that writing a file again changes only what changed.
  factory ScreenFile.of(Vt vt, (int, int)? cursor, {ScreenFile? previous}) {
    final legend = <String, String>{};
    final taken = <String>{};
    if (previous != null) {
      for (final MapEntry(key: char, value: style) in previous.legend.entries) {
        legend[style] = char;
      }
    }
    final used = <String, String>{};
    final text = <String>[];
    final styles = <String>[];
    var next = 0;
    String charOf(String style) {
      if (style.isEmpty) {
        return ' ';
      }
      if (used[style] case final char?) {
        return char;
      }
      var char = legend[style];
      if (char == null || taken.contains(char)) {
        do {
          if (next == _chars.length) {
            throw ScreenFileException(
              'the screen has more than ${_chars.length} styles',
            );
          }
          char = _chars[next++];
        } while (taken.contains(char) || legend.containsValue(char));
      }
      taken.add(char);
      used[style] = char;
      return char;
    }

    for (var y = 0; y < vt.height; y++) {
      final row = StringBuffer();
      final style = StringBuffer();
      for (var x = 0; x < vt.width; x++) {
        final cell = vt.cell(x, y);
        if (cell.role != -1) {
          row.write(cell.text);
        }
        style.write(charOf(cellStyle(cell)));
      }
      text.add('$row');
      styles.add('$style');
    }
    return ScreenFile._(vt.width, vt.height, cursor, text, styles, {
      for (final MapEntry(key: style, value: char) in used.entries) char: style,
    });
  }

  /// The screen [source] holds, as [write] wrote it; a [FormatException]
  /// where it is not one.
  factory ScreenFile.parse(String source) {
    final lines = source.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    final header = _header.firstMatch(lines.isEmpty ? '' : lines.first);
    if (header == null) {
      throw FormatException(
        'the first line is not "screen <columns>×<rows>, cursor …"',
        lines.isEmpty ? '' : lines.first,
      );
    }
    final width = int.parse(header[1]!);
    final height = int.parse(header[2]!);
    final cursor = header[3] == null
        ? null
        : (int.parse(header[3]!), int.parse(header[4]!));
    var i = 1;
    List<String> layer(String name) {
      if (i >= lines.length || lines[i] != name) {
        throw FormatException('line ${i + 1} is not "$name"');
      }
      i++;
      final rows = <String>[];
      for (var y = 0; y < height; y++, i++) {
        final line = i < lines.length ? lines[i] : '';
        if (line.length < 2 || !line.startsWith('│') || !line.endsWith('│')) {
          throw FormatException('line ${i + 1} is not a row in │…│', line);
        }
        rows.add(line.substring(1, line.length - 1));
      }
      return rows;
    }

    final text = layer('text');
    final styles = layer('styles');
    for (final (y, row) in styles.indexed) {
      if (row.length != width) {
        throw FormatException(
          'row $y of the styles has ${row.length} characters, not $width',
        );
      }
    }
    if (i >= lines.length || lines[i] != 'legend') {
      throw FormatException('line ${i + 1} is not "legend"');
    }
    final legend = <String, String>{};
    for (i++; i < lines.length; i++) {
      final line = lines[i];
      if (line.length < 3 || line[1] != ' ') {
        throw FormatException('line ${i + 1} is not "<character> <style>"');
      }
      legend[line[0]] = line.substring(2);
    }
    return ScreenFile._(width, height, cursor, text, styles, legend);
  }

  /// The screen's columns.
  final int width;

  /// The screen's rows.
  final int height;

  /// Where the cursor is, column and row; null while it is hidden.
  final (int, int)? cursor;

  /// Each row's text: the text of its cells, a wide glyph once.
  final List<String> text;

  /// Each row's styles: a character a cell, a space for a cell without a
  /// style.
  final List<String> styles;

  /// The style each character of [styles] stands for, as [cellStyle]
  /// names it.
  final Map<String, String> legend;

  /// The style of the cell at column [x] of row [y], `''` for none, or
  /// null where the legend does not name its character.
  String? styleAt(int x, int y) {
    final char = styles[y][x];
    return char == ' ' ? '' : legend[char];
  }

  /// The file's text.
  String write() {
    final where = switch (cursor) {
      (final x, final y) => 'cursor at $x,$y',
      null => 'cursor hidden',
    };
    return [
      'screen $width×$height, $where',
      'text',
      for (final row in text) '│$row│',
      'styles',
      for (final row in styles) '│$row│',
      'legend',
      for (final MapEntry(key: char, value: style) in legend.entries)
        '$char $style',
      '',
    ].join('\n');
  }
}

/// A screen a [ScreenFile] cannot hold.
final class ScreenFileException implements Exception {
  /// Says why: [message].
  ScreenFileException(this.message);

  /// Why the screen cannot be held.
  final String message;

  @override
  String toString() => 'ScreenFileException: $message';
}

/// The style of [cell] as a [ScreenFile] names it: [styleOf]'s, and
/// `link=` and the hyperlink's target where it has one. A space that shows
/// only its background ([Attr.visibleOnBlank] none of its attributes) has
/// the background's alone, whatever text color and attributes it was
/// written with, as they do not show.
String cellStyle(VtCell cell) {
  final blank = cell.text == ' ' && cell.attrs & Attr.visibleOnBlank == 0;
  return [
    if (!blank) styleOf(cell) else if (cell.bg != 0) 'on ${colorName(cell.bg)}',
    if (cell.link case final link?) 'link=$link',
  ].where((s) => s.isNotEmpty).join(' ');
}

final _header = RegExp(
  r'^screen (\d+)×(\d+), cursor (?:at (\d+),(\d+)|hidden)$',
);

/// The characters styles are given, in the order they are given out: the
/// letters and digits, the rest of printable ASCII but the space, then
/// letters of Latin, Greek, Cyrillic, Armenian, Georgian, Cherokee and the
/// Canadian syllabics, and the braille patterns: every one a column wide
/// and written left to right, so that the layer of styles keeps a column
/// a cell. A screen of an image drawn in blocks has a style nearly every
/// cell.
final List<String> _chars = [
  for (final (from, to) in const [
    (0x61, 0x7A), // a-z
    (0x41, 0x5A), // A-Z
    (0x30, 0x39), // 0-9
    (0x21, 0x2F),
    (0x3A, 0x40),
    (0x5B, 0x60),
    (0x7B, 0x7E),
    (0xC0, 0x24F), // Latin-1 letters, Latin Extended-A and -B
    (0x391, 0x3A1), // Greek
    (0x3A3, 0x3A9),
    (0x3B1, 0x3C9),
    (0x400, 0x482), // Cyrillic, its combining marks left out
    (0x48A, 0x52F),
    (0x531, 0x556), // Armenian
    (0x561, 0x586),
    (0x10D0, 0x10FA), // Georgian
    (0x13A0, 0x13F4), // Cherokee
    (0x1401, 0x166C), // Canadian syllabics
    (0x1E00, 0x1EFF), // Latin Extended Additional
    (0x2801, 0x28FF), // braille, the blank pattern left out
  ])
    for (var c = from; c <= to; c++)
      if (String.fromCharCode(c) case final char when stringWidth(char) == 1)
        char,
];
