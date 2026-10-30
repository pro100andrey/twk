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

/**
 * Cuts a socket's bytes into frames, however the reads split them. The
 * reads are kept as they came and joined once a frame is whole: a large
 * frame in many reads is copied once, not once a read.
 */
export class FrameReader {
  private chunks: Buffer[] = [];
  private length = 0;

  constructor(private readonly onFrame: (type: number, payload: Buffer) => void) {}

  /** Throws for a payload longer than Wire.maxPayload. */
  add(bytes: Buffer): void {
    if (bytes.length === 0) {
      return;
    }
    this.chunks.push(bytes);
    this.length += bytes.length;
    while (this.length >= 5) {
      const head = this.peek(5);
      const length = head.readUInt32BE(1);
      if (length > Wire.maxPayload) {
        throw new Error(`a frame of ${length} bytes`);
      }
      if (this.length - 5 < length) {
        break;
      }
      const whole = this.take(5 + length);
      this.onFrame(whole[0], Buffer.from(whole.subarray(5)));
    }
  }

  /** The first [n] bytes kept, left kept. */
  private peek(n: number): Buffer {
    const first = this.chunks[0];
    if (first.length >= n) {
      return first;
    }
    const joined = Buffer.concat(this.chunks);
    this.chunks = [joined];
    return joined;
  }

  /** The first [n] bytes kept, no more kept. */
  private take(n: number): Buffer {
    let first = this.chunks[0];
    if (first.length < n) {
      let k = 0;
      let got = 0;
      while (got < n) {
        got += this.chunks[k++].length;
      }
      first = Buffer.concat(this.chunks.splice(0, k), got);
      this.chunks.unshift(first);
    }
    this.length -= n;
    if (first.length === n) {
      this.chunks.shift();
    } else {
      this.chunks[0] = first.subarray(n);
    }
    return first.subarray(0, n);
  }
}
