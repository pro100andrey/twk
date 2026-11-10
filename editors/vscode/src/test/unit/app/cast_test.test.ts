// A test made of a recording (app/cast_test.ts): the command and its
// directory, which files it says it wrote, why it wrote none; over a fake
// process, which says what `twk test-from-cast` says.
import * as assert from 'node:assert/strict';

import { CastTests } from '../../../app/cast_test';
import { AppProcess, Exit } from '../../../core/process';
import { FakeLog } from '../fakes';

class FakeProcess implements AppProcess {
  readonly pid = 1;
  hasExited = false;
  readonly exited: Promise<Exit>;
  end!: (e: Exit) => void;
  private out: (t: string) => void = () => {};
  private err: (e: Error) => void = () => {};
  signals: string[] = [];
  constructor() {
    this.exited = new Promise((r) => (this.end = (e) => ((this.hasExited = true), r(e))));
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
  write(): void {}
  signal(s: 'SIGTERM' | 'SIGKILL'): void {
    this.signals.push(s);
    this.end({ code: null, signal: s });
  }
}

describe('CastTests', () => {
  const file = '/p/app/rec/counter.cast';
  let proc: FakeProcess;
  let started: { command: string; args: readonly string[]; cwd: string; group?: boolean }[];
  let log: FakeLog;
  let tests: CastTests;

  beforeEach(() => {
    proc = new FakeProcess();
    started = [];
    log = new FakeLog();
    tests = new CastTests({
      start: (command, args, o) => {
        started.push({ command, args, cwd: o.cwd, group: o.group });
        return proc;
      },
      command: () => ['dart', 'run', 'twk_dev:twk'],
      projectOf: () => '/p/app',
      env: {},
      log,
    });
  });

  it('runs twk test-from-cast over the recording in its project, as a group, and reads the files it wrote', async () => {
    const done = tests.create(file);
    proc.say('twk test-from-cast: no markers; the last screen is checked\nwrote test/counter_test.dart and test/counter.cast\n');
    proc.end({ code: 0, signal: null });
    const result = await done;
    assert.deepEqual(started, [{ command: 'dart', args: ['run', 'twk_dev:twk', 'test-from-cast', file], cwd: '/p/app', group: true }]);
    assert.equal(result.test, '/p/app/test/counter_test.dart');
    assert.equal(result.cast, '/p/app/test/counter.cast');
    assert.equal(result.said, 'twk test-from-cast: no markers; the last screen is checked');
    assert.equal(result.error, undefined);
    assert.match(log.text, /twk test-from-cast: exit 0/);
  });

  it('reports why no test was written: the recording it cannot read, a command that cannot start, one that was cancelled', async () => {
    let done = tests.create(file);
    proc.say('twk test-from-cast: cannot read /p/app/rec/counter.cast: No such file\n');
    proc.end({ code: 1, signal: null });
    let result = await done;
    assert.equal(result.test, undefined);
    assert.equal(result.error, 'twk test-from-cast: cannot read /p/app/rec/counter.cast: No such file');

    proc = new FakeProcess();
    done = tests.create(file);
    proc.fail(new Error('spawn dart ENOENT'));
    proc.end({ code: null, signal: null });
    result = await done;
    assert.equal(result.error, 'cannot start dart: spawn dart ENOENT');

    proc = new FakeProcess();
    const abort = new AbortController();
    done = tests.create(file, abort.signal);
    abort.abort();
    result = await done;
    assert.equal(result.cancelled, true);
    assert.equal(result.test, undefined);
    assert.ok(proc.signals.includes('SIGTERM'));
  });

  it('splits the files it wrote at the test and the recording, not at an " and " in a name', async () => {
    const done = tests.create('/p/app/rec/rock and roll.cast');
    proc.say('wrote test/rock and roll_test.dart and rec/rock and roll.cast\n');
    proc.end({ code: 0, signal: null });
    const result = await done;
    assert.equal(result.test, '/p/app/test/rock and roll_test.dart');
    assert.equal(result.cast, '/p/app/rec/rock and roll.cast');
    assert.equal(result.said, '');
  });
});
