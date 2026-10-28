// The glyphs each marker shows its dots as, on the emulator, and braille
// in place of a marker whose glyphs would not take one column each.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show Shot;

import 'shot.dart';

/// One row of cells, cell `k` showing pattern `patterns[k]` of [marker]:
/// bit `b` is dot `b`, counted row by row from the top left of the cell.
Shot cells(Marker marker, List<int> patterns) {
  final across = marker.dotsAcross;
  final down = marker.dotsDown;
  final points = [
    for (var k = 0; k < patterns.length; k++)
      for (var b = 0; b < across * down; b++)
        if ((patterns[k] >> b) & 1 != 0)
          (
            (k * across + b % across).toDouble(),
            (down - 1 - b ~/ across).toDouble(),
          ),
  ];
  return drawn(
    patterns.length,
    1,
    (c) => c.draw(.points(points)),
    marker: marker,
  );
}

String row(Marker marker, List<int> patterns) =>
    cells(marker, patterns).rows.single;

List<int> every(Marker marker) => [for (var p = 0; p < marker.patterns; p++) p];

void main() {
  group('Marker', () {
    test("a custom marker's char is its code point; the others' is 0", () {
      expect(Marker.custom('*').char, 0x2A);
      expect(Marker.custom('\u{1F600}').char, 0x1F600);
      expect(Marker.dot.char, 0);
      expect(Marker.braille.char, 0);
    });

    test('custom markers of the same char are equal and hash the same', () {
      expect(Marker.custom('*'), Marker.custom('*'));
      expect(Marker.custom('*').hashCode, Marker.custom('*').hashCode);
      expect(Marker.custom('*'), isNot(Marker.custom('+')));
      expect(Marker.custom('•'), isNot(Marker.dot));
    });

    test('reads as the constant or the constructor it is made by', () {
      expect('${Marker.sextant}', 'Marker.sextant');
      expect('${Marker.custom('*')}', 'Marker.custom(*)');
    });
  });

  group('glyphs', () {
    test('one dot a cell', () {
      expect(row(Marker.dot, [0, 1]), ' •');
      expect(row(Marker.block, [0, 1]), ' █');
      expect(row(Marker.bar, [0, 1]), ' ▄');
      expect(row(Marker.custom('x'), [0, 1]), ' x');
    });

    test('braille: the dots of the left column, then of the right', () {
      expect(row(Marker.braille, [1, 4, 16, 64, 2, 8, 32, 128]), '⠁⠂⠄⡀⠈⠐⠠⢀');
      expect(row(Marker.braille, [0, 0x0F, 0xF0, 0x55, 0xFF]), ' ⠛⣤⡇⣿');
    });

    test('half blocks', () {
      expect(row(Marker.halfBlock, every(Marker.halfBlock)), ' ▀▄█');
    });

    test('quadrants', () {
      expect(row(Marker.quadrant, every(Marker.quadrant)), ' ▘▝▀▖▌▞▛▗▚▐▜▄▙▟█');
    });

    // generated from the character names in UnicodeData.txt
    test('sextants', () {
      expect(
        row(Marker.sextant, every(Marker.sextant)),
        [
          ' 🬀🬁🬂🬃🬄🬅🬆🬇🬈🬉🬊🬋🬌🬍🬎🬏🬐🬑🬒🬓▌🬔🬕🬖🬗🬘🬙🬚🬛🬜🬝',
          '🬞🬟🬠🬡🬢🬣🬤🬥🬦🬧▐🬨🬩🬪🬫🬬🬭🬮🬯🬰🬱🬲🬳🬴🬵🬶🬷🬸🬹🬺🬻█',
        ].join(),
      );
    });

    // generated from the character names in UnicodeData.txt
    test('octants', () {
      expect(
        row(Marker.octant, every(Marker.octant)),
        [
          ' 𜺨𜺫🮂𜴀▘𜴁𜴂𜴃𜴄▝𜴅𜴆𜴇𜴈▀𜴉𜴊𜴋𜴌🯦𜴍𜴎𜴏𜴐𜴑𜴒𜴓𜴔𜴕𜴖𜴗',
          '𜴘𜴙𜴚𜴛𜴜𜴝𜴞𜴟🯧𜴠𜴡𜴢𜴣𜴤𜴥𜴦𜴧𜴨𜴩𜴪𜴫𜴬𜴭𜴮𜴯𜴰𜴱𜴲𜴳𜴴𜴵🮅',
          '𜺣𜴶𜴷𜴸𜴹𜴺𜴻𜴼𜴽𜴾𜴿𜵀𜵁𜵂𜵃𜵄▖𜵅𜵆𜵇𜵈▌𜵉𜵊𜵋𜵌▞𜵍𜵎𜵏𜵐▛',
          '𜵑𜵒𜵓𜵔𜵕𜵖𜵗𜵘𜵙𜵚𜵛𜵜𜵝𜵞𜵟𜵠𜵡𜵢𜵣𜵤𜵥𜵦𜵧𜵨𜵩𜵪𜵫𜵬𜵭𜵮𜵯𜵰',
          '𜺠𜵱𜵲𜵳𜵴𜵵𜵶𜵷𜵸𜵹𜵺𜵻𜵼𜵽𜵾𜵿𜶀𜶁𜶂𜶃𜶄𜶅𜶆𜶇𜶈𜶉𜶊𜶋𜶌𜶍𜶎𜶏',
          '▗𜶐𜶑𜶒𜶓▚𜶔𜶕𜶖𜶗▐𜶘𜶙𜶚𜶛▜𜶜𜶝𜶞𜶟𜶠𜶡𜶢𜶣𜶤𜶥𜶦𜶧𜶨𜶩𜶪𜶫',
          '▂𜶬𜶭𜶮𜶯𜶰𜶱𜶲𜶳𜶴𜶵𜶶𜶷𜶸𜶹𜶺𜶻𜶼𜶽𜶾𜶿𜷀𜷁𜷂𜷃𜷄𜷅𜷆𜷇𜷈𜷉𜷊',
          '𜷋𜷌𜷍𜷎𜷏𜷐𜷑𜷒𜷓𜷔𜷕𜷖𜷗𜷘𜷙𜷚▄𜷛𜷜𜷝𜷞▙𜷟𜷠𜷡𜷢▟𜷣▆𜷤𜷥█',
        ].join(),
      );
    });

    test('none is two columns wide', () {
      for (final marker in [
        Marker.dot,
        Marker.block,
        Marker.bar,
        Marker.braille,
        Marker.halfBlock,
        Marker.quadrant,
        Marker.sextant,
        Marker.octant,
      ]) {
        final shot = cells(marker, every(marker));
        expect(shot.anyWide, isFalse, reason: '$marker');
        expect(shot.vt.errors, isEmpty, reason: '$marker');
      }
    });
  });

  group('braille in place of', () {
    // a line from the bottom left to the top right of 4 × 4 dots
    void diagonal(DotContext c) => c.draw(const .line(0, 0, 3, 3));

    test('glyphs a terminal shows two columns wide', () {
      for (final marker in [
        Marker.dot,
        Marker.block,
        Marker.bar,
        Marker.halfBlock,
        Marker.quadrant,
        Marker.sextant,
        Marker.octant,
      ]) {
        final shot = drawn(
          2,
          1,
          diagonal,
          marker: marker,
          x: (0, 3),
          y: (0, 3),
          ambiguousWidth: 2,
        );
        expect(shot.rows, ['⡠⠊'], reason: '$marker');
        expect(shot.anyWide, isFalse, reason: '$marker');
      }
    });

    test('a custom glyph that is wide, joins its neighbour or may be wide', () {
      for (final char in ['日', '\u{1F1E6}', '☺']) {
        final shot = drawn(
          2,
          1,
          diagonal,
          marker: Marker.custom(char),
          x: (0, 3),
          y: (0, 3),
        );
        expect(shot.rows, ['⡠⠊'], reason: char);
      }
    });

    test('nothing that one column shows', () {
      final shot = drawn(
        2,
        1,
        diagonal,
        marker: Marker.custom('*'),
        x: (0, 1),
        y: (0, 1),
        ambiguousWidth: 2,
      );
      expect(shot.rows, ['**']);
    });
  });
}
