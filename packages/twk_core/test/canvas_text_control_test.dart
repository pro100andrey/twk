// Canvas.text drops control characters; in debug it says so, once for each.
import 'package:test/test.dart';
import 'package:twk_core/src/canvas.dart';
import 'package:twk_core/src/style.dart';
import 'package:twk_core/src/surface.dart';

void main() {
  var asserts = false;
  assert(asserts = true, 'debug only');

  late Canvas cv;
  late int pen;
  setUp(() {
    final styles = StyleTable();
    cv = Canvas(Surface(20, 1), styles, GlyphTable());
    pen = styles.pen(const Pen());
  });

  List<String> printed(void Function() body) {
    final lines = <String>[];
    cv.onDroppedControl = lines.add;
    body();
    return lines;
  }

  test('no hook, no word', () {
    expect(cv.text(0, 0, '\x1B[31m', pen), 4);
  });

  test('a dropped ESC is logged once, naming it', () {
    final lines = printed(() {
      expect(cv.text(0, 0, '\x1B[31mred', pen), 7);
      cv.text(0, 0, '\x1B[0m', pen);
    });
    expect(lines.length, asserts ? 1 : 0);
    if (asserts) {
      expect(lines.single, contains('control'));
      expect(lines.single, contains('ESC (U+001B)'));
      expect(lines.single, contains('Text'));
    }
  });

  test('another control is logged on its own; a C1 one too', () {
    final lines = printed(() {
      cv
        ..text(0, 0, 'a\x07b', pen)
        ..text(0, 0, 'a\x9Bb', pen)
        ..text(0, 0, 'a\x07b', pen);
    });
    expect(lines.length, asserts ? 2 : 0);
  });

  test('tab, printable text and wide glyphs log nothing', () {
    final lines = printed(() {
      cv
        ..text(0, 0, 'a\tb', pen)
        ..text(0, 0, 'plain text', pen)
        ..text(0, 0, '日本é', pen);
    });
    expect(lines, isEmpty);
  });

  test('a newline is told to split the text, not about ANSI', () {
    final lines = printed(() => cv.text(0, 0, 'a\nb', pen));
    expect(lines.length, asserts ? 1 : 0);
    if (asserts) {
      expect(lines.single, contains('U+000A'));
      expect(lines.single, contains('split the text into lines'));
      expect(lines.single, isNot(contains('ANSI')));
    }
  });
}
