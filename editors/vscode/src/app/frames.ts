// The twk frames panel: the last frames the app drew as bars (their time or
// their bytes), the median, the count and the slowest, in a view of the
// bottom panel ([FramesView]); a click on a bar shows that frame in the
// terminal's sequence log. The data is the app's own `twk.frame` event
// (core/frames.ts), which the app posts while `ext.twk.flags` `frameEvents`
// is on: switched on while the view is on the screen and off after, for the
// app the view shows (the newest, as the inspector's), told again to an app
// whose binding came after its VM service. A frame is found in the log by
// the app's count of the bytes it had written (`outputWritten`), which the
// log keeps by the same count (LogPanel.revealAppBytes). The state is sent to
// the view at most every [renderGap] ms.
import { Disposable, Event } from '../core/events';
import { FrameHistory, Metric, barsOf, parseFrameEvent, summarize } from '../core/frames';
import { AppService, flagParams, parseFlags } from '../core/inspect';
import { FramesState } from '../webview/frames_protocol';
import { AppConnection } from './hot_apps';
import { Clock, Notice } from './ports';
import { TwkTerminal } from './terminal';

/** The least time between two sendings of the bars to the view. */
export const renderGap = 100;

/** What the view says while no app is there. */
export const noApp = 'No twk app runs: Run or Debug one in a twk terminal (twk: Run Dart File in twk Terminal, or F5).';

/** What it says while the app drew nothing yet (or the view is hidden, which asks no events). */
export const noFrames = 'The app has drawn no frame yet.';

/** What it says of an app whose twk does not post `twk.frame`. */
export const noEvents = 'This app does not post frame events: its twk is older than the panel.';

/** What it says beside the bars of an app that gives no frame times. */
export const noTimes = 'This app gives no frame times: the bars show bytes only (the difference of its output counts).';

/** The frames panel on the screen. */
export interface FramesView {
  show(state: FramesState): void;
  /** Whether it is on the screen now. */
  readonly visible: boolean;
  readonly onVisible: Event<boolean>;
  /** The person chose what the bars measure. */
  readonly onMetric: Event<Metric>;
  /** The person clicked the bar of a frame. */
  readonly onPick: Event<number>;
  /** The person asked to forget the frames. */
  readonly onClear: Event<void>;
}

/** Where a frame is shown in the sequence log of a terminal. */
export interface FrameLogs {
  /** Opens the log of [terminal] when it is closed, and shows the entry where the app had written [count] bytes. */
  reveal(terminal: TwkTerminal, count: number): { readonly found: boolean; readonly dropped: boolean };
}

export interface FramesDeps {
  /** The apps' VM services as they come and go (HotApps.onApp). */
  readonly apps: Event<AppConnection>;
  readonly view: FramesView;
  readonly logs: FrameLogs;
  readonly notice: Notice;
  readonly clock: Clock;
}

/** An app the panel follows: its terminal, its service, and the frames it drew. */
interface Target {
  readonly terminal: TwkTerminal;
  readonly service: AppService;
  readonly history: FrameHistory;
  readonly listening: Disposable[];
  /** The app said it does not know `frameEvents`. */
  silent: boolean;
}

export class Frames {
  private readonly targets: Target[] = [];
  private current: Target | undefined;
  private metric: Metric = 'time';
  private timer: Disposable | undefined;
  private readonly listening: Disposable[];

  constructor(private readonly deps: FramesDeps) {
    this.listening = [
      deps.apps((c) => this.connected(c)),
      deps.view.onVisible((on) => {
        if (this.current) {
          void this.follow(this.current, on);
        }
        this.render();
      }),
      deps.view.onMetric((m) => {
        this.metric = m;
        this.render();
      }),
      deps.view.onPick((frame) => this.pick(frame)),
      deps.view.onClear(() => {
        this.current?.history.clear();
        this.render();
      }),
    ];
    deps.view.show(this.stateOf());
  }

  /** What the bars measure. */
  get measuring(): Metric {
    return this.metric;
  }

  /** The state the view was last given, as the app is now: for the tests. */
  get state(): FramesState {
    return this.stateOf();
  }

  private connected({ terminal, service }: AppConnection): void {
    const old = this.targets.find((t) => t.terminal === terminal);
    if (old) {
      this.drop(old);
    }
    if (!service) {
      return;
    }
    const target: Target = { terminal, service, history: new FrameHistory(), listening: [], silent: false };
    target.listening.push(
      service.onEvent((e) => {
        if (e.kind === 'bound') {
          // its binding came after its VM service: told now what it was to be told
          if (target === this.current && this.deps.view.visible) {
            void this.follow(target, true);
          }
          this.render();
        } else if (e.kind === 'extension' && e.name === 'twk.frame') {
          this.frame(target, e.data);
        }
      }),
    );
    this.targets.push(target);
    void service.closed.then(() => this.drop(target));
    this.show(target);
  }

  /** Takes a `twk.frame` of [target]; one of a version this does not read is not a frame. */
  private frame(target: Target, data: unknown): void {
    const event = parseFrameEvent(data);
    if (event && target.history.add(event) && target === this.current) {
      this.render();
    }
  }

  private show(target: Target): void {
    if (target === this.current) {
      return;
    }
    const before = this.current;
    this.current = target;
    if (this.deps.view.visible) {
      if (before) {
        void this.follow(before, false);
      }
      void this.follow(target, true);
    }
    this.render();
  }

  private drop(target: Target): void {
    const at = this.targets.indexOf(target);
    if (at < 0) {
      return;
    }
    this.targets.splice(at, 1);
    target.listening.forEach((d) => d.dispose());
    if (target === this.current) {
      this.current = undefined;
      const next = this.targets.at(-1);
      if (next) {
        this.show(next);
      } else {
        this.render();
      }
    }
  }

  /** Has the app post `twk.frame`, or not. */
  private async follow(target: Target, on: boolean): Promise<void> {
    if (!target.service.bound) {
      // told once it is
      return;
    }
    try {
      const answer = await target.service.extension('ext.twk.flags', flagParams({ frameEvents: on }));
      if (on) {
        target.silent = parseFlags(answer).frameEvents === undefined;
        this.render();
      }
    } catch {
      // gone, or not yet there: the next app is told as it comes
    }
  }

  /** A click on the bar of [frame]: shown in the log of the terminal of the app. */
  private pick(frame: number): void {
    const target = this.current;
    const sample = target?.history.samples.find((s) => s.frame === frame);
    if (!target || !sample) {
      return;
    }
    if (sample.outputWritten === null) {
      this.deps.notice.say(`Frame ${frame} cannot be found in the log: the app does not count its output.`);
      return;
    }
    const shown = this.deps.logs.reveal(target.terminal, sample.outputWritten);
    if (!shown.found) {
      this.deps.notice.say(`Frame ${frame} is not in the log.`);
    } else if (shown.dropped) {
      this.deps.notice.say(`Frame ${frame} is no longer in the log.`);
    }
  }

  private stateOf(): FramesState {
    const target = this.current;
    const empty = (message: string): FramesState => ({ message, note: '', metric: this.metric, bars: [], summary: summarize([], this.metric) });
    if (!target) {
      return empty(noApp);
    }
    if (!target.service.bound) {
      return empty('The app is starting.');
    }
    const samples = target.history.samples;
    if (samples.length === 0) {
      return empty(target.silent ? noEvents : noFrames);
    }
    return {
      message: '',
      note: this.metric === 'time' && samples.every((s) => s.micros === null) ? noTimes : '',
      metric: this.metric,
      bars: barsOf(samples, this.metric),
      summary: summarize(samples, this.metric, target.history.total),
    };
  }

  /** Sends the state to the view, at most every [renderGap]. */
  private render(): void {
    this.timer ??= this.deps.clock.setTimeout(() => {
      this.timer = undefined;
      this.deps.view.show(this.stateOf());
    }, renderGap);
  }

  dispose(): void {
    this.timer?.dispose();
    this.timer = undefined;
    if (this.current && this.deps.view.visible) {
      void this.follow(this.current, false);
    }
    this.listening.forEach((d) => d.dispose());
    this.targets.splice(0).forEach((t) => t.listening.forEach((d) => d.dispose()));
    this.current = undefined;
  }
}
