// The webview's pick of a cell: the point of a click on the screen element
// as a cell of the terminal.
import * as assert from 'node:assert/strict';

import { cellAt, cursorRowShown } from '../../../webview/pick';

describe("the webview's pick", () => {
  it('takes the cell under the point, from 0 at the top left', () => {
    // 80 x 24 cells of 9 x 18 pixels
    assert.deepEqual(cellAt(0, 0, 720, 432, 80, 24), { x: 0, y: 0 });
    assert.deepEqual(cellAt(8.9, 17.9, 720, 432, 80, 24), { x: 0, y: 0 });
    assert.deepEqual(cellAt(9, 18, 720, 432, 80, 24), { x: 1, y: 1 });
    assert.deepEqual(cellAt(719.9, 431.9, 720, 432, 80, 24), { x: 79, y: 23 });
    assert.deepEqual(cellAt(4 * 9 + 3, 2 * 18 + 1, 720, 432, 80, 24), { x: 4, y: 2 });
  });

  it("the cursor's row on the screen shown, scrolled back or not", () => {
    // xterm.js: the cursor on row 5 of the last screen, 30 rows of history above it
    assert.equal(cursorRowShown(5, 30, 30), 5);
    // scrolled back 10 rows: the screen shown begins 10 rows higher
    assert.equal(cursorRowShown(5, 30, 20), 15);
    // scrolled to the top: the cursor far below the screen shown
    assert.equal(cursorRowShown(5, 30, 0), 35);
  });

  it('none outside the screen, or of a screen not laid out', () => {
    assert.equal(cellAt(-1, 5, 720, 432, 80, 24), undefined);
    assert.equal(cellAt(720, 5, 720, 432, 80, 24), undefined);
    assert.equal(cellAt(5, 432, 720, 432, 80, 24), undefined);
    assert.equal(cellAt(5, 5, 0, 0, 80, 24), undefined);
    assert.equal(cellAt(5, 5, 720, 432, 0, 24), undefined);
  });
});
