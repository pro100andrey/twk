// An edit of a paragraph in visual order resolves the levels of what it can
// have changed without joining the text of all its spans into one string:
// the code units it copies to resolve are about those of the edit, not the
// paragraph's, whether the paragraph is many spans or one.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const _pens = [
  Pen(),
  Pen(fg: Color.rgb(200, 0, 0)),
  Pen(fg: Color.rgb(0, 0, 200)),
];

const _sentence =
    'The presenter (of the core) writes שָׁלוֹם עולם and مرحبا 1234 '
    'only where cells changed. ';

PipelineOwner _owner() =>
    PipelineOwner(() {}, segmenter: Screen(40, 30).canvas.segmenter)
      ..textOrder = TextOrder.visual;

void _layOut(PipelineOwner o, RenderParagraph p) {
  if (p.parent == null) {
    o.root = RenderFlex(
      direction: Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [p],
    );
  }
  o.flushLayout(40, 30);
}

void main() {
  for (final (name, spans) in [
    (
      'sixty spans',
      [for (var k = 0; k < 60; k++) (_sentence, _pens[k % 3])],
    ),
    ('one span', [(_sentence * 60, _pens[0])]),
  ]) {
    test('a character typed into a long paragraph of $name copies about '
        'the code units the edit changed, not the paragraph', () {
      final o = _owner();
      final p = RenderParagraph(spans);
      _layOut(o, p);
      const units = _sentence.length * 60;
      expect(p.debugLevelsResolved, units);
      const typed = 'ab שׁ ق9 x (y) עִם z';
      // into the eighth sentence, in its first words
      final s = spans.length > 1 ? 7 : 0;
      final i = (spans.length > 1 ? 0 : 7 * _sentence.length) + 12;
      final t = spans[s].$1;
      for (var k = 1; k <= typed.length; k++) {
        final copied = p.debugBidiUnitsCopied;
        p.spans = List.of(spans)
          ..[s] = (
            t.substring(0, i) + typed.substring(0, k) + t.substring(i),
            spans[s].$2,
          );
        _layOut(o, p);
        expect(p.debugDiffFromFresh(), isNull, reason: 'character $k');
        expect(
          p.debugBidiUnitsCopied - copied,
          lessThan(_sentence.length),
          reason: 'code units copied for character $k',
        );
      }
    });
  }
}
