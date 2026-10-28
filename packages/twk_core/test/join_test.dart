// Cells drawn separately must stay separate on a terminal that clusters
// graphemes: when a cluster could join the next code point (UAX #29 rules
// GB6, GB9b, GB9c, GB11, GB12/13), the next cell must not be printed
// contiguously; a cell never starts with a base-less mark.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

import 'support/harness.dart';

const pairs = <(String, String, String)>[
  ('GB9c virama + consonant', 'क\u{94D}', 'ष'),
  ('GB11 emoji ZWJ + pictograph', '🧪\u{200D}', '🧪'),
  ('GB9b prepend + anything', '\u{600}', 'x'),
  ('GB6 Hangul L + syllable', '\u{1100}', '가'),
  ('GB12 regional indicators', '🇺', '🇦'),
];

void main() {
  for (final (name, a, b) in pairs) {
    test(name, () {
      final hs = Harness(12, 2);
      final pen = hs.pens[1];
      final wa = hs.canvas.text(1, 0, a, pen);
      hs.canvas.text(1 + wa, 0, b, pen); // drawn separately, adjacent
      hs.frame();
      expect(hs.mismatches(), isEmpty, reason: '$name: ${hs.vt.dump()}');
      // the joining cluster is flagged so the presenter re-syncs after it
      expect(hs.surface.cells[1] & kUncertain, isNot(0), reason: name);
    });
  }

  test('a mark without a base is not drawn (grapheme mode)', () {
    final hs = Harness(12, 2);
    final pen = hs.pens[1];
    hs.canvas.text(1, 0, 'ab', pen);
    hs.canvas.text(3, 0, '\u{301}\u{93F}cd', pen); // starts with marks
    hs.frame();
    expect(hs.mismatches(), isEmpty, reason: hs.vt.dump());
    expect(hs.vt.dump().split('\n').first.trimRight(), ' abcd');
  });
}
