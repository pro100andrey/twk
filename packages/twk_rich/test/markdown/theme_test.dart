// A Markdown theme as a value: copyWith replacing each style alone, and
// themes equal by their styles hashing alike.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';

/// Each style of a theme: how copyWith replaces it, and how it is read.
final parts =
    <
      String,
      (
        MarkdownTheme Function(MarkdownTheme, Style),
        Style Function(MarkdownTheme),
      )
    >{
      'heading1': ((t, s) => t.copyWith(heading1: s), (t) => t.heading1),
      'heading2': ((t, s) => t.copyWith(heading2: s), (t) => t.heading2),
      'heading3': ((t, s) => t.copyWith(heading3: s), (t) => t.heading3),
      'heading4': ((t, s) => t.copyWith(heading4: s), (t) => t.heading4),
      'heading5': ((t, s) => t.copyWith(heading5: s), (t) => t.heading5),
      'heading6': ((t, s) => t.copyWith(heading6: s), (t) => t.heading6),
      'emphasis': ((t, s) => t.copyWith(emphasis: s), (t) => t.emphasis),
      'strong': ((t, s) => t.copyWith(strong: s), (t) => t.strong),
      'strikethrough': (
        (t, s) => t.copyWith(strikethrough: s),
        (t) => t.strikethrough,
      ),
      'code': ((t, s) => t.copyWith(code: s), (t) => t.code),
      'link': ((t, s) => t.copyWith(link: s), (t) => t.link),
      'image': ((t, s) => t.copyWith(image: s), (t) => t.image),
      'codeBlock': ((t, s) => t.copyWith(codeBlock: s), (t) => t.codeBlock),
      'quote': ((t, s) => t.copyWith(quote: s), (t) => t.quote),
      'quoteBar': ((t, s) => t.copyWith(quoteBar: s), (t) => t.quoteBar),
      'marker': ((t, s) => t.copyWith(marker: s), (t) => t.marker),
      'rule': ((t, s) => t.copyWith(rule: s), (t) => t.rule),
      'tableHeader': (
        (t, s) => t.copyWith(tableHeader: s),
        (t) => t.tableHeader,
      ),
      'tableBorder': (
        (t, s) => t.copyWith(tableBorder: s),
        (t) => t.tableBorder,
      ),
    };

void main() {
  final base = MarkdownTheme.from(const ThemeData.terminal(Brightness.dark));
  const red = Style(fg: Color.rgb(200, 0, 0));

  test('copyWith replaces the style given and keeps every other', () {
    for (final MapEntry(key: name, value: (copy, _)) in parts.entries) {
      final changed = copy(base, red);
      for (final MapEntry(key: other, value: (_, read)) in parts.entries) {
        expect(
          read(changed),
          other == name ? red : read(base),
          reason: '$other after copyWith($name:)',
        );
      }
    }
    expect(base.copyWith(), base);
  });

  test('themes with equal styles are equal and hash alike', () {
    final again = MarkdownTheme.from(const ThemeData.terminal(Brightness.dark));
    expect(again, base);
    expect(again.hashCode, base.hashCode);
    expect(base.copyWith(rule: red), isNot(base));
    for (final MapEntry(key: name, value: (copy, _)) in parts.entries) {
      expect(copy(base, red), isNot(base), reason: name);
    }
    expect(
      base.copyWith(rule: red).hashCode,
      base.copyWith(rule: red).hashCode,
    );
  });
}
