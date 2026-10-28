// Color.lerp: each channel between two RGB colors, rounded and kept from
// 0 to 255 where t runs past the ends; between colors of which one is not
// RGB, the first until halfway and the second from there.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  test('between two RGB colors each channel runs as far as t says', () {
    const a = Color.rgb(0, 100, 200);
    const b = Color.rgb(100, 200, 0);
    expect(Color.lerp(a, b, 0), a);
    expect(Color.lerp(a, b, 0.5), const Color.rgb(50, 150, 100));
    expect(Color.lerp(a, b, 0.25), const Color.rgb(25, 125, 150));
    expect(Color.lerp(a, b, 1), b);
  });

  test('past the ends, as a curve that overshoots takes it, each channel '
      'stays from 0 to 255', () {
    const a = Color.rgb(0, 100, 250);
    const b = Color.rgb(100, 200, 0);
    expect(Color.lerp(a, b, 1.5), const Color.rgb(150, 250, 0));
    expect(Color.lerp(a, b, -0.5), const Color.rgb(0, 50, 255));
  });

  test('with a palette or default color at either end it switches halfway', () {
    const rgb = Color.rgb(0, 0, 255);
    for (final other in [
      Color.red,
      const Color.indexed(200),
      Color.defaultColor,
    ]) {
      expect(Color.lerp(other, rgb, 0.49), other);
      expect(Color.lerp(other, rgb, 0.5), rgb);
      expect(Color.lerp(rgb, other, 0.49), rgb);
      expect(Color.lerp(rgb, other, 0.5), other);
    }
    expect(Color.lerp(Color.red, Color.blue, 0.25), Color.red);
  });

  test('a Color is an Object: it fills a type parameter bound by Object', () {
    T first<T extends Object>(List<T> values) => values.first;
    expect(first<Color>([Color.green]), Color.green);
  });
}
