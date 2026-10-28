// The shell's end of twk's socket terminal, in the extension: what
// `TerminalShell` (packages/twk_core/lib/src/terminal/socket.dart) does
// for `twk shell`, over a terminal pane (xterm.js in a webview) instead of
// the process's own terminal. Each shell listens on a socket of its own,
// in a new temporary directory, and writes no address file: the app it is
// for is told where by TWK_SHELL in its environment ([TerminalShell.variable],
// core/address.ts), which twk_core's `Terminal.open` reads when the app has
// no terminal of its own (started by the extension, or by Dart-Code's
// debugger in the Debug Console). Nothing here needs vscode, so it runs
// under plain node in the tests.

import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as path from 'node:path';

import { ShellAddress, toVariable } from './address';
import { Declaration } from './capabilities';
import { FrameReader, Wire, frame, jsonFrame } from './wire';

/** Throws for bytes that are no UTF-8, as Dart's utf8.decode does. */
const utf8 = new TextDecoder('utf-8', { fatal: true });

/** What the shell serves: a terminal that writes and tells its input and size. */
export interface TerminalPane {
  readonly columns: number;
  readonly lines: number;
  /** Resolves once the terminal parsed [bytes]. */
  write(bytes: Uint8Array): Promise<void>;
}

/** An app took the terminal; the app went away (not when a newer one took it over). */
export type ShellEvent = 'connected' | 'disconnected';

/** What an app is welcomed with beside the terminal's size: what the terminal tells it it is. */
export interface Welcome {
  /** The environment the app sees over the link (`TerminalLink.environment`), its TWK_SCREEN_READER and TWK_DEBUG the app's settings. */
  readonly environment: Readonly<Record<string, string>>;
  /** What the terminal declares it does (twk_core's `TerminalDeclaration`); left out of the welcome where empty. */
  readonly declares: Declaration;
}

export interface ShellOptions {
  /** What the next app is welcomed with: asked once for each, as it is taken. */
  readonly welcome: () => Welcome;
  readonly onEvent: (event: ShellEvent) => void;
  /** Where the socket's directory is made: the system's temporary directory. */
  readonly temporaryRoot: string;
  /** TCP on the loopback interface instead of a Unix domain socket: where there are none (Windows). */
  readonly tcp: boolean;
  /** The token an app opens with: a new random one when not given (a test gives the golden's). */
  readonly token?: string;
}

class Session {
  raw = false;
  lost: Buffer = Buffer.alloc(0);
  ended = false;

  constructor(readonly socket: net.Socket) {}

  send(type: number, payload?: Uint8Array): void {
    if (!this.ended) {
      this.socket.write(frame(type, payload));
    }
  }

  sendJson(type: number, json: unknown): void {
    if (!this.ended) {
      this.socket.write(jsonFrame(type, json));
    }
  }
}

/** Serves a [TerminalPane] to apps, one at a time, the newest. */
export class TerminalShell {
  private session: Session | undefined;
  private readonly pending = new Set<Session>();
  /** The last write to the pane: a flush waits for it. */
  private written: Promise<void> = Promise.resolve();
  private stopped = false;

  private constructor(
    private readonly pane: TerminalPane,
    private readonly server: net.Server,
    /** Where it listens, and the token an app opens with. */
    readonly address: ShellAddress,
    private readonly directory: string | undefined,
    private readonly options: ShellOptions,
  ) {
    server.on('connection', (socket) => this.accept(socket));
  }

  /**
   * Listens on a new local socket: `shell.sock` in a new directory of
   * [ShellOptions.temporaryRoot], or TCP on 127.0.0.1. Throws what the
   * listen threw, or that the socket's path is too long, nothing of it
   * left behind.
   */
  static async start(pane: TerminalPane, options: ShellOptions): Promise<TerminalShell> {
    const token = options.token ?? crypto.randomBytes(16).toString('hex');
    const server = net.createServer();
    const listening = (go: (done: () => void) => void) =>
      new Promise<void>((resolve, reject) => {
        server.once('error', reject);
        go(() => {
          server.off('error', reject);
          resolve();
        });
      });
    if (options.tcp) {
      await listening((done) => server.listen(0, '127.0.0.1', done));
      const bound = server.address();
      if (typeof bound !== 'object' || bound === null) {
        server.close();
        throw new Error('the shell listens on no TCP port');
      }
      const port = bound.port;
      return new TerminalShell(pane, server, { where: `tcp:127.0.0.1:${port}`, token }, undefined, options);
    }
    const directory = fs.mkdtempSync(path.join(options.temporaryRoot, 'twk-shell-'));
    const socketPath = path.join(directory, 'shell.sock');
    try {
      // a socket's path has room for 107 bytes (103 on macOS); node 22
      // binds a longer one where the kernel cut it, which no app finds
      const most = process.platform === 'darwin' ? 103 : 107;
      const length = Buffer.byteLength(socketPath);
      if (length > most) {
        throw new Error(`the shell's socket path is too long, ${length} bytes of at most ${most}: ${socketPath}`);
      }
      await listening((done) => server.listen(socketPath, done));
    } catch (e) {
      // the directory is this shell's alone
      fs.rmSync(directory, { recursive: true, force: true });
      throw e;
    }
    return new TerminalShell(pane, server, { where: `unix:${socketPath}`, token }, directory, options);
  }

  /** Its address as TWK_SHELL holds it, for the environment of the app it serves. */
  get variable(): string {
    return toVariable(this.address);
  }

  /** Whether an app has the terminal. */
  get serving(): boolean {
    return this.session !== undefined;
  }

  /** The terminal's input: to the app that has it in raw mode, else dropped. */
  input(bytes: Uint8Array): void {
    const s = this.session;
    if (s?.raw) {
      s.send(Wire.input, bytes);
    }
  }

  /** The terminal's size changed. */
  resized(): void {
    this.session?.sendJson(Wire.size, { columns: this.pane.columns, lines: this.pane.lines });
  }

  /** Writes [text] to the terminal: a line of the shell's while no app has it. */
  say(text: string): void {
    this.write(Buffer.from(text, 'utf8'));
  }

  private write(bytes: Uint8Array): void {
    if (bytes.length > 0) {
      this.written = this.pane.write(bytes);
    }
  }

  private accept(socket: net.Socket): void {
    if (this.stopped) {
      socket.destroy();
      return;
    }
    const session = new Session(socket);
    this.pending.add(session);
    const timer = setTimeout(() => {
      if (this.pending.delete(session)) {
        socket.destroy();
      }
    }, 5000);
    const reader = new FrameReader((type, payload) => {
      if (this.pending.has(session)) {
        clearTimeout(timer);
        this.pending.delete(session);
        this.hello(session, type, payload);
      } else if (session === this.session) {
        this.frame(session, type, payload);
      }
    });
    const end = () => {
      clearTimeout(timer);
      this.pending.delete(session);
      this.end(session);
    };
    socket.on('data', (bytes) => {
      try {
        reader.add(bytes);
      } catch {
        end();
      }
    });
    socket.on('error', end);
    socket.on('close', end);
  }

  private hello(session: Session, type: number, payload: Buffer): void {
    // as TerminalShell._hello: UTF-8 or no hello, a JSON object or no
    // hello, a protocol not named is null (the golden of the wire holds both)
    let refusal: string | undefined;
    let json: unknown;
    try {
      json = type === Wire.hello ? JSON.parse(utf8.decode(payload)) : undefined;
    } catch {
      json = undefined;
    }
    if (typeof json !== 'object' || json === null || Array.isArray(json)) {
      refusal = 'no hello';
    } else {
      const hello = json as { protocol?: unknown; token?: unknown };
      if (hello.protocol !== Wire.protocol) {
        refusal = `the app speaks protocol ${String(hello.protocol ?? null)}, this shell ${Wire.protocol}`;
      } else if (hello.token !== this.address.token) {
        refusal = 'not the token of this shell';
      }
    }
    if (refusal !== undefined) {
      session.send(Wire.refused, Buffer.from(refusal, 'utf8'));
      session.ended = true;
      session.socket.end();
      return;
    }
    if (this.session) {
      // taken over: the newer app follows at once, the terminal is not left
      this.end(this.session, { replaced: true });
    }
    this.session = session;
    session.raw = true;
    this.options.onEvent('connected');
    const { environment, declares } = this.options.welcome();
    session.sendJson(Wire.welcome, {
      columns: this.pane.columns,
      lines: this.pane.lines,
      // xterm.js's Backspace
      eraseChar: 0x7f,
      windows: false,
      environment,
      ...(Object.keys(declares).length > 0 ? { declares } : {}),
    });
  }

  private frame(session: Session, type: number, payload: Buffer): void {
    switch (type) {
      case Wire.output:
        // what the terminal answers, xterm.js's or the webview's, comes as its input
        this.write(payload);
        break;
      case Wire.flush:
        this.written.then(
          () => session.send(Wire.flushed),
          () => session.send(Wire.flushed),
        );
        break;
      case Wire.lost:
        session.lost = payload;
        break;
      case Wire.raw:
        // xterm.js has no line discipline: raw is whether input goes to the app
        session.raw = payload.length > 0 && payload[0] === 1;
        break;
      default:
        this.end(session);
    }
  }

  private end(session: Session, { replaced = false } = {}): void {
    if (session.ended && session !== this.session) {
      return;
    }
    session.ended = true;
    session.socket.destroy();
    if (session !== this.session) {
      return;
    }
    this.session = undefined;
    this.write(session.lost);
    if (!replaced) {
      this.options.onEvent('disconnected');
    }
  }

  /** Stops serving: the app disconnected, the terminal put back, the socket and its directory removed. */
  async stop(): Promise<void> {
    if (this.stopped) {
      return;
    }
    this.stopped = true;
    for (const s of this.pending) {
      s.socket.destroy();
    }
    this.pending.clear();
    if (this.session) {
      this.end(this.session);
    }
    await new Promise<void>((resolve) => this.server.close(() => resolve()));
    if (this.directory) {
      fs.rmSync(this.directory, { recursive: true, force: true });
    }
    await this.written.catch(() => {});
  }
}
