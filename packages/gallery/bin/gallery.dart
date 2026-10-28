// The twk gallery: every widget on a page of its own.
//
//   dart run packages/gallery/bin/gallery.dart
//   dart run packages/gallery/bin/gallery.dart --route='#/controls/button?theme=light'
//
// --route opens it where a route says (packages/gallery/README.md,
// "Routes"): the page, theme, options, tab, focus, filter, palette, a
// toast, the clock stopped at t=, and keys= and type= pressed and typed
// once it shows.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:gallery/gallery.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show
        MouseTracking,
        MouseTrackingBackend,
        SuspendableBackend,
        Terminal,
        TerminalInfo,
        TerminalStateBackend,
        WindowBackend;

Future<void> main(List<String> args) async {
  String? spec;
  for (final a in args) {
    if (a.startsWith('--route=')) {
      spec = a.substring('--route='.length);
    } else if (a == '--help' || a == '-h') {
      stdout.writeln(
        'usage: gallery.dart [--route=#/<group>/<page>?theme=…&o=…&t=…]',
      );
      return;
    } else if (!a.startsWith('-')) {
      spec = a;
    }
  }
  final route = spec == null ? null : GalleryRoute.parse(spec);
  final typed = [
    for (final k in route?.keys ?? const <String>[]) ?keyEvent(k),
    for (final c in (route?.type ?? '').split(''))
      if (c.isNotEmpty) KeyEvent(KeyCode.char, char: c),
  ];
  if (typed.isEmpty) {
    await runApp(galleryApp(route: route));
    return;
  }
  final terminal = await Terminal.open(const TerminalOptions(mouse: false));
  await runApp(galleryApp(route: route), terminal: Typing(terminal, typed));
}

/// The key event a route's key name stands for: `tab`, `shift+tab`,
/// `ctrl+p`, `space`, `pageup`, `t`; null for a name that is none.
KeyEvent? keyEvent(String name) {
  var mods = 0;
  var rest = name;
  for (;;) {
    final plus = rest.indexOf('+');
    if (plus <= 0 || plus == rest.length - 1) {
      break;
    }
    final m = switch (rest.substring(0, plus)) {
      'ctrl' => Mod.ctrl,
      'alt' => Mod.alt,
      'shift' => Mod.shift,
      _ => 0,
    };
    if (m == 0) {
      break;
    }
    mods |= m;
    rest = rest.substring(plus + 1);
  }
  if (rest.runes.length == 1) {
    return KeyEvent(KeyCode.char, char: rest, modifiers: mods);
  }
  final code = switch (rest) {
    'space' => null,
    'esc' => KeyCode.escape,
    'pageup' => KeyCode.pageUp,
    'pagedown' => KeyCode.pageDown,
    _ => KeyCode.values.where((c) => c.name == rest).firstOrNull,
  };
  if (rest == 'space') {
    return KeyEvent(KeyCode.char, char: ' ', modifiers: mods);
  }
  return code == null ? null : KeyEvent(code, modifiers: mods);
}

/// [terminal], with [keys] coming in after its own first events, one
/// every 40 ms once the app had a moment to show; every capability of a
/// [Terminal] is passed on to it, so a route that types keys loses none:
/// handing it to another program ([SuspendableBackend]), the mouse
/// reports ([MouseTrackingBackend]), the pointer's shape and the progress
/// ([TerminalStateBackend]), the window's title and notifications
/// ([WindowBackend]).
final class Typing
    implements
        SuspendableBackend,
        MouseTrackingBackend,
        TerminalStateBackend,
        WindowBackend {
  /// [terminal] with [keys] typed into it.
  Typing(this.terminal, this.keys);

  /// What is typed into.
  final Terminal terminal;

  /// What is typed.
  final List<KeyEvent> keys;

  @override
  late final Stream<InputEvent> events = () {
    final out = StreamController<InputEvent>();
    final sub = terminal.events.listen(out.add, onDone: out.close);
    out.onCancel = sub.cancel;
    unawaited(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      for (final k in keys) {
        if (out.isClosed) {
          return;
        }
        out.add(k);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }());
    return out.stream;
  }();

  @override
  TerminalInfo get info => terminal.info;

  @override
  int get width => terminal.width;

  @override
  int get height => terminal.height;

  @override
  void write(Uint8List bytes) => terminal.write(bytes);

  @override
  Future<void> flush() => terminal.flush();

  @override
  Future<void> close() => terminal.close();

  @override
  void setTitle(String title) => terminal.setTitle(title);

  @override
  void notify(String title, String body) => terminal.notify(title, body);

  @override
  Future<void> suspend() => terminal.suspend();

  @override
  Future<void> resume() => terminal.resume();

  @override
  MouseTracking get mouseTracking => terminal.mouseTracking;

  @override
  set mouseTracking(MouseTracking tracking) =>
      terminal.mouseTracking = tracking;

  @override
  void setTerminalState(
    Object key,
    String sequence,
    String restore, {
    Duration? refresh,
  }) => terminal.setTerminalState(key, sequence, restore, refresh: refresh);

  @override
  void restoreTerminalState(Object key) => terminal.restoreTerminalState(key);
}
