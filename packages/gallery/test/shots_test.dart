// tool/shots.dart and tool/shots/svg.dart: a golden screen read into
// cells, drawn as an SVG, and cut to a page's stage and its widget.
import 'dart:io';

import 'package:test/test.dart';

import '../tool/shots.dart';
import '../tool/shots/svg.dart';

/// A golden file of [text], [styles] and [legend], as matchesScreenFile
/// writes one.
String golden(List<String> text, List<String> styles, List<String> legend) => [
  'screen ${styles.first.length}×${text.length}, cursor hidden',
  'text',
  for (final row in text) '│$row│',
  'styles',
  for (final row in styles) '│$row│',
  'legend',
  ...legend,
  '',
].join('\n');

const palette = ShotPalette(foreground: 0xeeeeee, background: 0x101010);

void main() {
  test('a wide glyph takes two cells, the second empty', () {
    final shot = Shot.parse(golden(['漢a  '], ['aaa  '], ['a bold red']));
    expect([for (final c in shot.rows[0]) c.text], ['漢', '', 'a', ' ', ' ']);
    expect(shot.rows[0][0].style, 'bold red');
    expect(shot.rows[0][3].style, '');
  });

  test('backgrounds as rectangles, text in runs of one look, blocks and '
      'lines as shapes', () {
    final svg = svgOf(
      Shot.parse(
        golden(
          ['ab█c', '──┐ '],
          ['aabc', 'ddd '],
          ['a #ff0000 on #000080', 'b on #000080', 'c bold', 'd #00ff00'],
        ),
      ),
      palette,
    );
    expect(
      svg,
      startsWith(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="40" height="40" viewBox="0 0 40 40">',
      ),
    );
    expect(
      svg,
      contains(
        '<rect x="0" y="0" width="30" height="20" '
        'fill="#000080"/>',
      ),
    );
    expect(
      svg,
      contains(
        '<g fill="#ff0000"><text x="0" y="15">a</text><text x="10" '
        'y="15">b</text></g>',
      ),
    );
    expect(
      svg,
      contains(
        '<g font-weight="bold"><text x="30" y="15">c</text></g>',
      ),
    );
    // the full block, in its cell, in the color of b: the default
    expect(
      svg,
      contains(
        '<g fill="#eeeeee"><rect x="20" y="0" width="10" '
        'height="20"/>',
      ),
    );
    // the line, one rectangle over two cells, and the corner's arms
    expect(svg, contains('<rect x="0" y="29.25" width="20" height="1.5"/>'));
    expect(
      svg,
      contains(
        '<rect x="24.25" y="29.25" width="1.5" '
        'height="10.75"/>',
      ),
    );
  });

  test('reverse swaps the colors; dim takes the text halfway to the '
      'background', () {
    final svg = svgOf(
      Shot.parse(golden(['ab'], ['ab'], ['a reverse', 'b dim #ffffff'])),
      palette,
    );
    expect(
      svg,
      contains(
        '<rect x="0" y="0" width="10" height="20" '
        'fill="#eeeeee"/>',
      ),
    );
    expect(svg, contains('<g fill="#101010"><text x="0" y="15">a</text>'));
    expect(svg, contains('<g fill="#878787"><text x="10" y="15">b</text>'));
  });

  test("the stage is under the tabs' rule, left of the options' divider", () {
    final shot = Shot.parse(
      golden(
        ['Preview   ', ' ──━━─┬───', ' a   │ o  ', ' b   │    ', 'hints     '],
        [for (var i = 0; i < 5; i++) '          '],
        [],
      ),
    );
    final stage = stageOf(shot);
    expect((stage.width, stage.height), (5, 2));
    expect(stage.rows[0][0].text, 'a');
  });

  test('the widget is its corner marks and size, with a margin; the whole '
      'stage without a size', () {
    final stage = Shot.parse(
      golden(
        [
          '            ',
          '  ┌     ┐   ',
          '    hi      ',
          '  └     ┘   ',
          '     2 × 1  ',
          '            ',
        ],
        [for (var i = 0; i < 6; i++) '            '],
        [],
      ),
    );
    final widget = widgetOf(stage, margin: 1);
    expect((widget.width, widget.height), (9, 4));
    expect([for (final c in widget.rows[0]) c.text].join(), ' ┌     ┐ ');
    final bare = Shot.parse(golden([' a '], ['   '], []));
    expect(widgetOf(bare), same(bare));
  });

  test('the shots use no x list, textLength, currentColor or xml:space, '
      'which flutter_svg does not take', () {
    final shots = Directory('doc/shots')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.svg'))
        .toList();
    expect(shots, isNotEmpty);
    final xList = RegExp('<text x="[^"]* ');
    for (final shot in shots) {
      final svg = shot.readAsStringSync();
      expect(svg, isNot(matches(xList)), reason: shot.path);
      for (final word in ['textLength', 'currentColor', 'xml:space']) {
        expect(svg, isNot(contains(word)), reason: shot.path);
      }
    }
  });
}
