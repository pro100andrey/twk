// Events without vscode: what the app layer and its ports listen with.

/** Something to stop: a listener, a timer, a resource. */
export interface Disposable {
  dispose(): void;
}

/** Listens with [f] until the [Disposable] it returns is disposed. */
export type Event<T> = (f: (value: T) => void) => Disposable;

/** The listeners of one event, told in the order they came. */
export class Emitter<T> implements Disposable {
  private readonly listeners = new Set<(value: T) => void>();

  readonly event: Event<T> = (f) => {
    const listener = (value: T) => f(value);
    this.listeners.add(listener);
    return { dispose: () => this.listeners.delete(listener) };
  };

  /** How many listen now. */
  get size(): number {
    return this.listeners.size;
  }

  fire(value: T): void {
    for (const f of [...this.listeners]) {
      f(value);
    }
  }

  dispose(): void {
    this.listeners.clear();
  }
}

/** A timer source: real time in the extension, a fake clock in a test. */
export interface Clock {
  setTimeout(f: () => void, ms: number): Disposable;
  /** Milliseconds from a point of its own, never going back: what a recording's and a log's times are of. */
  now(): number;
}

/** The [Clock] of node's timers. */
export const realClock: Clock = {
  setTimeout: (f, ms) => {
    const t = setTimeout(f, ms);
    return { dispose: () => clearTimeout(t) };
  },
  now: () => performance.now(),
};
