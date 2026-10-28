// StyleTable and Color as a caller reads them: interning, the SGR a color
// mode writes, blank styles, and what a color holds.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  String sgr(List<int> bytes) => String.fromCharCodes(bytes);

  test('a color holds its channels, its palette entry, or the default', () {
    const orange = Color.rgb(255, 128, 7);
    expect(
      (orange.isRgb, orange.isIndexed, orange.isDefault),
      (
        true,
        false,
        false,
      ),
    );
    expect((orange.r, orange.g, orange.b), (255, 128, 7));
    for (final i in [0, 15, 200, 255]) {
      final entry = Color.indexed(i);
      expect((entry.isIndexed, entry.isRgb, entry.index), (true, false, i));
    }
    expect(Color.defaultColor.isDefault, isTrue);
  });

  test('a style is interned once: the same values give the same id', () {
    final styles = StyleTable();
    expect(styles.length, 1, reason: 'style 0, all defaults');
    final a = styles.style(fg: Color.red, attrs: Attr.bold);
    expect(styles.length, 2);
    expect(styles.style(fg: Color.red, attrs: Attr.bold), a);
    expect(styles.length, 2);
    expect(styles.style(), 0);
  });

  test('switching the color mode rewrites the SGR of the styles already '
      'interned, which keep their colors', () {
    final styles = StyleTable();
    expect(styles.colorMode, ColorMode.trueColor);
    final id = styles.style(fg: const Color.rgb(255, 0, 0));
    expect(sgr(styles.sgrFromReset(id)), '\x1b[0;38;2;255;0;0m');
    expect(sgr(styles.transition(0, id)), '\x1b[38;2;255;0;0m');
    styles.colorMode = ColorMode.ansi256;
    expect(styles.colorMode, ColorMode.ansi256);
    expect(sgr(styles.sgrFromReset(id)), '\x1b[0;38;5;196m');
    expect(sgr(styles.transition(0, id)), '\x1b[38;5;196m');
    styles.colorMode = ColorMode.ansi16;
    expect(sgr(styles.transition(0, id)), '\x1b[91m');
    styles.colorMode = ColorMode.none;
    expect(sgr(styles.sgrFromReset(id)), '\x1b[0m');
    expect(styles.fgOf(id), const Color.rgb(255, 0, 0));
  });

  test('from a style to itself takes no SGR', () {
    final styles = StyleTable();
    final id = styles.style(bg: Color.blue, attrs: Attr.italic);
    expect(styles.transition(id, id), isEmpty);
  });

  test('the blank of a style interned after many others keeps only what a '
      'space shows', () {
    final styles = StyleTable();
    for (var i = 0; i < 300; i++) {
      styles.style(fg: Color.rgb(i & 0xFF, i >> 8, 1));
    }
    final id = styles.style(
      fg: Color.red,
      bg: Color.blue,
      attrs: Attr.bold | Attr.italic,
    );
    expect(id, greaterThan(256));
    expect(styles.blankStyleOf(id), styles.style(bg: Color.blue));
  });
}
