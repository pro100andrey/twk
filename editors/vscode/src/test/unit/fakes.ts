// Fakes of the ports (app/ports.ts) and of a VM service, for the unit tests
// of core/ and app/ under plain node.
import * as net from 'node:net';
import * as os from 'node:os';

import { fromVariable } from '../../core/address';
import { Answers, Choice, choiceOf } from '../../core/capabilities';
import { TerminalRequest } from '../../core/emulation';
import { Clock, Disposable, Emitter } from '../../core/events';
import { HotStatus } from '../../core/hot';
import { AppEvent, AppService, InspectTree } from '../../core/inspect';
import { SourceSpot } from '../../core/locator';
import { Switches, noSwitches } from '../../core/switches';
import { HotRunOptions } from '../../core/runner';
import { TerminalShell } from '../../core/shell';
import { ShellStarter } from '../../app/terminal';
import { WebviewPanelPort } from '../../app/webview_view';
import { PlayerControl, PlayerState, ToWebview } from '../../webview/protocol';
import { Vm, VmEvent } from '../../core/vm';
import { FrameReader, Wire, jsonFrame } from '../../core/wire';
import {
  InspectorView,
  Notice,
  PickingIndicator,
  SourceOpener,
  DartLaunch,
  DebugSession,
  Debugger,
  Desktop,
  Log,
  RunHandle,
  Settings,
  Snapshot,
  StatusSink,
  TerminalView,
} from '../../app/ports';

/** A view whose readiness the test decides ([open]), recording what it is told. */
export class FakeView implements TerminalView {
  columns = 100;
  lines = 30;
  title: string;
  readonly written: Buffer[] = [];
  readonly sizes: { columns: number | null; lines: number | null }[] = [];
  /** What it was told to answer, each time. */
  readonly answered: Answers[] = [];
  readonly ready: Promise<void>;
  private closed = false;
  private resolveReady!: () => void;
  private rejectReady!: (e: Error) => void;
  private readonly inputs = new Emitter<Uint8Array>();
  private readonly requests = new Emitter<TerminalRequest>();
  private readonly resizes = new Emitter<void>();
  private readonly closes = new Emitter<void>();
  private readonly reloads = new Emitter<void>();
  private readonly picks = new Emitter<{ x: number; y: number; cursorY: number } | null>();
  /** Whether a click picks, as it was told last. */
  picking = false;
  /** Whether it is the active one, as the test says. */
  isActive = false;
  /** The player's bar as it was told, each time. */
  readonly players: (PlayerState | null)[] = [];
  private readonly controls = new Emitter<PlayerControl>();
  readonly onControl = this.controls.event;
  readonly onPick = this.picks.event;
  readonly onInput = this.inputs.event;
  readonly onRequest = this.requests.event;
  readonly onResize = this.resizes.event;
  readonly onClose = this.closes.event;
  readonly onReload = this.reloads.event;

  constructor(title: string, readyAtOnce = true) {
    this.title = title;
    this.ready = new Promise((resolve, reject) => {
      this.resolveReady = resolve;
      this.rejectReady = reject;
    });
    this.ready.catch(() => {});
    if (readyAtOnce) {
      this.open();
    }
  }

  /** The view is up. */
  open(): void {
    this.resolveReady();
  }

  get isClosed(): boolean {
    return this.closed;
  }

  get text(): string {
    return Buffer.concat(this.written).toString('latin1');
  }

  write(bytes: Uint8Array): Promise<void> {
    if (!this.closed) {
      this.written.push(Buffer.from(bytes));
    }
    return Promise.resolve();
  }

  snapshot(): Promise<Snapshot> {
    return Promise.resolve({ buffer: 'normal', rows: this.closed ? [] : this.text.split('\r\n') });
  }

  fixSize(columns: number | null, lines: number | null): void {
    this.sizes.push({ columns, lines });
  }

  answer(answers: Answers): void {
    if (!this.closed) {
      this.answered.push(answers);
    }
  }

  pick(on: boolean): void {
    this.picking = on;
  }

  /** A click picks [cell] (null: Escape, which ends the picking), as the webview tells it, when picking. */
  picked(cell: { x: number; y: number; cursorY: number } | null): void {
    if (this.picking) {
      this.picking = cell !== null;
      this.picks.fire(cell);
    }
  }

  player(state: PlayerState | null): void {
    if (!this.closed) {
      this.players.push(state);
    }
  }

  /** A button of its player's bar is pressed. */
  control(c: PlayerControl): void {
    this.controls.fire(c);
  }

  /** The app in it asks [r] of the editor. */
  request(r: TerminalRequest): void {
    this.requests.fire(r);
  }

  setTitle(title: string): void {
    if (!this.closed) {
      this.title = title;
    }
  }

  reveal(): void {}

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.rejectReady(new Error('the twk terminal was closed before it was ready'));
    this.closes.fire();
  }

  /** Typed in the view. */
  type(text: string): void {
    this.inputs.fire(Buffer.from(text));
  }

  resize(columns: number, lines: number): void {
    this.columns = columns;
    this.lines = lines;
    this.resizes.fire();
  }

  /** Comes back empty at [columns] x [lines], as a webview that loaded again. */
  reload(columns: number, lines: number): void {
    this.columns = columns;
    this.lines = lines;
    this.written.length = 0;
    this.reloads.fire();
  }
}

/** A webview's panel that keeps what it was sent ([posted]) and sends what the test says ([send]). */
export class FakePanel<To = ToWebview> implements WebviewPanelPort<To> {
  readonly posted: To[] = [];
  title = '';
  disposed = false;
  active = false;
  readonly messages = new Emitter<unknown>();
  readonly disposes = new Emitter<void>();
  readonly onMessage = this.messages.event;
  readonly onDispose = this.disposes.event;
  async post(message: To): Promise<boolean> {
    this.posted.push(message);
    return !this.disposed;
  }
  setTitle(title: string): void {
    this.title = title;
  }
  reveal(): void {}
  dispose(): void {
    this.disposed = true;
    this.disposes.fire();
  }
  /** The webview sends [m]. */
  send(m: unknown): void {
    this.messages.fire(m);
  }
}

/** Starts core's shell on a real local socket, in the system's temporary directory. */
export const realShell: ShellStarter = (pane, serves) => TerminalShell.start(pane, { ...serves, temporaryRoot: os.tmpdir(), tcp: false });

export class FakeLog implements Log {
  text = '';
  append(text: string): void {
    this.text += text;
  }
  appendLine(line: string): void {
    this.text += `${line}\n`;
  }
}

export class FakeStatus implements StatusSink {
  readonly shown: HotStatus[] = [];
  show(status: HotStatus): void {
    this.shown.push(status);
  }
  get states(): HotStatus['state'][] {
    return this.shown.map((s) => s.state);
  }
}

export class FakeSettings implements Settings {
  profileName = 'xterm.js';
  /** The switches changed from the preset, as the setting twk.terminal.capabilities holds them. */
  changes: unknown = {};
  columns: number | null = null;
  lines: number | null = null;
  reloadOnSave = true;
  switchesOn: Switches = noSwitches;
  capabilities(): Choice {
    return choiceOf(this.profileName, this.changes);
  }
  switches(): Switches {
    return this.switchesOn;
  }
  size(): { columns: number | null; lines: number | null } {
    return { columns: this.columns, lines: this.lines };
  }
  hotReloadOnSave(): boolean {
    return this.reloadOnSave;
  }
}

/** What the editor was asked to do for the apps, in order. */
export class FakeDesktop implements Desktop {
  readonly done: string[] = [];
  notify(source: string, title: string, body: string): void {
    this.done.push(`notify ${source}: ${title} | ${body}`);
  }
  progress(_owner: object, source: string, state: number, percent: number | null): void {
    this.done.push(`progress ${source}: ${state} ${percent}`);
  }
  writeClipboard(text: string): void {
    this.done.push(`clipboard ${text}`);
  }
  openLink(uri: string): void {
    this.done.push(`open ${uri}`);
  }
}

/** A clock the test moves ([elapse]). */
export class FakeClock implements Clock {
  /** Milliseconds since it was made, as the test moved it. */
  time = 0;
  private timers: { at: number; f: () => void }[] = [];
  setTimeout(f: () => void, ms: number): Disposable {
    const timer = { at: this.time + ms, f };
    this.timers.push(timer);
    return { dispose: () => (this.timers = this.timers.filter((t) => t !== timer)) };
  }
  now(): number {
    return this.time;
  }
  get pending(): number {
    return this.timers.length;
  }
  elapse(ms: number): void {
    this.time += ms;
    const due = this.timers.filter((t) => t.at <= this.time);
    this.timers = this.timers.filter((t) => t.at > this.time);
    due.forEach((t) => t.f());
  }
}

/** A debugger whose sessions the test ends ([terminate]), and tells VM services of ([vmService]). */
export class FakeDebugger implements Debugger {
  readonly started: DartLaunch[] = [];
  readonly stopped: string[] = [];
  /** What [start] answers. */
  starts = true;
  /** When set, [stop] rejects with it. */
  stopFails: Error | undefined;
  /** Ends the session as the stop button does, when [stop] is called. */
  terminateOnStop = true;
  readonly began = new Emitter<DebugSession>();
  readonly vmServices = new Emitter<{ session: DebugSession; uri: string }>();
  readonly terminated = new Emitter<string>();
  readonly onStarted = this.began.event;
  readonly onVmService = this.vmServices.event;
  readonly onTerminated = this.terminated.event;
  private next = 0;
  readonly sessions: DebugSession[] = [];

  /** Starts a session as VS Code does: its tracker made, which tells that it started. */
  async start(launch: DartLaunch): Promise<boolean> {
    this.started.push(launch);
    if (this.starts) {
      const session = { id: `s${this.next++}`, configuration: launch };
      this.sessions.push(session);
      this.began.fire(session);
    }
    return this.starts;
  }

  /** Stops [session]; one that ended already is stopped no more, as VS Code's debugger has it no more. */
  async stop(session: DebugSession): Promise<void> {
    this.stopped.push(session.id);
    if (this.stopFails) {
      throw this.stopFails;
    }
    if (this.terminateOnStop && !this.ended.has(session.id)) {
      setImmediate(() => this.terminate(session.id));
    }
  }

  vmService(session: DebugSession, uri = 'ws://vm'): void {
    this.vmServices.fire({ session, uri });
  }

  private readonly ended = new Set<string>();

  terminate(id: string): void {
    if (!this.ended.has(id)) {
      this.ended.add(id);
      this.terminated.fire(id);
    }
  }
}

/** A run the test drives: what it was started with, what was asked of it. */
export class FakeRun implements RunHandle {
  readonly asked: string[] = [];
  pid = 4242;
  readonly ended: Promise<number | string>;
  end!: (r: number | string) => void;
  constructor(readonly options: HotRunOptions) {
    this.ended = new Promise((resolve) => (this.end = resolve));
  }
  async reload(): Promise<HotStatus> {
    this.asked.push('reload');
    const s: HotStatus = { state: 'reloaded', libraries: 1, ms: 1 };
    this.options.onStatus(s);
    return s;
  }
  async restart(): Promise<void> {
    this.asked.push('restart');
  }
  async stop(): Promise<void> {
    this.asked.push('stop');
    this.end(143);
    await this.ended;
  }
  async redraw(): Promise<void> {
    this.asked.push('redraw');
  }
}

/** A VM service with one isolate, `i/1`, that registered [extensions]. */
export class FakeVm implements Vm {
  readonly calls: string[] = [];
  readonly streams = new Map<string, (e: VmEvent) => void>();
  report: Record<string, unknown> = { type: 'ReloadReport', success: true, details: { loadedLibraryCount: 2 } };
  /** A reload in flight waits for this, when set. */
  gate: Promise<void> | undefined;
  /** When set, `getVM` fails with it. */
  getVmFails: Error | undefined;
  isClosed = false;
  private gone!: () => void;
  readonly closed = new Promise<void>((r) => (this.gone = r));
  constructor(public extensions: string[] = ['ext.twk.reassemble', 'ext.twk.log']) {}
  async call(method: string, params: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
    this.calls.push(method === 'ext.twk.log' ? `log ${String(params.level)} ${String(params.message)}` : method);
    switch (method) {
      case 'getVM':
        if (this.getVmFails) {
          throw this.getVmFails;
        }
        return { isolates: [{ id: 'i/1' }] };
      case 'getIsolate':
        return { extensionRPCs: this.extensions };
      case 'reloadSources':
        await this.gate;
        return this.report;
      default:
        return {};
    }
  }
  async listen(stream: string, f: (e: VmEvent) => void): Promise<void> {
    this.streams.set(stream, f);
  }
  close(): void {
    this.isClosed = true;
    this.gone();
  }
}

/** Waits until [f] holds, a turn of the event loop at a time, for at most [turns]. */
export async function until(what: string, f: () => boolean, turns = 2000): Promise<void> {
  for (let i = 0; !f(); i++) {
    if (i > turns) {
      throw new Error(`no ${what}`);
    }
    await new Promise((r) => setImmediate(r));
  }
}

/** An app's end: connects to the shell TWK_SHELL's value names, with its token, and reads frames. */
export class App {
  readonly frames: { type: number; payload: Buffer }[] = [];
  private waiters: (() => void)[] = [];
  constructor(readonly socket: net.Socket) {
    const reader = new FrameReader((type, payload) => {
      this.frames.push({ type, payload });
      this.waiters.splice(0).forEach((w) => w());
    });
    socket.on('data', (b) => reader.add(b));
  }
  static async connect(variable: string, token?: string): Promise<App> {
    const address = fromVariable(variable);
    if (!address?.where.startsWith('unix:')) {
      throw new Error(`no shell at ${variable}`);
    }
    const socket = net.connect(address.where.substring('unix:'.length));
    await new Promise((r) => socket.once('connect', r));
    const app = new App(socket);
    socket.write(jsonFrame(Wire.hello, { protocol: Wire.protocol, token: token ?? address.token }));
    return app;
  }
  async next(type: number): Promise<Buffer> {
    for (;;) {
      const i = this.frames.findIndex((f) => f.type === type);
      if (i >= 0) {
        return this.frames.splice(i, 1)[0].payload;
      }
      await new Promise<void>((r) => this.waiters.push(r));
    }
  }
}


type Answer = Record<string, unknown>;

/**
 * An app as an inspector asks of it: its service extensions answered by
 * [answers] (by method, a function of the parameters), its VM service by
 * [vmAnswers]; each call recorded; its events fired by the test.
 */
export class FakeAppService implements AppService {
  readonly calls: { method: string; params: Readonly<Record<string, unknown>> }[] = [];
  readonly answers = new Map<string, (params: Readonly<Record<string, string>>) => Answer>();
  vmAnswers: (method: string, params: Readonly<Record<string, unknown>>) => Answer = () => ({});
  private readonly events = new Emitter<AppEvent>();
  readonly onEvent = this.events.event;
  private gone!: () => void;
  readonly closed = new Promise<void>((r) => (this.gone = r));
  bound = true;

  async extension(method: string, params: Readonly<Record<string, string>> = {}): Promise<Answer> {
    this.calls.push({ method, params });
    const answer = this.answers.get(method);
    if (!answer) {
      throw new Error(`no ${method}`);
    }
    return answer(params);
  }

  async vm(method: string, params: Readonly<Record<string, unknown>> = {}): Promise<Answer> {
    this.calls.push({ method, params });
    return this.vmAnswers(method, params);
  }

  /** The service extensions called, with their parameters, as `method k=v`. */
  get asked(): string[] {
    return this.calls
      .filter((c) => c.method.startsWith('ext.twk.'))
      .map((c) => [c.method, ...Object.entries(c.params).map(([k, v]) => `${k}=${String(v)}`)].join(' '));
  }

  /** The app posts [name] with [data]. */
  post(name: string, data: unknown = {}): void {
    this.events.fire({ kind: 'extension', name, data });
  }

  /** Its binding comes. */
  bind(): void {
    this.bound = true;
    this.events.fire({ kind: 'bound' });
  }

  /** A hot reload of it is done. */
  reloaded(): void {
    this.events.fire({ kind: 'reloaded' });
  }

  /** The app goes away. */
  end(): void {
    this.gone();
  }
}

/** An inspector's view that records what it is told to show and reveal. */
export class FakeInspectorView implements InspectorView {
  visible = true;
  tree: InspectTree | undefined;
  message = '';
  readonly shown: (InspectTree | undefined)[] = [];
  readonly revealed: number[] = [];
  private readonly visibility = new Emitter<boolean>();
  private readonly selections = new Emitter<number | undefined>();
  readonly onVisible = this.visibility.event;
  readonly onSelect = this.selections.event;

  show(tree: InspectTree | undefined, message: string): void {
    this.tree = tree;
    this.message = message;
    this.shown.push(tree);
  }

  reveal(id: number): void {
    this.revealed.push(id);
    this.selected = id;
  }

  /** Comes on the screen, or goes. */
  setVisible(on: boolean): void {
    this.visible = on;
    this.visibility.fire(on);
  }

  /** The node selected, as the view was told and the person did. */
  selected: number | undefined;

  /** The person selects [id]. */
  select(id: number | undefined): void {
    this.selected = id;
    this.selections.fire(id);
  }

  clearSelection(): void {
    this.selected = undefined;
  }
}

export class FakeOpener implements SourceOpener {
  readonly opened: SourceSpot[] = [];
  /** Whether each was opened with the focus kept. */
  readonly keptFocus: boolean[] = [];
  async open(spot: SourceSpot, options?: { readonly keepFocus?: boolean }): Promise<void> {
    this.opened.push(spot);
    this.keptFocus.push(options?.keepFocus === true);
  }
}

/** The pick mode's button, each time it was shown. */
export class FakePickingIndicator implements PickingIndicator {
  readonly shown: boolean[] = [];
  get on(): boolean {
    return this.shown.at(-1) ?? false;
  }
  show(on: boolean): void {
    this.shown.push(on);
  }
}

/** The messages said to the person. */
export class FakeNotice implements Notice {
  readonly said: string[] = [];
  say(text: string): void {
    this.said.push(text);
  }
}

/** An answer of `ext.twk.tree` as twk gives it (service_extensions_test.dart's app). */
export const treeAnswer = {
  version: 1,
  tree: 'element',
  app: 3,
  root: {
    id: 1,
    name: 'RootWidget',
    properties: [],
    flags: [],
    render: 9,
    children: [
      {
        id: 2,
        name: '_Count',
        key: '[GlobalKey#1]',
        properties: [],
        size: { width: 20, height: 3 },
        flags: ['needsBuild'],
        build: '_CountState',
        children: [
          {
            id: 3,
            name: 'Padding',
            properties: [{ name: 'padding', value: 'left 2' }],
            flags: [],
            render: 10,
            children: [{ id: 4, name: 'Text', properties: [{ value: '"n 0"' }], size: { width: 3, height: 1 }, flags: [], render: 11, children: [] }],
          },
        ],
      },
    ],
  },
};
