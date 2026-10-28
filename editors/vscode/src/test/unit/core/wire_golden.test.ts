// The extension's wire (core/wire.ts) and shell (core/shell.ts) held to
// the golden of twk's wire, packages/twk_core/test/terminal/
// shell_wire.golden.json, which twk_core's shell_wire_golden_test.dart
// holds socket.dart to as well: the kinds and their types, each frame's
// bytes, and the conversations of the shell's side played against this
// TerminalShell over a real local socket, byte for byte. A change to the
// Dart side's wire made in the golden fails here until this side follows.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as os from 'node:os';
import * as path from 'node:path';

import { fromVariable } from '../../../core/address';
import { declarationOf, presetNamed } from '../../../core/capabilities';
import { TerminalPane, TerminalShell } from '../../../core/shell';
import { switchEnvironment, switchesOf } from '../../../core/switches';
import { FrameReader, Wire, frame, jsonFrame } from '../../../core/wire';

/** From out/test/unit/core, where this runs compiled, to the repository's root. */
const goldenPath = path.resolve(__dirname, '../../../../../../packages/twk_core/test/terminal/shell_wire.golden.json');

interface Kind {
  readonly name: string;
  readonly type: number;
}

interface GoldenFrame {
  readonly name: string;
  readonly kind?: string;
  readonly type?: number;
  readonly description: string;
  readonly hex: string;
  readonly json?: unknown;
  readonly text?: string;
  readonly bytes?: string;
  /** Only a header, announcing this length. */
  readonly header?: number;
}

type Step =
  | { readonly by?: number; readonly sends: string }
  | { readonly by?: number; readonly gets: string }
  | { readonly by?: number; readonly closed: true }
  | { readonly by?: number; readonly closes: true }
  | { readonly types: string }
  | { readonly resizes: readonly [number, number] }
  | { readonly shows: string }
  | { readonly link: string }
  | { readonly reads: string }
  | { readonly sized: readonly [number, number] };

interface Conversation {
  readonly name: string;
  readonly side: 'shell' | 'app';
  readonly description: string;
  readonly steps: readonly Step[];
}

interface Golden {
  readonly protocol: number;
  readonly maxPayload: number;
  readonly kinds: readonly Kind[];
  readonly frames: readonly GoldenFrame[];
  readonly conversations: readonly Conversation[];
}

const golden = JSON.parse(fs.readFileSync(goldenPath, 'utf8')) as Golden;
const frames = new Map(golden.frames.map((f) => [f.name, f]));

function goldenFrame(name: string): GoldenFrame {
  const f = frames.get(name);
  if (!f) {
    throw new Error(`no frame "${name}" in the golden`);
  }
  return f;
}

function bytesOf(hex: string): Buffer {
  return Buffer.from(hex.replace(/ /g, ''), 'hex');
}

/** [bytes] as the golden writes a frame: `type length payload`. */
function hexOf(bytes: Uint8Array): string {
  const b = Buffer.from(bytes);
  return [b.subarray(0, 1), b.subarray(1, 5), ...(b.length > 5 ? [b.subarray(5)] : [])].map((p) => p.toString('hex')).join(' ');
}

function typeOf(f: GoldenFrame): number {
  const type = f.type ?? golden.kinds.find((k) => k.name === f.kind)?.type;
  if (type === undefined) {
    throw new Error(`frame "${f.name}" of no kind`);
  }
  return type;
}

/** The golden frame [f] made with this side's frame and jsonFrame. */
function encode(f: GoldenFrame): Buffer {
  if (f.json !== undefined) {
    return jsonFrame(typeOf(f), f.json);
  }
  if (f.bytes !== undefined) {
    return frame(typeOf(f), Buffer.from(f.bytes, 'hex'));
  }
  return frame(typeOf(f), Buffer.from(f.text ?? '', 'utf8'));
}

/** What [payload] says, decoded as the golden writes [f]'s. */
function decode(f: GoldenFrame, payload: Buffer): unknown {
  if (f.json !== undefined) {
    return JSON.parse(payload.toString('utf8'));
  }
  if (f.bytes !== undefined) {
    return payload.toString('hex');
  }
  return payload.toString('utf8');
}

/** Something to wait on: each change wakes the waits, which look again. */
class Changes {
  private waiters: (() => void)[] = [];
  changed(): void {
    this.waiters.splice(0).forEach((w) => w());
  }
  async until(condition: () => boolean): Promise<void> {
    while (!condition()) {
      await new Promise<void>((r) => this.waiters.push(r));
    }
  }
}

class Pane implements TerminalPane {
  readonly written: Buffer[] = [];
  constructor(
    public columns: number,
    public lines: number,
    private readonly changes: Changes,
  ) {}
  write(bytes: Uint8Array): Promise<void> {
    this.written.push(Buffer.from(bytes));
    this.changes.changed();
    return Promise.resolve();
  }
  get text(): string {
    return Buffer.concat(this.written).toString('latin1');
  }
}

/** An app's end of the wire, frame by frame. */
class Client {
  readonly frames: Buffer[] = [];
  seen = 0;
  closed = false;
  private constructor(
    readonly socket: net.Socket,
    changes: Changes,
  ) {
    const reader = new FrameReader((type, payload) => {
      this.frames.push(frame(type, payload));
      changes.changed();
    });
    socket.on('data', (b) => reader.add(b));
    socket.on('error', () => {});
    socket.on('close', () => {
      this.closed = true;
      changes.changed();
    });
  }
  static async connect(socketPath: string, changes: Changes): Promise<Client> {
    const socket = net.connect(socketPath);
    await new Promise((r) => socket.once('connect', r));
    return new Client(socket, changes);
  }
}

/** The settings of the welcome's environment, and the rest: what the capabilities say. */
const settingNames = new Set(['TWK_SCREEN_READER', 'TWK_DEBUG']);

describe('the golden of the wire', () => {
  it('names the protocol and the longest payload of wire.ts', () => {
    assert.equal(golden.protocol, Wire.protocol);
    assert.equal(golden.maxPayload, Wire.maxPayload);
  });

  it("has wire.ts's kinds, of their types, none left out", () => {
    const { protocol: _p, maxPayload: _m, ...kinds } = Wire;
    assert.deepEqual(Object.fromEntries(golden.kinds.map((k) => [k.name, k.type])), kinds);
  });

  describe('each frame', () => {
    for (const f of golden.frames) {
      const bytes = bytesOf(f.hex);
      if (f.header !== undefined) {
        it(`"${f.name}": its header is refused by a FrameReader`, () => {
          assert.equal(bytes.length, 5);
          assert.throws(() =>
            new FrameReader(() => assert.fail('a frame')).add(bytes),
          );
        });
        continue;
      }
      it(`"${f.name}": made by frame/jsonFrame, read back by a FrameReader a byte at a time`, () => {
        assert.equal(hexOf(encode(f)), f.hex, 'as this side makes it');
        const read: { type: number; payload: Buffer }[] = [];
        const reader = new FrameReader((type, payload) => read.push({ type, payload }));
        for (const b of bytes) {
          reader.add(Buffer.from([b]));
        }
        assert.equal(read.length, 1);
        assert.equal(read[0].type, typeOf(f));
        assert.deepEqual(decode(f, read[0].payload), f.json ?? f.bytes ?? f.text);
      });
    }
  });

  describe('conversation', () => {
    let root: string;
    let shell: TerminalShell | undefined;
    const clients: Client[] = [];

    beforeEach(() => {
      root = fs.mkdtempSync(path.join(os.tmpdir(), 'twk-golden-'));
    });

    afterEach(async () => {
      clients.splice(0).forEach((c) => c.socket.destroy());
      await shell?.stop();
      shell = undefined;
      fs.rmSync(root, { recursive: true, force: true });
    });

    for (const c of golden.conversations) {
      if (c.side === 'app') {
        // the extension has no app's end: twk_core's test alone plays it
        continue;
      }
      it(`"${c.name}" (${c.side} side): ${c.description}`, async () => {
        const changes = new Changes();
        const welcome = goldenFrame('welcome').json as {
          columns: number;
          lines: number;
          environment: Record<string, string>;
          declares: unknown;
        };
        const hello = goldenFrame('hello').json as { token: string };
        const environment = Object.fromEntries(Object.entries(welcome.environment).filter(([k]) => !settingNames.has(k)));
        // the settings as the switches that set them
        const debug = welcome.environment.TWK_DEBUG?.split(',').filter((a) => a !== 'keys') ?? [];
        const switches = switchesOf(welcome.environment.TWK_SCREEN_READER === '1', debug);
        // what the golden declares is what "everything" declares: in its fields, their values and their order
        const declares = declarationOf(presetNamed('everything').capabilities);
        assert.deepEqual(declares, welcome.declares);
        const pane = new Pane(welcome.columns, welcome.lines, changes);
        const s = (shell = await TerminalShell.start(pane, {
          welcome: () => ({ environment: { ...environment, ...switchEnvironment(switches) }, declares }),
          onEvent: () => {},
          temporaryRoot: root,
          tcp: false,
          token: hello.token,
        }));
        const socketPath = fromVariable(s.variable)?.where.substring('unix:'.length) ?? '';
        const apps = new Map<number, Client>();
        const app = async (by: number): Promise<Client> => {
          let client = apps.get(by);
          if (!client) {
            client = await Client.connect(socketPath, changes);
            clients.push(client);
            apps.set(by, client);
          }
          return client;
        };
        for (const step of c.steps) {
          const what = `step ${JSON.stringify(step)}`;
          const by = 'by' in step ? (step.by ?? 1) : 1;
          if ('sends' in step) {
            (await app(by)).socket.write(bytesOf(goldenFrame(step.sends).hex));
          } else if ('gets' in step) {
            const client = await app(by);
            await changes.until(() => client.frames.length > client.seen || client.closed);
            const got = client.frames[client.seen++];
            assert.equal(got ? hexOf(got) : 'the connection closed', goldenFrame(step.gets).hex, `${what}: the shell sent another frame`);
          } else if ('closed' in step) {
            const client = await app(by);
            await changes.until(() => client.closed || client.frames.length > client.seen);
            assert.deepEqual(client.frames.slice(client.seen).map(hexOf), [], `${what}: the shell sent a frame first`);
            assert.ok(client.closed, what);
          } else if ('closes' in step) {
            (await app(by)).socket.destroy();
          } else if ('types' in step) {
            s.input(Buffer.from(step.types, 'utf8'));
          } else if ('resizes' in step) {
            [pane.columns, pane.lines] = step.resizes;
            s.resized();
          } else if ('shows' in step) {
            await changes.until(() => pane.text.length >= step.shows.length);
            assert.equal(pane.text, step.shows, `${what}: the terminal shows another text`);
          } else {
            assert.fail(`a step of no kind for the shell's side: ${what}`);
          }
        }
        for (const [by, client] of apps) {
          assert.deepEqual(client.frames.slice(client.seen).map(hexOf), [], `app ${by} got frames the conversation does not name`);
        }
      });
    }
  });
});
