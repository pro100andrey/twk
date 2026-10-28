// A client of the Dart VM service: JSON-RPC 2.0 over a WebSocket (node's
// own, global since node 22), the few calls hot reload needs. No vscode
// import: its tests run under plain node.
import { Clock } from './events';

/** How long a connect may take: a service that neither answers nor fails is none. */
export const connectPatience = 10000;

/** An event of a stream the client listens to (`streamNotify`). */
export interface VmEvent {
  kind: string;
  isolate?: { id: string };
  /** ServiceExtensionAdded: the extension's method. */
  extensionRPC?: string;
  /** Extension: what the app posted (`developer.postEvent`). */
  extensionKind?: string;
  extensionData?: unknown;
}

/** What hot reload asks of a VM service: [VmClient], or a fake in a test. */
export interface Vm {
  call(method: string, params?: Record<string, unknown>): Promise<Record<string, unknown>>;
  /** Listens to [stream] (`streamListen`), [f] given each of its events. */
  listen(stream: string, f: (e: VmEvent) => void): Promise<void>;
  /** Settles when the connection is gone: the app ended, or [close]. */
  readonly closed: Promise<void>;
  close(): void;
}

/** An error the service answered a call with. */
export class VmError extends Error {
  constructor(
    readonly code: number,
    message: string,
    readonly data: unknown,
  ) {
    super(message);
  }
}

/**
 * The WebSocket address of the VM service at [uri], as the service info
 * file (`--write-service-info`) and Dart-Code's `dart.debuggerUris` give it:
 * `http://127.0.0.1:<port>/<token>=/` is `ws://127.0.0.1:<port>/<token>=/ws`.
 */
export function webSocketUri(uri: string): string {
  if (/^wss?:/.test(uri)) {
    return uri;
  }
  const u = new URL(uri);
  u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:';
  u.pathname = (u.pathname.endsWith('/') ? u.pathname : `${u.pathname}/`) + 'ws';
  return u.toString();
}

export class VmClient implements Vm {
  private nextId = 0;
  private readonly pending = new Map<string, { resolve: (r: Record<string, unknown>) => void; reject: (e: Error) => void }>();
  private readonly streams = new Map<string, (e: VmEvent) => void>();
  readonly closed: Promise<void>;

  private constructor(private readonly socket: WebSocket) {
    this.closed = new Promise((resolve) => socket.addEventListener('close', () => resolve()));
    void this.closed.then(() => {
      for (const p of this.pending.values()) {
        p.reject(new Error('the VM service went away'));
      }
      this.pending.clear();
    });
    socket.addEventListener('message', (m) => this.onMessage(String(m.data)));
  }

  /** Connects to the VM service at [uri] (http or ws); fails when it isn't open within [patience] ms on [clock]. */
  static connect(uri: string, clock: Clock, patience = connectPatience): Promise<VmClient> {
    if (typeof WebSocket === 'undefined') {
      return Promise.reject(new Error('no WebSocket in this node (22 or newer has one)'));
    }
    const socket = new WebSocket(webSocketUri(uri));
    return new Promise((resolve, reject) => {
      const timer = clock.setTimeout(() => {
        reject(new Error(`no answer from the VM service at ${uri} in ${patience} ms`));
        socket.close();
      }, patience);
      socket.addEventListener(
        'open',
        () => {
          timer.dispose();
          resolve(new VmClient(socket));
        },
        { once: true },
      );
      socket.addEventListener(
        'error',
        () => {
          timer.dispose();
          reject(new Error(`no VM service at ${uri}`));
        },
        { once: true },
      );
    });
  }

  call(method: string, params: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
    const id = String(this.nextId++);
    return new Promise((resolve, reject) => {
      if (this.socket.readyState !== WebSocket.OPEN) {
        reject(new Error('the VM service went away'));
        return;
      }
      this.pending.set(id, { resolve, reject });
      this.socket.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
    });
  }

  async listen(stream: string, f: (e: VmEvent) => void): Promise<void> {
    this.streams.set(stream, f);
    await this.call('streamListen', { streamId: stream });
  }

  close(): void {
    this.socket.close();
  }

  private onMessage(text: string): void {
    const m = parseMessage(text);
    if (m === undefined) {
      return;
    }
    if (m.kind === 'event') {
      this.streams.get(m.stream)?.(m.event);
      return;
    }
    const p = this.pending.get(m.id);
    if (!p) {
      return;
    }
    this.pending.delete(m.id);
    if (m.kind === 'error') {
      p.reject(new VmError(m.code, m.message, m.data));
    } else {
      p.resolve(m.result);
    }
  }
}

type Message =
  | { kind: 'event'; stream: string; event: VmEvent }
  | { kind: 'result'; id: string; result: Record<string, unknown> }
  | { kind: 'error'; id: string; code: number; message: string; data: unknown };

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

/** A JSON-RPC message of the service: a stream's event, or the answer to a call; undefined for anything else. */
export function parseMessage(text: string): Message | undefined {
  let m: unknown;
  try {
    m = JSON.parse(text);
  } catch {
    return undefined;
  }
  if (!isRecord(m)) {
    return undefined;
  }
  if (m.method === 'streamNotify') {
    const params = m.params;
    if (isRecord(params) && typeof params.streamId === 'string' && isRecord(params.event) && typeof params.event.kind === 'string') {
      return { kind: 'event', stream: params.streamId, event: toEvent(params.event) };
    }
    return undefined;
  }
  if (typeof m.id !== 'string') {
    return undefined;
  }
  if (isRecord(m.error)) {
    const { code, message, data } = m.error;
    return { kind: 'error', id: m.id, code: typeof code === 'number' ? code : 0, message: typeof message === 'string' ? message : 'error', data };
  }
  return { kind: 'result', id: m.id, result: isRecord(m.result) ? m.result : {} };
}

function toEvent(e: Record<string, unknown>): VmEvent {
  const isolate = isRecord(e.isolate) && typeof e.isolate.id === 'string' ? { id: e.isolate.id } : undefined;
  return {
    kind: String(e.kind),
    ...(isolate ? { isolate } : {}),
    ...(typeof e.extensionRPC === 'string' ? { extensionRPC: e.extensionRPC } : {}),
    ...(typeof e.extensionKind === 'string' ? { extensionKind: e.extensionKind } : {}),
    ...('extensionData' in e ? { extensionData: e.extensionData } : {}),
  };
}
