// Hot reload of a twk app over its VM service, as `twk run` does it
// (packages/twk_dev/lib/src/run.dart, HotRunner): the sources reloaded
// (`reloadSources`) in the isolate of the app's binding, the one that
// registered `ext.twk.reassemble`, then that extension called, so that the
// app rebuilds and repaints all of itself, each State kept; what it did
// told to the app's log (`ext.twk.log`; a failure as a warning, which
// leaves the app's console closed) and to [HotApp.onStatus]. The app's own hot keys (Ctrl+G h, Ctrl+G H with
// TWK_DEBUG=keys) post `twk.reload` and `twk.restart`: the first reloads,
// the second is given to whoever started the app ([HotApp.restart]), which
// alone can start it again. No vscode import: its tests run under plain node.
import { Emitter } from './events';
import { AppEvent, AppService } from './inspect';
import { Vm, VmError, VmEvent } from './vm';

export type HotStatus =
  | { state: 'running' }
  | { state: 'reloading' }
  | { state: 'reloaded'; libraries: number; ms: number }
  | { state: 'failed'; errors: string }
  | { state: 'restarting' }
  | { state: 'ended' };

export class HotApp implements AppService {
  /** The isolate of the app's binding, once it registered `ext.twk.reassemble`. */
  isolate: string | undefined;
  private reloading: Promise<HotStatus> | undefined;
  private again = false;
  /** A reload was asked for before the binding was there: done when it is. */
  private held: ((s: HotStatus) => void)[] = [];
  private last: HotStatus = { state: 'running' };
  private readonly events = new Emitter<AppEvent>();
  /** What the app posted on the `Extension` stream (its pick, its tree changed...), and each hot reload done: for an inspector. */
  readonly onEvent = this.events.event;

  private constructor(
    private readonly vmService: Vm,
    /** Each status the app goes through. */
    private readonly onStatus: (s: HotStatus) => void,
    /** The app asked for a restart (Ctrl+G H). */
    private readonly onRestart: () => void,
  ) {}

  /** Listens to [vm]'s app, its binding found as it registers its extensions or as it had. */
  static async attach(vm: Vm, onStatus: (s: HotStatus) => void, onRestart: () => void): Promise<HotApp> {
    const app = new HotApp(vm, onStatus, onRestart);
    try {
      await vm.listen('Isolate', (e) => app.onIsolateEvent(e));
      await vm.listen('Extension', (e) => app.onExtensionEvent(e));
      // registered before we listened
      const isolates = records((await vm.call('getVM')).isolates);
      for (const id of isolates.map((i) => i.id).filter((id) => typeof id === 'string')) {
        try {
          const isolate = await vm.call('getIsolate', { isolateId: id });
          if (Array.isArray(isolate.extensionRPCs) && isolate.extensionRPCs.includes('ext.twk.reassemble')) {
            app.found(id);
          }
        } catch {
          // gone meanwhile
        }
      }
    } catch (e) {
      // nobody else has the connection to close it
      vm.close();
      throw e;
    }
    void vm.closed.then(() => {
      app.events.dispose();
      app.status({ state: 'ended' });
      app.held.splice(0).forEach((f) => f(app.last));
    });
    return app;
  }

  /** Settles once the connection is gone: the app ended, or [close]. */
  get closed(): Promise<void> {
    return this.vmService.closed;
  }

  /** Calls the binding's service extension [method] (`ext.twk.tree`...); fails while the binding isn't there. */
  extension(method: string, params: Readonly<Record<string, string>> = {}): Promise<Record<string, unknown>> {
    return this.vm(method, params);
  }

  /** Calls the VM service's [method] in the binding's isolate; fails while the binding isn't there. */
  vm(method: string, params: Readonly<Record<string, unknown>> = {}): Promise<Record<string, unknown>> {
    const isolate = this.isolate;
    if (isolate === undefined) {
      return Promise.reject(new Error("the app's binding is not there (yet)"));
    }
    return this.vmService.call(method, { ...params, isolateId: isolate });
  }

  /** The status last told. */
  get current(): HotStatus {
    return this.last;
  }

  /**
   * Reloads the sources and reassembles the app; one reload at a time, one
   * asked for meanwhile running after it. Settles with how the reload that
   * took this request in ended.
   */
  reload(): Promise<HotStatus> {
    if (this.isolate === undefined) {
      return new Promise((resolve) => this.held.push(resolve));
    }
    if (this.reloading) {
      // the running one goes round once more, with what changed since
      this.again = true;
      return this.reloading;
    }
    const run = (async () => {
      let s: HotStatus;
      do {
        this.again = false;
        s = await this.reloadOnce(this.isolate!);
      } while (this.again);
      this.reloading = undefined;
      return s;
    })();
    this.reloading = run;
    return run;
  }

  /**
   * Has the app build and paint all of itself again, no sources reloaded
   * (`ext.twk.reassemble`): its terminal came back empty (a webview that
   * loaded again). Nothing when its binding isn't there, or it went away.
   */
  async redraw(): Promise<void> {
    const isolate = this.isolate;
    if (isolate === undefined) {
      return;
    }
    try {
      await this.vmService.call('ext.twk.reassemble', { isolateId: isolate });
    } catch {
      // the app went away
    }
  }

  /** The app is restarted by whoever started it: told as a status. */
  restarting(): void {
    this.status({ state: 'restarting' });
  }

  close(): void {
    this.vmService.close();
  }

  private async reloadOnce(isolate: string): Promise<HotStatus> {
    this.status({ state: 'reloading' });
    const started = Date.now();
    let report: Record<string, unknown>;
    try {
      report = await this.vmService.call('reloadSources', { isolateId: isolate });
    } catch (e) {
      return this.failed(isolate, e instanceof VmError ? `${e.message}: ${JSON.stringify(e.data)}` : String(e));
    }
    if (report.success !== true) {
      const messages = records(report.notices).map((n) => n.message);
      return this.failed(isolate, messages.filter((m) => typeof m === 'string' && m).join('\n') || JSON.stringify(report));
    }
    try {
      await this.vmService.call('ext.twk.reassemble', { isolateId: isolate });
    } catch (e) {
      return this.failed(isolate, `reassemble: ${String(e)}`);
    }
    const [details] = records([report.details]);
    const libraries = typeof details?.loadedLibraryCount === 'number' ? details.loadedLibraryCount : 0;
    const s: HotStatus = { state: 'reloaded', libraries, ms: Date.now() - started };
    await this.log(isolate, `hot reload: ${s.libraries === 1 ? '1 library' : `${s.libraries} libraries`} in ${s.ms} ms`);
    this.events.fire({ kind: 'reloaded' });
    return this.status(s);
  }

  // A warning, not an error as `twk run` logs it: an error opens the app's
  // console, which covers the app and takes its keys, where the status bar
  // and the output say it already.
  private async failed(isolate: string, errors: string): Promise<HotStatus> {
    await this.log(isolate, 'hot reload failed', 'warning', errors);
    return this.status({ state: 'failed', errors });
  }

  private async log(isolate: string, message: string, level = 'info', error?: string): Promise<void> {
    try {
      await this.vmService.call('ext.twk.log', { isolateId: isolate, message, level, ...(error ? { error } : {}) });
    } catch {
      // the app went away
    }
  }

  private status(s: HotStatus): HotStatus {
    this.last = s;
    this.onStatus(s);
    return s;
  }

  get bound(): boolean {
    return this.isolate !== undefined;
  }

  private found(isolate: string): void {
    this.isolate = isolate;
    this.events.fire({ kind: 'bound' });
    const held = this.held.splice(0);
    if (held.length) {
      void this.reload().then((s) => held.forEach((f) => f(s)));
    }
  }

  private onIsolateEvent(e: VmEvent): void {
    if (e.kind === 'ServiceExtensionAdded' && e.extensionRPC === 'ext.twk.reassemble' && e.isolate) {
      this.found(e.isolate.id);
    } else if (e.kind === 'IsolateExit' && e.isolate?.id === this.isolate) {
      this.isolate = undefined;
    }
  }

  private onExtensionEvent(e: VmEvent): void {
    if (e.kind !== 'Extension') {
      return;
    }
    if (e.extensionKind !== undefined) {
      this.events.fire({ kind: 'extension', name: e.extensionKind, data: e.extensionData });
    }
    if (e.extensionKind === 'twk.reload') {
      void this.reload();
    } else if (e.extensionKind === 'twk.restart') {
      this.onRestart();
    }
  }
}

/** The objects of [v], a JSON array; nothing else. */
function records(v: unknown): Record<string, unknown>[] {
  return Array.isArray(v) ? v.filter((e): e is Record<string, unknown> => typeof e === 'object' && e !== null) : [];
}

/** A line for [s], as the status bar shows it. */
export function describe(s: HotStatus): string {
  switch (s.state) {
    case 'running':
      return 'twk: hot reload ready';
    case 'reloading':
      return 'twk: reloading';
    case 'reloaded':
      return `twk: reloaded (${s.libraries === 1 ? '1 library' : `${s.libraries} libraries`}, ${s.ms} ms)`;
    case 'failed':
      return 'twk: reload failed';
    case 'restarting':
      return 'twk: restarting';
    case 'ended':
      return 'twk: the app ended';
  }
}
