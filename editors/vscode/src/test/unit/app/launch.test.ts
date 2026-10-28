// The debug configurations (app/launch.ts): a `twk` one as Dart-Code's,
// what one asks for, and the launch read back from a session.
import * as assert from 'node:assert/strict';

import { asDartConfiguration, debugRequest, fromConfiguration, toConfiguration, wantsTerminal } from '../../../app/launch';
import { DartLaunch } from '../../../app/ports';

const launch: DartLaunch = {
  type: 'dart',
  request: 'launch',
  name: 'twk: main.dart',
  program: '/p/bin/main.dart',
  cwd: '/p',
  console: 'debugConsole',
  env: { TWK_SHELL: 'unix:/tmp/twk-shell-1/shell.sock#abc', TWK_DEBUG: 'keys' },
  twkSession: 'twk-0',
  others: { args: ['--x'] },
};

describe('the twk debug configurations', () => {
  it('a "twk" one is Dart-Code\'s launch in the Debug Console, marked, the current file by default', () => {
    assert.deepEqual(asDartConfiguration({ type: 'twk', request: 'launch', name: 'n', args: ['a'] }), {
      type: 'dart',
      request: 'launch',
      name: 'n',
      args: ['a'],
      console: 'debugConsole',
      twkTerminal: true,
      program: '${file}',
    });
    assert.match(String(asDartConfiguration({ type: 'twk', request: 'attach' })), /launches/);
  });

  it('wants a terminal: a Dart one marked twkTerminal, and given none yet', () => {
    assert.equal(wantsTerminal({ type: 'dart', twkTerminal: true }), true);
    assert.equal(wantsTerminal({ type: 'dart' }), false);
    assert.equal(wantsTerminal({ type: 'dart', twkTerminal: true, twkSession: 'twk-0' }), false, 'a restart of one');
  });

  it('what one asks for; what is wrong with one said', () => {
    assert.deepEqual(
      debugRequest({ type: 'dart', request: 'launch', name: 'n', program: '/p/a.dart', cwd: '/p', env: { A: '1' }, twkTerminal: true, toolArgs: ['--t'] }),
      { program: '/p/a.dart', cwd: '/p', name: 'n', env: { A: '1' }, others: { toolArgs: ['--t'] } },
    );
    assert.match(String(debugRequest({ type: 'dart' })), /no program/);
    assert.match(String(debugRequest({ program: '/a.dart', env: { A: 1 } })), /"env"/);
    assert.match(String(debugRequest({ program: '/a.dart', cwd: 3 })), /"cwd"/);
  });

  it('a launch to a configuration and back, the rest kept', () => {
    const c = toConfiguration(launch);
    const { others, ...fields } = launch;
    assert.deepEqual(c, { ...others, ...fields });
    assert.equal('others' in c, false);
    assert.deepEqual(fromConfiguration(c), launch);
    // as Dart-Code's session holds it: fields of its own added
    assert.deepEqual(fromConfiguration({ ...c, dartSdkPath: '/sdk' })?.others, { args: ['--x'], dartSdkPath: '/sdk' });
    assert.equal(fromConfiguration({ ...c, twkSession: undefined }), undefined, 'not one the extension made');
    assert.equal(fromConfiguration({ ...c, env: { A: 1 } }), undefined);
  });
});
