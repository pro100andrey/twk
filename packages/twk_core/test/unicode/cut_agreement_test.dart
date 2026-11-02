// The three places that cut text off with an ellipsis (fitText, a
// paragraph's TextOverflow.ellipsis and a box's title) must cut the same
// text to the same room at the same place: no blank, tab or ideographic
// space left next to the mark, no cluster split. Review finding 1 of the
// architecture review.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const _family = '👨‍👩‍👧';

List<String> _paint(RenderObject root, int w, int h, TextMode mode) {
  final screen = Screen(w, h, textMode: mode);
  PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
    ..root = root
    ..flushLayout(w, h)
    ..flushPaint(PaintContext(screen.canvas, screen.surface, screen.presenter));
  return [
    for (var y = 0; y < h; y++)
      [
        for (var x = 0; x < w; x++)
          if ((screen.surface.cells[y * w + x] & kCont) == 0)
            screen.glyphs.stringOf(screen.surface.cells[y * w + x]),
      ].join(),
  ];
}

/// What the three cutters make of [text] in [room] columns, as strings
/// that can be compared: the tab shown as the blank it is drawn as, the
/// padding of the paragraph and the rule of the box's edge taken off.
({String fit, String paragraph, String title}) cuts(
  String text,
  int room,
  TextMode mode,
) {
  final fit = fitText(TextSegmenter(mode: mode), text, room);
  final paragraph = _paint(
    RenderParagraph(
      [(text, const Pen())],
      wrap: TextWrap.none,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    ),
    room,
    1,
    mode,
  )[0];
  final top = _paint(
    RenderDecoratedBox(
      border: const BoxBorder.all(type: BorderType.rounded),
      titles: [BoxTitle(text)],
    ),
    room + 2,
    3,
    mode,
  )[0];
  return (
    fit: fit.replaceAll('\t', ' '),
    paragraph: paragraph.trimRight(),
    title: top.substring(1, top.length - 1).replaceAll(RegExp(r'─+$'), ''),
  );
}

void agree(String text, TextMode mode, Iterable<int> rooms) {
  final failures = <String>[];
  for (final room in rooms) {
    final c = cuts(text, room, mode);
    if (c.fit != c.paragraph || c.paragraph != c.title) {
      failures.add(
        'room $room: fitText [${c.fit}] paragraph [${c.paragraph}] '
        'title [${c.title}]',
      );
    }
  }
  expect(failures, isEmpty, reason: 'the cutters differ');
}

void main() {
  test('a tab before the cut is not left next to the ellipsis', () {
    agree('ab\tcdefgh', TextMode.graphemes, [3, 4, 5, 6, 7]);
  });

  test('an ideographic space (U+3000) before the cut is not left next to '
      'the ellipsis', () {
    agree('ab　cdefgh', TextMode.graphemes, [3, 4, 5, 6, 7]);
  });

  test('a ZWJ family is cut whole or not at all under the legacy '
      'segmenter', () {
    agree('ab$_family', TextMode.legacy, [3, 4, 5, 6, 7]);
    agree('a$_family', TextMode.legacy, [3, 4, 5, 6, 7]);
  });

  test('plain text is cut the same by the three', () {
    agree('abcdefgh ijk', TextMode.graphemes, [3, 4, 5, 6, 9]);
  });
}
