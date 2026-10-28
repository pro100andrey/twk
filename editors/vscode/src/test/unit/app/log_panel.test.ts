// The sequence log's panel (app/log_panel.ts) over a fake panel and clock,
// of a twk terminal over a fake view: nothing sent before the webview is
// up, then all of it; what comes after sent at most every 100 ms; the
// extension's own lines and the app's coming and going as notes; cleared;
// the terminal's end told; one panel per screen. And the commands' screen
// and its text (app/screens.ts).
import * as assert from 'node:assert/strict';

import { LogPanel, LogPanels } from '../../../app/log_panel';
import { activeScreen, screenText } from '../../../app/screens';
import { TwkTerminal } from '../../../app/terminal';
import { ToLog } from '../../../webview/log_protocol';
import { FakeClock, FakeDesktop, FakeLog, FakePanel, FakeSettings, FakeView, realShell } from '../fakes';

function terminal(name = 'counter.dart', view = new FakeView(name)): TwkTerminal {
  return new TwkTerminal(name, { view, startShell: realShell, settings: new FakeSettings(), log: new FakeLog(), desktop: new FakeDesktop() });
}

/** The names of the entries of what [panel] was sent, message by message. */
const sent = (panel: FakePanel<ToLog>) => panel.posted.map((m) => (m.type === 'ended' ? 'ended' : `${m.type}: ${m.entries.map((e) => e.name).join(' | ')}`));

describe('the sequence log panel', () => {
  let clock: FakeClock;
  let panel: FakePanel<ToLog>;
  let t: TwkTerminal;

  beforeEach(async () => {
    clock = new FakeClock();
    panel = new FakePanel<ToLog>();
    t = terminal();
    await t.start();
  });

  afterEach(() => t.dispose());

  it('sends all of it once the webview is up, then what comes at most every 100 ms', async () => {
    const log = new LogPanel(t, panel, clock);
    await t.write(Buffer.from('\x1b[?1049h'));
    assert.equal(panel.posted.length, 0);
    assert.equal(clock.pending, 0);
    panel.send({ type: 'ready' });
    assert.deepEqual(sent(panel), ['reset: the log of counter.dart begins, at 100x30 | DECSET 1049 alternate screen, cursor saved']);
    const first = panel.posted[0];
    assert.equal(first.type === 'reset' ? first.title : undefined, 'counter.dart · twk sequence log');
    clock.elapse(30);
    await t.write(Buffer.from('\x1b[?2026hab\x1b[?2026l'));
    (t.view as FakeView).type('q');
    assert.equal(panel.posted.length, 1);
    clock.elapse(99);
    assert.equal(panel.posted.length, 1);
    clock.elapse(1);
    assert.deepEqual(sent(panel).slice(1), ['entries: frame 1: 1 DECSET, 1 text, 1 DECRST | key q']);
    const entries = log.entries();
    assert.deepEqual(
      entries.map((e) => [e.time, e.direction]),
      [
        [0, 'note'],
        [0, 'out'],
        [30, 'out'],
        [30, 'in'],
      ],
    );
    assert.equal(clock.pending, 0);
  });

  it("the extension's own lines and the sizes as notes; cleared; a webview that loaded again sent all again; the terminal's end", async () => {
    const log = new LogPanel(t, panel, clock);
    panel.send({ type: 'ready' });
    t.say('\x1b[2mtwk: the app went away\x1b[0m\r\n');
    (t.view as FakeView).resize(90, 20);
    log.flush();
    assert.deepEqual(sent(panel).slice(1), ['entries: twk: the app went away | size 90x20']);
    panel.send({ type: 'clear' });
    assert.deepEqual(sent(panel).slice(2), ['reset: ']);
    await t.write(Buffer.from('x'));
    panel.send({ type: 'ready' });
    assert.deepEqual(sent(panel).slice(3), ['reset: text "x"']);
    panel.send({ type: 'shown', rows: 1, held: 0, last: ['text "x"'] });
    assert.deepEqual(log.shown, { type: 'shown', rows: 1, held: 0, last: ['text "x"'] });
    panel.send({ type: 'nonsense' });
    await t.dispose();
    assert.deepEqual(sent(panel).slice(4), ['entries: counter.dart was closed', 'ended']);
    assert.equal(panel.disposed, false, 'the log stays open to be read');
  });

  it("a screen followed from its start: its log, opened later, begins with what came before, its times the screen's", async () => {
    const logs = new LogPanels(() => panel, clock);
    const other = terminal('other.dart');
    logs.follow(other);
    clock.elapse(40);
    await other.write(Buffer.from('\x1b[?1049h'));
    (other.view as FakeView).type('\x1b[?1;2c');
    clock.elapse(10);
    const log = logs.show(other);
    await other.write(Buffer.from('x'));
    assert.deepEqual(
      log.entries().map((e) => [e.time, e.name]),
      [
        [0, 'other.dart opened, at 100x30'],
        [40, 'DECSET 1049 alternate screen, cursor saved'],
        [40, 'DA1 answer: 1;2'],
        [50, 'text "x"'],
      ],
    );
    await other.dispose();
    logs.dispose();
  });

  it('one panel per screen, shown again when asked again, forgotten once closed', () => {
    const made: FakePanel<ToLog>[] = [];
    const logs = new LogPanels(() => {
      const p = new FakePanel<ToLog>();
      made.push(p);
      return p;
    }, clock);
    const other = terminal('other.dart');
    try {
      const a = logs.show(t);
      assert.equal(logs.show(t), a);
      assert.notEqual(logs.show(other), a);
      assert.equal(made.length, 2);
      made[0].dispose();
      assert.equal(logs.of(t), undefined);
      assert.notEqual(logs.show(t), a);
      logs.dispose();
      assert.ok(made.every((p) => p.disposed));
    } finally {
      void other.dispose();
    }
  });
});

describe("the twk terminal the commands take, and its screen's text", () => {
  it('the active one, else the newest open', async () => {
    const a = terminal('a.dart');
    const b = terminal('b.dart');
    assert.equal(activeScreen([a, b]), b);
    (a.view as FakeView).isActive = true;
    assert.equal(activeScreen([a, b]), a);
    await a.dispose();
    assert.equal(activeScreen([a, b]), b);
    await b.dispose();
    assert.equal(activeScreen([a, b]), undefined);
  });

  it('its rows without the blanks that end them, nor the blank rows at its end', () => {
    assert.equal(screenText({ buffer: 'alternate', rows: ['╭──╮  ', '│ab│', '╰──╯', '', '  '] }), '╭──╮\n│ab│\n╰──╯\n');
    assert.equal(screenText({ buffer: 'normal', rows: ['', ''] }), '');
  });
});
