// A stand-in for xterm.js's Terminal where there is no page: node, in
// tool/web_check.dart's twk_web and gallery cases, which load this before
// the app. It shows nothing; it keeps what was written as text, answers
// DA1 as xterm.js 6.0.0 does (CSI ? 1 ; 2 c) while it parses a write,
// after the write returned, then calls the write's callback. Each one made
// is in globalThis.terminals.
//
// What xterm.js has not, for the program that drives it: `writes`, how
// many writes it was given, each numbered from 1 when it is; and
// `onWritten(listener)`, which calls listener(text, number) once a
// write's text is in `text`, before its callback, so that a program
// awaits what was written instead of looking at `text` on a timer.
globalThis.terminals = [];

globalThis.Terminal = class {
  constructor(options) {
    this.options = options;
    this.cols = 80;
    this.rows = 24;
    this.text = '';
    this.decoder = new TextDecoder();
    this.opened = false;
    this.disposed = false;
    this.listeners = { data: new Set(), binary: new Set(), resize: new Set() };
    this.writes = 0;
    this.written = new Set();
    globalThis.terminals.push(this);
  }

  open(parent) { this.opened = parent !== undefined; }
  focus() {}
  loadAddon(addon) {}
  dispose() { this.disposed = true; }

  onData(listener) { return this.#add('data', listener); }
  onBinary(listener) { return this.#add('binary', listener); }
  onResize(listener) { return this.#add('resize', listener); }

  onWritten(listener) {
    this.written.add(listener);
    return { dispose: () => this.written.delete(listener) };
  }

  #add(name, listener) {
    this.listeners[name].add(listener);
    return { dispose: () => this.listeners[name].delete(listener) };
  }

  write(data, parsed) {
    const text = typeof data === 'string'
      ? data
      : this.decoder.decode(data, { stream: true });
    const number = ++this.writes;
    setTimeout(() => {
      this.text += text;
      for (const listener of this.written) listener(text, number);
      if (text.includes('\x1b[c')) {
        for (const listener of this.listeners.data) listener('\x1b[?1;2c');
      }
      parsed?.();
    });
  }
};
