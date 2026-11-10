// What the status bar says of the active twk terminal: its size, profile and
// switches, kept up to date as terminals come and go, are resized, retitled
// or focused.
import { Disposable } from '../core/events';
import { TerminalStatusSink } from './ports';
import { Terminals } from './terminals';

export class TerminalStatus implements Disposable {
  private readonly listening: Disposable[] = [];

  constructor(
    private readonly terminals: Terminals,
    private readonly sink: TerminalStatusSink,
  ) {
    this.listening.push(terminals.onDidCreate((t) => {
      this.listening.push(
        t.onDidRetitle(() => this.refresh()),
        t.onDidDispose(() => this.refresh()),
        t.view.onDidChangeActive(() => this.refresh()),
      );
      this.refresh();
    }));
  }

  /** Shows the active terminal (the panel focused, else the newest), or nothing where none is open. */
  refresh(): void {
    const open = this.terminals.all().filter((t) => !t.isClosed);
    const t = open.find((o) => o.view.isActive) ?? open.at(-1);
    if (t === undefined) {
      this.sink.show(undefined);
    } else {
      this.sink.show(t.statusText(), `${t.name}: the size, the profile and the switches of the twk terminal. Click to choose the capabilities.`);
    }
  }

  dispose(): void {
    this.listening.forEach((d) => d.dispose());
  }
}
