// Hot reload and restart: HotApp against a VM service written here (what a
// reload asks, in which order), and HotRun with a real Dart VM, running an
// app written here that answers twk's two service extensions as a twk app
// does (`ext.twk.reassemble`, `ext.twk.log`) and says on its stdout what
// they did, with a counter the test moves on its stdin: its state.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { realClock } from '../../../core/events';
import { HotApp, HotStatus } from '../../../core/hot';
import { startNodeProcess } from '../../../core/process';
import { HotRun } from '../../../core/runner';
import { Vm, VmClient, webSocketUri } from '../../../core/vm';
import { FakeVm } from '../fakes';

describe('HotApp', () => {
  const statuses: HotStatus['state'][] = [];
  const attach = (vm: Vm, restart = () => {}) => HotApp.attach(vm, (s) => statuses.push(s.state), restart);
  beforeEach(() => (statuses.length = 0));

  it('reloads the sources, then has the app reassemble, then says so in its log', async () => {
    const vm = new FakeVm();
    const app = await attach(vm);
    assert.equal(app.isolate, 'i/1', 'the isolate that registered ext.twk.reassemble before it was attached');
    const s = await app.reload();
    assert.equal(s.state, 'reloaded');
    assert.deepEqual(vm.calls.slice(2), ['reloadSources', 'ext.twk.reassemble', `log info hot reload: 2 libraries in ${(s as { ms: number }).ms} ms`]);
    assert.deepEqual(statuses, ['reloading', 'reloaded']);
  });

  it('a reload that fails to compile: no reassemble, the errors in the status and in the app log', async () => {
    const vm = new FakeVm();
    vm.report = { type: 'ReloadReport', success: false, notices: [{ type: 'ReasonForCancelling', message: "lib/a.dart:3:1: Error: Expected ';'" }] };
    const app = await attach(vm);
    const s = await app.reload();
    assert.deepEqual(s, { state: 'failed', errors: "lib/a.dart:3:1: Error: Expected ';'" });
    assert.ok(!vm.calls.includes('ext.twk.reassemble'), vm.calls.join(', '));
    assert.ok(vm.calls.includes('log warning hot reload failed'), vm.calls.join(', '));
  });

  it('one reload at a time: those asked for meanwhile are one more after it', async () => {
    const vm = new FakeVm();
    const app = await attach(vm);
    let open!: () => void;
    vm.gate = new Promise((r) => (open = r));
    const first = app.reload();
    const second = app.reload();
    const third = app.reload();
    vm.gate = undefined;
    open();
    await Promise.all([first, second, third]);
    assert.equal(vm.calls.filter((c) => c === 'reloadSources').length, 2);
  });

  it('a reload before the binding registered its extensions waits for it', async () => {
    const vm = new FakeVm([]);
    const app = await attach(vm);
    assert.equal(app.isolate, undefined);
    let done = false;
    const reload = app.reload().then((s) => ((done = true), s));
    await new Promise((r) => setTimeout(r, 10));
    assert.equal(done, false);
    assert.ok(!vm.calls.includes('reloadSources'));
    vm.streams.get('Isolate')!({ kind: 'ServiceExtensionAdded', extensionRPC: 'ext.twk.reassemble', isolate: { id: 'i/2' } });
    assert.equal((await reload).state, 'reloaded');
    assert.equal(app.isolate, 'i/2');
  });

  it("the app's keys: twk.reload reloads, twk.restart is passed on", async () => {
    const vm = new FakeVm();
    let restarts = 0;
    await attach(vm, () => restarts++);
    vm.streams.get('Extension')!({ kind: 'Extension', extensionKind: 'twk.restart' });
    assert.equal(restarts, 1);
    vm.streams.get('Extension')!({ kind: 'Extension', extensionKind: 'twk.reload' });
    await new Promise((r) => setTimeout(r, 10));
    assert.ok(vm.calls.includes('reloadSources'));
  });

  it("passes on what the app posts and each reload done, and calls into the binding's isolate, for an inspector", async () => {
    const vm = new FakeVm();
    const app = await attach(vm);
    const events: string[] = [];
    app.onEvent((e) => events.push(e.kind === 'extension' ? `${e.name} ${JSON.stringify(e.data)}` : e.kind));
    vm.streams.get('Extension')!({ kind: 'Extension', extensionKind: 'twk.treeChanged', extensionData: { version: 1, rebuilds: 2 } });
    vm.streams.get('Extension')!({ kind: 'Extension', extensionKind: 'twk.select', extensionData: { version: 1, x: 1, y: 2 } });
    await app.reload();
    vm.report = { type: 'ReloadReport', success: false, notices: [] };
    await app.reload();
    assert.deepEqual(events, ['twk.treeChanged {"version":1,"rebuilds":2}', 'twk.select {"version":1,"x":1,"y":2}', 'reloaded'], 'a failed reload is none');

    const asked: Record<string, unknown>[] = [];
    const call = vm.call.bind(vm);
    vm.call = (method, params = {}) => (asked.push({ method, ...params }), call(method, params));
    await app.extension('ext.twk.tree', { tree: 'element' });
    await app.vm('getClassList');
    assert.deepEqual(asked, [
      { method: 'ext.twk.tree', tree: 'element', isolateId: 'i/1' },
      { method: 'getClassList', isolateId: 'i/1' },
    ]);
    vm.streams.get('Isolate')!({ kind: 'IsolateExit', isolate: { id: 'i/1' } });
    await assert.rejects(app.vm('getClassList'), /binding is not there/);
    vm.close();
    await app.closed;
  });

  it("fails to attach: the VM service's connection closed, not left open", async () => {
    const vm = new FakeVm();
    vm.getVmFails = new Error('the service went away');
    await assert.rejects(attach(vm), /the service went away/);
    assert.ok(vm.isClosed);
  });

  it('the WebSocket address of a VM service', () => {
    assert.equal(webSocketUri('http://127.0.0.1:4040/abc=/'), 'ws://127.0.0.1:4040/abc=/ws');
    assert.equal(webSocketUri('http://127.0.0.1:4040/abc='), 'ws://127.0.0.1:4040/abc=/ws');
    assert.equal(webSocketUri('ws://127.0.0.1:4040/abc=/ws'), 'ws://127.0.0.1:4040/abc=/ws');
  });
});

const app = (word: string, broken = false) => `
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

String word() => '${word}'${broken ? '' : ';'}
var count = 0;

void main() {
  registerExtension('ext.twk.reassemble', (_, __) async {
    stdout.writeln('reassembled: \${word()} \$count');
    return ServiceExtensionResponse.result('{}');
  });
  registerExtension('ext.twk.log', (_, p) async {
    stdout.writeln('log \${p['level']}: \${p['message']}');
    return ServiceExtensionResponse.result('{}');
  });
  stdout.writeln('started \$pid \${Platform.environment['TWK_DEBUG']}');
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    switch (line) {
      case '+':
        count++;
        stdout.writeln('count \$count');
      case 'reload' || 'restart':
        postEvent('twk.\$line', {});
    }
  });
}
`;

describe('HotRun, with a Dart VM', function () {
  this.timeout(120000);
  let dir: string;
  let file: string;
  let out = '';
  const statuses: HotStatus[] = [];
  let run: HotRun | undefined;

  async function until(what: string, f: () => boolean, ms = 60000): Promise<void> {
    const end = Date.now() + ms;
    while (!f()) {
      if (Date.now() > end) {
        throw new Error(`no ${what} in ${ms} ms; output:\n${out}`);
      }
      await new Promise((r) => setTimeout(r, 20));
    }
  }

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'twk_hot_test_'));
    file = path.join(dir, 'app.dart');
    fs.writeFileSync(file, app('first'));
    out = '';
    statuses.length = 0;
  });

  afterEach(async () => {
    await run?.stop();
    run = undefined;
    fs.rmSync(dir, { recursive: true, force: true });
  });

  const start = () =>
    (run = HotRun.start({
      file,
      cwd: dir,
      env: { TWK_DEBUG: 'keys' },
      onOutput: (t) => (out += t),
      onStatus: (s) => statuses.push(s),
    }, { startProcess: startNodeProcess, connectVm: (uri) => VmClient.connect(uri, realClock), env: process.env, clock: realClock }));
  const type = (line: string) => run!.process!.write(`${line}\n`);

  it('reloads with the state kept, reports a failed one with the app going on, restarts afresh', async () => {
    start();
    await until('the VM service', () => statuses.some((s) => s.state === 'running'));
    const pid = run!.process!.pid;
    await until('the app with its debug keys on', () => /started \d+ keys/.test(out));
    type('+');
    await until('count 1', () => out.includes('count 1'));

    fs.writeFileSync(file, app('second'));
    const reloaded = await run!.reload();
    assert.equal(reloaded.state, 'reloaded', JSON.stringify(reloaded));
    assert.match(out, /reassembled: second 1/, 'the new code, the state kept');
    assert.match(out, /log info: hot reload: 1 library in \d+ ms/);

    fs.writeFileSync(file, app('third', true));
    const failed = await run!.reload();
    assert.equal(failed.state, 'failed');
    assert.match((failed as { errors: string }).errors, /Expected ';'/);
    assert.match(out, /log warning: hot reload failed/);
    type('+');
    await until('count 2: the app runs on', () => out.includes('count 2'));

    fs.writeFileSync(file, app('fourth'));
    await run!.restart();
    await until('a new app', () => run!.process?.pid !== pid && /started \d+ keys[\s\S]*started \d+ keys/.test(out));
    await until('its VM service', () => statuses.filter((s) => s.state === 'running').length === 2);
    assert.ok(statuses.some((s) => s.state === 'restarting'));
    type('+');
    await until('count 1 again: the state is new', () => out.split('count 1').length === 3);
    const again = await run!.reload();
    assert.equal(again.state, 'reloaded');
    assert.match(out, /reassembled: fourth 1/);
  });

  it("the app's own keys: twk.reload reloads it, twk.restart restarts it", async () => {
    start();
    await until('the VM service', () => statuses.some((s) => s.state === 'running'));
    const pid = run!.process!.pid;
    fs.writeFileSync(file, app('second'));
    type('reload');
    await until('the reload', () => out.includes('reassembled: second 0'));
    type('restart');
    await until('a new app', () => run!.process !== undefined && run!.process.pid !== pid && statuses.filter((s) => s.state === 'running').length === 2);
  });

  it("a dart that can't be started: the run ends, and says why", async function () {
    this.timeout(10000);
    run = HotRun.start(
      { file, cwd: dir, dart: path.join(dir, 'no-dart'), onOutput: (t) => (out += t), onStatus: (s) => statuses.push(s) },
      { startProcess: startNodeProcess, connectVm: (uri) => VmClient.connect(uri, realClock), env: process.env, clock: realClock },
    );
    await run.ended;
    assert.match(out, /ENOENT/);
    assert.equal(statuses.at(-1)?.state, 'ended');
    assert.equal(run.process, undefined);
    await run.stop();
  });

  it('stop ends the app it started, and the run', async () => {
    start();
    await until('the VM service', () => statuses.some((s) => s.state === 'running'));
    const app = run!.process!;
    await run!.stop();
    assert.ok(app.hasExited, 'the app ended');
    assert.equal(statuses.at(-1)?.state, 'ended');
    assert.equal(run!.process, undefined);
  });
});
