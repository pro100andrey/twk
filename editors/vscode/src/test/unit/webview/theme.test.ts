// The terminal's theme from VS Code's --vscode-terminal-* variables.
import * as assert from 'node:assert/strict';

import { ansiNames, sameTheme, terminalTheme } from '../../../webview/theme';

const reader = (vars: Record<string, string>) => (name: string) => vars[name] ?? '';

describe("the terminal's theme", () => {
  it('takes the terminal colours: background, foreground, cursor, selection and the 16 ANSI colours', () => {
    const vars: Record<string, string> = {
      '--vscode-terminal-background': ' #ffffff ',
      '--vscode-terminal-foreground': '#111111',
      '--vscode-terminalCursor-foreground': '#222222',
      '--vscode-terminalCursor-background': '#333333',
      '--vscode-terminal-selectionBackground': '#444444',
    };
    ansiNames.forEach((n, i) => (vars[`--vscode-terminal-ansi${n}`] = `#0000${i.toString(16).padStart(2, '0')}`));
    const t = terminalTheme(reader(vars));
    assert.equal(t.background, '#ffffff');
    assert.equal(t.foreground, '#111111');
    assert.equal(t.cursor, '#222222');
    assert.equal(t.cursorAccent, '#333333');
    assert.equal(t.selectionBackground, '#444444');
    assert.equal(t.black, '#000000');
    assert.equal(t.red, '#000001');
    assert.equal(t.white, '#000007');
    assert.equal(t.brightBlack, '#000008');
    assert.equal(t.brightWhite, '#00000f');
  });

  it("falls back to the editor's colours, then to a dark default, and leaves unset colours to xterm.js", () => {
    const editor = terminalTheme(reader({ '--vscode-editor-background': '#fafafa', '--vscode-editor-foreground': '#101010' }));
    assert.equal(editor.background, '#fafafa');
    assert.equal(editor.foreground, '#101010');
    const none = terminalTheme(reader({}));
    assert.equal(none.background, '#1e1e1e');
    assert.equal(none.foreground, '#cccccc');
    assert.equal('red' in none, false);
    assert.equal('cursor' in none, false);
  });

  it('tells a changed theme from the same one', () => {
    const dark = terminalTheme(reader({ '--vscode-terminal-background': '#1e1e1e' }));
    const light = terminalTheme(reader({ '--vscode-terminal-background': '#ffffff' }));
    assert.equal(sameTheme(dark, terminalTheme(reader({ '--vscode-terminal-background': '#1e1e1e' }))), true);
    assert.equal(sameTheme(dark, light), false);
    assert.equal(sameTheme(dark, { ...dark, red: '#f00' }), false);
  });
});
