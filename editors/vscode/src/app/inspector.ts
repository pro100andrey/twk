// The twk inspector: the widget tree of the app the extension runs or
// debugs, over the extension's own VM service connection to it ([AppService],
// HotApp), in a view ([InspectorView]). The tree follows the app: while
// the view is on the screen the app tells when its tree changed
// (`ext.twk.flags` `treeEvents`, the event `twk.treeChanged` at most once
// a frame), and the tree is asked again at most every [refreshGap] ms;
// after a hot reload, and for the new app of a restart, at once. A
// node selected is outlined on the app (`ext.twk.highlight`), and only
// that, so the tree can be browsed; a node leads to where its widget was
// made, or to the build method that makes its child ([SourceLocator]).
// The pick mode, a toggle as Flutter's Select Widget Mode: while it is on,
// each click on the app's terminal (the app's own pick, `select` with
// `selectMany`, or the webview's where the app can't: the inline mode)
// picks the widget under it, which is selected, outlined and opened where
// it was made, the build method above it where that is not found; off (the
// toggle, Escape in the terminal), the outline and the selection go. It
// is the terminal's: the app of a hot restart picks on, an app that ended
// picks no more. The debug aids drawn over the app are switched, kept for
// the next app of the same terminal (a restart) too.
import { Disposable, Event } from '../core/events';
import {
  AppService,
  Flags,
  InspectNode,
  InspectTree,
  Toggle,
  flagParams,
  nodeOf,
  parseFlags,
  parsePicked,
  parseSelect,
  parseTree,
  pathTo,
} from '../core/inspect';
import { SourceLocator, SourceSpot } from '../core/locator';
import { AppConnection } from './hot_apps';
import { Cell, Clock, InspectorView, Log, Notice, PickedCell, PickingIndicator, SourceOpener } from './ports';
import { TwkTerminal } from './terminal';

/** The least time between two askings of the tree that its changes cause. */
export const refreshGap = 250;

/** What the tree view says while no app is there to inspect. */
export const noApp = 'No twk app runs: Run or Debug one in a twk terminal (twk: Run Dart File in twk Terminal, or F5).';

export interface InspectorDeps {
  /** The apps' VM services as they come and go (HotApps.onApp). */
  readonly apps: Event<AppConnection>;
  readonly view: InspectorView;
  readonly opener: SourceOpener;
  /** The pick mode's button. */
  readonly picking: PickingIndicator;
  /** Where a pick says what it could not open. */
  readonly notice: Notice;
  readonly clock: Clock;
  readonly log: Log;
}

/** How an app picks while the pick mode is on: by itself, picking on until told off; or by its terminal's clicks. */
type PickBy = 'many' | 'terminal';

/** An app inspected: its terminal, its service, and what was read of its code. */
interface Target {
  readonly terminal: TwkTerminal;
  readonly service: AppService;
  readonly locator: SourceLocator;
  readonly listening: Disposable[];
  /** How it picks, while the pick mode is on in its terminal and it was told. */
  pickBy?: PickBy;
}

export class Inspector {
  /** The apps there, the newest last. */
  private readonly targets: Target[] = [];
  /** The app the view shows. */
  private current: Target | undefined;
  /** The tree the view shows, of [current]. */
  tree: InspectTree | undefined;
  /** The debug aids switched here, by terminal: given again to the next app in it. */
  private readonly wanted = new Map<TwkTerminal, Partial<Record<Toggle, boolean>>>();
  /** The terminal the pick mode is on in: its app's, and the next app's of a restart. */
  private pickingIn: TwkTerminal | undefined;
  /** What the pick mode's button shows. */
  private shownPicking = false;
  private refreshTimer: Disposable | undefined;
  /** The asking of the tree in flight, the latest; one asked meanwhile waits for it. */
  private asking = 0;
  private readonly listening: Disposable[];

  constructor(private readonly deps: InspectorDeps) {
    this.listening = [
      deps.apps((c) => this.connected(c)),
      deps.view.onVisible((on) => {
        if (this.current) {
          void this.followTree(this.current, on);
        }
        if (on) {
          void this.refresh();
        }
      }),
      deps.view.onSelect((id) => void this.highlight(id)),
    ];
    deps.view.show(undefined, noApp);
    deps.picking.show(false);
  }

  /** Whether the pick mode is on, its button pressed: for an app there to pick in. */
  get picking(): boolean {
    return this.shownPicking;
  }

  /** The terminal of the app the view shows. */
  get terminal(): TwkTerminal | undefined {
    return this.current?.terminal;
  }

  private connected({ terminal, service }: AppConnection): void {
    const old = this.targets.find((t) => t.terminal === terminal);
    if (old) {
      this.drop(old);
    }
    if (!service) {
      return;
    }
    const target: Target = { terminal, service, locator: new SourceLocator(service), listening: [] };
    target.listening.push(
      service.onEvent((e) => {
        if (e.kind === 'bound') {
          // its binding came after its VM service: told now what it was to be told
          void this.started(target);
          if (target === this.current) {
            if (this.deps.view.visible) {
              void this.followTree(target, true);
            }
            void this.refresh();
          }
        } else if (e.kind === 'reloaded') {
          target.locator.forget();
          if (target === this.current) {
            void this.refresh();
          }
        } else if (e.name === 'twk.treeChanged' && target === this.current) {
          this.refreshSoon();
        } else if (e.name === 'twk.select') {
          const cell = parsePicked(e.data);
          if (cell) {
            void this.picked(target, cell);
          } else if (cell === null && this.pickingIn === terminal) {
            // Escape in the terminal
            void this.stopPicking();
          }
        }
      }),
      terminal.onDidPick((cell) => {
        if (cell) {
          void this.picked(target, cell);
        } else if (this.pickingIn === terminal) {
          void this.stopPicking();
        }
      }),
    );
    this.targets.push(target);
    void service.closed.then(() => this.drop(target));
    if (service.bound) {
      void this.started(target);
    }
    this.show(target);
  }

  /** A new app: the aids switched for its terminal given again, and the pick mode. */
  private async started(target: Target): Promise<void> {
    if (this.pickingIn === target.terminal) {
      void this.arm(target);
    }
    const wanted = this.wanted.get(target.terminal);
    if (!wanted || !Object.keys(wanted).length) {
      return;
    }
    try {
      await target.service.extension('ext.twk.flags', flagParams(wanted));
    } catch (e) {
      this.deps.log.appendLine(`twk inspector: the debug aids not set again: ${String(e)}`);
    }
  }

  private drop(target: Target): void {
    const i = this.targets.indexOf(target);
    if (i < 0) {
      return;
    }
    this.targets.splice(i, 1);
    target.listening.forEach((d) => d.dispose());
    if (target.terminal === this.pickingIn) {
      // the app ended, or restarts: the next app of its terminal picks on
      if (target.pickBy === 'terminal') {
        target.terminal.pick(false);
      }
      if (target.terminal.isClosed) {
        this.pickingIn = undefined;
      }
      this.indicate(false);
    }
    if (target === this.current) {
      this.current = undefined;
      const next = this.targets.at(-1);
      if (next) {
        this.show(next);
      } else {
        this.tree = undefined;
        this.refreshTimer?.dispose();
        this.refreshTimer = undefined;
        this.deps.view.show(undefined, noApp);
      }
    }
  }

  /** Shows [target]'s tree from now on. */
  private show(target: Target): void {
    if (target === this.current) {
      return;
    }
    const before = this.current;
    this.current = target;
    if (this.deps.view.visible) {
      if (before) {
        void this.followTree(before, false);
      }
      void this.followTree(target, true);
    }
    void this.refresh();
  }

  /** Has the app tell when its tree changed, or not. */
  private async followTree(target: Target, on: boolean): Promise<void> {
    if (!target.service.bound) {
      // told once it is
      return;
    }
    try {
      await target.service.extension('ext.twk.flags', flagParams({ treeEvents: on }));
    } catch {
      // gone, or not yet there: the next app is told as it comes
    }
  }

  private refreshSoon(): void {
    this.refreshTimer ??= this.deps.clock.setTimeout(() => {
      this.refreshTimer = undefined;
      void this.refresh();
    }, refreshGap);
  }

  /** Asks the app shown for its tree again, and shows it. */
  async refresh(): Promise<InspectTree | undefined> {
    const target = this.current;
    if (!target) {
      this.tree = undefined;
      this.deps.view.show(undefined, noApp);
      return undefined;
    }
    const asked = ++this.asking;
    if (!target.service.bound) {
      // asked again once it is
      this.tree = undefined;
      this.deps.view.show(undefined, 'The app is starting.');
      return undefined;
    }
    try {
      const tree = parseTree(await target.service.extension('ext.twk.tree'));
      // an asking that came after it, or another app, wins
      if (asked === this.asking && target === this.current) {
        this.tree = tree;
        this.deps.view.show(tree, tree.root ? '' : 'The app has drawn no frame yet.');
        if (!tree.root) {
          // its first frame may come before it was told to say so
          this.refreshSoon();
        }
      }
      return tree;
    } catch (e) {
      if (asked === this.asking && target === this.current) {
        this.tree = undefined;
        this.deps.view.show(undefined, `The app's tree: ${e instanceof Error ? e.message : String(e)}`);
      }
      return undefined;
    }
  }

  /** Outlines the node [id] on the app shown, or [target]'s; none for undefined. */
  async highlight(id: number | undefined, target = this.current): Promise<void> {
    try {
      await target?.service.extension('ext.twk.highlight', id === undefined ? {} : { id: String(id) });
    } catch {
      // gone from the tree, or the app
    }
  }

  /**
   * Turns the pick mode on, in the terminal of the app shown: each click
   * on it picks the widget under it, which is selected, outlined and
   * opened where it was made, until [stopPicking] or Escape in the
   * terminal. The app picks itself (`select`, `selectMany`: the node under
   * the mouse outlined between the clicks), or where it can't (the inline
   * mode) the terminal's clicks do.
   */
  async pick(): Promise<void> {
    const target = this.current;
    if (!target) {
      throw new Error(noApp);
    }
    if (this.pickingIn === target.terminal) {
      return;
    }
    await this.stopPicking();
    this.pickingIn = target.terminal;
    target.terminal.reveal();
    await this.arm(target);
  }

  /** Turns the pick mode off: the app picks no more, its outline and the view's selection gone. */
  async stopPicking(): Promise<void> {
    const terminal = this.pickingIn;
    if (!terminal) {
      return;
    }
    this.pickingIn = undefined;
    this.indicate(false);
    terminal.pick(false);
    this.deps.view.clearSelection();
    const target = this.targets.find((t) => t.terminal === terminal);
    if (!target) {
      return;
    }
    const itself = target.pickBy !== 'terminal';
    target.pickBy = undefined;
    if (itself) {
      try {
        await target.service.extension('ext.twk.flags', { select: 'false', selectMany: 'false' });
      } catch {
        // gone
      }
    }
    await this.highlight(undefined, target);
  }

  /** Has [target]'s app pick, the pick mode being on in its terminal. */
  private async arm(target: Target): Promise<void> {
    if (!target.service.bound) {
      // armed once it is (started)
      return;
    }
    this.indicate(true);
    let pickBy: PickBy = 'terminal';
    try {
      const flags = parseFlags(await target.service.extension('ext.twk.flags', { selectMany: 'true', select: 'true' }));
      pickBy = flags.select ? 'many' : 'terminal';
    } catch {
      // an app that can't: the terminal picks
    }
    if (this.pickingIn !== target.terminal || !this.targets.includes(target)) {
      // turned off, or gone, meanwhile
      if (pickBy !== 'terminal') {
        await target.service.extension('ext.twk.flags', { select: 'false', selectMany: 'false' }).catch(() => {});
      }
      return;
    }
    target.pickBy = pickBy;
    if (pickBy === 'terminal') {
      target.terminal.pick(true);
    }
  }

  private indicate(on: boolean): void {
    if (on !== this.shownPicking) {
      this.shownPicking = on;
      this.deps.picking.show(on);
    }
  }

  /**
   * The widget at [cell] of [target]'s app: shown, selected, outlined, and opened where it was made.
   * A cell of the app's own pick is of its screen; one the terminal picked
   * is of the terminal's, which an inline app's region is a part of, so it
   * goes with the cursor's row, which twk finds the region by.
   */
  private async picked(target: Target, cell: Cell | PickedCell): Promise<number | undefined> {
    this.show(target);
    try {
      const at = { x: String(cell.x), y: String(cell.y), ...('cursorY' in cell ? { cursorY: String(cell.cursorY) } : {}) };
      const { id } = parseSelect(await target.service.extension('ext.twk.select', at));
      if (id === null) {
        return undefined;
      }
      const tree = this.tree && nodeOf(this.tree, id) ? this.tree : await this.refresh();
      const node = tree && nodeOf(tree, id);
      if (tree && node && target === this.current) {
        this.deps.view.reveal(id);
        await this.highlight(id);
        await this.openPicked(target, tree, node);
        return id;
      }
    } catch (e) {
      this.deps.log.appendLine(`twk inspector: the pick at ${cell.x}, ${cell.y}: ${String(e)}`);
    }
    return undefined;
  }

  /** The debug aids of the app shown. */
  async flags(): Promise<Flags> {
    const target = this.current;
    if (!target) {
      throw new Error(noApp);
    }
    return parseFlags(await target.service.extension('ext.twk.flags'));
  }

  /** Switches the debug aids [changes] of the app shown, and of the next app of its terminal. */
  async setFlags(changes: Readonly<Partial<Record<Toggle, boolean>>>): Promise<Flags> {
    const target = this.current;
    if (!target) {
      throw new Error(noApp);
    }
    this.wanted.set(target.terminal, { ...this.wanted.get(target.terminal), ...changes });
    return parseFlags(await target.service.extension('ext.twk.flags', flagParams(changes)));
  }

  /** Opens where the widget of the node [id] was made. */
  async goToSource(id: number): Promise<SourceSpot> {
    const { target, tree, node } = this.nodeShown(id);
    const spot = await this.creation(target, tree, node);
    await this.deps.opener.open(spot);
    this.sayGuessed(node, spot);
    return spot;
  }

  /** Where the widget of [node] was made; an error saying why where that is not found. */
  private async creation(target: Target, tree: InspectTree, node: InspectNode): Promise<SourceSpot> {
    const spot = await target.locator.creation(tree.root, node.id, node.name);
    if (!spot) {
      throw new Error(`no call of ${node.name}'s constructor found in the build methods above it`);
    }
    return spot;
  }

  /** Says that [spot] is one of several calls that may have made [node]'s widget, where it is. */
  private sayGuessed(node: InspectNode, spot: SourceSpot): void {
    if (!spot.exact) {
      this.deps.notice.say(`twk: one of several ${node.name}s made in ${spot.method}`);
    }
  }

  /**
   * Opens where the widget of [node], picked, was made, the focus left in
   * the terminal for the next pick; where that is not found, the build
   * method nearest above it (its own first), saying why.
   */
  private async openPicked(target: Target, tree: InspectTree, node: InspectNode): Promise<void> {
    let why: string;
    try {
      const spot = await this.creation(target, tree, node);
      await this.deps.opener.open(spot, { keepFocus: true });
      this.sayGuessed(node, spot);
      return;
    } catch (e) {
      why = e instanceof Error ? e.message : String(e);
    }
    const build = pathTo(tree.root, node.id)
      ?.reverse()
      .find((n) => n.build !== undefined)?.build;
    const spot = build === undefined ? undefined : await target.locator.buildMethod(build).catch(() => undefined);
    if (spot) {
      await this.deps.opener.open(spot, { keepFocus: true });
      this.deps.notice.say(`twk: where ${node.name} was made is not known (${why}): ${spot.method} opened`);
    } else {
      this.deps.notice.say(`twk: where ${node.name} was made is not known: ${why}`);
    }
  }

  /** Opens the build method that makes the child of the node [id]: its widget's, its state's. */
  async goToBuild(id: number): Promise<SourceSpot> {
    const { target, node } = this.nodeShown(id);
    if (!node.build) {
      throw new Error(`${node.name} has no build method of its own`);
    }
    const spot = await target.locator.buildMethod(node.build);
    if (!spot) {
      throw new Error(`${node.build}.build not found in the app's code`);
    }
    await this.deps.opener.open(spot);
    return spot;
  }

  private nodeShown(id: number) {
    const target = this.current;
    const tree = this.tree;
    const node = tree && nodeOf(tree, id);
    if (!target || !tree || !node) {
      throw new Error('that node is in the tree no more: refresh it');
    }
    return { target, tree, node };
  }

  dispose(): void {
    this.listening.forEach((d) => d.dispose());
    this.refreshTimer?.dispose();
    this.refreshTimer = undefined;
    [...this.targets].forEach((t) => this.drop(t));
  }
}
