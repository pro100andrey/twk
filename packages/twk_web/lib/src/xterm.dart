/// xterm.js through dart:js_interop: its `Terminal` ([Xterm]), the options
/// it is made with ([XtermOptions], [XtermTheme]), the addons `runWebApp`
/// loads where the page has them ([FitAddon], [Unicode11Addon]), and the
/// [XtermPort] an `XtermLink` runs over ([Xterm.port]). The page loads
/// xterm.js and its addons with script tags, which define them globally.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'link.dart';

/// xterm.js's `Terminal`.
@JS('Terminal')
extension type Xterm._(JSObject _) implements JSObject {
  /// A terminal made with [options], shown once [open]ed. Throws where the
  /// page did not load xterm.js ([loaded]).
  external Xterm(XtermOptions options);

  /// The page loaded xterm.js: `Terminal` is defined.
  static bool get loaded => globalContext.has('Terminal');

  /// How many columns the terminal has.
  external int get cols;

  /// How many rows the terminal has.
  external int get rows;

  /// Its options: setting one changes the terminal.
  external XtermOptions get options;

  /// The Unicode version its widths are of; needs
  /// [XtermOptions.allowProposedApi].
  external XtermUnicode get unicode;

  /// Shows the terminal in [parent], which must be in the document.
  external void open(web.HTMLElement parent);

  /// Gives the terminal the keyboard focus.
  external void focus();

  /// Loads [addon] into the terminal, such as a [FitAddon] or a
  /// [Unicode11Addon]; its owner disposes it with the terminal.
  external void loadAddon(JSObject addon);

  /// Writes [data] (a string, or UTF-8 bytes in a `Uint8Array`); [parsed]
  /// is called once it is parsed.
  external void write(JSAny data, JSFunction parsed);

  /// Takes the terminal out of the page; it can't be used again.
  external void dispose();

  @JS('onData')
  external _Disposable _onData(JSFunction listener);

  @JS('onBinary')
  external _Disposable _onBinary(JSFunction listener);

  @JS('onResize')
  external _Disposable _onResize(JSFunction listener);

  /// What an [XtermLink] to this terminal runs over.
  XtermPort get port => _Port(this);
}

/// What an xterm.js terminal is made with (`ITerminalOptions`): those given
/// are set, the others are xterm.js's defaults.
///
/// ```dart
/// final options = XtermOptions(
///   fontFamily: 'monospace',
///   fontSize: 14,
///   theme: XtermTheme(background: '#1e1e1e', foreground: '#d4d4d4'),
/// );
/// ```
extension type XtermOptions._(JSObject _) implements JSObject {
  /// Options with those given set: [allowProposedApi] for the proposed
  /// APIs (a [Unicode11Addon]'s), [cursorBlink] for a blinking cursor,
  /// [fontFamily], [fontSize] (in CSS pixels) and [lineHeight] (a multiple
  /// of the font's) for the cells' look, [theme] for the colors.
  external factory XtermOptions({
    bool allowProposedApi,
    bool cursorBlink,
    String fontFamily,
    num fontSize,
    num lineHeight,
    XtermTheme theme,
  });

  /// Whether the terminal's proposed APIs may be used, which
  /// [Xterm.unicode] is one of; null where it was not given, which
  /// xterm.js takes as false.
  external bool? get allowProposedApi;
  external set allowProposedApi(bool? allow);
}

/// The colors of an xterm.js terminal (`ITheme`), as CSS colors.
extension type XtermTheme._(JSObject _) implements JSObject {
  /// A theme with those colors given: the cells' [background] and
  /// [foreground], the [cursor]'s, and [selectionBackground] behind
  /// selected text; the others are xterm.js's.
  external factory XtermTheme({
    String background,
    String foreground,
    String cursor,
    String selectionBackground,
  });
}

/// The Unicode handling of an xterm.js terminal (`IUnicodeHandling`).
extension type XtermUnicode._(JSObject _) implements JSObject {
  /// The Unicode version the terminal measures characters by: '6' by
  /// default; '11' may be set once a [Unicode11Addon] is loaded.
  external String get activeVersion;
  external set activeVersion(String version);
}

/// @xterm/addon-fit's `FitAddon`: fits the terminal to its element.
@JS('FitAddon.FitAddon')
extension type FitAddon._(JSObject _) implements JSObject {
  /// An addon for [Xterm.loadAddon]. Throws where the page did not load
  /// @xterm/addon-fit ([loaded]).
  external FitAddon();

  /// The page loaded @xterm/addon-fit.
  static bool get loaded => globalContext.has('FitAddon');

  /// Resizes the terminal to as many cells as its element holds; nothing
  /// while the element has no size.
  external void fit();
}

/// @xterm/addon-unicode11's `Unicode11Addon`: Unicode 11's widths, version
/// '11' of [XtermUnicode].
@JS('Unicode11Addon.Unicode11Addon')
extension type Unicode11Addon._(JSObject _) implements JSObject {
  /// An addon for [Xterm.loadAddon]. Throws where the page did not load
  /// @xterm/addon-unicode11 ([loaded]).
  external Unicode11Addon();

  /// The page loaded @xterm/addon-unicode11.
  static bool get loaded => globalContext.has('Unicode11Addon');
}

/// xterm.js's `IDisposable`, what adding a listener returns.
extension type _Disposable._(JSObject _) implements JSObject {
  external void dispose();
}

/// What `onResize` gives.
extension type _Size._(JSObject _) implements JSObject {
  /// How many columns the terminal has.
  external int get cols;

  /// How many rows the terminal has.
  external int get rows;
}

final class _Port implements XtermPort {
  _Port(this._xterm);

  final Xterm _xterm;

  @override
  int get columns => _xterm.cols;

  @override
  int get rows => _xterm.rows;

  @override
  void Function() onData(void Function(String data) listener) {
    final added = _xterm._onData(
      ((JSString data) => listener(data.toDart)).toJS,
    );
    // ignore: unnecessary_lambdas, dart2wasm tears off no interop member
    return () => added.dispose();
  }

  @override
  void Function() onBinary(void Function(String data) listener) {
    final added = _xterm._onBinary(
      ((JSString data) => listener(data.toDart)).toJS,
    );
    // ignore: unnecessary_lambdas, dart2wasm tears off no interop member
    return () => added.dispose();
  }

  @override
  void Function() onResize(void Function(int columns, int rows) listener) {
    final added = _xterm._onResize(
      ((_Size size) => listener(size.cols, size.rows)).toJS,
    );
    // ignore: unnecessary_lambdas, dart2wasm tears off no interop member
    return () => added.dispose();
  }

  @override
  void write(Uint8List bytes, void Function() written) =>
      _xterm.write(bytes.toJS, written.toJS);
}
