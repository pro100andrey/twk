// Where a widget was made, looked for in the source of the build methods
// above it (core/source_find.ts): the builds that may have made it, the
// calls of its type's constructor in code (not in comments or strings),
// and which of them made it.
import * as assert from 'node:assert/strict';

import { InspectNode } from '../../../core/inspect';
import {
  buildsIn,
  className,
  codeOnly,
  constructorCalls,
  creationOwners,
  lineColumnOf,
  offsetOf,
  pickCall,
  tokenLineColumn,
} from '../../../core/source_find';

let nextId = 1;
/** A node of a tree for a test; [build] for one that builds. */
function n(name: string, children: InspectNode[] = [], build?: string): InspectNode {
  return { id: nextId++, name, properties: [], flags: [], children, ...(build ? { build } : {}) };
}

describe('where a widget was made', () => {
  it('the builds above it, the nearest first, each with its place among those of its type that build made', () => {
    // Page builds Column [Text a, Card(child: Text b), Text c]; Card builds Padding(child: its child)
    const a = n('Text');
    const b = n('Text');
    const c = n('Text');
    const card = n('Card', [n('Padding', [b])], 'Card');
    const page = n('Page', [n('Column', [a, card, c])], '_PageState');
    const root = n('RootWidget', [page]);

    const ofB = creationOwners(root, b.id);
    assert.deepEqual(
      ofB.map((o) => [o.build, o.index, o.count]),
      [
        // in Card's build no Text but b (passed through it)
        ['Card', 0, 1],
        // in the page's: a, b (through Card, on the way), c
        ['_PageState', 1, 3],
      ],
    );
    // c: Card's build is another's, not looked into
    assert.deepEqual(
      creationOwners(root, c.id).map((o) => [o.build, o.index, o.count]),
      [['_PageState', 1, 2]],
    );
    // Card's build makes no Text: what is below it was passed to it, made above
    assert.deepEqual(
      creationOwners(root, c.id, (build) => build !== 'Card').map((o) => [o.build, o.index, o.count]),
      [['_PageState', 2, 3]],
    );
    assert.deepEqual(buildsIn(root).sort(), ['Card', '_PageState']);
    // a component element is made by the build above it, not by its own
    assert.deepEqual(
      creationOwners(root, card.id).map((o) => [o.build, o.index, o.count]),
      [['_PageState', 0, 1]],
    );
    assert.deepEqual(creationOwners(root, 999), []);
    assert.deepEqual(creationOwners(null, 1), []);
  });

  it("a generic type's class", () => {
    assert.equal(className('ValueListenableBuilder<int>'), 'ValueListenableBuilder');
    assert.equal(className('Text'), 'Text');
    const list = n('ListView<int>');
    const page = n('Page', [list], 'Page');
    assert.deepEqual(
      creationOwners(n('R', [page]), list.id).map((o) => o.count),
      [1],
    );
  });

  it('blanks comments, nested ones too, and strings, keeping every offset', () => {
    const source = "a // Text(\nb /* x /* Text( */ y */ c 'Text(' \"it's\" r'\\' d '''\nText(''' e";
    const code = codeOnly(source);
    assert.equal(code.length, source.length);
    assert.ok(!code.includes('Text'), code);
    assert.deepEqual(code.match(/\b[a-e]\b/g), ['a', 'b', 'c', 'd', 'e']);
    // lines kept
    assert.equal(code.split('\n').length, source.split('\n').length);
  });

  it('finds the calls of a constructor in code, whatever their form, between two offsets', () => {
    const source = [
      'Widget build(BuildContext context) {', // 0
      "  // Text('no')", // 1
      '  return Column(children: [', // 2
      "    const Text('a'),", // 3
      "    Text.rich('b'),", // 4
      "    w.Text ('c'),", // 5
      '    TextField(), MyText(), _Text(), Texts(),', // 6
      '    Foo<int>(),', // 7
      '  ]);', // 8
      '}', // 9
      "Text('after')", // 10
    ].join('\n');
    const end = source.lastIndexOf('}') + 1;
    const lines = constructorCalls(source, 0, end, 'Text').map((o) => lineColumnOf(source, o));
    assert.deepEqual(lines, [
      { line: 4, column: 11 },
      { line: 5, column: 5 },
      { line: 6, column: 7 },
    ]);
    assert.deepEqual(
      constructorCalls(source, 0, end, 'Foo').map((o) => lineColumnOf(source, o).line),
      [8],
    );
    assert.deepEqual(
      constructorCalls(source, 0, end, '_Text').map((o) => lineColumnOf(source, o).line),
      [7],
    );
    // only from where it is asked
    assert.deepEqual(
      constructorCalls(source, offsetOf(source, 5, 1), end, 'Text').map((o) => lineColumnOf(source, o).line),
      [5, 6],
    );
  });

  it('lines and columns of offsets and of token positions', () => {
    const source = 'ab\ncd\n\nef';
    assert.deepEqual(lineColumnOf(source, 0), { line: 1, column: 1 });
    assert.deepEqual(lineColumnOf(source, 4), { line: 2, column: 2 });
    assert.deepEqual(lineColumnOf(source, 7), { line: 4, column: 1 });
    assert.equal(offsetOf(source, 2, 2), 4);
    assert.equal(offsetOf(source, 4, 2), 8);
    assert.equal(offsetOf(source, 9, 1), source.length);
    const table = [
      [3, 10, 1, 12, 5],
      [4, 20, 3],
    ];
    assert.deepEqual(tokenLineColumn(table, 12), { line: 3, column: 5 });
    assert.deepEqual(tokenLineColumn(table, 20), { line: 4, column: 3 });
    assert.equal(tokenLineColumn(table, 11), undefined);
  });

  it('the call that made it: the only one, or the one at its place when there are as many', () => {
    assert.deepEqual(pickCall([10], 2, 3), { offset: 10, exact: true });
    assert.deepEqual(pickCall([10, 20, 30], 1, 3), { offset: 20, exact: true });
    // a loop, an if: not as many calls as elements
    assert.deepEqual(pickCall([10, 20], 3, 4), { offset: 20, exact: false });
    assert.equal(pickCall([], 0, 1), undefined);
  });
});
