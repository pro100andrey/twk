// A .tape read for the editor (core/tape.ts), its preview page, and the
// grammar and package.json entries that make it a language.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

import { commentStart, parseCheck, tapeHover, tapeKeywords, tapeOutputs, tapeStatements } from '../../../core/tape';
import { previewClick, previewHtml } from '../../../core/tape_preview';

// the extension's directory; run from the gate's copy (.dart_tool/vscode: the sources, package.json), the grammar is read from the extension itself
const here = path.resolve(__dirname, '../../../../');
const root = fs.existsSync(path.join(here, 'syntaxes')) ? here : path.resolve(here, '../../editors/vscode');

describe('tapeStatements', () => {
  it('a statement a line, comments and blank lines left out, keys named Key', () => {
    const s = tapeStatements('# a tape\nOutput a.cast  # trailing\n\nSet Width 44\nCtrl+C\nDown@100ms 3\nEnter\nWait+Line@2s /q # not a comment/\n');
    assert.deepEqual(
      s.map((x) => [x.line, x.keyword, x.source]),
      [
        [1, 'Output', 'Output a.cast'],
        [3, 'Set', 'Set Width 44'],
        [4, 'Key', 'Ctrl+C'],
        [5, 'Key', 'Down@100ms 3'],
        [6, 'Key', 'Enter'],
        [7, 'Wait', 'Wait+Line@2s /q # not a comment/'],
      ],
    );
  });

  it('a # in a quoted word or a Wait pattern is no comment; after them it is', () => {
    assert.equal(commentStart('Type "a # b"'), undefined);
    assert.equal(commentStart("Type 'a # b' # c"), 13);
    assert.equal(commentStart('Wait /a#b\\/c/ # c'), 14);
    assert.equal(commentStart('Wait "x#" #y'), 10);
    assert.equal(commentStart('# all'), 0);
  });
});

describe('tapeOutputs', () => {
  it('the Outputs and Screenshots with their files, quoted or not', () => {
    const o = tapeOutputs('Output build/a.cast\nOutput "my dir/a.svg"\nRun x\nScreenshot b.svg # still\nSet Width 3\n');
    assert.deepEqual(o, [
      { kind: 'Output', file: 'build/a.cast', line: 0 },
      { kind: 'Output', file: 'my dir/a.svg', line: 1 },
      { kind: 'Screenshot', file: 'b.svg', line: 3 },
    ]);
  });
});

describe('parseCheck', () => {
  const tape = '/p/t.tape';

  it('a passed check: each statement ok, the summary', () => {
    const r = parseCheck(tape, `${tape}:2: ok Set Width 40\n${tape}:5: ok Type 'hi'\n${tape}: passed, 2 statements\n`, 0);
    assert.deepEqual(r.statements, [
      { line: 1, ok: true, statement: 'Set Width 40' },
      { line: 4, ok: true, statement: "Type 'hi'" },
    ]);
    assert.equal(r.summary, 'passed, 2 statements');
    assert.equal(r.error, undefined);
  });

  it('a failed Wait: its line failed, stderr names the line and keeps the screen', () => {
    const out = `${tape}:3: ok Run x\n${tape}:7: FAIL Wait@300ms /never/\n${tape}: failed, 1 of 2 statements passed\n${tape}:7: Wait timed out after 0.3s for /never/; the screen:\n│hello\n│\n`;
    const r = parseCheck(tape, out, 1);
    assert.deepEqual(r.statements.map((s) => [s.line, s.ok]), [[2, true], [6, false]]);
    assert.equal(r.summary, 'failed, 1 of 2 statements passed');
    assert.equal(r.error?.line, 6);
    assert.equal(r.error?.message, 'Wait timed out after 0.3s for /never/; the screen:\n│hello\n│');
  });

  it('a tape that is wrong: only stderr, the line said', () => {
    const r = parseCheck(tape, `twk tape: ${tape}:4: unknown statement "Foo"\n`, 1);
    assert.deepEqual(r.statements, []);
    assert.deepEqual(r.error, { line: 3, message: 'unknown statement "Foo"' });
  });

  it('stderr that names no line of the tape stays whole', () => {
    const r = parseCheck(tape, 'twk tape: cannot read /p/t.tape: No such file\n', 1);
    assert.deepEqual(r.error, { line: undefined, message: 'cannot read /p/t.tape: No such file' });
  });
});

describe('tapeHover', () => {
  it('has a text for each statement of the language, and a Set tells its setting', () => {
    for (const k of tapeKeywords) {
      assert.ok(tapeHover(k, k), k);
    }
    assert.ok(tapeHover('Key', 'Ctrl+C'));
    assert.match(tapeHover('Set', 'Set TypingSpeed 10ms') ?? '', /^`Set TypingSpeed/);
    assert.equal(tapeHover('Foo', 'Foo'), undefined);
  });
});

describe('previewHtml', () => {
  it('a figure a frame going to its line, a missing file said, titles escaped, a CSP with the nonce', () => {
    const html = previewHtml('t.tape', [
      { title: 'a<b>.svg', src: 'vscode-webview://x/a.svg', line: 4 },
      { title: 'end.svg', src: undefined, line: 9 },
    ], 'CSP', 'N0NCE');
    assert.match(html, /<figure data-line="4"[^>]*><img src="vscode-webview:\/\/x\/a.svg" alt="a&#60;b&#62;.svg">/);
    assert.match(html, /<figure data-line="9"[^>]*><div class="missing">not written yet/);
    assert.match(html, /img-src CSP; style-src 'unsafe-inline'; script-src 'nonce-N0NCE'/);
    assert.match(html, /<script nonce="N0NCE">/);
  });

  it('a frame with a note says it in place of "not written yet"', () => {
    const html = previewHtml('t', [{ title: '../a.svg', src: undefined, line: 1, note: 'outside the <project>' }], 'c', 'n');
    assert.match(html, /<div class="missing">outside the &#60;project&#62;<\/div>/);
    assert.doesNotMatch(html, /not written yet/);
  });

  it('a tape with no frames says so; a click message is checked', () => {
    assert.match(previewHtml('t', [], 'c', 'n'), /nothing to preview/);
    assert.deepEqual(previewClick({ line: 3 }), { line: 3 });
    assert.equal(previewClick({ line: -1 }), undefined);
    assert.equal(previewClick({ line: '3' }), undefined);
    assert.equal(previewClick(null), undefined);
  });
});

describe('the .tape language of the package', () => {
  const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')) as { contributes: Record<string, any> };
  const grammar = JSON.parse(fs.readFileSync(path.join(root, 'syntaxes/tape.tmLanguage.json'), 'utf8'));

  it('is registered with files that exist, and its commands are declared', () => {
    const lang = pkg.contributes.languages.find((l: { id: string }) => l.id === 'tape');
    assert.deepEqual(lang.extensions, ['.tape']);
    assert.ok(fs.existsSync(path.join(root, lang.configuration)));
    const g = pkg.contributes.grammars.find((x: { language: string }) => x.language === 'tape');
    assert.equal(g.scopeName, grammar.scopeName);
    assert.ok(fs.existsSync(path.join(root, g.path)));
    const commands = pkg.contributes.commands.map((c: { command: string }) => c.command);
    for (const c of ['twk.tape.run', 'twk.tape.check', 'twk.tape.preview']) {
      assert.ok(commands.includes(c), c);
    }
    assert.deepEqual(pkg.contributes.configuration.properties['twk.tape.command'].default, ['dart', 'run', 'twk_dev:twk']);
  });

  /** The first scope name each rule of the grammar gives a line, by a JS regex (the grammar's are written to work as one). */
  function scopes(line: string): string[] {
    const found: string[] = [];
    const walk = (rules: { include?: string; match?: string; name?: string; captures?: Record<string, { name: string }>; patterns?: unknown[] }[]) => {
      for (const r of rules) {
        if (r.include) {
          walk(grammar.repository[r.include.slice(1)].patterns ?? [grammar.repository[r.include.slice(1)]]);
        } else if (r.match) {
          const m = new RegExp(r.match, 'g');
          for (let x = m.exec(line); x; x = m.exec(line)) {
            if (r.name) found.push(r.name);
            Object.entries(r.captures ?? {}).forEach(([i, c]) => (x as RegExpExecArray)[Number(i)] !== undefined && found.push(c.name));
            if (x[0] === '') m.lastIndex++;
          }
        }
      }
    };
    walk(grammar.patterns);
    return found;
  }

  it('every pattern compiles, and tells statements, keys, settings and comments', () => {
    assert.ok(scopes('Output a.cast').includes('keyword.control.tape'));
    assert.ok(scopes('Set Width 44').includes('variable.parameter.tape'));
    assert.ok(scopes('Wait+Line@2s /q/').includes('support.constant.tape'));
    assert.ok(scopes('Ctrl+C').includes('support.constant.key.tape'));
    assert.ok(scopes('Sleep 500ms').includes('constant.numeric.time.tape'));
    assert.ok(scopes('# hi').includes('comment.line.number-sign.tape'));
    assert.ok(!scopes('Foo').includes('support.constant.key.tape'));
    for (const rule of Object.values(grammar.repository) as { begin?: string; end?: string }[]) {
      [rule.begin, rule.end].forEach((re) => re && new RegExp(re));
    }
  });
});
