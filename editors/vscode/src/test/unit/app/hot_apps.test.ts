// Running and debugging with hot reload (app/hot_apps.ts), each app in a
// twk terminal of its own, over fakes of the views, the runner, the
// debugger, the VM service, the status and the clock.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { HotApps } from '../../../app/hot_apps';
import { Terminals } from '../../../app/terminals';
import { Vm } from '../../../core/vm';
import { Wire } from '../../../core/wire';
import { App, FakeClock, FakeDebugger, FakeDesktop, FakeLog, FakeRun, FakeSettings, FakeStatus, FakeView, FakeVm, realShell, until } from '../fakes';

describe('HotApps', () => {
  let project: string;
  let file: string;
  let terminals: Terminals;
  let views: FakeView[];
  let runs: FakeRun[];
  let debug: FakeDebugger;
  let vms: FakeVm[];
  let connectVm: (uri: string) => Promise<Vm>;
  let status: FakeStatus;
  let context: boolean[];
  let log: FakeLog;
  let settings: FakeSettings;
  let clock: FakeClock;
  let apps: HotApps;

  beforeEach(() => {
    project = fs.mkdtempSync(path.join(os.tmpdir(), 'twk-vscode-app-'));
    fs.writeFileSync(path.join(project, 'pubspec.yaml'), 'name: app\n');
    file = path.join(project, 'bin', 'main.dart');
    log = new FakeLog();
    settings = new FakeSettings();
    views = [];
    terminals = new Terminals({
      views: (title) => {
        const v = new FakeView(title);
        views.push(v);
        return v;
      },
      startShell: realShell,
      settings,
      log,
      desktop: new FakeDesktop(),
    });
    runs = [];
    debug = new FakeDebugger();
    vms = [];
    connectVm = async () => {
      const vm = new FakeVm();
      vms.push(vm);
      return vm;
    };
    status = new FakeStatus();
    context = [];
    clock = new FakeClock();
    apps = new HotApps({
      terminals,
      runner: (options) => {
        const run = new FakeRun(options);
        runs.push(run);
        return run;
      },
      debugger: debug,
      connectVm: (uri) => connectVm(uri),
      status,
      context: (running) => context.push(running),
      log,
      settings,
      clock,
      env: { TWK_DEBUG: 'console' },
    });
  });

  afterEach(async () => {
    await apps.dispose();
    await terminals.dispose();
    fs.rmSync(project, { recursive: true, force: true });
  });

  it("runs a file in a terminal of its own, given to it as TWK_SHELL, with the app's hot keys on, until the run ends", async () => {
    const pid = await apps.runFile(file);
    assert.equal(pid, 4242);
    const [terminal] = terminals.all();
    assert.ok(terminal.shell, 'its terminal, serving');
    assert.equal(terminal.name, 'main.dart');
    const [run] = runs;
    assert.equal(run.options.file, file);
    assert.equal(run.options.cwd, project);
    assert.deepEqual(run.options.env, { TWK_DEBUG: 'console,keys', TWK_SHELL: terminal.variable });
    assert.equal(apps.hots().length, 1);
    assert.equal(apps.hots()[0].terminal, terminal);
    assert.deepEqual(context, [true]);
    const app = await App.connect(run.options.env!.TWK_SHELL);
    await app.next(Wire.welcome);
    app.socket.destroy();

    run.options.onOutput('hello\n');
    assert.match(log.text, /hello/);
    await apps.reloadAll();
    assert.deepEqual(run.asked, ['reload']);
    assert.deepEqual(status.states, ['reloaded']);

    run.end(0);
    await until('the run gone', () => apps.hots().length === 0);
    assert.deepEqual(context, [true, false]);
    assert.equal(terminal.isClosed, false, 'the terminal stays, with what the app left on it');
  });

  it('two runs of one file: two terminals, two shells', async () => {
    await apps.runFile(file);
    await apps.runFile(file);
    assert.equal(terminals.all().length, 2);
    assert.notEqual(runs[0].options.env!.TWK_SHELL, runs[1].options.env!.TWK_SHELL);
  });

  it('closing the terminal of a run ends its app, which is restarted no more', async () => {
    await apps.runFile(file);
    const [run] = runs;
    views[0].close();
    await until('the run ended', () => apps.hots().length === 0);
    assert.deepEqual(run.asked, ['stop']);
    await assert.rejects(apps.restartAll(), /no app running/);
  });

  it('a terminal that comes back empty has its app paint all of itself again', async () => {
    await apps.runFile(file);
    views[0].reload(100, 30);
    await until('the redraw', () => runs[0].asked.includes('redraw'));
  });

  it('a file of no project: refused', async () => {
    await assert.rejects(apps.runFile(path.join(os.tmpdir(), 'nowhere', 'x.dart')), /no Dart file of a project/);
  });

  it('nothing running: reload and restart say so', () => {
    assert.throws(() => apps.reloadAll(), /no app running with hot reload/);
  });

  it("debugs a file through Dart-Code in the Debug Console, in a terminal of its own, and reloads it over the session's VM service", async () => {
    assert.equal(await apps.debugFile(file), true);
    const [terminal] = terminals.all();
    const [launch] = debug.started;
    assert.deepEqual(launch, {
      type: 'dart',
      request: 'launch',
      name: 'twk: main.dart',
      program: file,
      cwd: project,
      console: 'debugConsole',
      env: { TWK_DEBUG: 'console,keys', TWK_SHELL: terminal.variable },
      twkSession: launch.twkSession,
      others: {},
    });
    const [session] = debug.sessions;
    debug.vmService(session);
    await until('the VM service', () => status.states.includes('running'));
    const [vm] = vms;
    assert.deepEqual(await apps.reloadAll(), [{ state: 'reloaded', libraries: 2, ms: (status.shown.at(-1) as { ms: number }).ms }]);
    assert.ok(vm.calls.includes('ext.twk.reassemble'));

    debug.terminate(session.id);
    await until('the session gone', () => apps.hots().length === 0);
    assert.ok(vm.isClosed, 'its VM service connection closed');
  });

  it("tells of each app's VM service as it comes and goes, with its terminal: a run's, a debug session's and its restart's", async () => {
    const told: string[] = [];
    apps.onApp(({ terminal, service }) => told.push(`${terminals.all().indexOf(terminal)} ${service ? 'up' : 'gone'}`));
    await apps.runFile(file);
    const [run] = runs;
    const service = { fake: 'HotApp' };
    // HotRun tells it of its HotApp, and of its going
    run.options.onApp!(service as never);
    run.options.onApp!(undefined);
    assert.deepEqual(told, ['0 up', '0 gone']);

    await apps.debugFile(file);
    const [session] = debug.sessions;
    debug.vmService(session);
    await until('the session connected', () => told.length === 3);
    assert.equal(told[2], '1 up');
    await apps.restartAll();
    debug.vmService(debug.sessions[1]);
    await until('the new session connected', () => told.length === 5);
    assert.deepEqual(told.slice(3), ['1 gone', '1 up'], 'the old session gone, the new one in the same terminal');
  });

  it("the launch of a configuration (F5): its name, cwd, env and the rest kept, TWK_DEBUG's own with keys", async () => {
    const launch = await apps.debugLaunch({
      program: file,
      cwd: path.join(project, 'bin'),
      name: 'mine',
      env: { A: '1', TWK_DEBUG: 'rainbow' },
      others: { args: ['--x'], toolArgs: ['--enable-asserts'] },
    });
    const [terminal] = terminals.all();
    assert.equal(launch.name, 'mine');
    assert.equal(launch.cwd, path.join(project, 'bin'));
    assert.deepEqual(launch.env, { A: '1', TWK_DEBUG: 'rainbow,keys', TWK_SHELL: terminal.variable });
    assert.deepEqual(launch.others, { args: ['--x'], toolArgs: ['--enable-asserts'] });
    await assert.rejects(apps.debugLaunch({ program: path.join(os.tmpdir(), 'nowhere', 'x.dart'), env: {}, others: {} }), /in no Dart project/);
  });

  it('two debug sessions: two terminals, each its own TWK_SHELL', async () => {
    await apps.debugFile(file);
    await apps.debugFile(file);
    assert.equal(terminals.all().length, 2);
    assert.notEqual(debug.started[0].env.TWK_SHELL, debug.started[1].env.TWK_SHELL);
    assert.notEqual(debug.started[0].twkSession, debug.started[1].twkSession);
  });

  it('a debug session that did not start: its terminal closed', async () => {
    debug.starts = false;
    assert.equal(await apps.debugFile(file), false);
    assert.deepEqual(terminals.all(), []);
  });

  it('closing the terminal of a debug session ends the session; a restart then starts no app', async () => {
    await apps.debugFile(file);
    const [session] = debug.sessions;
    debug.vmService(session);
    await until('the VM service', () => status.states.includes('running'));
    const [hot] = apps.hots();
    views[0].close();
    await until('the session stopped', () => debug.stopped.includes(session.id));
    await until('the session gone', () => apps.hots().length === 0);
    await hot.restart();
    assert.equal(debug.started.length, 1, 'not launched again: it would have no terminal');
  });

  it('closed while a restart waits for the session to end: not launched again', async () => {
    await apps.debugFile(file);
    const [session] = debug.sessions;
    debug.vmService(session);
    await until('the VM service', () => status.states.includes('running'));
    debug.terminateOnStop = false;
    const restarting = apps.restartAll();
    await until('the stop', () => debug.stopped.length === 1);
    views[0].close();
    await until('the terminal gone', () => terminals.all().length === 0);
    debug.terminate(session.id);
    await restarting;
    assert.equal(debug.started.length, 1);
  });

  it('a session of a launch whose terminal was closed meanwhile is stopped as it starts', async () => {
    const launch = await apps.debugLaunch({ program: file, env: {}, others: {} });
    views[0].close();
    await until('the terminal gone', () => terminals.all().length === 0);
    await debug.start(launch);
    assert.deepEqual(debug.stopped, [debug.sessions[0].id]);
  });

  it('a terminal of a debug session that comes back empty has the app paint all of itself again', async () => {
    await apps.debugFile(file);
    debug.vmService(debug.sessions[0]);
    await until('the VM service', () => status.states.includes('running'));
    const [vm] = vms;
    vm.calls.length = 0;
    views[0].reload(100, 30);
    await until('the redraw', () => vm.calls.includes('ext.twk.reassemble'));
    assert.ok(!vm.calls.includes('reloadSources'), 'no sources reloaded');
  });

  it('restarts a debug session: stopped, and the same launch started again once it ended, in the same terminal', async () => {
    await apps.debugFile(file);
    const [session] = debug.sessions;
    debug.vmService(session);
    await until('the VM service', () => status.states.includes('running'));
    await apps.restartAll();
    assert.deepEqual(debug.stopped, [session.id]);
    assert.equal(debug.started.length, 2);
    assert.deepEqual(debug.started[1], session.configuration);
    assert.ok(status.states.includes('restarting'));
    assert.equal(terminals.all().length, 1, 'no new terminal');
    // the new session ends with the terminal too
    views[0].close();
    await until('the new session stopped', () => debug.stopped.includes(debug.sessions[1].id));
  });

  it("a save reloads the saved file's project's apps, the saves of a moment as one, after 100 ms", async () => {
    await apps.runFile(file);
    const [run] = runs;
    apps.saved(path.join(project, 'lib', 'a.dart'));
    apps.saved(path.join(project, 'lib', 'b.dart'));
    apps.saved(path.join(project, 'README.md'));
    clock.elapse(99);
    assert.deepEqual(run.asked, []);
    clock.elapse(1);
    assert.deepEqual(run.asked, ['reload']);

    settings.reloadOnSave = false;
    apps.saved(path.join(project, 'lib', 'a.dart'));
    clock.elapse(100);
    assert.deepEqual(run.asked, ['reload'], 'twk.hotReloadOnSave off');
  });

  it("a save of a file in none of the apps' projects reloads every app", async () => {
    await apps.runFile(file);
    apps.saved(path.join(os.tmpdir(), 'elsewhere', 'dep.dart'));
    clock.elapse(100);
    assert.deepEqual(runs[0].asked, ['reload']);
  });

  it('dispose stops the apps it runs', async () => {
    await apps.runFile(file);
    await apps.dispose();
    assert.deepEqual(runs[0].asked, ['stop']);
  });

  it('a restart whose stop fails: said so, nothing left listening, and the next restart tries again', async () => {
    await apps.debugFile(file);
    const [session] = debug.sessions;
    debug.vmService(session);
    await until('the VM service', () => status.states.includes('running'));
    const listening = debug.terminated.size;
    debug.stopFails = new Error('the adapter is gone');
    await assert.rejects(apps.restartAll(), /the adapter is gone/);
    assert.equal(debug.terminated.size, listening, 'the restart waits for no end any more');
    await assert.rejects(apps.restartAll(), /the adapter is gone/);
    assert.deepEqual(debug.stopped, [session.id, session.id], 'tried again');
  });

  it("the app's own restart key (twk.restart) failing: logged, not thrown", async () => {
    await apps.debugFile(file);
    const [session] = debug.sessions;
    debug.vmService(session);
    await until('the VM service', () => status.states.includes('running'));
    debug.stopFails = new Error('the adapter is gone');
    vms[0].streams.get('Extension')!({ kind: 'Extension', extensionKind: 'twk.restart' });
    await until('the failure logged', () => /restart failed: Error: the adapter is gone/.test(log.text));
  });

  it("a debug session whose VM service can't be reached: no app to reload, said so", async () => {
    connectVm = () => Promise.reject(new Error('no VM service at ws://vm'));
    await apps.debugFile(file);
    debug.vmService(debug.sessions[0]);
    await until('the failure logged', () => /no hot reload for the debug session/.test(log.text));
    assert.deepEqual(apps.hots(), []);
    assert.equal(context.at(-1), false, 'the hot reload commands off');
  });

  it("a save's reload waits for no timer once disposed", async () => {
    await apps.runFile(file);
    apps.saved(path.join(project, 'lib', 'a.dart'));
    assert.equal(clock.pending, 1);
    await apps.dispose();
    assert.equal(clock.pending, 0);
  });
});
