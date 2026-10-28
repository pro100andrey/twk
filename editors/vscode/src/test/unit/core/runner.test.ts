// The wait of a run (core/runner.ts) for its app's VM service, over a fake
// process and a fake clock: the service info file found as it is written,
// and the wait bounded when the app never names a service.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

import { HotStatus } from '../../../core/hot';
import { AppProcess, Exit } from '../../../core/process';
import { HotRun, serviceInfoPatience } from '../../../core/runner';
import { Vm } from '../../../core/vm';
import { FakeClock, FakeVm, until } from '../fakes';

/** A process that runs until it is signalled, and writes nothing unless the test does. */
class FakeProcess implements AppProcess {
  readonly pid = 7;
  hasExited = false;
  readonly exited: Promise<Exit>;
  private exit!: (e: Exit) => void;
  constructor(readonly args: readonly string[]) {
    this.exited = new Promise((r) => (this.exit = r));
  }
  /** Where the app is to write its service info (`--write-service-info`). */
  get serviceInfo(): string {
    const arg = this.args.find((a) => a.startsWith('--write-service-info='));
    assert.ok(arg);
    return fileURLToPath(arg.substring('--write-service-info='.length));
  }
  onOutput(): void {}
  onError(): void {}
  write(): void {}
  signal(signal: string): void {
    this.hasExited = true;
    this.exit({ code: null, signal });
  }
}

describe('HotRun, waiting for the VM service', () => {
  let clock: FakeClock;
  let processes: FakeProcess[];
  let connected: string[];
  let out: string;
  let statuses: HotStatus[];
  let run: HotRun;

  beforeEach(() => {
    clock = new FakeClock();
    processes = [];
    connected = [];
    out = '';
    statuses = [];
    run = HotRun.start(
      { file: '/p/bin/main.dart', cwd: '/p', onOutput: (t) => (out += t), onStatus: (s) => statuses.push(s) },
      {
        startProcess: (_command, args) => {
          const p = new FakeProcess(args);
          processes.push(p);
          return p;
        },
        connectVm: async (uri): Promise<Vm> => {
          connected.push(uri);
          return new FakeVm();
        },
        env: {},
        clock,
      },
    );
  });

  afterEach(async () => {
    await run.stop();
  });

  it('connects once the app writes its service info: no timer polls for it', async () => {
    const [app] = processes;
    assert.equal(clock.pending, 1, 'the bound of the wait, nothing else');
    // as dart writes it: the file in two writes
    fs.writeFileSync(app.serviceInfo, '{"uri":');
    fs.appendFileSync(app.serviceInfo, '"http://127.0.0.1:1/x=/"}');
    await until('the connect', () => connected.length === 1, 100000);
    assert.deepEqual(connected, ['http://127.0.0.1:1/x=/']);
    await until('running', () => statuses.some((s) => s.state === 'running'), 100000);
    assert.equal(clock.pending, 0, 'the bound gone with the wait');
    assert.equal(path.basename(app.serviceInfo), 'service.json');
  });

  it('an app that never names its VM service: the wait ends after its bound, said so, a reload answered "ended"', async () => {
    const reload = run.reload();
    clock.elapse(serviceInfoPatience - 1);
    let settled = false;
    void reload.then(() => (settled = true));
    await new Promise((r) => setImmediate(r));
    assert.equal(settled, false, 'still waiting just before the bound');
    clock.elapse(1);
    assert.deepEqual(await reload, { state: 'ended' });
    assert.match(out, /no hot reload: the app named no VM service in 120 s/);
    assert.deepEqual(connected, []);
  });

  it('an app that ends before it names one: the wait ends with it', async () => {
    const reload = run.reload();
    processes[0].signal('SIGTERM');
    assert.deepEqual(await reload, { state: 'ended' });
    assert.equal(clock.pending, 0);
  });
});
