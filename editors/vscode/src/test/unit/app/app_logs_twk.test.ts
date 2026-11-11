// The apps' log against twk itself: a Dart app serving its log with
// `LogSink.serve` (twk_core) in a project of its own, followed by AppLogs
// over node's endpoints (the real address file and socket): the records it
// kept before, the ones it adds, with levels, error and stack; the frame
// of a package resolved by the project's package configuration; the app's
// end, and the next app of the terminal.
import * as assert from 'node:assert/strict';
import { ChildProcess, spawn } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

import { AppLogs, AppTerminal } from '../../../app/app_logs';
import { Emitter, realClock } from '../../../core/events';
import { nodeLogEndpoints } from '../../../core/log_socket';
import { FakeOpener, FakeSettings } from '../fakes';

/** From out/test/unit/app, where this runs compiled, to the repository's root. */
const root = path.resolve(__dirname, '../../../../../..');

const appSource = `
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:twk_core/terminal.dart';

// Serves a log in the project given, with a record kept; adds the records
// the lines of stdin ask for; ends on "quit".
Future<void> main(List<String> args) async {
  final sink = LogSink();
  await sink.serve(directory: args[0]);
  sink.add(LogRecord(DateTime(2026, 1, 1, 9, 5, 7, 42), LogLevel.info, 'kept before'));
  print('ready');
  final lines = StreamIterator(stdin.transform(utf8.decoder).transform(const LineSplitter()));
  while (await lines.moveNext()) {
    switch (lines.current) {
      case 'more':
        sink.add(LogRecord(DateTime.now(), LogLevel.warning, 'retrying', error: 'timeout'));
        sink.add(LogRecord(DateTime.now(), LogLevel.error, 'failed', error: 'Bad state', stack: StackTrace.fromString('#0      work (package:twk_core/terminal.dart:5:3)\\n#1      main (file:///nowhere/main.dart:9:1)\\n#2      _run (dart:isolate-patch/isolate_patch.dart:1:1)')));
        print('added');
      case 'quit':
        await sink.close();
        exit(0);
    }
  }
}
`;

class FakeTerminal implements AppTerminal {
  private readonly closes = new Emitter<void>();
  readonly onDidDispose = this.closes.event;
  readonly name = 'log_app.dart';
  close(): void {
    this.closes.fire();
  }
}

/** Waits until [f] holds, in real time (the app and the socket are real), for at most 30 s. */
async function waitFor(what: string | (() => string), f: () => boolean): Promise<void> {
  const end = Date.now() + 30000;
  while (!f()) {
    if (Date.now() > end) {
      throw new Error(`no ${typeof what === 'string' ? what : what()} in 30 s`);
    }
    await new Promise((r) => setTimeout(r, 20));
  }
}

describe('the apps\' log against a twk app serving its log', function () {
  this.timeout(120000);
  let dir: string;
  let project: string;
  let logs: AppLogs;
  const opener = new FakeOpener();
  const started: ChildProcess[] = [];

  before(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'twk-applogs-'));
    project = path.join(dir, 'project');
    fs.mkdirSync(path.join(project, '.dart_tool'), { recursive: true });
    fs.writeFileSync(path.join(project, 'pubspec.yaml'), 'name: log_app\n');
    // the project's package configuration: twk_core is the repository's
    fs.writeFileSync(
      path.join(project, '.dart_tool', 'package_config.json'),
      JSON.stringify({ configVersion: 2, packages: [{ name: 'twk_core', rootUri: pathToFileURL(path.join(root, 'packages', 'twk_core')).href, packageUri: 'lib/' }] }),
    );
    fs.writeFileSync(path.join(dir, 'log_app.dart'), appSource);
  });

  after(() => fs.rmSync(dir, { recursive: true, force: true }));

  beforeEach(() => {
    const settings = new FakeSettings();
    settings.switchesOn = { screenReader: false, debug: ['logs'] };
    logs = new AppLogs({ endpoints: nodeLogEndpoints, clock: realClock, settings, opener, readText: (f) => (fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : undefined) });
  });

  afterEach(() => {
    logs.dispose();
    started.splice(0).forEach((p) => p.exitCode === null && p.kill());
  });

  /** Starts the app; the lines it printed, and a way to talk to it. */
  async function app() {
    const p = spawn('dart', [`--packages=${path.join(root, '.dart_tool', 'package_config.json')}`, path.join(dir, 'log_app.dart'), project], {
      cwd: root,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    started.push(p);
    let out = '';
    let err = '';
    p.stdout!.on('data', (b: Buffer) => (out += b.toString('utf8')));
    p.stderr!.on('data', (b: Buffer) => (err += b.toString('utf8')));
    const exited = new Promise<number | null>((r) => p.on('exit', r));
    const saw = (text: string) => waitFor(() => `"${text}" from the app (exit ${p.exitCode}, stdout: ${out}, stderr: ${err})`, () => out.includes(text));
    await saw('ready');
    return {
      saw,
      send: (line: string) => p.stdin!.write(`${line}\n`),
      exited,
    };
  }

  it('shows the records the app kept, those it adds, and its end', async () => {
    const terminal = new FakeTerminal();
    const a = await app();
    logs.started(terminal, project);
    await waitFor('the kept record', () => logs.allRows().some((r) => r.message === 'kept before'));
    a.send('more');
    await a.saw('added');
    await waitFor('the added records', () => logs.allRows().some((r) => r.message === 'failed'));
    const rows = logs.allRows();
    assert.deepEqual(
      rows.map((r) => [r.level, r.message, r.error]),
      [
        ['note', 'connected to the log of the app', undefined],
        ['info', 'kept before', undefined],
        ['warning', 'retrying', 'timeout'],
        ['error', 'failed', 'Bad state'],
      ],
    );
    assert.equal(new Date(rows[1].time).getHours(), 9);
    const failed = rows[3];
    assert.deepEqual(failed.stack?.map((f) => f.open), [true, true, false]);
    await logs.open(failed.id, 0);
    await logs.open(failed.id, 1);
    assert.deepEqual(
      opener.opened.map((s) => [s.uri, s.line, s.column]),
      [
        [pathToFileURL(path.join(root, 'packages', 'twk_core', 'lib', 'terminal.dart')).href, 5, 3],
        ['file:///nowhere/main.dart', 9, 1],
      ],
    );
    a.send('quit');
    assert.equal(await a.exited, 0);
    await waitFor('the end', () => logs.allRows().at(-1)?.message === 'the app ended');
    assert.equal(logs.appsInfo()[0].state, 'waiting');
  });

  it('follows the next app of the terminal, which serves in the same project', async () => {
    const terminal = new FakeTerminal();
    logs.started(terminal, project);
    const first = await app();
    await waitFor('the first connection', () => logs.appsInfo()[0]?.state === 'connected');
    await waitFor('its kept record', () => logs.allRows().some((r) => r.message === 'kept before'));
    first.send('quit');
    await first.exited;
    await waitFor('the first end', () => logs.appsInfo()[0].state === 'waiting');
    const second = await app();
    await waitFor('the second connection', () => logs.appsInfo()[0].state === 'connected');
    await waitFor(() => `the kept record of the second app; rows: ${JSON.stringify(logs.allRows().map((r) => r.message))}`, () => logs.allRows().filter((r) => r.message === 'kept before').length === 2);
    terminal.close();
    assert.equal(logs.appsInfo()[0].state, 'ended');
    second.send('quit');
    await second.exited;
  });
});
