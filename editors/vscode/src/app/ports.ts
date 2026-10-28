// What the use cases of app/ need from the editor, as small interfaces
// (ports): vscode/ implements them with the VS Code API, the unit tests
// with fakes. Nothing here imports vscode.
import { Answers, Choice } from '../core/capabilities';
import { TerminalRequest } from '../core/emulation';
import { Clock, Event } from '../core/events';
import { HotStatus } from '../core/hot';
import { InspectTree } from '../core/inspect';
import { SourceSpot } from '../core/locator';
import { HotRunOptions } from '../core/runner';
import { Switches } from '../core/switches';
import { PlayerControl, PlayerState, ScreenBuffer } from '../webview/protocol';

/** A cell of a terminal's screen, from 0 at the top left. */
export interface Cell {
  readonly x: number;
  readonly y: number;
}

/**
 * A cell a click on a terminal picked, and the row its cursor was on then
 * (`cursorY`, in the rows `y` counts): what tells where an inline app's
 * region is on the screen, its rows being counted from its first.
 */
export interface PickedCell extends Cell {
  readonly cursorY: number;
}

/** What a terminal shows, row by row. */
export interface Snapshot {
  readonly buffer: ScreenBuffer;
  readonly rows: readonly string[];
  /** Each row's cells, `#` for one of a background of its own (an outline's), a space for the terminal's: where the view tells. */
  readonly backgrounds?: readonly string[];
}

/**
 * A terminal on the screen (a webview with xterm.js): bytes in, keys and
 * sizes out. It may be closed by the person at any time; then it takes no
 * more, and what it was asked settles at once.
 */
export interface TerminalView {
  readonly columns: number;
  readonly lines: number;
  /** Settles once the view is up and told its size; rejects when it was closed before. */
  readonly ready: Promise<void>;
  readonly isClosed: boolean;
  /** Whether it is the editor's active one (its panel focused, or the last focused). */
  readonly isActive: boolean;
  /** Settles once the view parsed [bytes], or at once when it is closed. */
  write(bytes: Uint8Array): Promise<void>;
  /** What it shows; empty once it is closed. */
  snapshot(): Promise<Snapshot>;
  /** Fixes its size, or (null) fits it to its space. */
  fixSize(columns: number | null, lines: number | null): void;
  /** What it answers and emulates beside xterm.js from now on (for the app taken now). */
  answer(answers: Answers): void;
  setTitle(title: string): void;
  reveal(): void;
  /** Closes it, as the person closing its tab. */
  close(): void;
  /** What is typed in it, keys and terminal answers alike. */
  readonly onInput: Event<Uint8Array>;
  /** Has each click on it pick a cell ([onPick]) in place of reaching the app, until told off or Escape; or not. */
  pick(on: boolean): void;
  /** The cell a click picked (from 0, as twk's), with the cursor's row, or null: the pick ended with none (Escape). */
  readonly onPick: Event<PickedCell | null>;
  /** Shows the bar of a recording played back in it, as [state] says; null takes it away. */
  player(state: PlayerState | null): void;
  /** A button of its player's bar was pressed. */
  readonly onControl: Event<PlayerControl>;
  /** What the app in it asked of the editor, as its answers allow. */
  readonly onRequest: Event<TerminalRequest>;
  /** Its size changed. */
  readonly onResize: Event<void>;
  /** It was closed. */
  readonly onClose: Event<void>;
  /**
   * It came back empty, at the size it says now: its webview loaded again
   * (a reload, a crash), what it showed and the size fixed for it gone.
   */
  readonly onReload: Event<void>;
}

/** Opens a new [TerminalView], named by [title]. */
export type TerminalViewFactory = (title: string) => TerminalView;

/** The extension's log (an output channel). */
export interface Log {
  append(text: string): void;
  appendLine(line: string): void;
}

/** Where the status of reloads and restarts is shown (the status bar). */
export interface StatusSink {
  show(status: HotStatus, appsRunning: boolean): void;
}

/** What the editor does for an app's requests through its terminal. */
export interface Desktop {
  /** Shows a notification of [title] and [body], from the terminal of [source]. */
  notify(source: string, title: string, body: string): void;
  /**
   * Shows the progress of the app in the terminal [owner] (its key: two
   * terminals of one name are two), named [source], OSC 9;4's [state] (0
   * takes it away) and [percent].
   */
  progress(owner: object, source: string, state: number, percent: number | null): void;
  /** Puts [text] on the clipboard. */
  writeClipboard(text: string): void;
  /** Opens [uri] (http, https, mailto) outside the editor. */
  openLink(uri: string): void;
}

/** The settings the use cases read, each time they need one. */
export interface Settings {
  /** What the terminals are for the apps that connect from now on: a preset and the switches changed from it. */
  capabilities(): Choice;
  /** What the terminals switch on in the apps that connect from now on. */
  switches(): Switches;
  /** The fixed size of the terminals, or nulls: fitted. */
  size(): { columns: number | null; lines: number | null };
  hotReloadOnSave(): boolean;
}

/** A timer source: real time in the extension, a fake clock in a test. */
export type { Clock };

/** A launch configuration of Dart-Code's debugger, for an app in a twk terminal. */
export interface DartLaunch {
  readonly type: 'dart';
  readonly request: 'launch';
  readonly name: string;
  readonly program: string;
  readonly cwd: string;
  readonly console: 'debugConsole';
  /** TWK_SHELL, the terminal's address, among them. */
  readonly env: Readonly<Record<string, string>>;
  /** Marks a session the extension serves: the key of its terminal. */
  readonly twkSession: string;
  /** The rest of the configuration it was made from (args, toolArgs...), passed on as it is. */
  readonly others: Readonly<Record<string, unknown>>;
}

/** A debug session the extension follows. */
export interface DebugSession {
  readonly id: string;
  readonly configuration: DartLaunch;
}

/** The editor's debugger. */
export interface Debugger {
  /** Starts a session of [launch]; whether it started. */
  start(launch: DartLaunch): Promise<boolean>;
  stop(session: DebugSession): Promise<void>;
  /** A session of a [DartLaunch] started. */
  readonly onStarted: Event<DebugSession>;
  /** A session told the address of its VM service (Dart-Code's `dart.debuggerUris`). */
  readonly onVmService: Event<{ readonly session: DebugSession; readonly uri: string }>;
  /** A session ended, by its id. */
  readonly onTerminated: Event<string>;
}

/** An app the extension runs: reloaded, restarted and stopped through it. */
export interface RunHandle {
  readonly pid: number | undefined;
  reload(): Promise<HotStatus>;
  /** Settles once the app was started again. */
  restart(): Promise<void>;
  stop(): Promise<void>;
  /** Has the app paint all of itself again: its terminal came back empty. */
  redraw(): Promise<void>;
  /** Settles once the run ended. */
  readonly ended: Promise<number | string>;
}

/** Runs an app: core's HotRun, or a fake. */
export type Runner = (options: HotRunOptions) => RunHandle;

/** Tells the editor whether an app runs with hot reload (enables its commands and keys). */
export type HotContext = (running: boolean) => void;

/** The inspector's tree on the screen (a tree view). */
export interface InspectorView {
  /** Shows [tree], or none with [message] saying why. */
  show(tree: InspectTree | undefined, message: string): void;
  /** Selects the node [id] and shows it, those above it expanded. */
  reveal(id: number): void;
  /** Whether it is on the screen now. */
  readonly visible: boolean;
  readonly onVisible: Event<boolean>;
  /** The person selected a node (its id), or none. */
  readonly onSelect: Event<number | undefined>;
  /** Selects no node. */
  clearSelection(): void;
}

/** Opens a place of the code in the editor. */
export interface SourceOpener {
  /** Opens [spot]; with [keepFocus] the focus stays where it is (the terminal a pick was made in). */
  open(spot: SourceSpot, options?: { readonly keepFocus?: boolean }): Promise<void>;
}

/** The inspector's pick mode as the editor shows it: its button pressed while it is on. */
export interface PickingIndicator {
  show(on: boolean): void;
}

/** A short message to the person, shown for a while (the status bar's). */
export interface Notice {
  say(text: string): void;
}

/** What a screen wrote: the app's bytes, or (not [fromApp]) the extension's own lines to the person. */
export interface Output {
  readonly bytes: Uint8Array;
  readonly fromApp: boolean;
}

/**
 * A terminal on the screen and its traffic, as the sequence log, a
 * recording and a copy of the screen take it: a twk terminal (an app's),
 * or a recording played back.
 */
export interface Screen {
  /** What it is for: the file of its app, or the recording's. */
  readonly name: string;
  readonly view: TerminalView;
  /** What was written to it. */
  readonly onDidOutput: Event<Output>;
  /** What it sent: keys, the mouse, the answers to queries. */
  readonly onDidInput: Event<Uint8Array>;
  /** Something of the session: an app came or went, a size. */
  readonly onDidNote: Event<string>;
  /** Its size changed (its view's columns and lines). */
  readonly onDidResize: Event<void>;
  readonly onDidDispose: Event<void>;
}

/** Where a recording's lines go as it is made (a file). */
export interface CastSink {
  /** Throws when it can't be written. */
  write(text: string): void;
  close(): Promise<void>;
}
