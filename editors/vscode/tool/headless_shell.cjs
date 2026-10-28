// Serves a headless xterm.js to a twk app through the extension's shell
// (out/core/shell.js: `npm run compile` first), types keys once an app
// connected, and prints the screen when asked ("screen") and when the app
// went away; "resize" makes it 50x10. It prints the TWK_SHELL to start the
// app with, without a tty:
//
//   node tool/headless_shell.cjs $PWD 'xterm.js' \
//       '["\u001b[A","screen","resize","screen","q"]' 1500 &
//   (cd ../../packages/twk && TWK_SHELL='<printed>' dart run example/counter.dart </dev/null)
//
// The preset is one of core/capabilities.ts's (xterm.js, everything, no
// answers...); the webview's answers (webview/answers.ts) are installed on
// the headless xterm.js as on the webview's, the requests printed.
//
// node headless_shell.cjs <ext dir> <preset> <keys-json> <ms-before-keys>
const [ext, presetName, keysJson, delay] = process.argv.slice(2);
const os = require('node:os');
const { Terminal } = require(ext + '/node_modules/@xterm/headless');
const { TerminalShell } = require(ext + '/out/core/shell.js');
const { answersOf, declarationOf, environmentOf, presetNamed } = require(ext + '/out/core/capabilities.js');
const { Emulation } = require(ext + '/out/webview/answers.js');
const t = new Terminal({ cols: 60, rows: 12, allowProposedApi: true });
const capabilities = presetNamed(presetName).capabilities;
const emulation = new Emulation(t, {
  reply: (text) => shell?.input(Buffer.from(text, 'utf8')),
  request: (r) => console.log('request', JSON.stringify(r)),
  pointer: (shape) => console.log('pointer', shape),
  cellSize: () => ({ width: 9, height: 18 }),
});
const pane = { get columns() { return t.cols; }, get lines() { return t.rows; },
  write: (b) => new Promise((r) => t.write(b, r)) };
const screen = () => { const b = t.buffer.active; const rows = [];
  for (let y = 0; y < t.rows; y++) rows.push(b.getLine(y).translateToString(true));
  return `[${b.type} buffer]\n` + rows.join('\n'); };
let shell;
t.onData((d) => shell?.input(Buffer.from(d, 'binary')));
(async () => {
  const onEvent = async (e) => {
    console.log('event', e);
    if (e === 'connected') {
      await new Promise((r) => setTimeout(r, Number(delay)));
      for (const k of JSON.parse(keysJson)) {
        if (k === 'resize') { t.resize(50, 10); shell.resized(); }
        else if (k === 'screen') { await new Promise((r) => t.write('', r)); console.log(screen()); }
        else shell.input(Buffer.from(k, 'latin1'));
        await new Promise((r) => setTimeout(r, 400));
      }
    } else {
      await new Promise((r) => t.write('', r));
      console.log(screen());
      await shell.stop();
      process.exit(0);
    }
  };
  shell = await TerminalShell.start(pane, {
    welcome: () => {
      emulation.configure(answersOf(capabilities));
      return { environment: environmentOf(capabilities), declares: declarationOf(capabilities) };
    },
    onEvent: (e) => void onEvent(e),
    temporaryRoot: os.tmpdir(),
    tcp: process.platform === 'win32',
  });
  console.log(`TWK_SHELL=${shell.variable}`);
  setTimeout(async () => { console.log('timeout'); await shell.stop(); process.exit(1); }, 60000);
})();
