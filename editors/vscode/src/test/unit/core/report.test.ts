// The terminal report (core/report.ts): what the twk terminal tells and
// answers per preset, equal to what the terminal is welcomed with and what
// the webview denies; and twk doctor's JSON read.
import * as assert from 'node:assert/strict';

import { answersOf, choiceOf, declarationOf, environmentOf, presetNamed, presets } from '../../../core/capabilities';
import { ProjectResult, isRefresh, parseDoctor, reportHtml, terminalReportOf } from '../../../core/report';
import { noSwitches, switchEnvironment } from '../../../core/switches';

const report = (preset: string, changes: unknown = {}) => terminalReportOf(choiceOf(preset, changes), noSwitches);
const outcome = (r: ReturnType<typeof report>, sequence: string) => r.queries.find((q) => q.sequence === sequence)?.outcome;

describe('the terminal report', () => {
  it('has the environment and the declaration the terminal welcomes an app with, for every preset', () => {
    for (const p of presets) {
      const r = terminalReportOf({ preset: p, capabilities: p.capabilities }, { screenReader: true, debug: ['logs'] });
      assert.deepEqual(r.environment, { ...environmentOf(p.capabilities), ...switchEnvironment({ screenReader: true, debug: ['logs'] }) }, p.name);
      assert.deepEqual(r.declares, declarationOf(p.capabilities), p.name);
      assert.equal(r.switches, 'screen reader, logs');
    }
  });

  it('answers every query, by xterm.js or the extension, in xterm.js', () => {
    const r = report('xterm.js');
    assert.deepEqual(r.queries.map((q) => q.outcome), ['answered', 'answered', 'answered', 'answered', 'answered', 'answered', 'answered', 'no answer', 'answered', 'answered']);
    assert.equal(r.queries.find((q) => q.query === 'terminal name and version')?.detail, 'twk-vscode(0.0.1)');
    assert.equal(r.profile, 'xterm.js');
  });

  it('says what the preset "no synchronized output" denies: the mode, not recognised, and no more', () => {
    const r = report('no synchronized output');
    assert.equal(outcome(r, 'CSI ? 2026 $ p'), 'not recognised');
    assert.equal(r.queries.filter((q) => q.outcome !== 'answered').length, 2, 'that and kitty (off in xterm.js)');
  });

  it('says what "no answers" does: the other modes not recognised, colours and DA1 silent, the probe times out', () => {
    const r = report('no answers');
    assert.equal(outcome(r, 'CSI ? 2027 $ p'), 'not recognised');
    assert.equal(outcome(r, 'CSI ? 69 $ p'), 'not recognised');
    assert.equal(outcome(r, 'OSC 10, 11, 4 ; ?'), 'no answer');
    assert.equal(outcome(r, 'CSI c'), 'no answer');
    assert.equal(outcome(r, 'CSI > q'), 'no answer');
    assert.equal(outcome(r, 'CSI 16 t'), 'no answer');
  });

  it("agrees with the webview's answers for every preset, switch by switch", () => {
    for (const p of presets) {
      const a = answersOf(p.capabilities);
      const r = terminalReportOf({ preset: p, capabilities: p.capabilities }, noSwitches);
      const denied = (n: string) => r.queries.filter((q) => q.outcome !== 'answered').some((q) => q.sequence === n);
      assert.equal(denied('CSI ? 2026 $ p'), a.deny.includes('synchronizedOutput'), p.name);
      assert.equal(denied('CSI c'), a.deny.includes('deviceAttributes'), p.name);
      assert.equal(outcome(r, 'CSI ? u') === 'answered', a.kittyKeyboard, p.name);
      assert.equal(outcome(r, 'CSI 16 t') === 'answered', a.cellSize, p.name);
      assert.equal(outcome(r, 'CSI > q') === 'answered', a.version !== null, p.name);
      assert.deepEqual(
        r.handled.map((h) => [h.name, h.on]),
        [['images', a.graphics !== 'none'], ['notifications', a.notifications], ['progress', a.progress], ['pointer shapes', a.pointerShapes], ['links', a.links], ['clipboard', a.clipboard], ['repeat character', p.capabilities.repeatChar]],
        p.name,
      );
    }
  });

  it('follows the switches changed from the preset: colours, images, kitty keyboard', () => {
    const r = report('xterm.js', { colors: '16', graphics: 'sixel', kittyKeyboard: true });
    assert.equal(r.environment.TERM, 'xterm');
    assert.equal(r.environment.COLORTERM, undefined);
    assert.equal(r.declares.graphics, 'sixel');
    assert.equal(outcome(r, 'CSI ? u'), 'answered');
    assert.equal(r.handled[0].detail, 'DEC sixel');
    assert.equal(r.profile, 'xterm.js, 16 colors, sixel images, kitty keyboard');
    assert.equal(presetNamed('xterm.js').capabilities.kittyKeyboard, false);
  });
});

const doctorJson = {
  project: '/p/app',
  dart: '3.13.7',
  environment: { TERM: 'xterm' },
  terminal: null,
  lock: '/p/pubspec.lock',
  versions: { twk: '0.3.0', twk_core: '0.3.0', twk_dev: '0.3.0' },
  sources: { twk: 'locked', twk_core: 'locked', twk_dev: 'path' },
  agree: true,
  state: { run: { address: 'ws://x', listens: false } },
  agents: { stale: ['a'], edited: [], missing: false },
};

describe('twk doctor --json, read', () => {
  it('into the project part, after a line dart run wrote first', () => {
    const r = parseDoctor(`Building package executable...\n${JSON.stringify(doctorJson, null, 2)}\n`);
    assert.equal(r.kind, 'ok');
    assert.deepEqual(r.kind === 'ok' && r.report, {
      project: '/p/app',
      dart: '3.13.7',
      lock: '/p/pubspec.lock',
      versions: { twk: '0.3.0', twk_core: '0.3.0', twk_dev: '0.3.0' },
      sources: { twk: 'locked', twk_core: 'locked', twk_dev: 'path' },
      agree: true,
      state: { run: { address: 'ws://x', listens: false } },
      agents: { stale: ['a'], edited: [], missing: false },
    });
  });

  it('with no lock, no agents and fields of the wrong type left out', () => {
    const r = parseDoctor(JSON.stringify({ project: '/p', dart: 7, lock: null, versions: { twk: 1, twk_core: '1' }, agree: 'yes', state: { logs: 5 }, agents: null }));
    assert.deepEqual(r.kind === 'ok' && r.report, { project: '/p', dart: '', lock: null, versions: { twk_core: '1' }, sources: {}, agree: false, state: {}, agents: null });
  });

  it('is failed, saying why, for output that is no report', () => {
    for (const out of ['', 'Could not find package "twk_dev"\n', '{not json', '[]', '{"dart":"3"}']) {
      assert.equal(parseDoctor(out).kind, 'failed', out);
    }
    assert.match((parseDoctor('Could not find package\nmore') as { message: string }).message, /Could not find package/);
  });
});

describe('the report page', () => {
  const ok = parseDoctor(JSON.stringify(doctorJson));
  if (ok.kind !== 'ok') {
    throw new Error('the fixture is no report');
  }
  const page = (project: ProjectResult) => reportHtml(report('xterm.js'), project, 'N0NCE');

  it('has both parts, and a script of the nonce alone', () => {
    const html = page(ok);
    assert.match(html, /<h1>The twk terminal<\/h1>/);
    assert.match(html, /<code>CSI \? 2026 \$ p<\/code>/);
    assert.match(html, /<th>twk_core<\/th><td>0\.3\.0 <span class="muted">\(locked\)<\/span><\/td>/);
    assert.match(html, /<th>twk_dev<\/th><td>0\.3\.0 <span class="muted">\(path\)/);
    assert.match(html, /<th>twk_test<\/th><td><span class="muted">not found/);
    assert.match(html, /left behind/);
    assert.match(html, /older than this twk_dev: a/);
    assert.match(html, /script-src 'nonce-N0NCE'/);
    assert.equal((html.match(/<script/g) ?? []).length, 1);
  });

  it('says the agreement whatever the lock, and shows a version without a source', () => {
    const noLock = { ...ok.report, lock: null, agree: false, sources: {} };
    const html = page({ kind: 'ok', report: noLock });
    assert.match(html, /DISAGREE/);
    assert.doesNotMatch(html, /no lock to compare|not in the lock/);
    assert.match(html, /<th>twk_core<\/th><td>0\.3\.0<\/td>/);
    assert.match(page({ kind: 'ok', report: { ...noLock, agree: true } }), /class="ok">agree/);
  });

  it('says a disagreement, no project and a failure', () => {
    assert.match(page({ kind: 'ok', report: { ...ok.report, agree: false } }), /DISAGREE/);
    assert.match(page({ kind: 'none' }), /No Dart project/);
    assert.match(page({ kind: 'failed', message: 'cannot start dart: <ENOENT>' }), /cannot start dart: &#60;ENOENT&#62;/);
  });

  it('escapes what a project says', () => {
    const r = parseDoctor(JSON.stringify({ ...doctorJson, project: '/p/<u>"x"', agents: { stale: ['<i>'], edited: [], missing: false } }));
    const html = page(r);
    assert.ok(!html.includes('<u>'));
    assert.ok(!html.includes('<i>'));
  });

  it('knows its Refresh message', () => {
    assert.equal(isRefresh({ refresh: true }), true);
    for (const m of [{ refresh: 1 }, null, 'refresh', {}]) {
      assert.equal(isRefresh(m), false);
    }
  });
});
