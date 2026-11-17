// A driver trace (core/trace.ts) in a panel of its own, the page of
// webview/trace.ts, spoken to in the messages of webview/trace_protocol.ts:
// once the page is up it is sent the steps (passed and failed), the cast's
// output to replay the screen before, between and after a step from, and
// the step to start at (the first that failed); the detail of a step (its
// facts, the tree, the app's log, the sequences it wrote) when it is selected.
import { Cast } from '../core/cast';
import { Disposable } from '../core/events';
import { TraceFile, eventOfFrame, firstFailed, siblingOf, stepFacts, stepLabel, stepScreens, stepSequences, treeAt, wireEvents } from '../core/trace';
import { StepDetail, StepRow, ToTrace, isFromTrace } from '../webview/trace_protocol';
import { WebviewPanelPort } from './webview_view';

/** The rows of the steps of [trace]. */
export function stepRows(trace: TraceFile): StepRow[] {
  return trace.steps.map((s) => ({
    label: stepLabel(s),
    ok: s.ok,
    ...stepScreens(trace, s),
    outline: s.target?.shown ?? null,
  }));
}

/** What is told of step [index] of [trace]. */
export function stepDetail(trace: TraceFile, cast: Cast, index: number): StepDetail {
  const step = trace.steps[index];
  return { facts: stepFacts(step), tree: treeAt(trace, index) ?? null, log: step.log, sequences: stepSequences(cast, trace, step) };
}

export class TraceViewer {
  private readonly listening: Disposable[];
  private disposed = false;

  constructor(
    /** What it is called: the trace's file. */
    readonly name: string,
    readonly trace: TraceFile,
    readonly cast: Cast,
    private readonly panel: WebviewPanelPort<ToTrace>,
  ) {
    this.listening = [
      panel.onMessage((m) => {
        if (!isFromTrace(m)) {
          return;
        }
        if (m.type === 'ready') {
          this.open();
        } else if (m.index < trace.steps.length) {
          this.detail(m.index);
        }
      }),
      panel.onDispose(() => {
        this.disposed = true;
        this.listening.forEach((d) => d.dispose());
      }),
    ];
    panel.setTitle(`${name} · twk trace`);
  }

  private open(): void {
    const { header, steps } = this.trace;
    const select = firstFailed(this.trace);
    void this.panel.post({
      type: 'open',
      title: `${this.name} · ${header.program}`,
      width: header.width,
      height: header.height,
      steps: stepRows(this.trace),
      events: wireEvents(this.cast),
      select,
    });
    if (select >= 0 && select < steps.length) {
      this.detail(select);
    }
  }

  private detail(index: number): void {
    void this.panel.post({ type: 'detail', index, detail: stepDetail(this.trace, this.cast, index) });
  }

  reveal(): void {
    this.panel.reveal();
  }

  dispose(): void {
    if (!this.disposed) {
      this.panel.dispose();
    }
  }
}

export { eventOfFrame, siblingOf };
