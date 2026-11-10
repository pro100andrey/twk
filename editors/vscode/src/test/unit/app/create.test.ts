// New Project and Install Agent Skill (app/create.ts): the commands and the
// directories they run in, what is read of their output, and where twk_dev
// is run from when the folder has none; over a fake process that says what
// `twk create` and `twk agents` say.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { Creator } from '../../../app/create';
import { AppProcess, Exit } from '../../../core/process';
import { FakeLog } from '../fakes';

class FakeProcess implements AppProcess {
  readonly pid = 1;
  hasExited = false;
  readonly exited: Promise<Exit>;
  private end!: (e: Exit) => void;
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
  write(): void {}
  signal(s: 'SIGTERM' | 'SIGKILL'): void {
    this.signals.push(s);
    this.end({ code: null, signal: s });
  }
  /** Says [text] and ends with [code], once the starter returned. */
  finish(text: string, code: number): void {
    queueMicrotask(() => {
      this.out(text);
      this.end({ code, signal: null });
    });
  }
  break(e: Error): void {
    queueMicrotask(() => {
      this.err(e);
      this.end({ code: null, signal: null });
    });
  }
}

type Said = { text: string; code: number } | Error;

describe('Creator', () => {
  const defaultCommand = ['dart', 'run', 'twk_dev:twk'];
  const globalCommand = ['dart', 'pub', 'global', 'run', 'twk_dev:twk'];
  let started: { command: string; args: readonly string[]; cwd: string; group?: boolean }[];
  let script: Said[];
  let procs: FakeProcess[];
  let command: string[];
  let creator: Creator;

  beforeEach(() => {
    started = [];
    script = [];
    procs = [];
    command = defaultCommand;
    creator = new Creator({
      start: (c, args, o) => {
        started.push({ command: c, args, cwd: o.cwd, group: o.group });
        const p = new FakeProcess();
        procs.push(p);
        const said = script.shift() ?? { text: '', code: 0 };
        if (said instanceof Error) {
          p.break(said);
        } else {
          p.finish(said.text, said.code);
        }
        return p;
      },
      command: () => command,
      defaultCommand,
      globalCommand,
      env: {},
      log: new FakeLog(),
    });
  });

  it('lists the templates as `twk create --list` names them, with their descriptions', async () => {
    script.push({ text: 'app        full screen: a list beside a detail pane\ninline     inline below the prompt\n', code: 0 });
    const templates = await creator.templates('/w');
    assert.deepEqual(templates, [
      { name: 'app', description: 'full screen: a list beside a detail pane' },
      { name: 'inline', description: 'inline below the prompt' },
    ]);
    assert.deepEqual(started, [{ command: 'dart', args: ['run', 'twk_dev:twk', 'create', '--list'], cwd: '/w', group: true }]);
  });

  it('creates with flags only, never its prompts: the template, the agents files or none', async () => {
    script.push({ text: 'twk create: demo, of the template app, in /w/demo:\n  pubspec.yaml\n', code: 0 });
    let outcome = await creator.create({ dir: '/w/demo', template: 'app', agents: ['skill', 'agents-md'] }, '/w');
    assert.deepEqual(started[0].args, ['run', 'twk_dev:twk', 'create', '/w/demo', '--template=app', '--agents=skill,agents-md']);
    assert.equal(outcome.error, undefined);
    assert.equal(outcome.dir, '/w/demo');
    assert.equal(outcome.lines[0], 'twk create: demo, of the template app, in /w/demo:');

    await creator.create({ dir: '/w/demo2', template: 'form', agents: [] }, '/w');
    assert.deepEqual(started[1].args.slice(-3), ['/w/demo2', '--template=form', '--agents=none']);
  });

  it('reports the CLI refusal as it says it (a folder that is not empty), without a second run', async () => {
    script.push({ text: 'twk create: target is not empty. --force writes into it.\n', code: 1 });
    const outcome = await creator.create({ dir: '/w/demo', template: 'app', agents: [] }, '/w');
    assert.equal(outcome.error, 'twk create: target is not empty. --force writes into it.');
    assert.equal(outcome.missing, false);
    assert.equal(started.length, 1);
  });

  it('runs twk agents in the project and reads the line that says what was done and the files it left', async () => {
    script.push({
      text: 'twk agents: /p:\n  .agents/skills/twk  wrote 3 files\nLeft as they are, files of the skill that are not as twk agents wrote them (delete one to have the skill\'s again): SKILL.md\n',
      code: 0,
    });
    const outcome = await creator.agents('/p');
    assert.deepEqual(started, [{ command: 'dart', args: ['run', 'twk_dev:twk', 'agents'], cwd: '/p', group: true }]);
    assert.equal(outcome.summary, 'twk agents: /p:');
    assert.equal(outcome.left.length, 1);
    assert.match(outcome.left[0], /SKILL\.md$/);
    assert.equal(outcome.error, undefined);
  });

  it('runs the globally activated twk_dev where the folder has none and twk.command is the default', async () => {
    script.push({ text: 'Could not find package `twk_dev` or file `twk_dev:twk`\n', code: 255 });
    script.push({ text: 'twk create: demo, of the template app, in /w/demo:\n', code: 0 });
    const outcome = await creator.create({ dir: '/w/demo', template: 'app', agents: [] }, '/w');
    assert.equal(outcome.error, undefined);
    assert.equal(outcome.missing, false);
    assert.deepEqual(
      started.map((s) => [s.command, ...s.args.slice(0, 4)]),
      [
        ['dart', 'run', 'twk_dev:twk', 'create', '/w/demo'],
        ['dart', 'pub', 'global', 'run', 'twk_dev:twk'],
      ],
    );
  });

  it('says twk_dev is missing where it is neither in the folder nor activated, and where a configured command fails so (no second run then)', async () => {
    script.push({ text: 'Found no `pubspec.yaml` file in `/w` or parent directories\n', code: 255 });
    script.push({ text: 'No active package twk_dev.\n', code: 255 });
    let outcome = await creator.agents('/w');
    assert.equal(outcome.missing, true);
    assert.ok(outcome.error);
    assert.equal(started.length, 2);

    started.length = 0;
    command = ['fvm', 'dart', 'run', 'twk_dev:twk'];
    script.push({ text: 'Could not find package `twk_dev` or file `twk_dev:twk`\n', code: 255 });
    outcome = await creator.agents('/w');
    assert.equal(outcome.missing, true);
    assert.equal(started.length, 1);
    assert.equal(started[0].command, 'fvm');
  });

  it('reports a command that cannot start', async () => {
    script.push(new Error('spawn dart ENOENT'));
    const outcome = await creator.agents('/p');
    assert.equal(outcome.error, 'cannot start dart: spawn dart ENOENT');
    assert.equal(outcome.missing, false);
  });
});

describe('the commands of New Project and Install Agent Skill', () => {
  it('are declared in package.json', () => {
    const pkg = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../../../package.json'), 'utf8'));
    const commands = pkg.contributes.commands.map((c: { command: string }) => c.command);
    assert.ok(commands.includes('twk.newProject'));
    assert.ok(commands.includes('twk.installAgentSkill'));
  });
});
