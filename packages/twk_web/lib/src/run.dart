/// Running a twk app in a page: [runWebApp].
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Terminal;
import 'package:web/web.dart' as web;

import 'link.dart';
import 'xterm.dart';

// Examples can assume:
// import 'package:twk/twk.dart';
// import 'package:web/web.dart' as web;

/// Runs [app] in [element] until it quits, as `runApp` runs one on the
/// alternate screen ([maxFps], [logs] and [exitOnCtrlC] are its): on an
/// xterm.js terminal made with [options], opened in [element] and
/// focused, through a `Terminal` over an [XtermLink] to it. Where the page
/// loaded @xterm/addon-fit the terminal is as big as [element], also as
/// that changes (a `ResizeObserver`); otherwise it keeps its size, 80x24.
/// Where the page loaded @xterm/addon-unicode11, the terminal measures
/// characters by Unicode 11, closer to the core's widths than xterm.js's
/// own Unicode 6, which has emoji one column wide; that sets
/// [XtermOptions.allowProposedApi]. The terminal is disposed when the app
/// ends, which takes it out of [element]. Throws [StateError] where the
/// page did not load xterm.js.
///
/// An app in the page's element `#terminal`:
///
/// ```dart
/// Future<void> main() => runWebApp(
///   web.document.querySelector('#terminal')! as web.HTMLElement,
///   const Text('Hello from the browser'),
/// );
/// ```
Future<void> runWebApp(
  web.HTMLElement element,
  Widget app, {
  XtermOptions? options,
  int maxFps = 60,
  LogSink? logs,
  bool exitOnCtrlC = true,
}) async {
  if (!Xterm.loaded) {
    throw StateError(
      'xterm.js is not loaded: the page needs its script, which defines '
      'Terminal',
    );
  }
  final xterm = Xterm(options ?? XtermOptions());
  final fit = FitAddon.loaded ? FitAddon() : null;
  web.ResizeObserver? observer;
  try {
    if (Unicode11Addon.loaded) {
      xterm
        ..options.allowProposedApi = true
        ..loadAddon(Unicode11Addon())
        ..unicode.activeVersion = '11';
    }
    if (fit != null) {
      xterm.loadAddon(fit);
    }
    xterm.open(element);
    if (fit != null) {
      fit.fit();
      if (globalContext.has('ResizeObserver')) {
        observer = web.ResizeObserver(
          ((
            JSArray<web.ResizeObserverEntry> _,
            web.ResizeObserver _,
          ) => fit.fit()).toJS,
        )..observe(element);
      }
    }
    xterm.focus();
    final terminal = await Terminal.overLink(
      XtermLink(xterm.port),
      const TerminalOptions(mouse: false),
    );
    await runApp(
      app,
      terminal: terminal,
      maxFps: maxFps,
      logs: logs,
      exitOnCtrlC: exitOnCtrlC,
    );
  } finally {
    observer?.disconnect();
    xterm.dispose();
  }
}
