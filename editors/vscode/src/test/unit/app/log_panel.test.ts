// The sequence log's panel (app/log_panel.ts) over a fake panel and clock,
// of a twk terminal over a fake view: nothing sent before the webview is
// up, then all of it; what comes after sent at most every 100 ms; the
// extension's own lines and the app's coming and going as notes; cleared;
// the terminal's end told; one panel per screen. And the commands' screen
// and its text (app/screens.ts).
import * as assert from 'node:assert/strict';

import { LogPanel, LogPanels, Traffic } from '../../../app/log_panel';
import { parseCast } from '../../../core/cast';
import { activeScreen, screenText } from '../../../app/screens';
import { Emitter } from '../../../core/events';
import { Output, Screen } from '../../../app/ports';
import { TwkTerminal } from '../../../app/terminal';
import { ToLog } from '../../../webview/log_protocol';
import { FakeClock, FakeDesktop, FakeLog, FakePanel, FakeSettings, FakeView, realShell } from '../fakes';

function terminal(name = 'counter.dart', view = new FakeView(name)): TwkTerminal {
  return new TwkTerminal(name, { view, startShell: realShell, settings: new FakeSettings(), log: new FakeLog(), desktop: new FakeDesktop() });
}

/** The names of the entries of what [panel] was sent, message by message. */
const sent = (panel: FakePanel<ToLog>) => panel.posted.map((m) => (m.type === 'ended' ? 'ended' : m.type === 'reveal' ? `reveal ${m.id}` : `${m.type}: ${m.entries.map((e) => e.name).join(' | ')}`));

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

  it('closes the synchronized update the app was in when the terminal ends, as a frame saying it was not closed', async () => {
    const log = new LogPanel(t, panel, clock);
    panel.send({ type: 'ready' });
    await t.write(Buffer.from('\x1b[?2026hab'));
    await t.dispose();
    const names = log.entries().map((e) => e.name);
    assert.match(names[names.length - 2], /^frame 1: .*not closed$/);
    assert.equal(names[names.length - 1], 'counter.dart was closed');
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

  it('saves what it holds: the rows as text, as the webview filters them; the bytes with their times as asciicast, from the clear on; the Save button asks', async () => {
    const asked: LogPanel[] = [];
    const logs = new LogPanels(() => panel, clock);
    logs.onDidAskSave((p) => asked.push(p));
    logs.follow(t);
    clock.elapse(7);
    await t.write(Buffer.from('\x1b[?1049h'));
    const log = logs.show(t);
    clock.elapse(13);
    (t.view as FakeView).type('q');
    await t.write(Buffer.from('hi'));
    panel.send({ type: 'save' });
    assert.deepEqual(asked, [log]);
    // whole before the webview told its filter
    assert.equal(log.text().split('\n').length, 5);
    const cast = parseCast(log.cast(1700000100, 'xterm-256color'));
    assert.deepEqual(cast.events.map((e) => [e.time, e.code, e.data]), [
      [0, 'm', 'counter.dart opened, at 100x30'],
      [0.007, 'o', '\x1b[?1049h'],
      [0.02, 'i', 'q'],
      [0.02, 'o', 'hi'],
    ]);
    assert.deepEqual([cast.header.width, cast.header.height, cast.header.title, cast.header.timestamp], [100, 30, 'counter.dart', 1700000099]);
    // the filter the webview applies
    panel.send({ type: 'shown', rows: 1, held: 0, last: [], filter: { out: false, in: true, note: false, text: true, word: '' } });
    assert.match(log.text(), /^ {4}0\.020 {2}in {2}key q +q\n$/);
    assert.deepEqual(parseCast(log.cast(1, undefined)).events.map((e) => e.code), ['i']);
    // cleared: the bytes before it are gone from the file too
    panel.send({ type: 'clear' });
    panel.send({ type: 'shown', rows: 0, held: 0, last: [] });
    await t.write(Buffer.from('x'));
    assert.deepEqual(parseCast(log.cast(1)).events.map((e) => e.data), ['x']);
    assert.match(log.text(), /^ {4}0\.020 {2}out text "x" +x\n$/);
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

/** A screen the test writes to ([app], [say]) and tells an app took ([appStarts]). */
class FakeScreen implements Screen {
  readonly name = 'counter.dart';
  readonly view = new FakeView('counter.dart');
  readonly outputs = new Emitter<Output>();
  readonly inputs = new Emitter<Uint8Array>();
  readonly notes = new Emitter<string>();
  readonly resizes = new Emitter<void>();
  readonly disposes = new Emitter<void>();
  readonly starts = new Emitter<void>();
  readonly onDidOutput = this.outputs.event;
  readonly onDidInput = this.inputs.event;
  readonly onDidNote = this.notes.event;
  readonly onDidResize = this.resizes.event;
  readonly onDidDispose = this.disposes.event;
  readonly onDidAppStart = this.starts.event;
  /** What the app writes. */
  app(text: string): void {
    this.outputs.fire({ bytes: Buffer.from(text), fromApp: true });
  }
  /** A line of the extension's. */
  say(text: string): void {
    this.outputs.fire({ bytes: Buffer.from(text), fromApp: false });
  }
}

const frame = (text: string) => `\x1b[?2026h${text}\x1b[?2026l`;

describe('showing a frame of the app in the log by the bytes the app wrote', () => {
  let clock: FakeClock;
  let panel: FakePanel<ToLog>;
  let screen: FakeScreen;

  beforeEach(() => {
    clock = new FakeClock();
    panel = new FakePanel<ToLog>();
    screen = new FakeScreen();
  });

  /** The frames of [log]'s entries, by name. */
  const frames = (log: LogPanel) => log.entries().filter((e) => e.kind === 'frame');

  it('tells the webview the frame where the app had written that many bytes, the extension\'s own lines not counted', () => {
    const traffic = new Traffic(screen, clock);
    screen.starts.fire(undefined);
    screen.say('twk: dart run counter.dart\r\n');
    const log = new LogPanel(screen, panel, clock, traffic);
    panel.send({ type: 'ready' });
    screen.app(frame('one'));
    screen.say('a line of ours');
    screen.app(frame('two'));
    const [one, two] = frames(log);
    const end1 = Buffer.byteLength(frame('one'));
    assert.deepEqual(log.revealAppBytes(end1), { found: true, dropped: false });
    assert.deepEqual(panel.posted.at(-1), { type: 'reveal', id: one.id });
    assert.deepEqual(log.revealAppBytes(end1 + Buffer.byteLength(frame('two'))), { found: true, dropped: false });
    assert.deepEqual(panel.posted.at(-1), { type: 'reveal', id: two.id });
  });

  it('counts a log opened after the app wrote as the one opened before: the bytes it wrote since the app took the screen', () => {
    const traffic = new Traffic(screen, clock);
    screen.starts.fire(undefined);
    screen.app(frame('one'));
    const log = new LogPanel(screen, panel, clock, traffic);
    screen.app(frame('two'));
    const [one, two] = frames(log);
    panel.send({ type: 'ready' });
    log.revealAppBytes(Buffer.byteLength(frame('one')));
    assert.deepEqual(panel.posted.at(-1), { type: 'reveal', id: one.id });
    log.revealAppBytes(Buffer.byteLength(frame('one')) + 1);
    assert.deepEqual(panel.posted.at(-1), { type: 'reveal', id: two.id });
  });

  it('counts a new app from its own start, and looks for the frame in its run', () => {
    const traffic = new Traffic(screen, clock);
    screen.starts.fire(undefined);
    screen.app(frame('old app'));
    screen.starts.fire(undefined);
    screen.app(frame('x'));
    const log = new LogPanel(screen, panel, clock, traffic);
    panel.send({ type: 'ready' });
    const [, fresh] = frames(log);
    log.revealAppBytes(Buffer.byteLength(frame('x')));
    assert.deepEqual(panel.posted.at(-1), { type: 'reveal', id: fresh.id });
  });

  it('counts an app that takes the screen while the log is open from its own start', () => {
    const log = new LogPanel(screen, panel, clock, new Traffic(screen, clock));
    panel.send({ type: 'ready' });
    screen.starts.fire(undefined);
    screen.app(frame('old app'));
    screen.starts.fire(undefined);
    screen.app(frame('x'));
    const [, fresh] = frames(log);
    log.revealAppBytes(Buffer.byteLength(frame('x')));
    assert.deepEqual(panel.posted.at(-1), { type: 'reveal', id: fresh.id });
  });

  it('shows it once the webview is up, where it was not', () => {
    const traffic = new Traffic(screen, clock);
    screen.starts.fire(undefined);
    screen.app(frame('one'));
    const log = new LogPanel(screen, panel, clock, traffic);
    assert.deepEqual(log.revealAppBytes(Buffer.byteLength(frame('one'))), { found: true, dropped: false });
    assert.equal(panel.posted.length, 0);
    panel.send({ type: 'ready' });
    assert.deepEqual(
      panel.posted.map((m) => m.type),
      ['reset', 'reveal'],
    );
  });

  it('says dropped, showing the first entry, where the traffic kept begins after the frame', () => {
    // room for the last frame only
    const traffic = new Traffic(screen, clock, Buffer.byteLength(frame('three')) + 1);
    screen.starts.fire(undefined);
    screen.app(frame('one'));
    screen.app(frame('two'));
    screen.app(frame('three'));
    const log = new LogPanel(screen, panel, clock, traffic);
    panel.send({ type: 'ready' });
    const [only] = frames(log);
    assert.equal(frames(log).length, 1);
    assert.deepEqual(log.revealAppBytes(Buffer.byteLength(frame('one'))), { found: true, dropped: true });
    assert.deepEqual(panel.posted.at(-1), { type: 'reveal', id: only.id });
    const all = Buffer.byteLength(frame('one')) + Buffer.byteLength(frame('two')) + Buffer.byteLength(frame('three'));
    assert.deepEqual(log.revealAppBytes(all), { found: true, dropped: false });
  });

  it('finds none where no app wrote to the screen', () => {
    const log = new LogPanel(screen, panel, clock, new Traffic(screen, clock));
    panel.send({ type: 'ready' });
    screen.say('twk: waiting');
    assert.deepEqual(log.revealAppBytes(10), { found: false, dropped: false });
    assert.equal(
      panel.posted.some((m) => m.type === 'reveal'),
      false,
    );
  });
});
