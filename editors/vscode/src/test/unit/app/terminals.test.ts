// The twk terminals (app/terminals.ts, app/terminal.ts) over fake views,
// with core's shell serving each on a real local socket of its own.
import * as assert from 'node:assert/strict';

import { Terminals } from '../../../app/terminals';
import { Wire } from '../../../core/wire';
import { answersOf, presetNamed } from '../../../core/capabilities';
import { App, FakeDesktop, FakeLog, FakeSettings, FakeView, realShell, until } from '../fakes';

describe('Terminals', () => {
  let views: FakeView[];
  let settings: FakeSettings;
  let terminals: Terminals;
  let readyAtOnce: boolean;
  let desktop: FakeDesktop;

  beforeEach(() => {
    views = [];
    settings = new FakeSettings();
    desktop = new FakeDesktop();
    readyAtOnce = true;
    terminals = new Terminals({
      views: (title) => {
        const v = new FakeView(title, readyAtOnce);
        views.push(v);
        return v;
      },
      startShell: realShell,
      settings,
      log: new FakeLog(),
      desktop,
    });
  });

  afterEach(async () => {
    await terminals.dispose();
  });

  it('serves a new view to the app its TWK_SHELL is given to, at the view size, titled by what it is for', async () => {
    settings.columns = 90;
    settings.lines = 20;
    const t = await terminals.create('counter.dart');
    assert.equal(views.length, 1);
    assert.deepEqual(views[0].sizes, [{ columns: 90, lines: 20 }], 'the size of the settings');
    assert.equal(views[0].title, 'counter.dart · twk 100x30 · xterm.js (waiting)');

    const app = await App.connect(t.variable);
    const welcome = JSON.parse((await app.next(Wire.welcome)).toString()) as { columns: number; lines: number };
    assert.deepEqual([welcome.columns, welcome.lines], [100, 30]);
    await until('the title', () => views[0].title === 'counter.dart · twk 100x30 · xterm.js');

    views[0].type('q');
    assert.equal((await app.next(Wire.input)).toString(), 'q');
    views[0].resize(70, 10);
    assert.deepEqual(JSON.parse((await app.next(Wire.size)).toString()), { columns: 70, lines: 10 });
    app.socket.destroy();
    await until('the line saying so', () => /the app went away/.test(views[0].text));
    assert.equal(t.isClosed, false);
  });

  it('says the switches on in its title, and gives them to the next app to connect', async () => {
    const t = await terminals.create('counter.dart');
    settings.switchesOn = { screenReader: true, debug: ['overlay'] };
    const app = await App.connect(t.variable);
    const welcome = JSON.parse((await app.next(Wire.welcome)).toString()) as { environment: Record<string, string> };
    assert.equal(welcome.environment.TWK_SCREEN_READER, '1');
    assert.equal(welcome.environment.TWK_DEBUG, 'keys,overlay');
    await until('the title', () => views[0].title === 'counter.dart · twk 100x30 · xterm.js + screen reader, overlay');
    app.socket.destroy();
  });

  it("welcomes each app with the settings' capabilities then, their environment and what they declare, its view set to answer as they say before the app writes", async () => {
    const t = await terminals.create('counter.dart');
    settings.changes = { kittyKeyboard: true, notifications: false, graphics: 'sixel' };
    const first = await App.connect(t.variable);
    const welcome = JSON.parse((await first.next(Wire.welcome)).toString()) as { environment: Record<string, string>; declares: unknown };
    assert.deepEqual(welcome.environment, { TERM: 'xterm-256color', COLORTERM: 'truecolor', TERM_PROGRAM: 'twk-vscode' });
    assert.deepEqual(welcome.declares, { notifications: 'none', progressReports: true, pointerShapes: true, repeatChar: true, graphics: 'sixel' });
    assert.equal(views[0].answered.length, 1, 'told as the app was taken');
    assert.equal(views[0].answered[0].kittyKeyboard, true);
    assert.equal(views[0].answered[0].notifications, false);
    await until('the title', () => views[0].title === 'counter.dart · twk 100x30 · xterm.js, sixel images, kitty keyboard, no notifications');

    settings.profileName = 'no answers';
    settings.changes = {};
    const second = await App.connect(t.variable);
    const again = JSON.parse((await second.next(Wire.welcome)).toString()) as { declares: { repeatChar: boolean } };
    assert.equal(again.declares.repeatChar, false);
    assert.deepEqual(views[0].answered[1], answersOf(presetNamed('no answers').capabilities));
    assert.ok(views[0].answered[1].deny.includes('deviceAttributes'));
    second.socket.destroy();
  });

  it("passes what the app asks of the editor to the desktop, a link only to the web or mail, and takes the app's progress away as it goes", async () => {
    const t = await terminals.create('counter.dart');
    const app = await App.connect(t.variable);
    await app.next(Wire.welcome);
    const v = views[0];
    v.request({ type: 'notify', title: 'Build', body: 'done' });
    v.request({ type: 'progress', state: 1, percent: 40 });
    v.request({ type: 'clipboard', text: 'copied' });
    v.request({ type: 'openLink', uri: 'https://dart.dev' });
    v.request({ type: 'openLink', uri: 'command:workbench.action.quit' });
    v.request({ type: 'openLink', uri: 'file:///etc/passwd' });
    assert.deepEqual(desktop.done, ['notify counter.dart: Build | done', 'progress counter.dart: 1 40', 'clipboard copied', 'open https://dart.dev']);
    app.socket.destroy();
    await until('the progress taken away', () => desktop.done.at(-1) === 'progress counter.dart: 0 null');
  });

  it('one shell each: two terminals, two addresses; one closed is forgotten, its shell stopped, the other serving on', async () => {
    const first = await terminals.create('a.dart');
    const second = await terminals.create('b.dart');
    assert.notEqual(first.variable, second.variable);
    assert.deepEqual(terminals.all(), [first, second]);
    views[0].close();
    await until('the first shell stopped', () => first.shell === undefined);
    assert.deepEqual(terminals.all(), [second]);
    const app = await App.connect(second.variable);
    await app.next(Wire.welcome);
    app.socket.destroy();
  });

  it('closed before its view was up: fails, and serves nothing', async () => {
    readyAtOnce = false;
    const opening = terminals.create('a.dart');
    views[0].close();
    await assert.rejects(opening, /closed before it was ready/);
    assert.deepEqual(terminals.all(), []);
  });

  it('a newer app taking it over: no line between the two apps', async () => {
    const t = await terminals.create('a.dart');
    const first = await App.connect(t.variable);
    await first.next(Wire.welcome);
    const closed = new Promise((r) => first.socket.once('close', r));
    const second = await App.connect(t.variable);
    await second.next(Wire.welcome);
    await closed;
    assert.doesNotMatch(views[0].text, /went away/);
    second.socket.destroy();
    await until('the line once the last one went', () => /the app went away/.test(views[0].text));
  });

  it('a view that comes back empty (its webview loaded again): the size fixed for it again, the app told its size, a redraw asked for', async () => {
    settings.columns = 90;
    settings.lines = 20;
    const t = await terminals.create('a.dart');
    let reloads = 0;
    t.onDidReload(() => reloads++);
    const app = await App.connect(t.variable);
    await app.next(Wire.welcome);
    views[0].reload(90, 20);
    assert.deepEqual(JSON.parse((await app.next(Wire.size)).toString()), { columns: 90, lines: 20 });
    assert.deepEqual(views[0].sizes, [
      { columns: 90, lines: 20 },
      { columns: 90, lines: 20 },
    ]);
    assert.equal(reloads, 1);
    assert.equal(views[0].title, 'a.dart · twk 90x20 · xterm.js');
    assert.equal(views[0].answered.length, 2, 'told again what to answer');
    assert.deepEqual(views[0].answered[1], views[0].answered[0]);
    app.socket.destroy();
  });

  it('one for any app shows the TWK_SHELL an app takes it with', async () => {
    const t = await terminals.createForAnyApp();
    assert.ok(views[0].text.includes(`TWK_SHELL='${t.variable}'`), views[0].text);
    const app = await App.connect(t.variable);
    await app.next(Wire.welcome);
    app.socket.destroy();
  });
});
