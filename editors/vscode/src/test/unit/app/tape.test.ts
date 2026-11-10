// Running a tape (app/tape.ts): the command, the working directory, the
// diagnostics, over a fake process and over a real one writing what twk
// tape --check writes.
import * as assert from 'node:assert/strict';
import * as os from 'node:os';

import { Tapes, TapeDiagnostic, diagnosticsOf } from '../../../app/tape';
import { AppProcess, Exit, startNodeProcess } from '../../../core/process';
import { parseCheck } from '../../../core/tape';
import { FakeLog } from '../fakes';

class FakeTapeProcess implements AppProcess {
  readonly pid = 1;
  hasExited = false;
  readonly exited: Promise<Exit>;
  end!: (e: Exit) => void;
  private out: (t: string) => void = () => {};
  private err: (e: Error) => void = () => {};
  constructor() {
    this.exited = new Promise((r) => (this.end = r));
  }
  onOutput(f: (t: string) => void): void {
    this.out = f;
  }
  onError(f: (e: Error) => void): void {
    this.err = f;
  }
  say(t: string): void {
    this.out(t);
  }
  fail(e: Error): void {
    this.err(e);
  }
  signals: string[] = [];
  write(): void {}
  signal(s: 'SIGTERM' | 'SIGKILL'): void {
    this.signals.push(s);
    this.end({ code: null, signal: s });
  }
}

describe('Tapes', () => {
  const file = '/p/example/t.tape';
  let log: FakeLog;
  let shown: Map<string, readonly TapeDiagnostic[]>;
  let started: { command: string; args: readonly string[]; cwd: string }[];
  let proc: FakeTapeProcess;
  let tapes: Tapes;
  let version: number | undefined;

  beforeEach(() => {
    log = new FakeLog();
    shown = new Map();
    started = [];
    proc = new FakeTapeProcess();
    version = 1;
    tapes = new Tapes({
      start: (command, args, o) => {
        started.push({ command, args, cwd: o.cwd });
        return proc;
      },
      command: () => ['dart', 'run', 'twk_dev:twk'],
      projectOf: () => '/p',
      env: {},
      diagnostics: { set: (f, d) => shown.set(f, d), clear: (f) => shown.delete(f) },
      version: () => version,
      log,
    });
  });

  it('check: twk tape --check <file> in the project; a failed Wait is a diagnostic on its line', async () => {
    const done = tapes.check(file);
    assert.deepEqual(started, [{ command: 'dart', args: ['run', 'twk_dev:twk', 'tape', '--check', file], cwd: '/p' }]);
    assert.ok(tapes.busy(file));
    proc.say(`${file}:3: ok Run x\n${file}:7: FAIL Wait /nev`);
    proc.say(`er/\n${file}: failed, 1 of 2 statements passed\n${file}:7: Wait timed out after 15s for /never/; the screen:\n│x\n`);
    proc.end({ code: 1, signal: null });
    const r = await done;
    assert.equal(r.exit, 1);
    assert.equal(r.summary, 'failed, 1 of 2 statements passed');
    assert.deepEqual(shown.get(file), [{ line: 6, message: 'Wait timed out after 15s for /never/; the screen:' }]);
    assert.match(log.text, /\$ dart run twk_dev:twk tape --check \/p\/example\/t.tape/);
    assert.match(log.text, /│x/);
    assert.ok(!tapes.busy(file));
  });

  it('run: twk tape <file>; a passed run clears the diagnostics', async () => {
    shown.set(file, [{ line: 1, message: 'old' }]);
    const done = tapes.run(file);
    assert.deepEqual(started[0].args, ['run', 'twk_dev:twk', 'tape', file]);
    proc.end({ code: 0, signal: null });
    assert.equal((await done).exit, 0);
    assert.deepEqual(shown.get(file), []);
  });

  it('a tape that is wrong: the line stderr says is the diagnostic', async () => {
    const done = tapes.check(file);
    proc.say(`twk tape: ${file}:4: unknown statement "Foo"\n`);
    proc.end({ code: 1, signal: null });
    await done;
    assert.deepEqual(shown.get(file), [{ line: 3, message: 'unknown statement "Foo"' }]);
  });

  it('a command that cannot be started is an error on the first line', async () => {
    const done = tapes.check(file);
    proc.fail(new Error('spawn dart ENOENT'));
    proc.end({ code: -2, signal: null });
    const r = await done;
    assert.match(r.error?.message ?? '', /cannot start dart: spawn dart ENOENT/);
    assert.deepEqual(shown.get(file)?.map((d) => d.line), [0]);
  });

  it('a text edited during the run gets no diagnostics: they describe the text before', async () => {
    const done = tapes.check(file);
    version = 2;
    proc.say(`twk tape: ${file}:4: unknown statement "Foo"\n`);
    proc.end({ code: 1, signal: null });
    const r = await done;
    assert.equal(r.error?.line, 3);
    assert.equal(shown.has(file), false);
  });

  it('an error with no line, after statements that passed, is on the first line and replaces the old ones', async () => {
    shown.set(file, [{ line: 5, message: 'old' }]);
    const done = tapes.check(file);
    proc.say(`${file}:2: ok Run sh\n${file}:3: ok Type "x"\ntwk tape: cannot write /p/out.cast: permission denied\n`);
    proc.end({ code: 1, signal: null });
    await done;
    assert.deepEqual(shown.get(file), [{ line: 0, message: 'cannot write /p/out.cast: permission denied' }]);
  });

  it('a passed run whose stderr said something has no diagnostic', async () => {
    const done = tapes.run(file);
    proc.say('Building package executable...\n');
    proc.end({ code: 0, signal: null });
    await done;
    assert.deepEqual(shown.get(file), []);
  });

  it('cancel ends the run, group and all, reports it, and sets no diagnostics', async () => {
    shown.set(file, [{ line: 1, message: 'old' }]);
    const abort = new AbortController();
    const done = tapes.check(file, abort.signal);
    abort.abort();
    const r = await done;
    assert.ok(r.cancelled);
    assert.equal(proc.signals[0], 'SIGTERM');
    assert.equal(shown.has(file), false);
    assert.ok(!tapes.busy(file));
  });

  it('is started as a group of its own, so that what it starts can be ended with it', async () => {
    let group: boolean | undefined;
    const t = new Tapes({
      start: (_c, _a, o) => ((group = o.group), proc),
      command: () => ['twk'],
      projectOf: () => '/p',
      env: {},
      diagnostics: { set: () => {}, clear: () => {} },
      version: () => undefined,
      log,
    });
    const done = t.run(file);
    proc.end({ code: 0, signal: null });
    await done;
    assert.equal(group, true);
  });

  it('one run of a file at a time; another file may run', async () => {
    const first = tapes.check(file);
    await assert.rejects(tapes.run(file), /is being run already/);
    proc.end({ code: 0, signal: null });
    await first;
    proc = new FakeTapeProcess();
    const second = tapes.run(file);
    proc.end({ code: 0, signal: null });
    await second;
  });
});

describe('Tapes over a real process', function () {
  this.timeout(30000);

  it('stdout and stderr of a check, as twk tape writes them, make the report', async () => {
    const file = '/p/t.tape';
    const script = `
      console.log(${JSON.stringify(`${file}:2: ok Run sh`)});
      console.log(${JSON.stringify(`${file}:5: FAIL Wait /x/`)});
      console.log(${JSON.stringify(`${file}: failed, 1 of 2 statements passed`)});
      console.error(${JSON.stringify(`${file}:5: Wait timed out after 1s for /x/; the screen:`)});
      console.error('│');
      process.exitCode = 1;`;
    const log = new FakeLog();
    const tapes = new Tapes({
      start: (_c, _a, o) => startNodeProcess(process.execPath, ['-e', script], o),
      command: () => ['twk'],
      projectOf: () => os.tmpdir(),
      env: process.env,
      diagnostics: { set: () => {}, clear: () => {} },
      version: () => undefined,
      log,
    });
    const r = await tapes.check(file);
    assert.equal(r.exit, 1);
    assert.equal(r.cwd, os.tmpdir());
    assert.deepEqual(r.statements.map((s) => [s.line, s.ok]), [[1, true], [4, false]]);
    assert.equal(r.error?.line, 4);
    assert.deepEqual(diagnosticsOf(r).map((d) => d.line), [4]);
  });
});

describe('diagnosticsOf', () => {
  it('a report that passed has none', () => {
    assert.deepEqual(diagnosticsOf(parseCheck('t', 't:1: ok Hide\nt: passed, 1 statements\n', 0)), []);
  });
});
