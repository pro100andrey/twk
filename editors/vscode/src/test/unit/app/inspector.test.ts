// The inspector (app/inspector.ts) over fakes: of the apps' services, the
// tree view, the opener and the clock; the terminals real ones over fake
// views (their picks).
import * as assert from 'node:assert/strict';

import { AppConnection } from '../../../app/hot_apps';
import { Inspector, noApp, noNode, refreshGap } from '../../../app/inspector';
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
  FakeNodeDetailsView,
  FakeNotice,
  FakeOpener,
  FakePickingIndicator,
  FakeSettings,
  FakeView,
  realShell,
  renderAnswer,
  treeAnswer,
  until,
} from '../fakes';

/** The flags an app answers, [on] those on. */
function flagsAnswer(...on: string[]) {
  const all = ['overlay', 'console', 'rainbow', 'relayout', 'overflow', 'keys', 'select', 'selectMany', 'treeEvents'];
  return { version: 1, ...Object.fromEntries(all.map((f) => [f, on.includes(f)])), framesInRow: false };
}

/** An app with the tree of inspect.test.ts that answers what an inspector asks; its flags kept as set. */
function app(): FakeAppService {
  const service = new FakeAppService();
  const on = new Set<string>();
  service.answers.set('ext.twk.tree', (p) => (p.tree === 'render' ? renderAnswer : treeAnswer));
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
  service.answers.set('ext.twk.properties', (p) =>
    p.id === '4'
      ? { version: 1, id: 4, name: 'Text', render: 11, properties: [{ value: '"n 0"' }, { name: 'overflow', value: 'clip' }], flags: ['needsLayout'] }
      : { version: 1, id: Number(p.id), name: 'Padding', render: 10, properties: [{ name: 'padding', value: 'left 2' }], flags: [] },
  );
  service.answers.set('ext.twk.layout', (p) => ({
    version: 1,
    id: Number(p.id),
    render: 11,
    name: 'RenderText',
    constraints: { minWidth: 0, maxWidth: 40, minHeight: 0, maxHeight: null },
    size: { width: 3, height: 1 },
    offset: { x: 2, y: 0 },
    global: { x: 2, y: 1 },
  }));
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
  let details: FakeNodeDetailsView;
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
    details = new FakeNodeDetailsView();
    opener = new FakeOpener();
    button = new FakePickingIndicator();
    notice = new FakeNotice();
    clock = new FakeClock();
    inspector = new Inspector({ apps: apps.event, view, details, opener, picking: button, notice, clock, log });
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

  it("a node selected or picked has its properties and layout shown in the node view; none selected, the node gone, or no app, says so", async () => {
    const service = app();
    await connect(service);
    assert.equal(details.message, noNode);
    view.select(4);
    await until('its details', () => details.lines.length > 0);
    assert.deepEqual(details.lines, [
      'Text: id #4',
      'Text: render #11',
      'Text: "n 0"',
      'Text: overflow clip',
      'Text: flags needsLayout',
      'Layout: constraints w 0..40, h 0..inf',
      'Layout: size 3 x 1',
      'Layout: offset 2, 0',
      'Layout: on screen 2, 1',
    ]);
    assert.equal(details.message, '');
    assert.deepEqual(callsOf(service, 'ext.twk.layout'), ['ext.twk.layout id=4']);
    // another node replaces it
    view.select(3);
    await until('the Padding', () => details.lines.includes('Padding: padding left 2'));
    // its layout is asked again as the tree is: a size may have changed
    const before = callsOf(service, 'ext.twk.layout').length;
    await inspector.refresh();
    await until('layout asked again', () => callsOf(service, 'ext.twk.layout').length > before);
    // none selected
    view.select(undefined);
    await until('none', () => details.message === noNode);
    assert.deepEqual(details.lines, []);
    // a pick shows its node without the person selecting it
    await inspector.pick();
    await until('armed', () => inspector.picking);
    service.post('twk.select', { version: 1, x: 3, y: 1 });
    await until('picked details', () => details.lines.includes('Text: id #4'));
    // the pick mode off: the selection goes, so do its details
    await inspector.stopPicking();
    await until('none after the pick', () => details.message === noNode);
    // the app goes
    view.select(3);
    await until('details again', () => details.lines.length > 0);
    service.end();
    await until('no app', () => details.message === noApp);
    assert.deepEqual(details.lines, []);
  });

  it('an element with no render object shows its properties without a layout; a node the app no more has says why', async () => {
    const service = app();
    await connect(service);
    service.answers.set('ext.twk.layout', () => {
      throw new Error('no render object');
    });
    view.select(3);
    await until('properties', () => details.lines.length > 0);
    assert.deepEqual(
      details.sections.map((s) => s.title),
      ['Padding'],
    );
    service.answers.set('ext.twk.properties', () => {
      throw new Error('no node with id 3');
    });
    view.select(3);
    await until('why', () => details.message.includes('no node with id 3'));
    assert.deepEqual(details.lines, []);
  });

  it('a refresh that finds the node as it was leaves the node view alone; one that finds it changed shows it', async () => {
    const service = app();
    await connect(service);
    view.select(4);
    await until('its details', () => details.lines.length > 0);
    const shows = details.shows;
    const asked = callsOf(service, 'ext.twk.layout').length;
    await inspector.refresh();
    await until('asked again', () => callsOf(service, 'ext.twk.layout').length > asked);
    await settle();
    assert.equal(details.shows, shows);
    service.answers.set('ext.twk.layout', (p) => ({ version: 1, id: Number(p.id), render: 11, name: 'RenderText', size: { width: 9, height: 1 } }));
    await inspector.refresh();
    await until('changed', () => details.lines.includes('Layout: size 9 x 1'));
    assert.equal(details.shows, shows + 1);
  });

  it('the node view is cleared when the app shown changes: the node was of the other app', async () => {
    const first = app();
    await connect(first);
    view.select(4);
    await until('its details', () => details.lines.length > 0);
    const second = app();
    const t = await terminals.create('other.dart');
    apps.fire({ terminal: t, service: second });
    await until('the other app', () => inspector.terminal === t);
    await until('cleared', () => details.message === noNode);
    assert.deepEqual(details.lines, []);
    const asked = callsOf(second, 'ext.twk.properties').length;
    await inspector.refresh();
    await settle();
    assert.equal(callsOf(second, 'ext.twk.properties').length, asked, 'the old node is not asked of the new app');
  });

  it('a layout the extension cannot read gives the properties alone', async () => {
    const service = app();
    await connect(service);
    service.answers.set('ext.twk.layout', () => ({ version: 1, constraints: { minWidth: 'wide' } }));
    view.select(3);
    await until('properties', () => details.lines.length > 0);
    assert.deepEqual(details.sections.map((s) => s.title), ['Padding']);
    assert.equal(details.message, '');
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

  it('the render tree: the switch selects the counterpart of the node selected, in either direction; following, outlining and the node view work in it; a render object leads to no code', async () => {
    const service = app();
    withCode(service);
    await connect(service);
    assert.equal(inspector.treeKind, 'element');
    // the Text selected: its render object is selected on the switch
    view.select(4);
    await until('its details', () => details.lines.length > 0);
    await inspector.showTree('render');
    assert.equal(inspector.treeKind, 'render');
    assert.equal(inspector.tree!.kind, 'render');
    assert.equal(view.tree!.kind, 'render');
    assert.deepEqual(view.kinds, ['element', 'render']);
    assert.ok(service.asked.includes('ext.twk.tree tree=render'), service.asked.join('\n'));
    assert.equal(view.selected, 11);
    assert.ok(service.asked.includes('ext.twk.highlight id=11'));
    await until('its details', () => callsOf(service, 'ext.twk.properties').includes('ext.twk.properties id=11'));
    // the same tree again: nothing asked
    const asked = service.asked.length;
    await inspector.showTree('render');
    assert.equal(service.asked.length, asked);
    // followed: a change of the app asks for the render tree
    service.post('twk.treeChanged', { version: 1 });
    clock.elapse(refreshGap);
    await until('asked again', () => service.asked.filter((c) => c === 'ext.twk.tree tree=render').length === 2);
    // a render object has no widget
    await assert.rejects(inspector.goToSource(11), /no widget/);
    await assert.rejects(inspector.goToBuild(11), /no widget/);
    assert.deepEqual(opener.opened, []);
    // selected by hand: outlined
    view.select(10);
    await until('outlined', () => service.asked.includes('ext.twk.highlight id=10'));
    // and back: the element of the render object
    await inspector.toggleTree();
    assert.equal(inspector.treeKind, 'element');
    assert.equal(view.selected, 3, 'the Padding is the element of RenderPadding');
    assert.equal(view.tree!.kind, 'element');
    // a node with no counterpart (the render root): none selected
    await inspector.showTree('render');
    view.select(9);
    await inspector.showTree('element');
    assert.equal(view.selected, undefined);
    assert.equal(details.message, noNode);
  });

  it('a pick in the render tree selects the render object and opens the code of its widget all the same', async () => {
    const service = app();
    withCode(service);
    await connect(service);
    await inspector.showTree('render');
    await inspector.pick();
    // ext.twk.select answers the element; its properties tell the render object
    service.post('twk.select', { version: 1, x: 3, y: 2 });
    await until('opened', () => opener.opened.length === 1);
    assert.deepEqual(view.revealed, [11]);
    assert.ok(service.asked.includes('ext.twk.highlight id=11'));
    assert.equal(opener.opened[0].method, '_CountState.build');
    assert.equal(inspector.treeKind, 'render');
    assert.equal(inspector.tree!.kind, 'render');
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
