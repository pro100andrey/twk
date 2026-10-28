// A recording of a real twk app, read back by twk_dev: packages/twk's
// example/counter.dart run by the extension's run (HotApps over core's
// HotRun) in a twk terminal over a headless xterm.js, recorded from the
// middle of its session (the app asked to paint all of itself), Up typed
// twice; then twk_dev's own castFrames (cast_frames.dart, twk_test's
// emulator) shows the file's frames, and the extension's player, a frame
// at a time into another headless xterm.js, the same frames with the same
// screens. And its sequence log names what the app wrote.
import * as assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { HotApps } from '../../../app/hot_apps';
import { LogPanel } from '../../../app/log_panel';
import { Player } from '../../../app/player';
import { Recordings } from '../../../app/recording';
import { Terminals } from '../../../app/terminals';
import { castSteps, parseCast } from '../../../core/cast';
import { fileSink } from '../../../core/cast_file';
import { realClock } from '../../../core/events';
import { startNodeProcess } from '../../../core/process';
import { HotRun } from '../../../core/runner';
import { VmClient } from '../../../core/vm';
import { ToLog } from '../../../webview/log_protocol';
import { FakeDebugger, FakeDesktop, FakeLog, FakePanel, FakeSettings, FakeStatus, realShell } from '../fakes';
import { HeadlessView } from '../headless_view';

/** From out/test/unit/app, where this runs compiled, to the repository's root. */
const root = path.resolve(__dirname, '../../../../../..');
const counter = path.join(root, 'packages', 'twk', 'example', 'counter.dart');
/** In packages/twk_dev, whose package config has twk_dev; git ignores .dart_tool. */
const twkDev = path.join(root, 'packages', 'twk_dev');
const scratch = path.join(twkDev, '.dart_tool', 'twk_vscode_unit');

/** Prints castFrames of the recording it is given, as JSON. */
const framesProgram = `import 'dart:convert';
import 'dart:io';

import 'package:twk_dev/cast_frames.dart';

void main(List<String> args) {
  final frames = castFrames(Cast.read(args.single));
  stdout.write(jsonEncode([
    for (final f in frames)
      {'number': f.number, 'time': f.time, 'width': f.width, 'height': f.height, 'lines': f.lines, 'errors': f.errors},
  ]));
}
`;

interface DartFrame {
  readonly number: number;
  readonly time: number;
  readonly width: number;
  readonly height: number;
  readonly lines: readonly string[];
  readonly errors: readonly string[];
}

describe('a recording of a twk app, read back by twk_dev', function () {
  this.timeout(240000);
  let log: FakeLog;
  let views: HeadlessView[];
  let terminals: Terminals;
  let apps: HotApps;
  let dir: string;

  async function until(what: string, f: () => boolean, ms = 90000): Promise<void> {
    const end = Date.now() + ms;
    while (!f()) {
      if (Date.now() > end) {
        throw new Error(`no ${what} in ${ms} ms; the screen:\n${views[0]?.rows().join('\n')}\nlog:\n${log.text}`);
      }
      await new Promise((r) => setTimeout(r, 20));
    }
  }

  beforeEach(() => {
    fs.mkdirSync(scratch, { recursive: true });
    dir = fs.mkdtempSync(path.join(scratch, 'cast_'));
    log = new FakeLog();
    views = [];
    const settings = new FakeSettings();
    terminals = new Terminals({
      views: () => {
        const v = new HeadlessView(50, 12);
        views.push(v);
        return v;
      },
      startShell: realShell,
      settings,
      log,
      desktop: new FakeDesktop(),
    });
    const connectVm = (uri: string) => VmClient.connect(uri, realClock);
    apps = new HotApps({
      terminals,
      runner: (options) => {
        const run = HotRun.start(options, { startProcess: startNodeProcess, connectVm, env: process.env, clock: realClock });
        return {
          get pid() {
            return run.process?.pid;
          },
          reload: () => run.reload(),
          restart: () => run.restart(),
          stop: () => run.stop(),
          redraw: () => run.redraw(),
          ended: run.ended,
        };
      },
      debugger: new FakeDebugger(),
      connectVm,
      status: new FakeStatus(),
      context: () => {},
      log,
      settings,
      clock: realClock,
      env: {},
    });
  });

  afterEach(async () => {
    await apps.dispose();
    await terminals.dispose();
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it('recorded from the middle of a session: twk_dev shows its frames, and the player the same', async () => {
    await apps.runFile(counter);
    const shows = (text: string) => () => views[0].rows().some((r) => r.includes(text));
    await until('Count: 0', shows('Count: 0'));
    // the app's VM service is up once it can be reloaded
    await until('the app reloadable', () => apps.hots()[0] !== undefined);
    const terminal = terminals.all()[0];
    const panel = new FakePanel<ToLog>();
    const logPanel = new LogPanel(terminal, panel, realClock);

    const file = path.join(dir, 'counter.cast');
    const recordings = new Recordings({
      clock: realClock,
      epochSeconds: () => Date.now() / 1000,
      term: () => 'xterm-256color',
      redrawOf: (t) => {
        const app = apps.hots().find((h) => h.terminal === t);
        return app ? () => app.redraw() : undefined;
      },
    });
    const recording = await recordings.start(terminal, fileSink(file));
    // the whole screen again, by the app
    await until('the redraw recorded', () => fs.readFileSync(file, 'utf8').includes('Count: '));
    views[0].type('\x1b[A');
    await until('Count: 1', shows('Count: 1'));
    views[0].type('\x1b[A');
    await until('Count: 2', shows('Count: 2'));
    const end = await recording.stop();
    assert.equal(end.error, undefined);
    views[0].type('q');
    await until('the app gone', () => apps.hots().length === 0);

    const cast = parseCast(fs.readFileSync(file, 'utf8'));
    assert.deepEqual([cast.header.width, cast.header.height], [50, 12]);
    assert.ok(cast.events.some((e) => e.code === 'i' && e.data === '\x1b[A'), 'the keys recorded');

    // twk_dev's frames of it
    const program = path.join(dir, 'frames.dart');
    fs.writeFileSync(program, framesProgram);
    const json = await new Promise<string>((resolve, reject) =>
      execFile('dart', ['run', program, file], { cwd: twkDev, timeout: 180000, maxBuffer: 1 << 26 }, (e, out, err) =>
        e ? reject(new Error(`${e.message}\n${err}`)) : resolve(out),
      ),
    );
    const dart = JSON.parse(json) as DartFrame[];
    assert.ok(dart.length >= 3, `${dart.length} frames`);
    assert.deepEqual(dart.at(-1)?.errors, [], 'nothing twk_test does not know');
    assert.ok(
      dart[0].lines.some((l) => l.includes('Count: 0')),
      `the first frame a whole screen:\n${dart[0].lines.join('\n')}`,
    );
    assert.ok(dart.at(-1)!.lines.some((l) => l.includes('Count: 2')));

    // the player's: the same frames, at the same times, showing the same
    const steps = castSteps(cast).filter((s) => s.frame > 0);
    assert.deepEqual(
      steps.map((s) => [s.frame, s.time]),
      dart.map((f) => [f.number, f.time]),
    );
    const replay = new HeadlessView(80, 24);
    const player = new Player('counter.cast', cast, replay, realClock);
    try {
      await player.start(false);
      for (const f of dart) {
        do {
          player.step();
          await player.settled;
        } while (player.state.frame < f.number);
        assert.deepEqual(replay.rows(), f.lines, `frame ${f.number}`);
        assert.deepEqual([replay.columns, replay.lines], [f.width, f.height]);
      }
    } finally {
      player.dispose();
    }

    // and what its log made of the same
    logPanel.flush();
    const names = logPanel.entries().map((e) => e.name);
    assert.ok(names.some((n) => /^frame \d+: .*CUP/.test(n)), names.join('\n'));
    assert.ok(names.includes('key Up'), names.join('\n'));
    assert.ok(names.includes('key q'), names.join('\n'));
    assert.ok(names.some((n) => n.startsWith('DECRST 1049')), names.join('\n'));
    logPanel.dispose();
  });
});
