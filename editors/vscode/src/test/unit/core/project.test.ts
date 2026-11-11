// Where a file is, in relation to a directory (core/project.ts).
import * as assert from 'node:assert/strict';
import * as path from 'node:path';

import { isInside } from '../../../core/project';

describe('isInside', () => {
  const root = path.resolve('/p/app');

  it('the directory, a file below it, and a name that merely starts with ..', () => {
    assert.ok(isInside(root, root));
    assert.ok(isInside(root, path.join(root, 'out', 'a.svg')));
    assert.ok(isInside(root, path.join(root, '..shot.svg')));
    assert.ok(isInside(root, path.join(root, '..', 'app', 'a.svg')));
  });

  it('the parent, a sibling and another place are outside', () => {
    assert.ok(!isInside(root, path.resolve('/p')));
    assert.ok(!isInside(root, path.resolve('/p/other/a.svg')));
    assert.ok(!isInside(root, path.join(root, '..', 'a.svg')));
    assert.ok(!isInside(root, path.resolve('/etc/passwd')));
  });
});
