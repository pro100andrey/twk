// The apps' log (app/app_logs.ts) over a fake address file and socket, panel,
// opener and clock: followed only while the debug aid `logs` is on, once
// for a terminal, until it is closed; the rows (levels, error, stack, notes)
// kept and sent to the panel once the webview is up, at most every 100 ms;
// the frames of a stack opened as places of code (a package through the
// package configuration); cleared; the rows kept bounded.
import * as assert from 'node:assert/strict';

import { AppLogs, AppLogsPanel, AppLogsView, AppTerminal } from '../../../app/app_logs';
import { Emitter } from '../../../core/events';
import { ToAppLogs } from '../../../webview/app_logs_protocol';
import { FakeClock, FakeLogEndpoints, FakeOpener, FakePanel, FakeSettings, until } from '../fakes';

class FakeTerminal implements AppTerminal {
  private readonly closes = new Emitter<void>();
  readonly onDidDispose = this.closes.event;
  constructor(readonly name: string) {}
  close(): void {
    this.closes.fire();
  }
}

const record = (level: string, message: string, extra: object = {}) => JSON.stringify({ time: '2026-01-01T09:05:07.042', level, message, ...extra });

describe('the apps\' log', () => {
  let endpoints: FakeLogEndpoints;
  let clock: FakeClock;
  let settings: FakeSettings;
  let opener: FakeOpener;
  let files: Map<string, string>;
  let logs: AppLogs;

  beforeEach(() => {
    endpoints = new FakeLogEndpoints();
    clock = new FakeClock();
    settings = new FakeSettings();
    settings.switchesOn = { screenReader: false, debug: ['logs'] };
    opener = new FakeOpener();
    files = new Map();
    logs = new AppLogs({ endpoints, clock, settings, opener, readText: (f) => files.get(f) });
  });
  afterEach(() => logs.dispose());

  /** An app of /p in a terminal that serves its log, connected. */
  async function connected(name = 'counter.dart') {
    const t = new FakeTerminal(name);
    logs.started(t, '/p');
    endpoints.serve('/p', `tok-${endpoints.connections.length}`);
    clock.elapse(200);
    await until('the connection', () => endpoints.connections.length > 0);
    return { t, conn: endpoints.connections.at(-1)! };
  }

  it('is followed only while the aid logs is on, once for a terminal', () => {
    settings.switchesOn = { screenReader: false, debug: ['overlay'] };
    const t = new FakeTerminal('a.dart');
    logs.started(t, '/p');
    assert.deepEqual(logs.appsInfo(), []);
    settings.switchesOn = { screenReader: false, debug: ['logs'] };
    logs.started(t, '/p');
    logs.started(t, '/p');
    assert.deepEqual(logs.appsInfo(), [{ id: 1, label: 'a.dart', state: 'waiting' }]);
  });

  it('keeps the records by level, with error and stack, and the notes of the app coming and going', async () => {
    const { conn } = await connected();
    conn.line(record('info', 'started'));
    conn.line(record('error', 'boom', { error: 'Bad state', stack: '#0 f (file:///a/b.dart:3:4)\n#1 g (dart:core/x.dart:1:1)' }));
    conn.line('not a record');
    conn.end();
    assert.deepEqual(
      logs.allRows().map((r) => [r.level, r.message, r.error, r.stack?.map((f) => f.open)]),
      [
        ['note', 'connected to the log of the app', undefined, undefined],
        ['info', 'started', undefined, undefined],
        ['error', 'boom', 'Bad state', [true, false]],
        ['info', 'not a record', undefined, undefined],
        ['note', 'the app ended', undefined, undefined],
      ],
    );
    assert.equal(logs.appsInfo()[0].state, 'waiting');
  });

  it('follows the next app of the terminal (a restart) and ends with the terminal', async () => {
    const { t, conn } = await connected();
    conn.end();
    endpoints.serve('/p', 'second');
    clock.elapse(200);
    await until('the second connection', () => endpoints.connections.length === 2);
    assert.equal(logs.appsInfo()[0].state, 'connected');
    t.close();
    assert.equal(endpoints.connections[1].closed, true);
    assert.equal(logs.appsInfo()[0].state, 'ended');
    assert.equal(logs.allRows().at(-1)!.message, 'the terminal of the app was closed');
    assert.equal(clock.pending, 0);
  });

  it('tells two apps of one file apart', async () => {
    logs.follow(new FakeTerminal('a.dart'), '/p');
    logs.follow(new FakeTerminal('a.dart'), '/q');
    logs.follow(new FakeTerminal('b.dart'), '/r');
    assert.deepEqual(logs.appsInfo().map((a) => a.label), ['a.dart (1)', 'a.dart (2)', 'b.dart']);
  });

  it('opens the frames that are code on the disk: file: ones, and package: ones by the package configuration', async () => {
    files.set(
      '/p/.dart_tool/package_config.json',
      JSON.stringify({ configVersion: 2, packages: [{ name: 'app', rootUri: '../', packageUri: 'lib/' }] }),
    );
    const { conn } = await connected();
    conn.line(record('error', 'x', { stack: '#0 f (package:app/src/run.dart:3:4)\n#1 g (file:///home/me/g.dart:9:2)\n#2 h (dart:async/zone.dart:1:1)' }));
    const row = logs.allRows().at(-1)!;
    assert.deepEqual(row.stack?.map((f) => f.open), [true, true, false]);
    assert.equal(await logs.open(row.id, 0), true);
    assert.equal(await logs.open(row.id, 1), true);
    assert.equal(await logs.open(row.id, 2), false);
    assert.equal(await logs.open(9999, 0), false);
    assert.deepEqual(
      opener.opened.map((s) => [s.uri, s.line, s.column]),
      [
        ['file:///p/lib/src/run.dart', 3, 4],
        ['file:///home/me/g.dart', 9, 2],
      ],
    );
  });

  it('finds the package configuration above the project (a workspace\'s)', async () => {
    files.set('/.dart_tool/package_config.json', JSON.stringify({ configVersion: 2, packages: [{ name: 'app', rootUri: '../packages/app', packageUri: 'lib/' }] }));
    const { conn } = await connected();
    conn.line(record('error', 'x', { stack: '#0 f (package:app/a.dart:1:1)' }));
    assert.deepEqual(logs.allRows().at(-1)!.stack, [{ text: '#0 f (package:app/a.dart:1:1)', open: true }]);
  });

  it('follows a project once, for all its terminals: a row is shown once, and the app lives until the last terminal closes', async () => {
    const first = await connected('a.dart');
    const second = new FakeTerminal('b.dart');
    logs.started(second, '/p');
    clock.elapse(200);
    first.conn.line(record('info', 'once'));
    assert.equal(endpoints.connections.length, 1);
    assert.equal(logs.appsInfo().length, 1);
    assert.equal(logs.allRows().filter((r) => r.message === 'once').length, 1);
    first.t.close();
    assert.equal(logs.appsInfo()[0].state, 'connected');
    assert.equal(endpoints.connections[0].closed, false);
    second.close();
    assert.equal(logs.appsInfo()[0].state, 'ended');
    assert.equal(endpoints.connections[0].closed, true);
    assert.equal(clock.pending, 0);
  });

  it('keeps the last 5000 rows', async () => {
    const { conn } = await connected();
    for (let i = 0; i < AppLogs.keep + 10; i++) {
      conn.line(record('debug', `m${i}`));
    }
    const rows = logs.allRows();
    assert.equal(rows.length, AppLogs.keep);
    assert.equal(rows.at(-1)!.message, `m${AppLogs.keep + 9}`);
  });

  describe('on its panel', () => {
    let panel: FakePanel<ToAppLogs>;
    let shown: AppLogsPanel;

    beforeEach(() => {
      panel = new FakePanel<ToAppLogs>();
      shown = new AppLogsPanel(logs, panel, clock);
    });

    const kinds = () => panel.posted.map((m) => (m.type === 'reset' ? `reset ${m.rows.map((r) => r.message).join('|')}` : m.type === 'rows' ? `rows ${m.rows.map((r) => r.message).join('|')}` : 'apps'));

    it('sends nothing before the webview is up, then all of it, then rows at most every 100 ms', async () => {
      const { conn } = await connected();
      conn.line(record('info', 'one'));
      clock.elapse(500);
      assert.equal(panel.posted.length, 0);
      panel.send({ type: 'ready' });
      assert.deepEqual(kinds(), ['reset connected to the log of the app|one']);
      conn.line(record('info', 'two'));
      conn.line(record('warning', 'three'));
      clock.elapse(99);
      assert.equal(panel.posted.length, 1);
      clock.elapse(1);
      assert.deepEqual(kinds().slice(1), ['rows two|three']);
      shown.dispose();
    });

    it('tells the apps when one comes or changes', async () => {
      panel.send({ type: 'ready' });
      logs.follow(new FakeTerminal('a.dart'), '/p');
      const last = panel.posted.at(-1)!;
      assert.equal(last.type, 'apps');
      assert.deepEqual(last.type === 'apps' ? last.apps : [], [{ id: 1, label: 'a.dart', state: 'waiting' }]);
    });

    it('clears at the webview\'s asking: every row forgotten, the webview reset, the apps that went away dropped', async () => {
      const { t, conn } = await connected();
      panel.send({ type: 'ready' });
      conn.line(record('info', 'one'));
      t.close();
      panel.send({ type: 'clear' });
      assert.deepEqual(logs.allRows(), []);
      assert.deepEqual(logs.appsInfo(), []);
      const last = panel.posted.at(-1)!;
      assert.equal(last.type === 'reset' ? last.rows.length : -1, 0);
    });

    it('opens a frame the webview clicked, and ignores what is no message of it', async () => {
      const { conn } = await connected();
      panel.send({ type: 'ready' });
      conn.line(record('error', 'x', { stack: '#0 f (file:///a.dart:2:3)' }));
      const id = logs.allRows().at(-1)!.id;
      panel.send({ type: 'open', row: id, frame: 0 });
      panel.send({ type: 'open', row: 'x' });
      panel.send(42);
      await until('the editor opened', () => opener.opened.length === 1);
      assert.equal(opener.opened[0].uri, 'file:///a.dart');
      panel.send({ type: 'shown', rows: 2, held: 1, last: ['a'] });
      assert.deepEqual(shown.shown, { type: 'shown', rows: 2, held: 1, last: ['a'] });
    });

    it('a webview loaded again is sent all of it again; a closed panel listens no more', async () => {
      await connected();
      panel.send({ type: 'ready' });
      panel.send({ type: 'ready' });
      assert.equal(panel.posted.filter((m) => m.type === 'reset').length, 2);
      shown.dispose();
      assert.equal(panel.disposed, true);
      const before = panel.posted.length;
      logs.follow(new FakeTerminal('z.dart'), '/z');
      clock.elapse(500);
      assert.equal(panel.posted.length, before);
    });
  });

  it('has one panel, shown again when asked again, opened again once closed', () => {
    const made: FakePanel<ToAppLogs>[] = [];
    const view = new AppLogsView(logs, () => {
        const p = new FakePanel<ToAppLogs>();
        made.push(p);
        return p;
      }, clock);
    const a = view.show();
    assert.equal(view.show(), a);
    assert.equal(made.length, 1);
    made[0].dispose();
    assert.equal(view.current, undefined);
    assert.notEqual(view.show(), a);
    view.dispose();
  });
});
