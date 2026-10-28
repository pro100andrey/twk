// The inspector against twk itself: a twk app written here, run by the
// extension's run (HotApps over core's HotRun, a real `dart run` with its
// VM service) in a twk terminal over a fake view, inspected over the
// extension's own VM service connection: the tree as twk gives it,
// followed by twk's `twk.treeChanged` as the app changes, a pick made on
// the app's screen, where each widget was made found in the app's code
// through the VM service, a hot reload and a hot restart.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

import { HotApps } from '../../../app/hot_apps';
import { Inspector } from '../../../app/inspector';
import { Terminals } from '../../../app/terminals';
import { realClock } from '../../../core/events';
import { InspectNode, InspectTree } from '../../../core/inspect';
import { startNodeProcess } from '../../../core/process';
import { HotRun } from '../../../core/runner';
import { VmClient } from '../../../core/vm';
import { HeadlessView } from '../headless_view';
import { TerminalView } from '../../../app/ports';
import { FakeDebugger, FakeDesktop, FakeInspectorView, FakeLog, FakeNotice, FakeOpener, FakePickingIndicator, FakeSettings, FakeStatus, FakeView, realShell } from '../fakes';

/** From out/test/unit/app, where this runs compiled, to the repository's root. */
const root = path.resolve(__dirname, '../../../../../..');
/** In packages/twk, whose package config has twk; git ignores .dart_tool. */
const scratch = path.join(root, 'packages', 'twk', '.dart_tool', 'twk_vscode_unit');

const appSource = (last: string, above = '') => `import 'package:twk/twk.dart';

void main() => runApp(const Page());
${above}
class Page extends StatefulWidget {
  const Page({super.key});

  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'up': () => setState(() => _n++)},
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('first'),
        Framed(child: Text('count \$_n')),
        Text('${last}'),
      ],
    ),
  );
}

class Framed extends StatelessWidget {
  const Framed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(left: 2), child: child);
}
`;

/** The nodes of [tree] below [n], [n] first. */
function nodes(n: InspectNode | null): InspectNode[] {
  return n ? [n, ...n.children.flatMap(nodes)] : [];
}

/** The Text of [tree] that shows [text]. */
function textShowing(tree: InspectTree | undefined, text: string): InspectNode | undefined {
  return nodes(tree?.root ?? null).find((n) => n.name === 'Text' && n.properties.some((p) => p.value === `"${text}"`));
}

describe('the inspector, on a twk app', function () {
  this.timeout(180000);
  let dir: string;
  let file: string;
  let log: FakeLog;
  let views: FakeView[];
  /** The view of the next terminal: a FakeView, unless a test says otherwise. */
  let viewFor: ((title: string) => TerminalView) | undefined;
  let terminals: Terminals;
  let apps: HotApps;
  let view: FakeInspectorView;
  let opener: FakeOpener;
  let inspector: Inspector;

  async function until(what: string, f: () => boolean, ms = 90000): Promise<void> {
    const end = Date.now() + ms;
    while (!f()) {
      if (Date.now() > end) {
        throw new Error(`no ${what} in ${ms} ms; the view: ${view.message} ${JSON.stringify(view.tree)?.substring(0, 3000)}; log:\n${log.text}`);
      }
      await new Promise((r) => setTimeout(r, 20));
    }
  }

  beforeEach(() => {
    fs.mkdirSync(scratch, { recursive: true });
    dir = fs.mkdtempSync(path.join(scratch, 'app_'));
    file = path.join(dir, 'app.dart');
    fs.writeFileSync(file, appSource('last'));
    viewFor = undefined;
    log = new FakeLog();
    views = [];
    const settings = new FakeSettings();
    terminals = new Terminals({
      views: (title) => {
        if (viewFor) {
          return viewFor(title);
        }
        const v = new FakeView(title);
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
    view = new FakeInspectorView();
    opener = new FakeOpener();
    inspector = new Inspector({ apps: apps.onApp, view, opener, picking: new FakePickingIndicator(), notice: new FakeNotice(), clock: realClock, log });
  });

  afterEach(async () => {
    inspector.dispose();
    await apps.dispose();
    await terminals.dispose();
    fs.rmSync(dir, { recursive: true, force: true });
  });

  /** The line and column, from 1, of the first [text] in [source] after [after]. */
  function place(source: string, text: string, after = ''): { line: number; column: number } {
    const at = source.indexOf(text, source.indexOf(after));
    const before = source.substring(0, at).split('\n');
    return { line: before.length, column: before[before.length - 1].length + 1 };
  }

  it("shows the app's tree and follows it, picks on its screen, finds where each widget was made, and takes a reload and a restart", async () => {
    await apps.runFile(file);
    await until('the tree', () => textShowing(view.tree, 'count 0') !== undefined);
    const shown = view.shown.length;

    // the app changes: twk says so, and the tree is asked again
    views[0].type('\x1b[A');
    await until('count 1, by the event', () => textShowing(view.tree, 'count 1') !== undefined);
    assert.ok(view.shown.length > shown);

    // where each was made, in the app's code as the VM runs it
    const source = fs.readFileSync(file, 'utf8');
    const uri = (s: { uri: string }) => fileURLToPath(s.uri);
    const count = await inspector.goToSource(textShowing(inspector.tree, 'count 1')!.id);
    assert.equal(uri(count), file);
    assert.deepEqual({ line: count.line, column: count.column }, place(source, "Text('count"));
    assert.equal(count.exact, true);
    assert.equal(count.method, '_PageState.build');
    const last = await inspector.goToSource(textShowing(inspector.tree, 'last')!.id);
    assert.deepEqual({ line: last.line, column: last.column }, place(source, "Text('last"));
    const padding = nodes(inspector.tree!.root).find((n) => n.name === 'Padding')!;
    const made = await inspector.goToSource(padding.id);
    assert.deepEqual({ line: made.line, column: made.column, method: made.method }, { ...place(source, 'Padding('), method: 'Framed.build' });
    const page = nodes(inspector.tree!.root).find((n) => n.name === 'Page')!;
    assert.equal(page.build, '_PageState');
    const build = await inspector.goToBuild(page.id);
    assert.deepEqual({ line: build.line, column: build.column }, place(source, 'build(', '_PageState extends'));
    // a widget of twk's, built in twk's code: its package: URI resolved to its file
    const keys = nodes(inspector.tree!.root).find((n) => n.name === 'KeyBindings')!;
    assert.ok(keys.build, JSON.stringify(keys));
    const inTwk = await inspector.goToBuild(keys.id);
    assert.ok(uri(inTwk).startsWith(path.join(root, 'packages', 'twk', 'lib')), inTwk.uri);

    // a pick on the app's screen: the app picks, its cell posted, the widget revealed
    const opened = opener.opened.length;
    await inspector.pick();
    // a press of the left button on the third row, the first column (SGR)
    views[0].type('\x1b[<0;1;3M');
    views[0].type('\x1b[<0;1;3m');
    await until('the pick revealed', () => view.revealed.length === 1);
    assert.equal(view.revealed[0], textShowing(inspector.tree, 'last')!.id);
    // and opened where it was made
    await until('the pick opened', () => opener.opened.length === opened + 1);
    assert.deepEqual({ line: opener.opened[opened].line, column: opener.opened[opened].column }, place(source, "Text('last"));
    // twk picks on (selectMany): a press on the first row picks again
    views[0].type('\x1b[<0;1;1M');
    views[0].type('\x1b[<0;1;1m');
    await until('the second pick revealed', () => view.revealed.length === 2);
    assert.equal(view.revealed[1], textShowing(inspector.tree, 'first')!.id);
    assert.equal((await inspector.flags()).select, true, 'picking on');
    await inspector.stopPicking();
    assert.equal((await inspector.flags()).select, false, 'picking no more');

    // a hot reload: the tree asked again, the code read again (its lines moved)
    fs.writeFileSync(file, appSource('final word', '\n// a line more\n'));
    assert.equal((await apps.reloadAll())[0].state, 'reloaded');
    await until('the reloaded tree', () => textShowing(view.tree, 'final word') !== undefined);
    assert.ok(textShowing(view.tree, 'count 1'), 'the state kept');
    const moved = await inspector.goToSource(textShowing(inspector.tree, 'final word')!.id);
    assert.deepEqual({ line: moved.line, column: moved.column }, place(fs.readFileSync(file, 'utf8'), "Text('final"));

    // the debug aids, given again to the app a restart starts
    await inspector.setFlags({ overlay: true });
    await apps.restartAll();
    await until('the new app', () => textShowing(view.tree, 'count 0') !== undefined);
    let flags = await inspector.flags();
    for (const end = Date.now() + 10000; !(flags.overlay && flags.treeEvents) && Date.now() < end; flags = await inspector.flags()) {
      await new Promise((r) => setTimeout(r, 20));
    }
    assert.equal(flags.overlay, true, 'its overlay on');
    assert.equal(flags.treeEvents, true, 'its tree followed');
  });

  it("picks on an inline app's region by the terminal's click, the region found by the cursor's row", async () => {
    const screen = new HeadlessView(60, 12);
    viewFor = () => screen;
    fs.writeFileSync(file, appSource('last').replace('runApp(const Page())', 'runApp(const Page(), mode: .inline)'));
    // what the shell showed before: the region begins below it
    await screen.write(Buffer.from('$ one\r\n$ two\r\n$ three\r\n'));
    await apps.runFile(file);
    await until('the tree', () => textShowing(view.tree, 'count 0') !== undefined);
    await until('the region drawn', () => screen.rows().some((r) => r.includes('count 0')));
    const row = screen.rows().findIndex((r) => r.includes('count 0'));
    assert.ok(row > 0, screen.rows().join('\n'));

    // the app can't pick itself inline: the terminal's click does
    await inspector.pick();
    assert.equal(screen.picking, true);
    screen.click(screen.rows()[row].indexOf('count'), row);
    await until('the pick revealed', () => view.revealed.length === 1);
    assert.equal(view.revealed[0], textShowing(inspector.tree, 'count 0')!.id, screen.rows().join('\n'));
  });
});
