// Whether a file is in a workspace folder (app/terminal.ts inFolders): by the
// path's own separators, so a name that merely starts with `..` is inside.
import * as assert from 'node:assert/strict';
import * as path from 'node:path';

import { inFolders } from '../../../app/terminal';

describe('inFolders', () => {
  const fs = { realPath: (p: string) => p, foldsCase: false };
  const root = path.resolve('/p/work');

  it('is the folder itself and what is below it, a name starting with two dots included', () => {
    assert.ok(inFolders(root, [root], fs));
    assert.ok(inFolders(path.join(root, 'lib', 'a.dart'), [root], fs));
    assert.ok(inFolders(path.join(root, '..hidden.txt'), [root], fs));
    assert.ok(inFolders(path.join(root, '..d', 'a.txt'), [root], fs));
  });

  it('is not what is beside or above it', () => {
    assert.ok(!inFolders(path.resolve('/p/work2/a.dart'), [root], fs));
    assert.ok(!inFolders(path.resolve('/p/a.dart'), [root], fs));
    assert.ok(!inFolders(path.resolve('/p/work/../a.dart'), [root], fs));
  });
});
