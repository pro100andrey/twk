// The node process of a run (core/process.ts), with real child processes.
import * as assert from 'node:assert/strict';

import { startNodeProcess } from '../../../core/process';

describe('startNodeProcess', () => {
  it('a character whose UTF-8 bytes come in two reads is one character', async () => {
    // U+2500, e2 94 80: two bytes, then the last one once the first are read
    const script = `process.stdout.write(Buffer.from([0xe2, 0x94]), () => setTimeout(() => process.stdout.write(Buffer.from([0x80, 0x0a])), 200));`;
    const p = startNodeProcess(process.execPath, ['-e', script], { cwd: process.cwd(), env: process.env });
    let out = '';
    p.onOutput((t) => (out += t));
    await p.exited;
    assert.equal(out, '─\n');
  });

  it("a command that can't be started: the error told, and it has ended", async () => {
    const p = startNodeProcess('/nonexistent/twk-dart', [], { cwd: process.cwd(), env: process.env });
    const errors: Error[] = [];
    p.onError((e) => errors.push(e));
    const exit = await p.exited;
    assert.match(String(errors[0]), /ENOENT/);
    assert.ok(p.hasExited);
    assert.notEqual(exit.code, 0);
  });
});

describe('startNodeProcess, written to once the app closed its stdin', () => {
  it('the broken pipe (EPIPE) ends nothing: no error thrown at the extension host', async () => {
    const script = `require('fs').closeSync(0); console.log('closed'); setTimeout(() => {}, 300);`;
    const p = startNodeProcess(process.execPath, ['-e', script], { cwd: process.cwd(), env: process.env });
    let out = '';
    const said = new Promise<void>((resolve) => p.onOutput((t) => (out += t).includes('closed') && resolve()));
    const uncaught: unknown[] = [];
    const listener = (e: unknown) => uncaught.push(e);
    process.on('uncaughtException', listener);
    try {
      await said;
      p.write('x\n');
      p.write('y'.repeat(100000));
      await p.exited;
    } finally {
      process.off('uncaughtException', listener);
    }
    assert.deepEqual(uncaught, []);
  });
});
