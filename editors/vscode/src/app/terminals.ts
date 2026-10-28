// The twk terminals open: one per run or debug session, each with a shell
// of its own, opened on demand and forgotten once closed.
import { shellVariable } from '../core/address';
import { Emitter } from '../core/events';
import { Desktop, Log, Settings, TerminalViewFactory } from './ports';
import { ShellStarter, TwkTerminal } from './terminal';

export interface TerminalsDeps {
  readonly views: TerminalViewFactory;
  readonly startShell: ShellStarter;
  readonly settings: Settings;
  readonly log: Log;
  readonly desktop: Desktop;
}

export class Terminals {
  private readonly open = new Set<TwkTerminal>();
  private readonly creations = new Emitter<TwkTerminal>();
  /** A terminal was made: before it serves, before anything was written to it. */
  readonly onDidCreate = this.creations.event;

  constructor(private readonly deps: TerminalsDeps) {}

  /** The terminals open now, the oldest first. */
  all(): TwkTerminal[] {
    return [...this.open];
  }

  /** A new terminal for [name] (the file of the app it is for), serving once it settles. */
  async create(name: string): Promise<TwkTerminal> {
    const { views, startShell, settings, log, desktop } = this.deps;
    const t = new TwkTerminal(name, { view: views(`${name} · twk (starting)`), startShell, settings, log, desktop });
    this.open.add(t);
    t.onDidDispose(() => this.open.delete(t));
    this.creations.fire(t);
    try {
      await t.start();
    } catch (e) {
      await t.dispose();
      throw e;
    }
    return t;
  }

  /**
   * A terminal for an app started anywhere (a shell, a task) with its
   * TWK_SHELL, which the terminal shows: no project's address file names it.
   */
  async createForAnyApp(): Promise<TwkTerminal> {
    const t = await this.create('twk');
    t.say(`\x1b[2mtwk: an app with no terminal of its own takes this one with ${shellVariable} in its environment:\x1b[0m\r\n`);
    t.say(`${shellVariable}='${t.variable}'\r\n`);
    return t;
  }

  /** Titles each as it is now: the settings' capabilities or switches changed. */
  retitle(): void {
    this.open.forEach((t) => t.retitle());
  }

  /** Applies the size of the settings to each. */
  applySize(): void {
    this.open.forEach((t) => t.applySize());
  }

  async dispose(): Promise<void> {
    this.creations.dispose();
    await Promise.all([...this.open].map((t) => t.dispose()));
  }
}
