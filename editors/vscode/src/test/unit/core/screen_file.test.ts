// The extension's reading of a screen file (core/screen_file.ts), held to
// the file twk_test's own test matches,
// packages/twk_test/test/screen_file.golden.txt (screen_file_test.dart
// holds matchesScreenFile to write exactly it): what it reads, the message
// of a file that is none, the cells of a wide glyph, the difference of two
// screens and a style as CSS fields.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { ScreenFileError, cellsOf, colorCss, diffScreens, isSame, parseScreenFile, parseStyle, styleAt } from '../../../core/screen_file';

/** From out/test/unit/core, where this runs compiled, to the repository's root. */
const goldenPath = path.resolve(__dirname, '../../../../../../packages/twk_test/test/screen_file.golden.txt');
const golden = fs.readFileSync(goldenPath, 'utf8');

describe('a screen file', () => {
  it('reads a golden checked out with CRLF line ends, as it reads the LF one', () => {
    assert.deepEqual(parseScreenFile(golden.replace(/\r?\n/g, '\r\n')), parseScreenFile(golden));
  });

  it("reads the shared golden: size, cursor, rows, styles, legend", () => {
    const f = parseScreenFile(golden);
    assert.equal(f.width, 14);
    assert.equal(f.height, 3);
    assert.equal(f.cursor, null);
    assert.deepEqual(f.text, ['sent: привет  ', '[x] 界        ', '              ']);
    assert.deepEqual(f.styles, ['aaaaa         ', 'bbbcbb        ', '              ']);
    assert.deepEqual(f.legend, { a: 'bold', b: 'red on #010203', c: 'on #010203' });
    assert.equal(styleAt(f, 0, 0), 'bold');
    assert.equal(styleAt(f, 6, 0), '');
    assert.equal(styleAt(f, 3, 1), 'on #010203');
  });

  it('reads a cursor', () => {
    const f = parseScreenFile(golden.replace('cursor hidden', 'cursor at 5,2'));
    assert.deepEqual(f.cursor, [5, 2]);
  });

  it('says what is wrong with a file that is none, as twk_test does', () => {
    const bad = (s: string) => assert.throws(() => parseScreenFile(s), ScreenFileError);
    bad('');
    bad(golden.replace('screen 14×3', 'screen 14x3'));
    assert.throws(() => parseScreenFile(golden.replace('│[x] 界        │', '[x] 界')), /line 4 is not a row in │…│/);
    assert.throws(() => parseScreenFile(golden.replace('│bbbcbb        │', '│bbbcbb       │')), /row 1 of the styles has 13 characters, not 14/);
    assert.throws(() => parseScreenFile(golden.replace('legend', 'legends')), /is not "legend"/);
    assert.throws(() => parseScreenFile(golden.replace('a bold', 'abold')), /is not "<character> <style>"/);
  });

  it('puts a wide glyph in the cell it begins, the cell after it covered', () => {
    assert.deepEqual(cellsOf('[x] 界  ', 8), ['[', 'x', ']', ' ', '界', '', ' ', ' ']);
    // a row that does not add up to its width: a glyph a cell
    assert.deepEqual(cellsOf('界', 3), ['界', ' ', ' ']);
  });

  it('tells the cells whose text or style differs, and the cursor and size', () => {
    const a = parseScreenFile(golden);
    assert.ok(isSame(diffScreens(a, a)));
    const b = parseScreenFile(golden.replace('привет', 'привед').replace('b red on', 'b green on'));
    const d = diffScreens(a, b);
    const text = d.cells.find((c) => c.y === 0);
    assert.deepEqual(text, { x: 11, y: 0, text: ['т', 'д'], style: ['', ''] });
    const style = d.cells.filter((c) => c.y === 1);
    assert.deepEqual(style.map((c) => c.x), [0, 1, 2, 4, 5]);
    assert.deepEqual(style[0].style, ['red on #010203', 'green on #010203']);
    assert.equal(d.cursor, null);
    assert.deepEqual(diffScreens(a, parseScreenFile(golden.replace('cursor hidden', 'cursor at 1,1'))).cursor, [null, [1, 1]]);
    assert.deepEqual(diffScreens(a, parseScreenFile(golden.replace('screen 14×3', 'screen 14×2').replace('│              │\nstyles', 'styles').replace('│              │\nlegend', 'legend'))).size, [[14, 3], [14, 2]]);
  });

  it('names a style as CSS fields', () => {
    const s = parseStyle('bold italic doubleUnderline brightRed on #010203 ul=indexed(33) link=https://x.dev/a b');
    assert.equal(s.bold, true);
    assert.equal(s.italic, true);
    assert.equal(s.underline, 'double');
    assert.equal(s.fg, '#ff0000');
    assert.equal(s.bg, '#010203');
    assert.equal(s.underlineColor, 'rgb(0, 135, 255)');
    assert.equal(s.link, 'https://x.dev/a b');
    assert.equal(parseStyle('').fg, null);
    assert.equal(parseStyle('reverse').reverse, true);
    assert.equal(parseStyle('on default').bg, null);
    assert.equal(colorCss('indexed(244)'), 'rgb(128, 128, 128)');
    assert.equal(colorCss('red'), '#cd0000');
  });
});
