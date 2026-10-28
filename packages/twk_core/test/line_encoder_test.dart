import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

/// A surface of [width] x 1 cells and its canvas, [paint] drawing on it.
(Surface, GlyphTable) _row(
  StyleTable styles,
  int width,
  void Function(Canvas canvas) paint,
) {
  final surface = Surface(width, 1);
  final glyphs = GlyphTable();
  paint(Canvas(surface, styles, glyphs));
  return (surface, glyphs);
}

void main() {
  group('text', () {
    test('each style as the SGR sequence from the one before', () {
      final styles = StyleTable();
      final bold = styles.style(attrs: Attr.bold);
      final boldRed = styles.style(attrs: Attr.bold, fg: Color.red);
      final out = LineEncoder(styles)
        ..text(bold, 'a')
        ..text(boldRed, 'b')
        ..text(0, 'c')
        ..end();
      expect(out.take(), '\x1B[1ma\x1B[31mb\x1B[0mc');
    });

    test('the style reset at the end of the line', () {
      final styles = StyleTable();
      final out = LineEncoder(styles)
        ..text(styles.style(attrs: Attr.bold), 'a')
        ..end()
        ..text(0, 'b')
        ..end();
      expect(out.take(), '\x1B[1ma\x1B[0mb');
    });

    test('nothing to reset after a style that looks as the default', () {
      final styles = StyleTable(colorMode: ColorMode.none);
      final red = styles.style(fg: Color.red);
      final out = LineEncoder(styles)
        ..text(red, 'x')
        ..end();
      expect(out.take(), 'x');
    });

    test('the text alone without ANSI', () {
      final styles = StyleTable();
      final out = LineEncoder(styles, ansi: false, hyperlinks: true)
        ..text(styles.style(attrs: Attr.bold, link: 'https://dart.dev'), 'a')
        ..end();
      expect(out.take(), 'a');
    });

    test('a link as OSC 8 only where hyperlinks are taken', () {
      final styles = StyleTable();
      final link = styles.style(link: 'https://dart.dev');
      final without = LineEncoder(styles)
        ..text(link, 'dart')
        ..end();
      expect(without.take(), 'dart');
      final with_ = LineEncoder(styles, hyperlinks: true)
        ..text(link, 'dart')
        ..text(0, '!')
        ..end();
      expect(
        with_.take(),
        '\x1B]8;;https://dart.dev\x1B\\dart\x1B]8;;\x1B\\!',
      );
    });

    test('a link target percent-encoded past printable ASCII', () {
      final styles = StyleTable();
      final link = styles.style(link: 'https://x.dev/é a\x07\x1B\\');
      final out = LineEncoder(styles, hyperlinks: true)
        ..text(link, 'x')
        ..end();
      expect(
        out.take(),
        '\x1B]8;;https://x.dev/%C3%A9%20a%07%1B\\\x1B\\x\x1B]8;;\x1B\\',
      );
    });

    test('a lone surrogate as U+FFFD', () {
      final out = LineEncoder(StyleTable())
        ..text(0, 'a\uD800b')
        ..end();
      expect(out.take(), 'a�b');
    });

    test('take empties the sink', () {
      final out = LineEncoder(StyleTable())..text(0, 'a');
      expect(out.take(), 'a');
      expect(out.take(), '');
    });
  });

  group('row', () {
    test('without the blanks that end it, a wide glyph once', () {
      final styles = StyleTable();
      final (surface, glyphs) = _row(styles, 8, (c) {
        c.text(0, 0, '世a', styles.pen(const Pen()));
      });
      final out = LineEncoder(styles, ansi: false)..row(surface, glyphs, 0);
      expect(out.take(), '世a');
    });

    test('a background to the end of the row with ANSI, not without', () {
      final styles = StyleTable();
      final (surface, glyphs) = _row(styles, 3, (c) {
        c
          ..fill(0, 0, 3, 1, styles.pen(const Pen(bg: Color.blue)))
          ..text(0, 0, 'a', styles.pen(const Pen()));
      });
      expect(
        (LineEncoder(styles)..row(surface, glyphs, 0)).take(),
        '\x1B[44ma  \x1B[0m',
      );
      expect(
        (LineEncoder(styles, ansi: false)..row(surface, glyphs, 0)).take(),
        'a',
      );
    });

    test('a linked blank kept only where links are written', () {
      final styles = StyleTable();
      final (surface, glyphs) = _row(styles, 3, (c) {
        c.text(0, 0, 'a ', styles.pen(const Pen(link: 'https://dart.dev')));
      });
      expect(
        (LineEncoder(styles, hyperlinks: true)..row(surface, glyphs, 0)).take(),
        '\x1B]8;;https://dart.dev\x1B\\a \x1B]8;;\x1B\\',
      );
      expect((LineEncoder(styles)..row(surface, glyphs, 0)).take(), 'a');
    });

    test('an interned cluster as its bytes', () {
      final styles = StyleTable();
      final (surface, glyphs) = _row(styles, 4, (c) {
        c.text(0, 0, 'é!', styles.pen(const Pen()));
      });
      expect(
        (LineEncoder(styles, ansi: false)..row(surface, glyphs, 0)).take(),
        'é!',
      );
    });
  });

  test('linkTarget is what the presenter writes as a link', () {
    final styles = StyleTable();
    const uri = 'https://x.dev/é\x07';
    final surface = Surface(1, 1);
    final glyphs = GlyphTable();
    Canvas(
      surface,
      styles,
      glyphs,
    ).text(0, 0, 'x', styles.pen(const Pen(link: uri)));
    final presenter = Presenter(1, 1, styles, glyphs)..present(surface);
    final written = String.fromCharCodes(presenter.out.view);
    expect(
      written,
      contains('\x1B]8;;${String.fromCharCodes(LineEncoder.linkTarget(uri))}'),
    );
    expect(
      String.fromCharCodes(LineEncoder.linkTarget(uri)),
      'https://x.dev/%C3%A9%07',
    );
  });
}
