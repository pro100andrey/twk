import * as assert from 'node:assert';
import * as path from 'node:path';

import { editorCommandOf } from '../../../core/editor';

describe('the editor command for the apps', () => {
  it("is the editor's own command line, quoted, with the place put in", () => {
    const code = path.join('/opt/code/resources/app', 'bin', 'code');
    assert.equal(editorCommandOf('/opt/code/resources/app', 'linux', (f) => f === code), `"${code}" -r -g {file}:{line}:{column}`);
  });

  it('takes the first command line there is, .cmd on Windows, none where there is none', () => {
    const codium = path.join('/x', 'bin', 'codium.cmd');
    assert.equal(editorCommandOf('/x', 'win32', (f) => f === codium), `"${codium}" -r -g {file}:{line}:{column}`);
    assert.equal(editorCommandOf('/x', 'linux', () => false), undefined);
  });
});
