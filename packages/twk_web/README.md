# twk_web — a twk app in the browser

Runs an app of [twk](../twk/README.md) in a web page, on
[xterm.js](https://xtermjs.org): `runWebApp` mounts it into a DOM
element, where a `Terminal` of the core runs over a link to an xterm.js
terminal (`XtermLink`, through `Terminal.overLink`) as it runs over the
process's own terminal elsewhere. It takes twk and the core as path
dependencies, and [package:web](https://pub.dev/packages/web), whose
dart:js_interop reaches xterm.js; xterm.js itself is the page's, loaded
from a CDN at a pinned version.

```dart
import 'package:twk/twk.dart';
import 'package:twk_web/twk_web.dart';
import 'package:web/web.dart' as web;

Future<void> main() => runWebApp(
  web.document.querySelector('#terminal')! as web.HTMLElement,
  const Text('Hello from the browser'),
);
```

## Building

The build is dart2wasm's, and only that: dart2js compiles the core too,
but the 64-bit views its cells are kept in (`Uint64List`, `Int64List`)
throw once run there. The example, [web/main.dart](web/main.dart), shows
what xterm.js answered the core's probe, a button the mouse or Enter
presses and the last input; [web/index.html](web/index.html) is its page:

```bash
dart compile wasm web/main.dart -o web/main.wasm
python3 -m http.server -d web 8080      # then http://localhost:8080
```

`dart compile wasm` writes `main.wasm` and `main.mjs`, its loader, which
the page imports. A build runs where WasmGC, JS string builtins and
exception handling are: Chrome and Edge 137 and later, Firefox 134 and
later, Safari 26.2 and later
([dart.dev/web/wasm](https://dart.dev/web/wasm)).

## The page

The page loads xterm.js 6.0.0 (`lib/xterm.js` and `css/xterm.css` of
@xterm/xterm), which defines `Terminal`, before the build. Two addons
are used where it loads them too, as the example's does: @xterm/addon-fit
0.11.0, so that the terminal is as big as its element, also as that
changes (a `ResizeObserver`); without it the terminal keeps its size,
80x24. And @xterm/addon-unicode11 0.9.0, so that it measures characters
by Unicode 11, closer to the core's widths than xterm.js's own Unicode 6,
which has emoji one column wide. `runWebApp` throws a `StateError` where
xterm.js is not loaded.

`runWebApp(element, app, options:, maxFps:, logs:, exitOnCtrlC:)` makes
the terminal with `options` (`XtermOptions`: font, size, theme), opens
it in `element` and focuses it, and runs `app` on the alternate screen as
`runApp` does, the rest of its options being `runApp`'s. When the app
quits, the terminal is disposed, which takes it out of `element`, and the
returned future completes.

A page with a terminal of its own runs a `Terminal` over it with
`Terminal.overLink(XtermLink(xterm.port))`: `Xterm` is xterm.js's
`Terminal` through dart:js_interop, `XtermPort` what the link needs of it.

## What xterm.js is to the core

The link tells the core it is `TERM=xterm-256color`, `COLORTERM=truecolor`
and `TERM_PROGRAM=xterm.js` (`XtermLink.xtermEnvironment`; a link given
an environment of its own tells that). It has no console modes: xterm.js
has no line discipline, its input is raw, and Backspace sends 0x7F. Its
input is xterm.js's `onData`, the binary input of `onBinary` as its
bytes; its output goes to `write`, and a flush completes once xterm.js
called back for the last write, when it has parsed it; its resizes are
`onResize`'s.

What xterm.js 6.0.0 answers the probe with its default options, from
`src/common/InputHandler.ts` and `src/browser/CoreBrowserTerminal.ts` of
the @xterm/xterm package, and as `test/browser/xterm_test.dart` finds
it in Chrome:

| Query | Answer | Found |
|---|---|---|
| DA1 (`CSI c`) | `CSI ? 1 ; 2 c`, by its `termName` 'xterm' (`sendDeviceAttributesPrimary`) | answered; no sixel |
| DECRQM 2026, synchronized output | `CSI ? 2026 ; 2 $ y`, reset (`requestMode`); frames are held while it is set (`RenderService`) | synchronized output |
| DECRQM 2027, 2048, 69, 2031 | `; 0 $ y`, not recognized | no grapheme clustering, no in-band resizes, no left and right margins, no color scheme reports |
| OSC 10 and 11 `?` | `OSC 10 ; rgb:ffff/ffff/ffff ST`, `OSC 11 ; rgb:0000/0000/0000 ST`, the theme's (`_handleColorEvent`) | white on black, dark |
| kitty keyboard (`CSI ? u`) | nothing: no handler for it | the legacy keys, a lone ESC resolved after the escape timeout |
| kitty graphics (an APC), XTVERSION (`CSI > 0 q`) | nothing: its parser drops APC strings, and no handler takes `CSI > q` | no images |
| cell size (`CSI 16 t`) | nothing unless `windowOptions.getCellSizePixels` is set (`windowOptions`) | not known |
| CPR (`CSI 6 n`) | `CSI row ; column R` (`deviceStatus`) | U+2500 one column wide |

It reports the mouse in the SGR encoding (DECSET 1000, 1002, 1003 and
1006), focus (1004) and bracketed pastes (2004). Images, the clipboard
(OSC 52) and notifications are not there without addons of its own, which
`runWebApp` does not load.

## Tests

`dart test` runs the link over a fake xterm.js terminal on the VM
(`test/fake_xterm.dart`, answering the probe as above) and compiles the
example with dart2wasm. In a browser, with Chrome as the test runner
finds it (`CHROME_EXECUTABLE`):

```bash
CHROME_EXECUTABLE=google-chrome-stable \
    dart test -p chrome --compiler dart2wasm
```

runs the js_interop layer over a JS object of its own, then over
xterm.js and its addons loaded from jsDelivr as the example's page loads
them: what it answers the probe, its input, pastes and resizes, and
`runWebApp`. `dart run tool/web_check.dart twk_web`, from the
repository's root, builds a `runWebApp` app and runs it in node on a
stand-in for xterm.js (`test/web/xterm_stub.mjs`).

## Checks

From this directory: `dart pub get`, `dart analyze`, `dart test`, and
`dart format --output=none --set-exit-if-changed lib test`.

## License

MIT, copyright 2026 Andrii Ivanov: [LICENSE](LICENSE).
