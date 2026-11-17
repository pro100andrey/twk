# web_template

An app in a browser: a counter, on [xterm.js](https://xtermjs.org), which
[twk_web](https://pub.dev/packages/twk_web)'s `runWebApp` mounts into the
page's `#terminal`. Up counts, q quits. Made by `twk create
--template=web`, on the widgets of twk.

## Run

```bash
dart pub get
dart compile wasm web/main.dart -o web/main.wasm
python3 -m http.server -d web 8080      # then http://localhost:8080
```

The build is dart2wasm's and only that (dart2js does not run the core). It
writes `main.wasm` and `main.mjs` next to `index.html`, which loads xterm.js
and its addons from a CDN at pinned versions, so the page needs the network.
A browser that has WasmGC runs it: Chrome and Edge 137 and later, Firefox 134
and later, Safari 26.2 and later.

## Test

```bash
dart test
dart analyze
dart format --output=none --set-exit-if-changed .
```

`testTwk` (twk_test) runs the app on a terminal in memory under a fake
clock: keys go in as a terminal sends them, the screen is read back. The
page itself is checked by building it: `dart compile wasm web/main.dart -o
web/main.wasm` must succeed.

## Files

- `web/index.html` is the page, `web/main.dart` mounts the app into it.
- `lib/web_template.dart` is the app.
- `test/web_template_test.dart` tests it.
