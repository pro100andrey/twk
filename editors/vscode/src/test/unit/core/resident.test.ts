// The resident compiler of the runs (core/resident.ts): the arguments a
// run takes it by, and its shutdown with the extension, over a fake
// process and a fake clock.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { AppProcess, Exit } from '../../../core/process';
import { ResidentCompiler, shutdownPatience } from '../../../core/resident';
import { FakeClock } from '../fakes';

/** A process that ends when the test ends it ([end]) or a signal does. */
class FakeProcess implements AppProcess {
  readonly pid = 9;
  hasExited = false;
  readonly signals: string[] = [];
  readonly exited: Promise<Exit>;
  private exit!: (e: Exit) => void;
  constructor(
    readonly command: string,
    readonly args: readonly string[],
  ) {
    this.exited = new Promise((r) => (this.exit = r));
  }
  groupAlive = () => false;
  onOutput(): void {}
  onError(): void {}
  write(): void {}
  end(code: number): void {
    this.hasExited = true;
    this.exit({ code, signal: null });
  }
  signal(signal: string): void {
    this.signals.push(signal);
    this.hasExited = true;
    this.exit({ code: null, signal });
  }
}

describe('ResidentCompiler', () => {
  let root: string;
  let clock: FakeClock;
  let processes: FakeProcess[];
  let compiler: ResidentCompiler;

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'twk_resident_test_'));
    clock = new FakeClock();
    processes = [];
    compiler = ResidentCompiler.create(root, {
      startProcess: (command, args) => {
        const p = new FakeProcess(command, args);
        processes.push(p);
        return p;
      },
      env: {},
      clock,
    });
  });

  afterEach(() => fs.rmSync(root, { recursive: true, force: true }));

  it("names an info file of its own, in a directory of its own: not the machine's default compiler", () => {
    assert.deepEqual(compiler.runArgs, ['--resident', '--quiet', `--resident-compiler-info-file=${compiler.infoFile}`]);
    assert.equal(path.dirname(path.dirname(compiler.infoFile)), root);
    assert.ok(fs.statSync(path.dirname(compiler.infoFile)).isDirectory());
  });

  it('never started (no info file): shutdown starts nothing, and removes its directory', async () => {
    await compiler.shutdown();
    assert.deepEqual(processes, []);
    assert.equal(fs.existsSync(path.dirname(compiler.infoFile)), false);
  });

  it('started: shutdown asks dart to end the compiler of its info file, then removes its directory', async () => {
    fs.writeFileSync(compiler.infoFile, 'address:127.0.0.1 sdkHash:x port:1 ');
    const done = compiler.shutdown();
    assert.equal(processes.length, 1);
    const [p] = processes;
    assert.equal(p.command, 'dart');
    assert.deepEqual(p.args, ['compilation-server', 'shutdown', `--resident-compiler-info-file=${compiler.infoFile}`]);
    p.end(0);
    await done;
    assert.deepEqual(p.signals, []);
    assert.equal(clock.pending, 0, 'the bound gone with the wait');
    assert.equal(fs.existsSync(path.dirname(compiler.infoFile)), false);
  });

  it('a shutdown that hangs is killed after its bound: the window is closing', async () => {
    fs.writeFileSync(compiler.infoFile, 'address:127.0.0.1 sdkHash:x port:1 ');
    const done = compiler.shutdown();
    clock.elapse(shutdownPatience - 1);
    assert.deepEqual(processes[0].signals, []);
    clock.elapse(1);
    await done;
    assert.deepEqual(processes[0].signals, ['SIGKILL']);
    assert.equal(fs.existsSync(path.dirname(compiler.infoFile)), false);
  });
});
