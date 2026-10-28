// The twk terminal's capabilities (core/capabilities.ts): the settings
// checked, what they make of the welcome and of the webview's answers, the
// title, and the picks of the switch panel.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import {
  Capabilities,
  answersOf,
  changesFrom,
  changesSetting,
  choiceOf,
  declarationOf,
  describeChoice,
  environmentOf,
  presetNamed,
  presets,
  toggleItems,
  toggles,
  togglesPicked,
} from '../../../core/capabilities';

const xtermJs = presetNamed('xterm.js');

describe('the capabilities', () => {
  it('of the settings: the preset named (xterm.js for none or another), each switch of the right type over it', () => {
    assert.equal(choiceOf(undefined, undefined).preset.name, 'xterm.js');
    assert.equal(choiceOf('no such', {}).preset.name, 'xterm.js');
    assert.deepEqual(choiceOf('16 colors', undefined).capabilities, presetNamed('16 colors').capabilities);
    const c = choiceOf('xterm.js', {
      colors: '256',
      graphics: 'iterm2',
      kittyKeyboard: true,
      clipboard: false,
      notifications: 'yes', // no boolean: left as the preset has it
      progress: 1,
      cellSize: null,
      colours: 'none', // no switch of that name
    }).capabilities;
    assert.deepEqual(c, { ...xtermJs.capabilities, colors: '256', graphics: 'iterm2', kittyKeyboard: true, clipboard: false });
    assert.deepEqual(choiceOf('xterm.js', { colors: 'many', graphics: 'kitty' }).capabilities, xtermJs.capabilities, 'kitty images: no switch of xterm.js 6.0');
    for (const changes of [[true], 'kittyKeyboard', 7, null]) {
      assert.deepEqual(choiceOf('xterm.js', changes).capabilities, xtermJs.capabilities, JSON.stringify(changes));
    }
  });

  it('each switch changed from its preset kept in the settings, and read back to the same', () => {
    const changed: Capabilities = { ...xtermJs.capabilities, colors: 'none', graphics: 'sixel', answers: false, links: false };
    const setting = changesSetting(changesFrom(xtermJs, changed));
    assert.deepEqual(setting, { colors: 'none', graphics: 'sixel', answers: false, links: false });
    assert.deepEqual(choiceOf('xterm.js', JSON.parse(JSON.stringify(setting))).capabilities, changed);
    assert.deepEqual(changesSetting(changesFrom(xtermJs, xtermJs.capabilities)), {}, 'none changed: none kept');
  });

  it('in the title: the preset, and each switch changed from it', () => {
    assert.equal(describeChoice({ preset: xtermJs, capabilities: xtermJs.capabilities }), 'xterm.js');
    assert.equal(
      describeChoice({ preset: xtermJs, capabilities: { ...xtermJs.capabilities, colors: '16', graphics: 'sixel', kittyKeyboard: true, clipboard: false } }),
      'xterm.js, 16 colors, sixel images, kitty keyboard, no clipboard',
    );
  });

  it("the environment: TERM, COLORTERM and NO_COLOR by the colours, as twk's colorModeFor reads them", () => {
    const of = (colors: Capabilities['colors']) => environmentOf({ ...xtermJs.capabilities, colors });
    assert.deepEqual(of('truecolor'), { TERM: 'xterm-256color', COLORTERM: 'truecolor', TERM_PROGRAM: 'twk-vscode' });
    assert.deepEqual(of('256'), { TERM: 'xterm-256color', TERM_PROGRAM: 'twk-vscode' });
    assert.deepEqual(of('16'), { TERM: 'xterm', TERM_PROGRAM: 'twk-vscode' });
    assert.equal(of('none').NO_COLOR, '1');
  });

  it('what the terminal declares: all of it, in the order of twk_core\'s TerminalDeclaration', () => {
    assert.deepEqual(Object.keys(declarationOf(xtermJs.capabilities)), ['notifications', 'progressReports', 'pointerShapes', 'repeatChar', 'graphics']);
    assert.deepEqual(declarationOf(xtermJs.capabilities), { notifications: 'osc777', progressReports: true, pointerShapes: true, repeatChar: true, graphics: 'none' });
    assert.deepEqual(declarationOf(presetNamed('bare').capabilities), { notifications: 'none', progressReports: false, pointerShapes: false, repeatChar: false, graphics: 'none' });
  });

  it("the webview's answers: the queries denied, and what it emulates", () => {
    const a = answersOf(xtermJs.capabilities);
    assert.deepEqual(a.deny, []);
    assert.equal(a.version, 'twk-vscode(0.0.1)');
    assert.equal(a.kittyKeyboard, false);
    assert.equal(a.cellSize, true);
    assert.deepEqual(answersOf(presetNamed('no synchronized output').capabilities).deny, ['synchronizedOutput']);
    const none = answersOf(presetNamed('no answers').capabilities);
    assert.deepEqual(none.deny, ['synchronizedOutput', 'graphemes', 'inBandResize', 'margins', 'colorSchemeReports', 'colors', 'deviceAttributes']);
    assert.equal(none.version, null);
    const off = answersOf({ ...presetNamed('everything').capabilities, answers: false });
    assert.equal(off.kittyKeyboard, false, 'no answers: not even kitty keyboard');
    assert.equal(off.cellSize, false);
    assert.equal(off.graphics, 'sixel', 'what it shows is no answer');
  });

  it("every preset of a name of its own, the first the default, as the settings' schema has them", () => {
    assert.equal(new Set(presets.map((p) => p.name)).size, presets.length);
    assert.equal(presetNamed(undefined), presets[0]);
    // from out/test/unit/core, where this runs compiled, to the extension's package.json
    const manifest = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../../../package.json'), 'utf8')) as {
      contributes: { configuration: { properties: Record<string, { enum?: string[]; default?: unknown; properties?: Record<string, unknown> }> } };
    };
    const settings = manifest.contributes.configuration.properties;
    assert.deepEqual(settings['twk.terminal.profile'].enum, presets.map((p) => p.name));
    assert.equal(settings['twk.terminal.profile'].default, presets[0].name);
    assert.deepEqual(Object.keys(settings['twk.terminal.capabilities'].properties ?? {}).sort(), Object.keys(xtermJs.capabilities).sort());
  });

  it('the toggles picked: those of the labels on, the others off', () => {
    const items = toggleItems(xtermJs.capabilities);
    assert.deepEqual(
      items.filter((i) => i.picked).map((i) => i.label),
      toggles.filter((t) => xtermJs.capabilities[t.toggle]).map((t) => t.label),
    );
    const picked = togglesPicked(xtermJs.capabilities, ['kitty keyboard', 'answers']);
    assert.deepEqual(
      toggles.filter((t) => picked[t.toggle]).map((t) => t.toggle),
      ['answers', 'kittyKeyboard'],
    );
    assert.equal(picked.colors, 'truecolor', 'the rest as it was');
  });
});
