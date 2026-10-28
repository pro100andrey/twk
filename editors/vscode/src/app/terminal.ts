// A twk terminal: a [TerminalView] that a [TerminalShell] of its own
// serves, to the app of one run or debug session (or, opened by itself,
// to an app started anywhere with its TWK_SHELL). Its title says what it
// is for, the size, the capabilities, the switches on and whether an app
// has it. As each app is taken it is welcomed with what the settings'
// capabilities make of the environment and of what the terminal declares,
// and its view answers and emulates as they say; what the app asks of the
// editor through it (a notification, progress, the clipboard, a link) goes
// to the [Desktop].
import { Answers, answersOf, declarationOf, describeChoice, environmentOf } from '../core/capabilities';
import { TerminalRequest, isSafeLink } from '../core/emulation';
import { Disposable, Emitter } from '../core/events';
import { ShellOptions, TerminalPane, TerminalShell, Welcome } from '../core/shell';
import { describeSwitches, switchEnvironment } from '../core/switches';
import { Desktop, Log, Output, PickedCell, Screen, Settings, Snapshot, TerminalView } from './ports';

/** What a twk terminal gives its shell: what an app is welcomed with, and what follows from an app's coming and going. */
export type ShellServes = Pick<ShellOptions, 'welcome' | 'onEvent'>;

/** Starts a shell serving [pane]: core's TerminalShell.start with the platform's options, or a fake. */
export type ShellStarter = (pane: TerminalPane, serves: ShellServes) => Promise<TerminalShell>;

export interface TerminalDeps {
  readonly view: TerminalView;
  readonly startShell: ShellStarter;
  readonly settings: Settings;
  readonly log: Log;
  readonly desktop: Desktop;
}

export class TwkTerminal implements TerminalPane, Screen {
  shell: TerminalShell | undefined;
  readonly view: TerminalView;
  private disposing: Promise<void> | undefined;
  private readonly disposed = new Emitter<void>();
  /** Fires once it was disposed: closed, its shell stopped. */
  readonly onDidDispose = this.disposed.event;
  private readonly inputs = new Emitter<Uint8Array>();
  /** What the terminal sends, keys and answers alike: whether an app has it or not. */
  readonly onDidInput = this.inputs.event;
  private readonly outputs = new Emitter<Output>();
  /** What was written to its view: the app's bytes (the lost ones too), or a line of the extension's. */
  readonly onDidOutput = this.outputs.event;
  private readonly notes = new Emitter<string>();
  /** An app came or went, its size changed: said for the sequence log. */
  readonly onDidNote = this.notes.event;
  private readonly resizes = new Emitter<void>();
  /** Its view's size changed. */
  readonly onDidResize = this.resizes.event;
  /** Whether a line written now is the extension's ([say]), not the app's. */
  private saying = false;
  /** Whether its session is recorded: its title says so. */
  private recorded = false;
  private readonly reloads = new Emitter<void>();
  /** Its view came back empty; the app was told the size again, and is to paint all of itself. */
  readonly onDidReload = this.reloads.event;
  private readonly picks = new Emitter<PickedCell | null>();
  /** A click on its view picked a cell, or (null) the pick ended with none ([pick]). */
  readonly onDidPick = this.picks.event;
  private readonly listening: Disposable[];
  /** What its view answers for the app taken last: given again to a view that came back empty. */
  private answering: Answers | undefined;

  constructor(
    /** What it is for: the file of the app it runs, or "twk". */
    readonly name: string,
    private readonly deps: TerminalDeps,
  ) {
    this.view = deps.view;
    this.listening = [
      this.view.onInput((bytes) => {
        this.inputs.fire(bytes);
        this.shell?.input(bytes);
      }),
      this.view.onResize(() => {
        this.shell?.resized();
        this.retitle();
        this.notes.fire(`size ${this.columns}x${this.lines}`);
        this.resizes.fire();
      }),
      this.view.onRequest((r) => this.request(r)),
      this.view.onPick((cell) => this.picks.fire(cell)),
      this.view.onReload(() => {
        // the new view knows neither the size fixed for it nor what it
        // showed, nor what to answer
        if (this.answering) {
          this.view.answer(this.answering);
        }
        this.applySize();
        this.retitle();
        this.shell?.resized();
        this.reloads.fire();
      }),
      this.view.onClose(() => void this.dispose()),
    ];
  }

  get columns(): number {
    return this.view.columns;
  }

  get lines(): number {
    return this.view.lines;
  }

  /** Whether its view was closed. */
  get isClosed(): boolean {
    return this.view.isClosed;
  }

  /** Its shell's address, as TWK_SHELL in an app's environment holds it; once started. */
  get variable(): string {
    if (!this.shell) {
      throw new Error('the twk terminal serves nothing yet');
    }
    return this.shell.variable;
  }

  reveal(): void {
    this.view.reveal();
  }

  /** The title for its view now. */
  title(): string {
    const app = this.shell?.serving ? '' : ' (waiting)';
    const switches = describeSwitches(this.deps.settings.switches());
    const on = switches === '' ? '' : ` + ${switches}`;
    const recording = this.recorded ? ' · ● recording' : '';
    return `${this.name} · twk ${this.columns}x${this.lines} · ${describeChoice(this.deps.settings.capabilities())}${on}${app}${recording}`;
  }

  /** Has its title say it is recorded, or not. */
  setRecorded(on: boolean): void {
    this.recorded = on;
    this.retitle();
  }

  /** Titles its view as it is now (the settings' capabilities and switches among it). */
  retitle(): void {
    this.view.setTitle(this.title());
  }

  /** Starts serving, once the view told its size. */
  async start(): Promise<void> {
    await this.view.ready;
    this.applySize();
    this.retitle();
    this.shell = await this.deps.startShell(this, {
      welcome: () => this.welcome(),
      onEvent: (event) => {
        const said = event === 'connected' ? 'an app connected' : 'the app went away';
        this.deps.log.appendLine(`twk terminal ${this.name}: ${said}`);
        this.notes.fire(event === 'connected' ? `${said}, welcomed at ${this.columns}x${this.lines}` : said);
        if (event === 'disconnected') {
          this.say('\r\n\x1b[2mtwk: the app went away\x1b[0m\r\n');
          // its progress goes with it
          this.deps.desktop.progress(this, this.name, 0, null);
        }
        this.retitle();
      },
    });
    if (this.isClosed) {
      await this.dispose();
      throw new Error('the twk terminal was closed before it was ready');
    }
  }

  /**
   * An app is taken: its view set to answer and emulate as the settings'
   * capabilities say, before the app's first bytes reach it, and what the
   * app is welcomed with: their environment with the switches' settings
   * over it, and what they declare.
   */
  private welcome(): Welcome {
    const { capabilities } = this.deps.settings.capabilities();
    this.answering = answersOf(capabilities);
    this.view.answer(this.answering);
    return {
      environment: { ...environmentOf(capabilities), ...switchEnvironment(this.deps.settings.switches()) },
      declares: declarationOf(capabilities),
    };
  }

  /** What the app asked of the editor, as its view passed it on; a link only of the kinds that may be opened, whatever the view says. */
  private request(r: TerminalRequest): void {
    const { desktop } = this.deps;
    switch (r.type) {
      case 'notify':
        desktop.notify(this.name, r.title, r.body);
        break;
      case 'progress':
        desktop.progress(this, this.name, r.state, r.percent);
        break;
      case 'clipboard':
        desktop.writeClipboard(r.text);
        break;
      case 'openLink':
        if (isSafeLink(r.uri)) {
          desktop.openLink(r.uri);
        }
        break;
    }
  }

  /** Has each click on its view pick a cell ([onDidPick]) in place of reaching the app, until told off or Escape; or not. */
  pick(on: boolean): void {
    if (!this.isClosed) {
      this.view.pick(on);
    }
  }

  /** Writes a line of the extension's to the terminal (dim). */
  say(text: string): void {
    this.saying = true;
    try {
      this.shell?.say(text);
    } finally {
      this.saying = false;
    }
  }

  /** Applies the size the settings fix, or fits the view. */
  applySize(): void {
    const { columns, lines } = this.deps.settings.size();
    this.view.fixSize(columns, lines);
  }

  write(bytes: Uint8Array): Promise<void> {
    this.outputs.fire({ bytes, fromApp: !this.saying });
    return this.view.write(bytes);
  }

  snapshot(): Promise<Snapshot> {
    return this.view.snapshot();
  }

  /** Types [text] as if from the keyboard: what its view sends. */
  type(text: string): void {
    const bytes = Buffer.from(text, 'utf8');
    this.inputs.fire(bytes);
    this.shell?.input(bytes);
  }

  /** Stops serving and closes the view; once, however often it is called. */
  dispose(): Promise<void> {
    this.disposing ??= this.disposeOnce();
    return this.disposing;
  }

  private async disposeOnce(): Promise<void> {
    this.view.close();
    this.listening.forEach((d) => d.dispose());
    await this.shell?.stop();
    this.shell = undefined;
    this.disposed.fire();
    this.disposed.dispose();
    [this.inputs, this.reloads, this.picks, this.outputs, this.notes, this.resizes].forEach((e) => e.dispose());
  }
}
