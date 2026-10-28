// What the twk terminal's webview does beside xterm.js, as its
// capabilities say (core/capabilities.ts's [Answers], sent as each app is
// taken): handlers on xterm.js's parser that answer the queries of twk's
// probe xterm.js leaves or that are denied, keep kitty's keyboard flags,
// and turn an app's requests (a notification, progress, the clipboard, the
// pointer's shape) into messages for the extension. The answers are typed
// as the terminal's input, as xterm.js's own are. Over the least of
// xterm.js it needs ([Xterm]), so the unit tests run it on
// @xterm/headless; main.ts on the webview's xterm.js.
import { Answers } from '../core/capabilities.js';
import {
  TerminalRequest,
  cellSizeReply,
  clipboardOf,
  isColorQuery,
  isSafeLink,
  modeReply,
  notificationOf,
  pointerOf,
  progressOf,
  versionReply,
} from '../core/emulation.js';
import { KeyPress, KittyKeyboard, encodeKey } from '../core/kitty_keyboard.js';

interface Disposable {
  dispose(): void;
}

type Params = (number | number[])[];

/** What of xterm.js's Terminal (or @xterm/headless's) the handlers need. */
export interface Xterm {
  readonly parser: {
    registerCsiHandler(id: { prefix?: string; intermediates?: string; final: string }, callback: (params: Params) => boolean): Disposable;
    registerOscHandler(ident: number, callback: (data: string) => boolean): Disposable;
  };
  readonly buffer: { readonly active: { readonly type: 'normal' | 'alternate' } };
  /** Its window reports: xterm.js drops `CSI 16 t` unless getCellSizePixels is on, before any handler of it sees it. */
  readonly options: { windowOptions?: { getCellSizePixels?: boolean } };
}

/** Where what the handlers make goes. */
export interface EmulationSinks {
  /** An answer for the app, typed as the terminal's input. */
  reply(text: string): void;
  /** A request of the app's for the editor. */
  request(request: TerminalRequest): void;
  /** The pointer's shape over the terminal, a CSS cursor; null, the terminal's own. */
  pointer(shape: string | null): void;
  /** A cell's size in pixels, where it is known. */
  cellSize(): { width: number; height: number } | undefined;
}

/** Answers nothing, emulates nothing: until the extension says what to. */
const nothing: Answers = {
  deny: [],
  kittyKeyboard: false,
  version: null,
  cellSize: false,
  graphics: 'none',
  notifications: false,
  progress: false,
  pointerShapes: false,
  links: true,
  clipboard: false,
};

/** The first parameter of a sequence, or [fallback] where it has none. */
function first(params: Params, fallback: number): number {
  const p = params[0];
  return typeof p === 'number' ? p : fallback;
}

export class Emulation implements Disposable {
  private answers: Answers = nothing;
  private readonly kitty = new KittyKeyboard();
  private readonly handlers: Disposable[];

  constructor(
    private readonly term: Xterm,
    private readonly sinks: EmulationSinks,
  ) {
    const p = term.parser;
    const reply = (text: string | undefined) => {
      if (text === undefined) {
        return false;
      }
      sinks.reply(text);
      return true;
    };
    const screen = () => term.buffer.active.type;
    const kitty = (f: () => void) => {
      if (!this.answers.kittyKeyboard) {
        return false;
      }
      f();
      return true;
    };
    const request = (r: TerminalRequest | undefined, on: boolean) => {
      if (!on || r === undefined) {
        return false;
      }
      sinks.request(r);
      return true;
    };
    const denied = (q: 'colors') => this.answers.deny.includes(q);
    this.handlers = [
      // DECRQM: a mode denied is not recognised; the rest xterm.js answers
      p.registerCsiHandler({ prefix: '?', intermediates: '$', final: 'p' }, (params) => reply(modeReply(first(params, 0), this.answers))),
      // DA1, the probe's last: no answer at all where denied
      p.registerCsiHandler({ final: 'c' }, (params) => this.answers.deny.includes('deviceAttributes') && first(params, 0) === 0),
      ...[10, 11, 4].map((ident) => p.registerOscHandler(ident, (data) => denied('colors') && isColorQuery(data))),
      // XTVERSION
      p.registerCsiHandler({ prefix: '>', final: 'q' }, () => reply(versionReply(this.answers))),
      // a cell's size in pixels; the other window reports xterm.js's
      p.registerCsiHandler({ final: 't' }, (params) => first(params, 0) === 16 && reply(cellSizeReply(this.answers, sinks.cellSize()))),
      // kitty's keyboard protocol: query, push, pop, set
      p.registerCsiHandler({ prefix: '?', final: 'u' }, () => kitty(() => sinks.reply(this.kitty.query(screen())))),
      p.registerCsiHandler({ prefix: '>', final: 'u' }, (params) => kitty(() => this.kitty.push(screen(), first(params, 0)))),
      p.registerCsiHandler({ prefix: '<', final: 'u' }, (params) => kitty(() => this.kitty.pop(screen(), first(params, 1)))),
      p.registerCsiHandler({ prefix: '=', final: 'u' }, (params) =>
        kitty(() => this.kitty.set(screen(), first(params, 0), typeof params[1] === 'number' ? params[1] : 1)),
      ),
      p.registerOscHandler(777, (data) => request(notificationOf(data), this.answers.notifications)),
      p.registerOscHandler(9, (data) => request(progressOf(data), this.answers.progress)),
      // the clipboard: dropped where off, as xterm.js does by itself
      p.registerOscHandler(52, (data) => {
        request(clipboardOf(data), this.answers.clipboard);
        return true;
      }),
      p.registerOscHandler(22, (data) => {
        const shape = pointerOf(data);
        if (!this.answers.pointerShapes || shape === undefined) {
          return false;
        }
        sinks.pointer(shape);
        return true;
      }),
      // links off: shown as their text alone
      p.registerOscHandler(8, () => !this.answers.links),
    ];
  }

  /** What it answers and emulates from now on: an app is taken. Its kitty keyboard flags start again, the pointer is the terminal's. */
  configure(answers: Answers): void {
    this.answers = answers;
    this.term.options.windowOptions = { ...this.term.options.windowOptions, getCellSizePixels: answers.cellSize };
    this.kitty.reset();
    this.sinks.pointer(null);
  }

  /** What it answers and emulates now. */
  get current(): Answers {
    return this.answers;
  }

  /** What [press] sends where the app pushed kitty's keyboard flags; undefined, what xterm.js sends. */
  key(press: KeyPress): string | undefined {
    return this.answers.kittyKeyboard ? encodeKey(press, this.kitty.flags(this.term.buffer.active.type)) : undefined;
  }

  /** A link the person activated in the terminal: asked to be opened, where links are on and it is one that may be. */
  activateLink(uri: string): void {
    if (this.answers.links && isSafeLink(uri)) {
      this.sinks.request({ type: 'openLink', uri });
    }
  }

  dispose(): void {
    this.handlers.forEach((h) => h.dispose());
  }
}
