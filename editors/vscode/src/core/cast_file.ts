// A recording's file (app/ports.ts's CastSink): made or emptied when the
// recording begins, a line written at a time as it goes, as `twk record`
// writes its own; node's fs, so not in the webview's bundle.
import * as fs from 'node:fs';

/** The file at [path] as a recording's sink. */
export function fileSink(path: string): { write(text: string): void; close(): Promise<void> } {
  const fd = fs.openSync(path, 'w');
  let closed = false;
  return {
    write: (text) => {
      if (!closed) {
        fs.writeSync(fd, text);
      }
    },
    close: async () => {
      if (!closed) {
        closed = true;
        fs.closeSync(fd);
      }
    },
  };
}
