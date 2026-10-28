// The sequence decoder (core/sequences.ts): the stream cut into text,
// controls and escape sequences, read by read, a sequence cut between two
// reads put together; each named as the app wrote it or as the terminal
// sent it; and where a synchronized update begins and ends.
import * as assert from 'node:assert/strict';

import { SequenceReader, Token, describeInput, describeOutput, describeSgr, syncChange, visible } from '../../../core/sequences';

const bytes = (s: string) => Buffer.from(s, 'latin1');
const utf8 = (s: string) => Buffer.from(s, 'utf8');

/** The kinds and raw bytes of [tokens]. */
const shapes = (tokens: Token[]) => tokens.map((t) => `${t.kind}:${t.raw}`);

const out = (s: string) => new SequenceReader(false).read(utf8(s)).map(describeOutput);
const typed = (s: string, binary = false) => new SequenceReader(true).read(binary ? bytes(s) : utf8(s)).map(describeInput);

describe('the sequence decoder', () => {
  it('cuts text, controls and each kind of escape sequence', () => {
    const r = new SequenceReader();
    assert.deepEqual(
      shapes(r.read(bytes('ab\r\n\x1b7\x1b(B\x1b[1;31m\x1b[?1049h\x1bOP\x1b]2;t\x07\x1b]8;;u\x1b\\\x1bPq#0\x1b\\\x1b_Gf=1\x1b\\\x1b^p\x1b\\'))),
      [
        'text:ab',
        'control:\r',
        'control:\n',
        'esc:\x1b7',
        'esc:\x1b(B',
        'csi:\x1b[1;31m',
        'csi:\x1b[?1049h',
        'ss3:\x1bOP',
        'osc:\x1b]2;t\x07',
        'osc:\x1b]8;;u\x1b\\',
        'dcs:\x1bPq#0\x1b\\',
        'apc:\x1b_Gf=1\x1b\\',
        'pm:\x1b^p\x1b\\',
      ],
    );
    assert.equal(r.waiting, '');
  });

  it('holds a sequence cut off at the end of a read for the next, and a character cut in two', () => {
    const r = new SequenceReader();
    assert.deepEqual(shapes(r.read(bytes('a\x1b[?20'))), ['text:a']);
    assert.equal(r.waiting, '\x1b[?20');
    assert.deepEqual(shapes(r.read(bytes('26hb\x1b'))), ['csi:\x1b[?2026h', 'text:b']);
    assert.deepEqual(shapes(r.read(bytes(']0;x'))), []);
    assert.deepEqual(shapes(r.read(bytes('\x1b'))), []);
    assert.deepEqual(shapes(r.read(bytes('\\'))), ['osc:\x1b]0;x\x1b\\']);
    // ─ is e2 94 80
    const t = r.read(Buffer.from([0x41, 0xe2, 0x94]));
    assert.deepEqual(
      t.map((x) => (x.kind === 'text' ? x.text : x.kind)),
      ['A'],
    );
    assert.deepEqual(
      r.read(Buffer.from([0x80, 0x42])).map((x) => (x.kind === 'text' ? x.text : x.kind)),
      ['─B'],
    );
  });

  it("takes tmux's passthrough whole, its doubled ESCs inside", () => {
    const r = new SequenceReader();
    assert.deepEqual(shapes(r.read(bytes('\x1bPtmux;\x1b\x1b]52;c;eA==\x07\x1b\\x'))), ['dcs:\x1bPtmux;\x1b\x1b]52;c;eA==\x07\x1b\\', 'text:x']);
    assert.deepEqual(out('\x1bPtmux;\x1b\x1b]2;t\x07\x1b\\'), ['DCS tmux passthrough']);
  });

  it('names what an app writes', () => {
    assert.deepEqual(out('\x1b[3;5H\x1b[H\x1b[2J\x1b[K\x1b[4b\x1b[1;38;2;255;136;0;48;5;17m\x1b[0m\x1b[m'), [
      'CUP cursor to row 3, column 5',
      'CUP cursor to row 1, column 1',
      'ED erase the screen all',
      'EL erase the line to the end',
      'REP repeat the last character 4 times',
      'SGR bold, fg #ff8800, bg 17',
      'SGR reset',
      'SGR reset',
    ]);
    assert.deepEqual(out('\x1b[?1049h\x1b[?25l\x1b[?1000;1006h\x1b[?2026l\x1b[?2026$p\x1b[>1u\x1b[<u\x1b[?u\x1b[>q\x1b[c\x1b[16t\x1b[6n\x1b[2 q'), [
      'DECSET 1049 alternate screen, cursor saved',
      'DECRST 25 cursor visible',
      'DECSET 1000 mouse buttons, 1006 SGR mouse',
      'DECRST 2026 synchronized output',
      'DECRQM query: mode 2026 synchronized output',
      'kitty keyboard push flags 1',
      'kitty keyboard pop 1',
      'kitty keyboard query: the flags',
      'XTVERSION query: the terminal name and version',
      'DA1 query: primary device attributes',
      'XTWINOPS query: a cell size in pixels',
      'DSR query: the cursor position',
      'DECSCUSR cursor shape block',
    ]);
    assert.deepEqual(out('\x1b]2;counter\x1b\\\x1b]11;?\x1b\\\x1b]8;id=1;https://x.y\x1b\\\x1b]8;;\x1b\\\x1b]9;4;1;40\x07\x1b]777;notify;T;B\x1b\\\x1b]52;c;aGk=\x1b\\\x1b]22;pointer\x1b\\'), [
      'OSC 2 title "counter"',
      'OSC 11 query: the background colour',
      'OSC 8 link to https://x.y',
      'OSC 8 link end',
      'OSC 9;4 progress set 40%',
      'OSC 777 notification T;B',
      'OSC 52 clipboard (4 base64 bytes)',
      'OSC 22 pointer shape pointer',
    ]);
    assert.deepEqual(out('\x1bPq#0;2;0;0;0#0~~\x1b\\\x1b_Ga=q,i=1;AAAA\x1b\\\x1b7\x1b8\x1bc\x1b[?S'), [
      'DCS sixel image (15 bytes)',
      'APC kitty graphics a=q,i=1',
      'DECSC save the cursor',
      'DECRC restore the cursor',
      'RIS reset the terminal',
      'XTSMGRAPHICS colour registers query',
    ]);
    assert.deepEqual(out('hé\x07\x08\t'), ['text "hé"', 'BEL bell', 'BS backspace', 'HT tab']);
  });

  it('names SGR in its forms', () => {
    assert.equal(describeSgr('4:3;58:2::1:2:3;38:5:208;9;22;97;100'), 'underline curly, underline colour #010203, fg 208, strikethrough, not bold or dim, fg bright white, bg bright black');
  });

  it('names what the terminal sends: keys, the mouse, answers', () => {
    assert.deepEqual(typed('a'), ['key a']);
    assert.deepEqual(typed('héllo'), ['typed "héllo"']);
    assert.deepEqual(typed(' '), ['key Space']);
    assert.deepEqual(typed('\r'), ['key Enter']);
    assert.deepEqual(typed('\x7f'), ['key Backspace']);
    assert.deepEqual(typed('\x03'), ['key Ctrl+C']);
    assert.deepEqual(typed('\x1b'), ['key Escape']);
    assert.deepEqual(typed('\x1bx'), ['key Alt+x']);
    assert.deepEqual(typed('\x1b[A'), ['key Up']);
    assert.deepEqual(typed('\x1b[1;5C'), ['key Ctrl+Right']);
    assert.deepEqual(typed('\x1bOA'), ['key Up']);
    assert.deepEqual(typed('\x1b[3~'), ['key Delete']);
    assert.deepEqual(typed('\x1b[15;2~'), ['key Shift+F5']);
    assert.deepEqual(typed('\x1b[Z'), ['key Shift+Tab']);
    assert.deepEqual(typed('\x1b[27u'), ['key Escape (kitty)']);
    assert.deepEqual(typed('\x1b[99;5u'), ['key Ctrl+c (kitty)']);
    assert.deepEqual(typed('\x1b[13;2u'), ['key Shift+Enter (kitty)']);
    assert.deepEqual(typed('\x1b[200~pasted\x1b[201~'), ['paste begins', 'typed "pasted"', 'paste ends']);
    assert.deepEqual(typed('\x1b[<0;10;5M\x1b[<0;10;5m\x1b[<32;11;5M\x1b[<65;1;1M\x1b[<16;2;3M'), [
      'mouse left press at column 10, row 5',
      'mouse left release at column 10, row 5',
      'mouse left moved at column 11, row 5',
      'mouse wheel down at column 1, row 1',
      'mouse Ctrl+left press at column 2, row 3',
    ]);
    assert.deepEqual(typed('\x1b[M *(', true), ['mouse (X10) left press at column 10, row 8']);
    assert.deepEqual(typed('\x1b[M#*(', true), ['mouse (X10) release at column 10, row 8']);
    assert.deepEqual(typed('\x1b[?2026;2$y\x1b[?2027;0$y\x1b[?1;2c\x1b[?1u\x1b[6;18;9t\x1b[12;40R\x1b[I'), [
      'DECRPM answer: mode 2026 synchronized output reset',
      'DECRPM answer: mode 2027 grapheme clusters not recognised',
      'DA1 answer: 1;2',
      'kitty keyboard answer: flags 1',
      'answer: a cell is 9x18 pixels',
      'CPR answer: the cursor at row 12, column 40',
      'focus in',
    ]);
    assert.deepEqual(typed('\x1b]11;rgb:1e1e/1e1e/1e1e\x1b\\\x1bP>|twk-vscode(0.0.1)\x1b\\'), [
      'OSC 11 answer: background rgb:1e1e/1e1e/1e1e',
      'XTVERSION answer: twk-vscode(0.0.1)',
    ]);
  });

  it('tells where a synchronized update begins and ends', () => {
    const changes = (s: string) => new SequenceReader().read(bytes(s)).map(syncChange);
    assert.deepEqual(changes('\x1b[?2026h\x1b[?2026l\x1b[?25;2026h\x1b[2026h\x1b[?2026$p'), [1, -1, 1, 0, 0]);
  });

  it('shows the bytes with ESC and the controls readable, a long one cut', () => {
    assert.equal(visible('\x1b[1;1Hab\r\n\x7f'), 'ESC [1;1Hab^M^J^?');
    assert.equal(visible('\x1b[A\x1b[B'), 'ESC [A ESC [B');
    assert.equal(visible('x'.repeat(200), 10), `${'x'.repeat(10)}… (200 bytes)`);
  });
});
