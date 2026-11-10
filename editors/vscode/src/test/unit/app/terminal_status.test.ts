// The status of the active twk terminal (app/terminal_status.ts) over fake views and a fake sink.
import * as assert from 'node:assert/strict';

import { TerminalStatusSink } from '../../../app/ports';
import { TerminalStatus } from '../../../app/terminal_status';
import { Terminals } from '../../../app/terminals';
import { FakeDesktop, FakeLog, FakeSettings, FakeView, realShell } from '../fakes';

class FakeSink implements TerminalStatusSink {
  text: string | undefined;
  tooltip: string | undefined;
  shown = 0;
  show(text: string | undefined, tooltip?: string): void {
    this.text = text;
    this.tooltip = tooltip;
    this.shown++;
  }
}

describe('TerminalStatus', () => {
  let views: FakeView[];
  let settings: FakeSettings;
  let terminals: Terminals;
  let sink: FakeSink;
  let status: TerminalStatus;

  beforeEach(() => {
    views = [];
    settings = new FakeSettings();
    sink = new FakeSink();
    terminals = new Terminals({
      views: (title) => {
        const v = new FakeView(title);
        views.push(v);
        return v;
      },
      startShell: realShell,
      settings,
      log: new FakeLog(),
      desktop: new FakeDesktop(),
    });
    status = new TerminalStatus(terminals, sink);
  });

  afterEach(async () => {
    status.dispose();
    await terminals.dispose();
  });

  it('says the size, the profile and the switches on of the newest terminal, and follows a resize and the settings', async () => {
    assert.equal(sink.text, undefined);
    await terminals.create('a.dart');
    assert.equal(sink.text, 'twk 100x30 · xterm.js');
    views[0].resize(44, 7);
    assert.equal(sink.text, 'twk 44x7 · xterm.js');
    settings.switchesOn = { screenReader: false, debug: ['overlay'] };
    terminals.retitle();
    assert.equal(sink.text, 'twk 44x7 · xterm.js · overlay');
    assert.match(sink.tooltip ?? '', /a\.dart/);
  });

  it('follows the terminal whose panel is focused, else the newest; hides with the last one closed', async () => {
    await terminals.create('a.dart');
    views[0].resize(40, 10);
    const b = await terminals.create('b.dart');
    views[1].resize(50, 12);
    assert.equal(sink.text, 'twk 50x12 · xterm.js', 'the newest');
    views[0].setActive(true);
    assert.equal(sink.text, 'twk 40x10 · xterm.js', 'the focused');
    views[0].setActive(false);
    views[1].setActive(true);
    assert.equal(sink.text, 'twk 50x12 · xterm.js');
    await b.dispose();
    assert.equal(sink.text, 'twk 40x10 · xterm.js');
    await terminals.all()[0].dispose();
    assert.equal(sink.text, undefined);
  });
});
