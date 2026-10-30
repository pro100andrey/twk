// twk's inspector answers as typed values (core/inspect.ts): each checked,
// its version among it; and what the tree view says of a node.
import * as assert from 'node:assert/strict';

import {
  InspectNode,
  describeNode,
  detailsOf,
  flagParams,
  nodeOf,
  parseFlags,
  parsePicked,
  parseSelect,
  parseTree,
  pathTo,
  shownRoot,
  toggleItems,
  togglesPicked,
} from '../../../core/inspect';
import { treeAnswer } from '../fakes';

describe("twk's inspector answers", () => {
  it('reads the element tree, each node with what twk tells of it', () => {
    const tree = parseTree(treeAnswer);
    assert.equal(tree.app, 3);
    const count = nodeOf(tree, 2)!;
    assert.equal(count.build, '_CountState');
    assert.equal(count.key, '[GlobalKey#1]');
    assert.deepEqual(count.size, { width: 20, height: 3 });
    assert.deepEqual(count.flags, ['needsBuild']);
    const text = nodeOf(tree, 4)!;
    assert.deepEqual(text.properties, [{ value: '"n 0"' }]);
    assert.equal(text.render, 11);
    assert.equal(text.build, undefined);
    assert.deepEqual(
      pathTo(tree.root, 4)!.map((n) => n.id),
      [1, 2, 3, 4],
    );
    assert.equal(pathTo(tree.root, 99), undefined);
    assert.equal(shownRoot(tree)!.name, 'Padding');
    assert.equal(shownRoot({ ...tree, app: null })!.name, 'RootWidget');
    assert.deepEqual(parseTree({ version: 1, tree: 'element', root: null, app: null }), { root: null, app: null });
  });

  it('refuses an answer of another version, of the render tree, or one it does not read', () => {
    assert.throws(() => parseTree({ ...treeAnswer, version: 2 }), /version 2; this extension reads 1/);
    assert.throws(() => parseTree({ ...treeAnswer, tree: 'render' }), /not the element tree/);
    assert.throws(() => parseTree({ ...treeAnswer, root: { id: 'x', name: 'A', children: [] } }), /does not read/);
    assert.throws(() => parseTree({ ...treeAnswer, root: { id: 1, name: 'A', children: [{ id: 0, name: 'B', children: [] }] } }), /does not read/);
    assert.throws(() => parseTree([]), /no JSON object/);
  });

  it('reads the node at a cell, the debug aids, and the cell of a pick on the app', () => {
    assert.deepEqual(parseSelect({ version: 1, id: 4, path: [1, 2, 3, 4], render: [11, 10] }), { id: 4, path: [1, 2, 3, 4] });
    assert.deepEqual(parseSelect({ version: 1, id: null, path: [] }), { id: null, path: [] });
    const flags = parseFlags({ version: 1, overlay: true, console: false, rainbow: true, relayout: false, keys: true, select: true, selectMany: true, treeEvents: true, framesInRow: false });
    assert.deepEqual(flags, { overlay: true, console: false, rainbow: true, relayout: false, keys: true, select: true, selectMany: true, treeEvents: true });
    // an answer without a flag is no answer of this twk
    assert.throws(() => parseFlags({ version: 1, overlay: false }), /no console/);
    assert.deepEqual(parsePicked({ version: 1, x: 3, y: 2 }), { x: 3, y: 2 });
    assert.equal(parsePicked({ version: 1, x: null, y: null }), null);
    assert.equal(parsePicked({ version: 2, x: 3, y: 2 }), undefined);
    assert.equal(parsePicked({ version: 1, x: -1, y: 2 }), undefined);
    assert.equal(parsePicked('twk'), undefined);
  });

  it("says of a node its key, first property and size beside its name, and all of it in the tooltip", () => {
    const tree = parseTree(treeAnswer);
    assert.equal(describeNode(nodeOf(tree, 4)!), '"n 0" · 3×1');
    assert.equal(describeNode(nodeOf(tree, 3)!), 'padding: left 2');
    assert.equal(describeNode(nodeOf(tree, 2)!), '[GlobalKey#1] · 20×3');
    const long: InspectNode = { id: 5, name: 'Text', properties: [{ value: 'x'.repeat(60) }], flags: [], children: [] };
    assert.equal(describeNode(long), `${'x'.repeat(39)}…`);
    assert.deepEqual(detailsOf(nodeOf(tree, 2)!), ['_Count [GlobalKey#1]', 'size 20×3', 'needsBuild', 'built by _CountState.build']);
  });

  it('the toggles: picked as the app has them, and back as each on or off', () => {
    const flags = parseFlags({ version: 1, overlay: true, rainbow: false, relayout: true, console: false, keys: false, select: false, selectMany: false, treeEvents: false });
    const items = toggleItems(flags);
    assert.deepEqual(
      items.map((i) => [i.label, i.picked]),
      [
        ['Frame overlay', true],
        ['Repaint rainbow', false],
        ['Relayout highlight', true],
        ['Log console', false],
      ],
    );
    assert.deepEqual(togglesPicked(['Repaint rainbow', 'Log console']), { overlay: false, rainbow: true, relayout: false, console: true });
    assert.deepEqual(flagParams({ overlay: true, treeEvents: false }), { overlay: 'true', treeEvents: 'false' });
  });
});
