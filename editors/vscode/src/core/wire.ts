// The frames of twk's socket terminal (packages/twk_core/lib/src/terminal/
// socket.dart, `Wire`): a type byte, the payload's length (4 bytes, big
// endian) and the payload. This file must say what that one says:
// packages/twk_core/test/terminal/shell_wire.golden.json holds both to the
// same bytes (test/unit/core/wire_golden.test.ts here).

export const Wire = {
  protocol: 1,
  // app to shell
  hello: 1,
  output: 2,
  flush: 3,
  lost: 4,
  raw: 5,
  // shell to app
  welcome: 16,
  refused: 17,
  input: 18,
  size: 19,
  flushed: 20,
  maxPayload: 1 << 26,
} as const;

/** A frame of [type] with [payload]. */
export function frame(type: number, payload: Uint8Array = new Uint8Array()): Buffer {
  const b = Buffer.alloc(5 + payload.length);
  b[0] = type;
  b.writeUInt32BE(payload.length, 1);
  b.set(payload, 5);
  return b;
}

/** A frame of [type] whose payload is [json], UTF-8 encoded. */
export function jsonFrame(type: number, json: unknown): Buffer {
  return frame(type, Buffer.from(JSON.stringify(json), 'utf8'));
}

/** Cuts a socket's bytes into frames, however the reads split them. */
export class FrameReader {
  private buffer: Buffer = Buffer.alloc(0);

  constructor(private readonly onFrame: (type: number, payload: Buffer) => void) {}

  /** Throws for a payload longer than Wire.maxPayload. */
  add(bytes: Buffer): void {
    this.buffer = this.buffer.length === 0 ? bytes : Buffer.concat([this.buffer, bytes]);
    let at = 0;
    while (this.buffer.length - at >= 5) {
      const length = this.buffer.readUInt32BE(at + 1);
      if (length > Wire.maxPayload) {
        throw new Error(`a frame of ${length} bytes`);
      }
      if (this.buffer.length - at - 5 < length) {
        break;
      }
      const type = this.buffer[at];
      const payload = Buffer.from(this.buffer.subarray(at + 5, at + 5 + length));
      at += 5 + length;
      this.onFrame(type, payload);
    }
    this.buffer = this.buffer.subarray(at);
  }
}
