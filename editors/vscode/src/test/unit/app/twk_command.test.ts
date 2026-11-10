// Running twk (app/twk_command.ts) with real processes: a deadline or a
// cancel ends the whole group the command started, by SIGKILL where SIGTERM
// is ignored.
import * as assert from 'node:assert/strict';

import { runTwk } from '../../../app/twk_command';
import { AppProcess, Exit, startNodeProcess } from '../../../core/process';
import { FakeLog } from '../fakes';

/** Whether process [pid] exists. */
function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/** A parent that starts a child ignoring SIGTERM, tells its pid, and waits; the parent ignores SIGTERM too. */
const parent = `
  const { spawn } = require('node:child_process');
  process.on('SIGTERM', () => {});
  const child = spawn(process.execPath, ['-e', "process.on('SIGTERM', () => {}); setInterval(() => {}, 1000)"], { stdio: 'ignore' });
  console.log('child ' + child.pid);
  setInterval(() => {}, 1000);`;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe('runTwk over real processes', function () {
  this.timeout(30000);

  (process.platform === 'win32' ? it.skip : it)('a cancel ends the group: SIGTERM ignored by both, SIGKILL reaches the child too', async () => {
    const abort = new AbortController();
    let seen = '';
    const start: typeof startNodeProcess = (c, a, o) => {
      const p = startNodeProcess(c, a, o);
      p.onOutput((t) => (seen += t));
      return p;
    };
    const run = runTwk({ start, command: () => [process.execPath, '-e', parent, '--'], env: process.env, log: new FakeLog() }, [], {
      cwd: process.cwd(),
      label: 'x',
      cancel: abort.signal,
      graceMs: 200,
    });
    // what is awaited is a real process's start
    while (!/child \d+/.test(seen)) {
      await sleep(20);
    }
    const pid = Number(/child (\d+)/.exec(seen)![1]);
    assert.ok(alive(pid));
    abort.abort();
    const r = await run;
    assert.ok(r.cancelled);
    assert.ok(!r.timedOut);
    assert.equal(r.exit.signal, 'SIGKILL');
    while (alive(pid)) {
      await sleep(20);
    }
  });

  (process.platform === 'win32' ? it.skip : it)('a child that ignores SIGTERM does not outlive a leader that exited on it: SIGKILL to the group after the grace', async () => {
    const leader = parent.replace("process.on('SIGTERM', () => {});\n  const child", "process.on('SIGTERM', () => process.exit(0));\n  const child");
    assert.notEqual(leader, parent);
    const abort = new AbortController();
    let seen = '';
    const start: typeof startNodeProcess = (c, a, o) => {
      const p = startNodeProcess(c, a, o);
      p.onOutput((t) => (seen += t));
      return p;
    };
    const run = runTwk({ start, command: () => [process.execPath, '-e', leader, '--'], env: process.env, log: new FakeLog() }, [], { cwd: process.cwd(), label: 'x', cancel: abort.signal, graceMs: 200 });
    while (!/child \d+/.test(seen)) {
      await sleep(20);
    }
    const pid = Number(/child (\d+)/.exec(seen)![1]);
    abort.abort();
    const r = await run;
    assert.equal(r.exit.code, 0);
    // the leader is gone; the child ignored SIGTERM and lives until the grace is over
    assert.ok(alive(pid));
    // bounded: a child that stays would otherwise keep this loop, and mocha, running after the failure
    for (let i = 0; i < 150 && alive(pid); i++) {
      await sleep(20);
    }
    const stays = alive(pid);
    if (stays) {
      process.kill(pid, 'SIGKILL');
    }
    assert.ok(!stays, 'the child outlived the group kill');
  });

  it('after the leader exited on SIGTERM, SIGKILL still goes to the group after the grace, on POSIX only', async () => {
    const sent: string[] = [];
    let exited = false;
    let finish!: (e: Exit) => void;
    const done = new Promise<Exit>((r) => (finish = r));
    const fake: AppProcess = {
      pid: 1,
      get hasExited() {
        return exited;
      },
      exited: done,
      onOutput: () => {},
      onError: () => {},
      write: () => {},
      signal(sig) {
        sent.push(sig);
        if (sig === 'SIGTERM') {
          exited = true;
          finish({ code: null, signal: 'SIGTERM' });
        }
      },
    };
    const abort = new AbortController();
    const run = runTwk({ start: () => fake, command: () => ['twk'], env: {}, log: new FakeLog() }, [], { cwd: '.', label: 'x', cancel: abort.signal, graceMs: 10 });
    abort.abort();
    await run;
    await sleep(50);
    assert.deepEqual(sent, process.platform === 'win32' ? ['SIGTERM'] : ['SIGTERM', 'SIGKILL']);
  });
});
