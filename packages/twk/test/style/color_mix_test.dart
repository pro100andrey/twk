// The colour mixing the widgets share: two theme colours mixed only where
// both are RGB, as Color.lerp mixes them; an RGB of a palette entry and of
// the default colours; a style shaded towards a colour, its text faint
// where the terminal has not told its text colour.
import 'package:test/test.dart';
import 'package:twk/src/style/color_mix.dart';
import 'package:twk/twk.dart';

void main() {
  group('mixRgb', () {
    test('mixes two RGB colours as Color.lerp, each channel rounded', () {
      const a = Color.rgb(10, 100, 255);
      const b = Color.rgb(20, 0, 0);
      expect(mixRgb(a, b, 0.25), const Color.rgb(13, 75, 191));
      expect(mixRgb(a, b, 0.25), Color.lerp(a, b, 0.25));
      expect(mixRgb(a, b, 0), a);
      expect(mixRgb(a, b, 1), b);
    });

    test('is null where either colour is null, a palette entry or the '
        'default', () {
      const rgb = Color.rgb(1, 2, 3);
      expect(mixRgb(null, rgb, 0.5), isNull);
      expect(mixRgb(rgb, null, 0.5), isNull);
      expect(mixRgb(Color.red, rgb, 0.5), isNull);
      expect(mixRgb(rgb, Color.defaultColor, 0.5), isNull);
    });
  });

  test('lerpRgb mixes two RGBs given as ints', () {
    expect(lerpRgb(0x0A64FF, 0x140000, 0.25), const Color.rgb(13, 75, 191));
    expect(rgbColor(0x123456), const Color.rgb(0x12, 0x34, 0x56));
  });

  test('rgbOf: its own, the palette entry the table knows, the default '
      'given', () {
    final styles = StyleTable();
    expect(rgbOf(styles, const Color.rgb(1, 2, 3), 0), 0x010203);
    expect(rgbOf(styles, Color.red, 0), styles.paletteRgb(1));
    expect(rgbOf(styles, Color.defaultColor, 0xABCDEF), 0xABCDEF);
  });

  group('shadeStyle', () {
    test('takes background, text and underline colours towards the colour', () {
      final styles = StyleTable()..defaultForegroundRgb = 0xFFFFFF;
      final style = styles.style(
        fg: const Color.rgb(200, 200, 200),
        bg: const Color.rgb(100, 0, 0),
        underlineColor: const Color.rgb(0, 0, 100),
      );
      final shaded = shadeStyle(styles, style, 0x000000, 0.5);
      expect(styles.bgOf(shaded), const Color.rgb(50, 0, 0));
      expect(styles.fgOf(shaded), const Color.rgb(100, 100, 100));
      expect(styles.underlineColorOf(shaded), const Color.rgb(0, 0, 50));
      expect(styles.attrsOf(shaded) & Attr.dim, 0);
    });

    test('makes default text faint while the terminal has not told its '
        'colour, and keeps a default underline colour', () {
      final styles = StyleTable();
      final style = styles.style();
      final shaded = shadeStyle(styles, style, 0x000000, 0.5);
      expect(styles.fgOf(shaded), Color.defaultColor);
      expect(styles.attrsOf(shaded) & Attr.dim, Attr.dim);
      expect(styles.underlineColorOf(shaded), Color.defaultColor);
      final bg = styles.defaultBackgroundRgb;
      expect(
        styles.bgOf(shaded),
        Color.lerp(rgbColor(bg), const Color.rgb(0, 0, 0), 0.5),
      );
    });
  });
}
