/// A twk app in the browser, built with dart2wasm: `runWebApp` mounts one
/// into a DOM element, on an xterm.js terminal (`Xterm`) that a `Terminal`
/// runs over through an `XtermLink`.
library;

export 'src/link.dart' show XtermLink, XtermPort;
export 'src/run.dart' show runWebApp;
export 'src/xterm.dart'
    show
        FitAddon,
        Unicode11Addon,
        Xterm,
        XtermOptions,
        XtermTheme,
        XtermUnicode;
