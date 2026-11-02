// A RenderText shapes its text into a buffer of its own, which a text
// that changes keeps while the new text fits it; Canvas.shapeInto is what
// it shapes with, the same glyphs and width as Canvas.shape.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  group('Canvas.shapeInto', () {
    test('writes the glyphs and width that shape makes', () {
      final canvas = Canvas(Surface(10, 1), StyleTable(), GlyphTable());
      final out = GlyphBuffer();
      for (final s in ['', 'plain', 'wide 日本 text', 'é tab\tx', 'e\u0301ü']) {
        final run = canvas.shape(s);
        canvas.shapeInto(s, out);
        expect(out.words.sublist(0, out.length), run.glyphs, reason: s);
        expect(out.width, run.width, reason: s);
      }
    });

    test('grows past its capacity and keeps it', () {
      final canvas = Canvas(Surface(10, 1), StyleTable(), GlyphTable());
      final out = GlyphBuffer();
      const start = 16;
      canvas.shapeInto('x' * (start * 3), out);
      expect(out.length, start * 3);
      expect(out.width, start * 3);
      final grown = out.capacity;
      expect(grown, greaterThanOrEqualTo(start * 3));
      canvas.shapeInto('ab', out);
      expect(out.length, 2);
      expect(out.width, 2);
      expect(out.capacity, grown);
      out.clear();
      expect((out.length, out.width, out.capacity), (0, 0, grown));
    });

    test('two buffers shaped in turn do not disturb each other', () {
      final canvas = Canvas(Surface(10, 1), StyleTable(), GlyphTable());
      final a = GlyphBuffer();
      final b = GlyphBuffer();
      canvas
        ..shapeInto('日本', a)
        ..shapeInto('abc', b);
      expect((a.length, a.width), (2, 4));
      expect((b.length, b.width), (3, 3));
    });

    test('draws as the run does through runBuffer', () {
      final a = Screen(12, 1);
      final b = Screen(12, 1);
      final pa = a.styles.pen(const Pen());
      final pb = b.styles.pen(const Pen());
      a.canvas.run(0, 0, a.canvas.shape('日本 ab'), pa);
      final out = GlyphBuffer();
      b.canvas.shapeInto('日本 ab', out);
      b.canvas.runBuffer(0, 0, out, pb);
      expect(b.surface.cells, a.surface.cells);
    });
  });

  group('RenderText', () {
    void frame(PipelineOwner o, Screen s) {
      o
        ..flushLayout(s.surface.width, 1)
        ..flushPaint(PaintContext(s.canvas, s.surface, s.presenter));
      s.render();
    }

    test('shows each new text, longer or shorter than the one before', () {
      final screen = Screen(12, 1);
      final text = RenderText('hello', screen.styles.pen(const Pen()));
      final owner = PipelineOwner(() {})..root = text;
      frame(owner, screen);
      for (final t in ['hello world', 'hi', '日本', 'e\u0301x', '']) {
        text.text = t;
        frame(owner, screen);
        final fresh = Screen(12, 1);
        frame(
          PipelineOwner(() {})
            ..root = RenderText(t, fresh.styles.pen(const Pen())),
          fresh,
        );
        expect(screen.surface.cells, fresh.surface.cells, reason: t);
      }
    });
  });
}
