// The inspector (app/inspector.ts) over fakes: of the apps' services, the
// tree view, the opener and the clock; the terminals real ones over fake
// views (their picks).
import * as assert from 'node:assert/strict';

import { AppConnection } from '../../../app/hot_apps';
import { Inspector, noApp, refreshGap } from '../../../app/inspector';
import { TwkTerminal } from '../../../app/terminal';
import { Terminals } from '../../../app/terminals';
import { Emitter } from '../../../core/events';
import { nodeOf } from '../../../core/inspect';
import {
  FakeAppService,
  FakeClock,
  FakeDesktop,
  FakeInspectorView,
  FakeLog,
  FakeNotice,
  FakeOpener,
  FakePickingIndicator,
  FakeSettings,
  FakeView,
  realShell,
  treeAnswer,
  until,
} from '../fakes';

/** The flags an app answers, [on] those on. */
function flagsAnswer(...on: string[]) {
  const all = ['overlay', 'console', 'rainbow', 'relayout', 'keys', 'select', 'selectMany', 'treeEvents'];
  return { version: 1, ...Object.fromEntries(all.map((f) => [f, on.includes(f)])), framesInRow: false };
}

/** An app with the tree of inspect.test.ts that answers what an inspector asks; its flags kept as set. */
function app(): FakeAppService {
  const service = new FakeAppService();
  const on = new Set<string>();
  service.answers.set('ext.twk.tree', () => treeAnswer);
  service.answers.set('ext.twk.flags', (p) => {
    for (const [k, v] of Object.entries(p)) {
      if (v === 'true') {
        on.add(k);
      } else {
        on.delete(k);
      }
    }
    return flagsAnswer(...on);
  });
  service.answers.set('ext.twk.highlight', (p) => ({ version: 1, id: p.id === undefined ? null : Number(p.id) }));
  service.answers.set('ext.twk.select', () => ({ version: 1, id: 4, path: [1, 2, 3, 4], render: [11] }));
  return service;
}

/** A source with `_CountState.build` making a Padding with a Text, and the VM service's view of it. */
const source = [
  'class _CountState extends State<_Count> {',
  '  @override',
  '  Widget build(BuildContext context) =>',
  "      Padding(padding: p, child: Text('n'));",
  '}',
].join('\n');

function withCode(service: FakeAppService): void {
  service.vmAnswers = (method, params) => {
    switch (method) {
      case 'getClassList':
        return {
          classes: [
            { id: 'classes/1', name: '_CountState', library: { uri: 'package:app/count.dart' } },
            { id: 'classes/2', name: '_CountState', library: { uri: 'dart:core' } },
          ],
        };
      case 'lookupResolvedPackageUris':
        return { uris: ['file:///app/lib/count.dart'] };
      case 'getObject':
        switch (params.objectId) {
          case 'classes/1':
            return { functions: [{ id: 'f/0', name: 'initState' }, { id: 'f/1', name: 'build' }] };
          case 'f/1':
            return { location: { script: { id: 's/1', uri: 'package:app/count.dart' }, tokenPos: 100, endTokenPos: 200 } };
          case 's/1':
            return { uri: 'package:app/count.dart', source, tokenPosTable: [[2, 100, 3], [4, 200, 44]] };
        }
    }
    throw new Error(`no ${method} ${JSON.stringify(params)}`);
  };
}

describe('Inspector', () => {
  let terminals: Terminals;
  let views: FakeView[];
  let apps: Emitter<AppConnection>;
  let view: FakeInspectorView;
  let opener: FakeOpener;
  let button: FakePickingIndicator;
  let notice: FakeNotice;
  let clock: FakeClock;
  let log: FakeLog;
  let inspector: Inspector;

  beforeEach(() => {
    views = [];
    log = new FakeLog();
    terminals = new Terminals({
      views: (title) => {
        const v = new FakeView(title);
        views.push(v);
        return v;
      },
      startShell: realShell,
      settings: new FakeSettings(),
      log,
      desktop: new FakeDesktop(),
    });
    apps = new Emitter();
    view = new FakeInspectorView();
    opener = new FakeOpener();
    button = new FakePickingIndicator();
    notice = new FakeNotice();
    clock = new FakeClock();
    inspector = new Inspector({ apps: apps.event, view, opener, picking: button, notice, clock, log });
  });

  afterEach(async () => {
    inspector.dispose();
    await terminals.dispose();
  });

  /** A terminal with [service]'s app connected in it. */
  async function connect(service: FakeAppService, terminal?: TwkTerminal): Promise<TwkTerminal> {
    const t = terminal ?? (await terminals.create('app.dart'));
    apps.fire({ terminal: t, service });
    await until('the tree shown', () => inspector.tree !== undefined && inspector.terminal === t);
    return t;
  }

  const treeAsked = (s: FakeAppService) => s.asked.filter((c) => c === 'ext.twk.tree').length;

  it("shows the tree of the app that connected, from the app's own element; none once it went away", async () => {
    assert.equal(view.message, noApp);
    const service = app();
    await connect(service);
    assert.equal(nodeOf(view.tree!, 4)?.name, 'Text');
    assert.equal(view.message, '');
    // shown on the screen: the app tells when its tree changed
    await until('the tree followed', () => service.asked.includes('ext.twk.flags treeEvents=true'));
    service.end();
    await until('no app', () => view.message === noApp);
    assert.equal(view.tree, undefined);
    assert.equal(inspector.terminal, undefined);
  });

  it('follows the tree: its changes asked for at most once in each gap, and only while it is on the screen', async () => {
    const service = app();
    await connect(service);
    const before = treeAsked(service);
    service.post('twk.treeChanged', { version: 1, rebuilds: 3 });
    service.post('twk.treeChanged', { version: 1, rebuilds: 1 });
    clock.elapse(refreshGap - 1);
    service.post('twk.treeChanged', { version: 1, rebuilds: 1 });
    assert.equal(treeAsked(service), before);
    clock.elapse(1);
    await until('the tree asked again', () => treeAsked(service) === before + 1);
    assert.equal(clock.pending, 0, 'one asking for the three');

    view.setVisible(false);
    await until('the tree followed no more', () => service.asked.includes('ext.twk.flags treeEvents=false'));
    view.setVisible(true);
    await until('followed again, and asked at once', () => service.asked.filter((c) => c === 'ext.twk.flags treeEvents=true').length === 2);
    await until('the tree asked at once', () => treeAsked(service) === before + 2);
  });

  it('an app whose binding comes after its VM service connected: asked nothing until it is there, then told and asked', async () => {
    const service = app();
    service.bound = false;
    const t = await terminals.create('app.dart');
    apps.fire({ terminal: t, service });
    await until('the app starting', () => view.message === 'The app is starting.');
    assert.deepEqual(service.asked, []);
    service.bind();
    await until('the tree', () => view.tree !== undefined);
    await until('the tree followed', () => service.asked.includes('ext.twk.flags treeEvents=true'));
  });

  it('asks for the tree again until the app has drawn its first frame', async () => {
    const service = app();
    let frames = 0;
    service.answers.set('ext.twk.tree', () => (frames > 0 ? treeAnswer : { version: 1, tree: 'element', root: null, app: null }));
    const t = await terminals.create('app.dart');
    apps.fire({ terminal: t, service });
    await until('the empty tree', () => view.message === 'The app has drawn no frame yet.');
    frames = 1;
    clock.elapse(refreshGap);
    await until('the tree', () => view.tree?.root !== null && view.tree !== undefined);
  });

  it("after a hot reload: the tree asked again at once, and the app's code read again", async () => {
    const service = app();
    withCode(service);
    await connect(service);
    await inspector.goToSource(4);
    const before = treeAsked(service);
    service.reloaded();
    await until('the tree asked again', () => treeAsked(service) === before + 1);
    await inspector.goToSource(4);
    assert.equal(service.calls.filter((c) => c.method === 'getClassList').length, 2, 'the classes asked again after the reload, not before');
  });

  it("goes to where a widget was made, and to a build method, through the app's VM service", async () => {
    const service = app();
    withCode(service);
    await connect(service);
    const text = await inspector.goToSource(4);
    const line4 = source.split('\n')[3];
    assert.deepEqual(text, { uri: 'file:///app/lib/count.dart', line: 4, column: line4.indexOf('Text(') + 1, exact: true, method: '_CountState.build' });
    const padding = await inspector.goToSource(3);
    assert.equal(padding.column, line4.indexOf('Padding(') + 1);
    const build = await inspector.goToBuild(2);
    assert.deepEqual(build, { uri: 'file:///app/lib/count.dart', line: 3, column: 10, exact: true, method: '_CountState.build' });
    assert.deepEqual(opener.opened, [text, padding, build]);
    // read once
    assert.equal(service.calls.filter((c) => c.method === 'getClassList').length, 1);
    await assert.rejects(inspector.goToBuild(3), /Padding has no build method of its own/);
    await assert.rejects(inspector.goToSource(99), /in the tree no more/);
    // the binding's own element above the app: made in no build the app's code has
    await assert.rejects(inspector.goToSource(2), /no call of _Count's constructor found/);
  });

  it('a node selected is outlined on the app, and only that: none selected, none outlined', async () => {
    const service = app();
    withCode(service);
    await connect(service);
    view.select(3);
    view.select(undefined);
    await until('both outlines', () => service.asked.filter((c) => c.startsWith('ext.twk.highlight')).length === 2);
    assert.deepEqual(
      service.asked.filter((c) => c.startsWith('ext.twk.highlight')),
      ['ext.twk.highlight id=3', 'ext.twk.highlight'],
    );
    assert.deepEqual(opener.opened, [], 'nothing opened');
  });

  /** Lets what the events started settle. */
  const settle = () => new Promise((r) => setImmediate(r));

  /** The calls of [method] [s] was asked. */
  const callsOf = (s: FakeAppService, method: string) => s.asked.filter((c) => c === method || c.startsWith(`${method} `));

  it("the pick mode: on, each of the app's own picks (picking many) selects, outlines and opens where it was made, the focus kept; off, the app picks no more, its outline and the selection gone", async () => {
    const service = app();
    withCode(service);
    await connect(service);
    assert.deepEqual(button.shown, [false]);
    await inspector.pick();
    assert.ok(service.asked.includes('ext.twk.flags selectMany=true select=true'), service.asked.join('\n'));
    assert.equal(views[0].picking, false, 'the app picks, not the terminal');
    assert.equal(button.on, true);
    assert.equal(inspector.picking, true);
    // on already: nothing more
    await inspector.pick();
    assert.equal(callsOf(service, 'ext.twk.flags').filter((c) => c.includes('select=true')).length, 1);

    service.post('twk.select', { version: 1, x: 3, y: 2 });
    await until('opened', () => opener.opened.length === 1);
    assert.deepEqual(view.revealed, [4]);
    assert.ok(service.asked.includes('ext.twk.select x=3 y=2'));
    assert.ok(service.asked.includes('ext.twk.highlight id=4'));
    const line4 = source.split('\n')[3];
    assert.deepEqual(opener.opened[0], { uri: 'file:///app/lib/count.dart', line: 4, column: line4.indexOf('Text(') + 1, exact: true, method: '_CountState.build' });
    assert.deepEqual(opener.keptFocus, [true]);
    // a second pick, the app picking on by itself: nothing asked of it again
    service.post('twk.select', { version: 1, x: 2, y: 1 });
    await until('opened again', () => opener.opened.length === 2);
    assert.equal(callsOf(service, 'ext.twk.flags').filter((c) => c.includes('select=true')).length, 1);
    assert.deepEqual(notice.said, []);

    await inspector.stopPicking();
    assert.equal(button.on, false);
    assert.equal(inspector.picking, false);
    assert.equal(view.selected, undefined, 'the selection gone');
    assert.ok(service.asked.includes('ext.twk.flags select=false selectMany=false'));
    assert.equal(service.asked.at(-1), 'ext.twk.highlight', 'the outline gone');
    assert.deepEqual(button.shown, [false, true, false]);
    // off already: nothing more
    const asked = service.asked.length;
    await inspector.stopPicking();
    assert.equal(service.asked.length, asked);
  });

  it('Escape in the terminal turns the pick mode off, as the app tells it', async () => {
    const service = app();
    await connect(service);
    view.select(3);
    await inspector.pick();
    service.post('twk.select', { version: 1, x: null, y: null });
    await until('off', () => !button.on);
    await settle();
    assert.equal(callsOf(service, 'ext.twk.select').length, 0, 'nothing picked');
    assert.equal(view.selected, undefined);
    assert.equal(service.asked.at(-1), 'ext.twk.highlight');
  });

  it('an app of a twk before selectMany is armed again after each pick', async () => {
    const service = app();
    withCode(service);
    // it knows no selectMany: its answer has none
    service.answers.set('ext.twk.flags', (p) => flagsAnswer(...(p.select === 'true' ? ['select'] : [])));
    await connect(service);
    await inspector.pick();
    service.post('twk.select', { version: 1, x: 3, y: 2 });
    await until('armed again', () => service.asked.includes('ext.twk.flags select=true'));
    await until('opened', () => opener.opened.length === 1);
    assert.equal(service.asked.filter((c) => c === 'ext.twk.flags select=true').length, 1, service.asked.join('\n'));
  });

  it("where the app can't pick itself (the inline mode), each click on its terminal picks, by the cursor's row, until Escape", async () => {
    const service = app();
    withCode(service);
    service.answers.set('ext.twk.flags', () => flagsAnswer());
    await connect(service);
    await inspector.pick();
    assert.equal(views[0].picking, true);
    assert.equal(button.on, true);
    // cells of the terminal's screen, the cursor on its row 7: an inline
    // region's rows are found by it
    views[0].picked({ x: 5, y: 6, cursorY: 7 });
    await until('opened', () => opener.opened.length === 1);
    assert.ok(service.asked.includes('ext.twk.select x=5 y=6 cursorY=7'), service.asked.join('\n'));
    assert.equal(views[0].picking, true, 'picking on');
    views[0].picked({ x: 1, y: 6, cursorY: 7 });
    await until('opened again', () => opener.opened.length === 2);
    // Escape
    views[0].picked(null);
    await until('off', () => !button.on);
    assert.equal(views[0].picking, false);
    assert.equal(view.selected, undefined);
    assert.ok(!service.asked.some((c) => c.includes('select=false')), 'the app was not picking');

    // off by the button: the terminal picks no more
    await inspector.pick();
    assert.equal(views[0].picking, true);
    await inspector.stopPicking();
    assert.equal(views[0].picking, false);
  });

  it("ends with its app, and is given again to a restart's app in the same terminal", async () => {
    const service = app();
    const t = await connect(service);
    await inspector.pick();
    service.end();
    await until('off with the app', () => !button.on);
    await until('no app', () => view.message === noApp);
    service.post('twk.select', { version: 1, x: 3, y: 2 });
    await settle();
    assert.equal(callsOf(service, 'ext.twk.select').length, 0, 'the app gone picks nothing');

    const restarted = app();
    restarted.bound = false;
    apps.fire({ terminal: t, service: restarted });
    await settle();
    assert.equal(button.on, false, 'not before its binding is there');
    restarted.bind();
    await until('armed', () => restarted.asked.includes('ext.twk.flags selectMany=true select=true'));
    assert.equal(button.on, true);
    await inspector.stopPicking();
    assert.ok(restarted.asked.includes('ext.twk.flags select=false selectMany=false'));

    // the terminal closed: the mode forgotten with it
    await inspector.pick();
    restarted.end();
    await t.dispose();
    await until('off', () => !button.on);
    const next = app();
    const other = await connect(next);
    assert.notEqual(other, t);
    await settle();
    assert.ok(!next.asked.some((c) => c.includes('select=true')));
    assert.equal(button.on, false);
  });

  it('a pick whose widget is made in no build found opens the build method above it, saying why; with none, says so', async () => {
    const service = app();
    withCode(service);
    // the binding's element above the app, _Count: no build makes it, its own state's build is the one above
    service.answers.set('ext.twk.select', () => ({ version: 1, id: 2, path: [1, 2], render: [] }));
    await connect(service);
    await inspector.pick();
    service.post('twk.select', { version: 1, x: 0, y: 0 });
    await until('opened', () => opener.opened.length === 1);
    assert.deepEqual(opener.opened[0], { uri: 'file:///app/lib/count.dart', line: 3, column: 10, exact: true, method: '_CountState.build' });
    assert.deepEqual(notice.said, ["twk: where _Count was made is not known (no call of _Count's constructor found in the build methods above it): _CountState.build opened"]);

    // no code to be read at all
    service.vmAnswers = () => ({});
    service.reloaded();
    service.answers.set('ext.twk.select', () => ({ version: 1, id: 4, path: [1, 2, 3, 4], render: [] }));
    service.post('twk.select', { version: 1, x: 0, y: 0 });
    await until('said', () => notice.said.length === 2);
    assert.equal(notice.said[1], "twk: where Text was made is not known: no call of Text's constructor found in the build methods above it");
    assert.equal(opener.opened.length, 1);
  });

  it('a pick in the terminal of another app shows that app', async () => {
    const first = app();
    const t1 = await connect(first);
    const second = app();
    const t2 = await connect(second);
    assert.equal(inspector.terminal, t2, 'the newest shown');
    first.post('twk.select', { version: 1, x: 0, y: 0 });
    await until('the first shown', () => inspector.terminal === t1 && view.revealed.length === 1);
    // shown on the screen: the one shown follows its tree, the other no more
    await until('the second not followed', () => second.asked.includes('ext.twk.flags treeEvents=false'));
    second.end();
    first.end();
    await until('none', () => view.message === noApp);
  });

  it('switches the debug aids, and gives them again to the next app of the same terminal (a restart)', async () => {
    const service = app();
    const t = await connect(service);
    const flags = await inspector.setFlags({ overlay: true, rainbow: true });
    assert.equal(flags.overlay, true);
    assert.equal(flags.rainbow, true);
    await inspector.setFlags({ rainbow: false });
    assert.equal((await inspector.flags()).rainbow, false);

    const restarted = app();
    await connect(restarted, t);
    await until('the aids given again', () => restarted.asked.includes('ext.twk.flags overlay=true rainbow=false'));
    assert.equal((await inspector.flags()).overlay, true);
    // the old app is forgotten as the new one comes
    service.post('twk.select', { version: 1, x: 0, y: 0 });
    await new Promise((r) => setImmediate(r));
    assert.equal(view.revealed.length, 0);
  });

  it("an answer it can't read says so in the view", async () => {
    const service = app();
    service.answers.set('ext.twk.tree', () => ({ ...treeAnswer, version: 2 }));
    const t = await terminals.create('app.dart');
    apps.fire({ terminal: t, service });
    await until('the message', () => view.message.includes('version 2'));
    assert.equal(view.tree, undefined);
    await assert.rejects(inspector.goToSource(4), /in the tree no more/);
  });

  it('with no app: a pick, the aids say so', async () => {
    await assert.rejects(inspector.pick(), /No twk app runs/);
    assert.equal(button.on, false);
    await inspector.stopPicking();
    await assert.rejects(inspector.flags(), /No twk app runs/);
    assert.equal(await inspector.refresh(), undefined);
  });
});
