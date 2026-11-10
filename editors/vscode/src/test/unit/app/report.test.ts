// Asking twk doctor (app/report.ts): the command and directory, the output
// read, a failure to start, and a run that does not end.
import * as assert from 'node:assert/strict';

import { Doctor } from '../../../app/report';
import { AppProcess, Exit, startNodeProcess } from '../../../core/process';
import { FakeLog } from '../fakes';

class FakeProcess implements AppProcess {
  readonly pid = 1;
  hasExited = false;
  readonly exited: Promise<Exit>;
  end!: (e: Exit) => void;
  signals: string[] = [];
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
  write(): void {}
  signal(s: 'SIGTERM' | 'SIGKILL'): void {
    this.signals.push(s);
    this.end({ code: null, signal: s });
  }
}

describe('Doctor', () => {
  let proc: FakeProcess;
  let started: { command: string; args: readonly string[]; cwd: string }[];
  let command: string[];
  let doctor: Doctor;

  beforeEach(() => {
    proc = new FakeProcess();
    started = [];
    command = ['dart', 'run', 'twk_dev:twk'];
    doctor = new Doctor({
      start: (c, args, o) => {
        started.push({ command: c, args, cwd: o.cwd });
        return proc;
      },
      command: () => command,
      env: {},
      log: new FakeLog(),
      timeoutMs: 20,
      graceMs: 10,
    });
  });

  it('runs `doctor --json -C <project>` in the project and reads the report, also of exit 1', async () => {
    const result = doctor.project('/p/app');
    proc.say('{"project":"/p/app","agree":false,');
    proc.say('"versions":{"twk":"1","twk_core":"2"}}');
    proc.end({ code: 1, signal: null });
    const r = await result;
    assert.deepEqual(started, [{ command: 'dart', args: ['run', 'twk_dev:twk', 'doctor', '--json', '-C', '/p/app'], cwd: '/p/app' }]);
    assert.equal(r.kind, 'ok');
    assert.equal(r.kind === 'ok' && r.report.agree, false);
  });

  it('is failed where the command is empty or cannot be started', async () => {
    command = [];
    assert.equal((await doctor.project('/p')).kind, 'failed');
    command = ['nope'];
    const result = doctor.project('/p');
    proc.fail(new Error('spawn nope ENOENT'));
    proc.end({ code: -2, signal: null });
    const r = await result;
    assert.equal(r.kind, 'failed');
    assert.match(r.kind === 'failed' ? r.message : '', /cannot start nope: spawn nope ENOENT/);
  });

  it('is failed, with the first line of what it said, where twk doctor does not exist or fails', async () => {
    const result = doctor.project('/p');
    proc.say('Could not find `doctor` in package twk_dev.\n');
    proc.end({ code: 255, signal: null });
    const r = await result;
    assert.match(r.kind === 'failed' ? r.message : '', /Could not find `doctor`/);
  });

  it('ends a run that does not end, and says so', async () => {
    const r = await doctor.project('/p');
    // SIGTERM; nothing after the leader exited (its pid may be reused)
    assert.deepEqual(proc.signals, ['SIGTERM']);
    assert.match(r.kind === 'failed' ? r.message : '', /did not finish/);
  });

  it('a new ask ends the one running; only the latest answers', async () => {
    const first = doctor.latest('/old');
    const older = proc;
    older.say('{"project":"/old","agree":true}');
    proc = new FakeProcess();
    const second = doctor.latest('/new');
    assert.deepEqual(older.signals[0], 'SIGTERM');
    proc.say('{"project":"/new","agree":true}');
    proc.end({ code: 0, signal: null });
    assert.equal(await first, undefined);
    const r = await second;
    assert.equal(r?.kind === 'ok' && r.report.project, '/new');
  });

  it('asking with no project is none, and ends the one running', async () => {
    doctor = new Doctor({ start: () => proc, command: () => ['twk'], env: {}, log: new FakeLog(), timeoutMs: 60_000, graceMs: 10 });
    const running = doctor.latest('/p');
    assert.deepEqual(await doctor.latest(undefined), { kind: 'none' });
    assert.equal(await running, undefined);
    assert.equal(proc.signals[0], 'SIGTERM');
  });

  it('reads the real thing: a process that writes a report', async () => {
    const real = new Doctor({
      start: startNodeProcess,
      command: () => [process.execPath, '-e', 'console.log("noise"); console.log(JSON.stringify({project: process.argv.at(-1), agree: true}))', '--'],
      env: process.env,
      log: new FakeLog(),
      timeoutMs: 20_000,
    });
    const r = await real.project(process.cwd());
    assert.equal(r.kind === 'ok' && r.report.project, process.cwd());
  });
});
