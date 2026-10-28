// The js_interop layer in a browser:
//
//   CHROME_EXECUTABLE=google-chrome-stable \
//       dart test -p chrome --compiler dart2wasm
//
// The port over a JS object of its own, then xterm.js 6.0.0 and its fit
// and Unicode 11 addons loaded from jsDelivr, as web/index.html loads
// them: what it answers the probe, its input and resizes, and runWebApp.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Terminal;
import 'package:twk_test/twk_test.dart' show waitUntil;
import 'package:twk_web/twk_web.dart';
import 'package:web/web.dart' as web;

const _cdn = 'https://cdn.jsdelivr.net/npm/@xterm';

/// The scripts of web/index.html and their hashes.
const _scripts = {
  '$_cdn/xterm@6.0.0/lib/xterm.js':
      'sha384-f/1U6Z9wM4D71a5eRXEZnyOTMOvjqxr2XLwh+Go1OvIl3L3tOcvUrzudnhbECwl4',
  '$_cdn/addon-fit@0.11.0/lib/addon-fit.js':
      'sha384-txoiwu4RR2GD3qySbaj+BbzibkLbSJRcfqGYMu6z1EqHil4A2dyBiBW5dlacG6OR',
  '$_cdn/addon-unicode11@0.9.0/lib/addon-unicode11.js':
      'sha384-s7G1tpQVHxwemnFdH7ZEOPEAMxRSbFGsvrhaHpxYuMssFdike2DQuIBzg43+p5/3',
};

Future<void> _load(String url, String integrity) {
  final loaded = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = url
    ..integrity = integrity
    ..crossOrigin = 'anonymous'
    ..onload = ((web.Event _) => loaded.complete()).toJS
    ..onerror = ((web.Event _) => loaded.completeError(
      StateError('$url did not load'),
    )).toJS;
  web.document.head!.append(script);
  return loaded.future;
}

/// A [width] by [height] pixels element in the page, removed after the
/// test.
web.HTMLDivElement _element(int width, int height) {
  final div = web.HTMLDivElement()
    ..style.width = '${width}px'
    ..style.height = '${height}px';
  web.document.body!.append(div);
  // ignore: unnecessary_lambdas, dart2wasm tears off no interop member
  addTearDown(() => div.remove());
  return div;
}

/// The xterm.js terminals made from now on, until the test ends: its
/// `Terminal` behind a proxy that keeps them.
List<JSObject> _madeTerminals() {
  final made = <JSObject>[];
  final terminal = globalContext['Terminal']! as JSFunction;
  final reflect = globalContext['Reflect']! as JSObject;
  final keep = JSObject()
    ..['construct'] = ((JSFunction target, JSArray<JSAny?> arguments) {
      final one = reflect.callMethod<JSObject>(
        'construct'.toJS,
        target,
        arguments,
      );
      made.add(one);
      return one;
    }).toJS;
  globalContext['Terminal'] = (globalContext['Proxy']! as JSFunction)
      .callAsConstructor<JSObject>(terminal, keep);
  addTearDown(() => globalContext['Terminal'] = terminal);
  return made;
}

void main() {
  test('the port goes through to the JS object', () {
    final added = <String, JSFunction>{};
    final writes = <List<int>>[];
    JSFunction listen(String name) => ((JSFunction listener) {
      added[name] = listener;
      return JSObject()..['dispose'] = (() => added.remove(name)).toJS;
    }).toJS;
    final object = JSObject()
      ..['cols'] = 90.toJS
      ..['rows'] = 30.toJS
      ..['onData'] = listen('data')
      ..['onBinary'] = listen('binary')
      ..['onResize'] = listen('resize')
      ..['write'] = ((JSUint8Array data, JSFunction parsed) {
        writes.add(data.toDart);
        parsed.callAsFunction();
      }).toJS;
    final port = (object as Xterm).port;
    expect((port.columns, port.rows), (90, 30));

    final got = <Object>[];
    final removers = [
      port.onData(got.add),
      port.onBinary((data) => got.add('binary $data')),
      port.onResize((columns, rows) => got.add((columns, rows))),
    ];
    added['data']!.callAsFunction(null, 'é😀'.toJS);
    added['binary']!.callAsFunction(null, 'é'.toJS);
    added['resize']!.callAsFunction(
      null,
      JSObject()
        ..['cols'] = 100.toJS
        ..['rows'] = 40.toJS,
    );
    expect(got, ['é😀', 'binary é', (100, 40)]);

    var parsed = false;
    port.write(Uint8List.fromList([0x1B, 0x5B, 0x6D]), () => parsed = true);
    expect(writes, [
      [0x1B, 0x5B, 0x6D],
    ]);
    expect(parsed, isTrue);

    for (final remove in removers) {
      remove();
    }
    expect(added, isEmpty);
  });

  group('xterm.js 6.0.0', () {
    setUpAll(() async {
      for (final MapEntry(key: url, value: integrity) in _scripts.entries) {
        await _load(url, integrity);
      }
    });

    test('answers the probe', () async {
      final xterm = Xterm(XtermOptions())..open(_element(800, 400));
      // ignore: unnecessary_lambdas, dart2wasm tears off no interop member
      addTearDown(() => xterm.dispose());
      final terminal = await Terminal.overLink(
        XtermLink(xterm.port),
        const TerminalOptions(probeTimeout: Duration(seconds: 20)),
      );
      addTearDown(terminal.close);
      final info = terminal.info;
      expect(info.answeredQueries, isTrue);
      expect(info.caps.synchronizedOutput, isTrue);
      expect(info.graphemeMode, isFalse);
      expect(info.inBandResize, isFalse);
      expect(info.colorSchemeReports, isFalse);
      expect(info.caps.leftRightMargins, isFalse);
      expect(info.kittyKeyboard, isFalse);
      expect(info.foregroundRgb, 0xFFFFFF);
      expect(info.backgroundRgb, 0x000000);
      expect(info.caps.graphics, GraphicsProtocol.none);
      expect(info.caps.cellPixelWidth, 0);
      expect(info.ambiguousWidth, 1);
      expect((terminal.width, terminal.height), (80, 24));
    });

    test('sends input, pastes and resizes', () async {
      final xterm = Xterm(XtermOptions())..open(_element(800, 400));
      // ignore: unnecessary_lambdas, dart2wasm tears off no interop member
      addTearDown(() => xterm.dispose());
      final terminal = await Terminal.overLink(XtermLink(xterm.port));
      addTearDown(terminal.close);
      final events = <InputEvent>[];
      // whether the page has the focus is the browser's
      terminal.events.where((e) => e is! FocusEvent).listen(events.add);
      // bracketed paste on once xterm.js parsed it
      await terminal.flush();
      xterm
        ..callMethod('input'.toJS, 'é'.toJS)
        ..callMethod('paste'.toJS, 'pasted'.toJS);
      await waitUntil(() => events.length >= 2, 'the key and the paste');
      xterm.callMethod('resize'.toJS, 100.toJS, 30.toJS);
      await waitUntil(() => events.length >= 3, 'the resize');
      expect(events, [
        const KeyEvent(KeyCode.char, char: 'é'),
        const PasteEvent('pasted'),
        const ResizeEvent(100, 30),
      ]);
    });

    test('runWebApp fits the app to its element until it quits', () async {
      final made = _madeTerminals();
      final element = _element(1000, 500);
      final seen = _Seen();
      final ran = runWebApp(element, _App(seen));
      await waitUntil(
        () => (element.textContent ?? '').contains('in a page'),
        'the app in the page',
      );
      expect(seen.sizes.single.$1, greaterThan(80));
      final unicode = made.single['unicode']! as JSObject;
      expect((unicode['activeVersion']! as JSString).toDart, '11');
      element.style.width = '500px';
      await waitUntil(
        () => seen.sizes.length > 1,
        'the app laid out again at the narrower element',
      );
      expect(seen.sizes.last.$1, lessThan(seen.sizes.first.$1));
      seen.binding!.quit();
      await ran;
      expect(element.children.length, 0);
    });

    test('runWebApp throws where xterm.js is not loaded', () async {
      final terminal = globalContext['Terminal'];
      globalContext.delete('Terminal'.toJS);
      addTearDown(() => globalContext['Terminal'] = terminal);
      await expectLater(
        runWebApp(_element(100, 100), const Text('')),
        throwsStateError,
      );
    });
  });
}

/// Text, which tells [seen] its binding and the sizes it was laid out at.
final class _App extends StatelessWidget {
  const _App(this.seen);

  final _Seen seen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      seen
        ..binding = AppBinding.of(context)
        ..sizes.add((constraints.maxW, constraints.maxH));
      return const Text('in a page');
    },
  );
}

final class _Seen {
  AppBinding? binding;
  final sizes = <(int, int)>[];
}
