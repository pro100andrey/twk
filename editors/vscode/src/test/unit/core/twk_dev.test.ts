// Whether a folder runs twk_dev, and which folder names `twk create` takes (core/twk_dev.ts).
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { dependsOnTwkDev, folderNameError, packageNameOf } from '../../../core/twk_dev';

describe('dependsOnTwkDev', () => {
  let root: string;
  beforeEach(() => (root = fs.mkdtempSync(path.join(os.tmpdir(), 'twk-dev-'))));
  afterEach(() => fs.rmSync(root, { recursive: true, force: true }));

  const write = (file: string, text: string) => {
    fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
    fs.writeFileSync(path.join(root, file), text);
  };

  it('a folder with no pubspec.yaml above it has none', () => {
    assert.equal(dependsOnTwkDev(root), false);
  });

  it('a pubspec that does not name it, and a package_config that does not hold it, have none', () => {
    write('app/pubspec.yaml', 'name: app\ndependencies:\n  path: ^1.0.0\n');
    assert.equal(dependsOnTwkDev(path.join(root, 'app')), false);
    write('app/.dart_tool/package_config.json', JSON.stringify({ packages: [{ name: 'path' }] }));
    assert.equal(dependsOnTwkDev(path.join(root, 'app')), false);
  });

  it('a package_config that holds it, or a pubspec that names it not yet resolved, have it', () => {
    write('app/pubspec.yaml', 'name: app\ndev_dependencies:\n  twk_dev: any\n');
    assert.equal(dependsOnTwkDev(path.join(root, 'app')), true);
    write('b/pubspec.yaml', 'name: b\n');
    write('b/.dart_tool/package_config.json', JSON.stringify({ packages: [{ name: 'twk_dev' }] }));
    assert.equal(dependsOnTwkDev(path.join(root, 'b')), true);
  });

  it('a workspace member is resolved by the package_config of the workspace above it', () => {
    write('ws/pubspec.yaml', 'name: ws\n');
    write('ws/.dart_tool/package_config.json', JSON.stringify({ packages: [{ name: 'twk_dev' }] }));
    write('ws/member/pubspec.yaml', 'name: member\nresolution: workspace\n');
    assert.equal(dependsOnTwkDev(path.join(root, 'ws', 'member')), true);
  });

  it('a package_config that cannot be read says nothing', () => {
    write('app/pubspec.yaml', 'name: app\n');
    write('app/.dart_tool/package_config.json', '{');
    assert.equal(dependsOnTwkDev(path.join(root, 'app')), undefined);
  });
});

describe('folderNameError', () => {
  it('takes what twk create takes: the name is made of the folder as it makes it', () => {
    assert.equal(packageNameOf('My App'), 'my_app');
    for (const ok of ['app', 'My App', 'my-app', 'a1_b']) {
      assert.equal(folderNameError(ok), undefined, ok);
    }
  });

  it('refuses a digit first, a reserved word, a package the app depends on, with why', () => {
    assert.match(folderNameError('1app')!, /lower case letter first/);
    assert.match(folderNameError('_app')!, /lower case letter first/);
    assert.match(folderNameError('class')!, /reserved word/);
    assert.match(folderNameError('Twk')!, /depends on/);
    assert.match(folderNameError('1 app')!, /1 app is 1_app/);
  });
});
