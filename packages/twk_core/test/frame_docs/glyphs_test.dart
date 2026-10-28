// Glyphs interned in a GlyphTable and text shaped into a GlyphRun, past
// the sizes their tables start with.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  test('every cluster interned keeps its id and its text as the table '
      'grows', () {
    final glyphs = GlyphTable();
    final ids = <String, int>{};
    for (var i = 0; i < 2000; i++) {
      // a letter with a combining mark: two code points, one cluster
      final cluster = '${String.fromCharCode(0x4E00 + i)}́';
      ids[cluster] = glyphs.intern(cluster, 0, cluster.length);
    }
    expect(glyphs.length, 2000);
    for (final MapEntry(key: cluster, value: id) in ids.entries) {
      expect(id, greaterThan(0x10FFFF), reason: 'past every code point');
      expect(glyphs.stringOf(id), cluster);
      expect(glyphs.intern('x$cluster', 1, cluster.length + 1), id);
    }
    expect(glyphs.length, 2000, reason: 'nothing interned twice');
  });

  test('text longer than the shaping buffer is shaped whole', () {
    final styles = StyleTable();
    final surface = Surface(200, 1);
    final canvas = Canvas(surface, styles, GlyphTable());
    final text = 'ab' * 50 + '你好' * 20;
    final run = canvas.shape(text);
    expect(run.width, 100 + 80);
    expect(run.glyphs, hasLength(100 + 40));
    expect(canvas.run(0, 0, run, styles.pen(const Pen())), 180);
    final row = StringBuffer();
    for (var x = 0; x < surface.width; x++) {
      final cell = surface.cells[x];
      if (cell & kCont == 0) {
        row.writeCharCode(cell & kGlyphMask);
      }
    }
    expect(row.toString().trimRight(), text);
  });
}
