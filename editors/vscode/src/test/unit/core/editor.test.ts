import * as assert from 'node:assert';

import { editorCommandOf } from '../../../core/editor';

const args = '-r -g {file}:{line}:{column}';

/** A file system that has [files], for the install layouts of each platform. */
const has = (...files: string[]) => (f: string) => files.includes(f);

describe('the editor command for the apps', () => {
  it('on Linux is <install>/bin/code, two directories above appRoot (resources/app)', () => {
    const appRoot = '/opt/visual-studio-code/resources/app';
    assert.equal(editorCommandOf(appRoot, 'linux', has('/opt/visual-studio-code/bin/code')), `"/opt/visual-studio-code/bin/code" ${args}`);
  });

  it('on Windows is <install>\\bin\\code.cmd', () => {
    const appRoot = 'C:\\Users\\a\\AppData\\Local\\Programs\\Microsoft VS Code\\resources\\app';
    const cmd = 'C:\\Users\\a\\AppData\\Local\\Programs\\Microsoft VS Code\\bin\\code.cmd';
    assert.equal(editorCommandOf(appRoot, 'win32', has(cmd)), `"${cmd}" ${args}`);
  });

  it('on macOS is <appRoot>/bin/code (Contents/Resources/app/bin/code)', () => {
    const appRoot = '/Applications/Visual Studio Code.app/Contents/Resources/app';
    assert.equal(editorCommandOf(appRoot, 'darwin', has(`${appRoot}/bin/code`)), `"${appRoot}/bin/code" ${args}`);
    // not the two-up directory there
    assert.equal(editorCommandOf(appRoot, 'darwin', has('/Applications/Visual Studio Code.app/Contents/bin/code')), `code ${args}`);
  });

  it('takes the first command line there is (VS Code, Insiders, VSCodium); appRoot/bin is the last place', () => {
    assert.equal(editorCommandOf('/x/resources/app', 'linux', has('/x/bin/codium', '/x/bin/code-insiders')), `"/x/bin/code-insiders" ${args}`);
    assert.equal(editorCommandOf('/srv/app', 'linux', has('/srv/app/bin/code')), `"/srv/app/bin/code" ${args}`);
  });

  it('is `code`, for the PATH, where no file is found', () => {
    for (const platform of ['linux', 'win32', 'darwin']) {
      assert.equal(editorCommandOf('/x/resources/app', platform, () => false), `code ${args}`, platform);
    }
  });
});
