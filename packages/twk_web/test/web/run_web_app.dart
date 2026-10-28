// A twk_web app where there is no page: runWebApp on a stand-in for
// xterm.js (xterm_stub.mjs, which tool/web_check.dart loads first; node
// has no DOM) until the app was shown, which the stub tells as it writes
// it, then quit. What tool/web_check.dart compiles for the web and runs,
// handing it its bound (main's one argument, in milliseconds): it prints a
// line per part, then `done` unless the bound passed first, which it says
// with what the app showed, or the terminal was not opened, not disposed,
// kept a listener or was left on the alternate screen.

// a browser has no stdout: print is its console
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:twk/twk.dart';
import 'package:twk_web/twk_web.dart';
import 'package:web/web.dart' as web;

const _shown = 'hello from twk_web';

Future<void> main(List<String> args) async {
  // tool/web_check.dart's, which waits for the run a while longer
  final bound = Duration(milliseconds: int.parse(args.single));
  // what xterm.js would be opened in
  final element = JSObject() as web.HTMLElement;
  AppBinding? binding;
  final ran = runWebApp(
    element,
    _App((b) => binding = b),
  );
  final xterm = (globalContext['terminals']! as JSArray<JSObject>).toDart.last;
  String text() => (xterm['text']! as JSString).toDart;
  // quit once the stub has what the app showed, as it writes it
  final shown = xterm.callMethod<JSObject>(
    'onWritten'.toJS,
    ((JSString _, JSNumber _) {
      if (text().contains(_shown)) {
        binding?.quit();
      }
    }).toJS,
  );
  try {
    await ran.timeout(
      bound,
      onTimeout: () => throw StateError(
        'after ${bound.inMilliseconds} ms the app showed: ${text()}',
      ),
    );
  } finally {
    shown.callMethod<JSAny?>('dispose'.toJS);
  }
  bool flag(String name) => (xterm[name]! as JSBoolean).toDart;
  final listeners = xterm['listeners']! as JSObject;
  int count(String name) =>
      ((listeners[name]! as JSObject)['size']! as JSNumber).toDartInt;
  final left = count('data') + count('binary') + count('resize');
  final screen = text().contains('\x1b[?1049l');
  print('app: shown, then quit');
  print(
    'xterm: ${flag('opened') ? 'opened' : 'not opened'}, '
    '${flag('disposed') ? 'disposed' : 'left'}, $left listeners left',
  );
  print('screen: ${screen ? 'left' : 'not left'}');
  if (!flag('opened') || !flag('disposed') || left > 0 || !screen) {
    throw StateError('runWebApp left the terminal as it should not');
  }
  print('done');
}

/// [_shown], which tells [bound] its binding.
final class _App extends StatelessWidget {
  const _App(this.bound);

  final void Function(AppBinding binding) bound;

  @override
  Widget build(BuildContext context) {
    bound(AppBinding.of(context));
    return const Text(_shown);
  }
}
