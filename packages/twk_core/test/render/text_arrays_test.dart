// A RenderText shapes its text into a buffer of its own, which a text
// that changes keeps while the new text fits it; Canvas.shapeInto is what
// it shapes with, the same glyphs and width as Canvas.shape.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  group('Canvas.shapeInto', () {
    test('writes the glyphs and width that shape makes', () {
      final canvas = Canvas(Surface(10, 1), StyleTable(), GlyphTable());
      for (final s in ['', 'plain', 'wide 日本 text', 'é tab\tx']) {
        final run = canvas.shape(s);
        final out = Uint32List(s.length);
        final n = canvas.shapeInto(s, out);
        expect(out.sublist(0, n), run.glyphs, reason: s);
        expect(canvas.shapedWidth, run.width, reason: s);
      }
    });

    test('draws as the run does through runRange', () {
      final a = Screen(12, 1);
      final b = Screen(12, 1);
      final pa = a.styles.pen(const Pen());
      final pb = b.styles.pen(const Pen());
      a.canvas.run(0, 0, a.canvas.shape('日本 ab'), pa);
      final out = Uint32List(8);
      final n = b.canvas.shapeInto('日本 ab', out);
      b.canvas.runRange(0, 0, out, 0, n, pb);
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
