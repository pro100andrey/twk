// The golden screens in the editor (app/goldens.ts): the state of a screen
// file with the screen a failed test left beside it, Accept Actual, and the
// editor over a fake panel. The files are a map.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { GoldenEditor, GoldenFiles, acceptActual, actualSuffix, screenState } from '../../../app/goldens';
import { ToScreen, isToScreen } from '../../../webview/screen_protocol';
import { FakePanel } from '../fakes';

const golden = fs.readFileSync(path.resolve(__dirname, '../../../../../../packages/twk_test/test/screen_file.golden.txt'), 'utf8');
const changed = golden.replace('b red on', 'b green on');

/** Files in memory, with the times they were written at. */
class MapFiles implements GoldenFiles {
  readonly texts = new Map<string, string>();
  readonly times = new Map<string, number>();
  clock = 0;
  put(p: string, text: string): void {
    this.texts.set(p, text);
    this.times.set(p, ++this.clock);
  }
  async read(p: string) {
    return this.texts.get(p);
  }
  async modified(p: string) {
    return this.times.get(p);
  }
  async write(p: string, text: string) {
    this.put(p, text);
  }
  async remove(p: string) {
    this.texts.delete(p);
    this.times.delete(p);
  }
}

const file = '/p/test/goldens/form.txt';

describe('golden screens', () => {
  it('a golden alone: its screen, nothing to compare', async () => {
    const files = new MapFiles();
    files.put(file, golden);
    const s = await screenState(files, file);
    assert.equal(s.kind, 'ok');
    assert.ok(s.kind === 'ok' && s.actual === null && s.diff === null && !s.stale);
  });

  it('a file that is none, or gone, is said so', async () => {
    const files = new MapFiles();
    assert.deepEqual(await screenState(files, file), { kind: 'bad', message: 'the file is gone' });
    files.put(file, 'hello');
    const s = await screenState(files, file);
    assert.ok(s.kind === 'bad' && s.message.startsWith('not a screen file: the first line is not'));
  });

  it('the screen of a failed test beside it: the cells that differ', async () => {
    const files = new MapFiles();
    files.put(file, golden);
    files.put(file + actualSuffix, changed);
    const s = await screenState(files, file);
    assert.ok(s.kind === 'ok' && s.actual !== null && s.diff !== null);
    assert.equal(s.diff.cells.length, 5);
    assert.deepEqual(s.diff.cells[0].style, ['red on #010203', 'green on #010203']);
  });

  it('a screen older than the golden is of an earlier run: stale, not compared', async () => {
    const files = new MapFiles();
    files.put(file + actualSuffix, changed);
    files.put(file, golden);
    const s = await screenState(files, file);
    assert.ok(s.kind === 'ok' && s.actual === null && s.stale);
    assert.equal(await acceptActual(files, file), false);
    assert.equal(files.texts.get(file), golden);
  });

  it('a screen that is none beside a golden is said so', async () => {
    const files = new MapFiles();
    files.put(file, golden);
    files.put(file + actualSuffix, 'x');
    const s = await screenState(files, file);
    assert.ok(s.kind === 'bad' && s.message.startsWith(`${file}${actualSuffix} is not a screen file`));
  });

  it('Accept Actual: the actual becomes the golden, byte for byte, and goes', async () => {
    const files = new MapFiles();
    files.put(file, golden);
    files.put(file + actualSuffix, changed);
    assert.equal(await acceptActual(files, file), true);
    assert.equal(files.texts.get(file), changed);
    assert.equal(files.texts.has(file + actualSuffix), false);
    assert.equal(await acceptActual(files, file), false);
  });

  it('the editor shows the file when the webview is up, and again when asked or after an accept', async () => {
    const files = new MapFiles();
    files.put(file, golden);
    files.put(file + actualSuffix, changed);
    const panel = new FakePanel<ToScreen>();
    const said: string[] = [];
    const editor = new GoldenEditor(panel, files, file, 'form.txt', (m) => said.push(m));
    panel.send({ type: 'ready' });
    await settle();
    assert.equal(panel.posted.length, 1);
    assert.ok(isToScreen(panel.posted[0]));
    assert.ok(panel.posted[0].state.kind === 'ok' && panel.posted[0].state.diff?.cells.length === 5);

    panel.send({ type: 'accept' });
    await settle();
    assert.equal(files.texts.get(file), changed);
    assert.deepEqual(said, ['twk: form.txt now holds the screen of the failed test']);
    const last = panel.posted[panel.posted.length - 1];
    assert.ok(last.state.kind === 'ok' && last.state.actual === null);

    panel.send({ type: 'accept' });
    await settle();
    assert.match(said[1], /no screen of a failed test/);

    const before = panel.posted.length;
    await editor.refresh();
    assert.equal(panel.posted.length, before + 1);
    panel.send({ type: 'something else' });
    panel.dispose();
    await editor.refresh();
    assert.equal(panel.posted.length, before + 1);
  });
});

/** Lets the editor's promises run. */
const settle = () => new Promise<void>((r) => setImmediate(r));
