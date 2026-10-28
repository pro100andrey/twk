// The gallery where there is no page: runWebApp on twk_web's stand-in for
// xterm.js (packages/twk_web/test/web/xterm_stub.mjs, which
// tool/web_check.dart loads first; node has no DOM), every page of the
// catalog in turn, the next once the stub has the frame of the last, then
// the Images page with its PNG, which only decodes on the web through
// package:twk_rich/image.dart's own inflater; then quit. What
// tool/web_check.dart compiles for the web and runs, handing it its bound
// (main's one argument, in milliseconds): it prints a line per part, then
// `done` unless a page showed an error (an exception's text, a thrown
// Unsupported operation) but App › ErrorWidget, whose widget it is, or
// the bound passed first, which it says with the page it stopped at.

// a browser has no stdout: print is its console
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:gallery/gallery.dart';
import 'package:twk/twk.dart';
import 'package:twk_web/twk_web.dart';
import 'package:web/web.dart' as web;

/// What a page that failed shows.
const _errors = ['Unsupported operation', 'Exception', 'Error:'];

Future<void> main(List<String> args) async {
  // tool/web_check.dart's, which waits for the run a while longer
  final bound = Duration(milliseconds: int.parse(args.single));
  final routes = [
    for (final g in catalog)
      for (final p in g.pages) '#/${slug(g.title)}/${slug(p.title)}?t=2000',
    // the PNG, in half blocks
    '#/images/image?o=picture:logo.png&t=2000',
  ];
  final at = ValueNotifier(0);
  // what xterm.js would be opened in
  final element = JSObject() as web.HTMLElement;
  AppBinding? binding;
  // the stub runWebApp made, as it makes it
  JSObject stub() =>
      (globalContext['terminals']! as JSArray<JSObject>).toDart.last;
  int writes() => (stub()['writes']! as JSNumber).toDartInt;
  // marks[i]: how many writes the stub was given when routes[i] was first
  // built; a write after it, and up to the next page's mark, is the frame
  // of that page, however late the stub parses it
  final marks = <int>[];
  final ran = runWebApp(
    element,
    Builder(
      builder: (context) {
        binding = AppBinding.of(context);
        return ListenableBuilder(
          listenable: at,
          builder: (context, _) {
            if (marks.length == at.value) {
              marks.add(writes());
            }
            return galleryApp(route: GalleryRoute.parse(routes[at.value]));
          },
        );
      },
    ),
  );
  final xterm = stub();
  String text() => (xterm['text']! as JSString).toDart;
  final failed = <String>[];
  // a page a frame: what it wrote looked at once the stub has it, then the
  // next page
  final pages = xterm.callMethod<JSObject>(
    'onWritten'.toJS,
    ((JSString written, JSNumber number) {
      final wrote = written.toDart;
      final n = number.toDartInt;
      final page = marks.lastIndexWhere((mark) => mark < n);
      if (page < 0) {
        // what twk_web asks the terminal before the app is built
        return;
      }
      // App › ErrorWidget shows a failed build: that is its widget
      final own = routes[page].startsWith('#/app/errorwidget');
      for (final error in _errors) {
        if (wrote.contains(error) && !own) {
          failed.add('${routes[page]}: $error');
        }
      }
      if (page != at.value) {
        // a frame of a page already left
        return;
      }
      if (at.value + 1 < routes.length) {
        at.value++;
      } else if (wrote.contains('▀') || text().contains('12 rows')) {
        binding?.quit();
      }
    }).toJS,
  );
  try {
    await ran.timeout(
      bound,
      onTimeout: () => throw StateError(
        'the gallery stopped at ${routes[at.value]} '
        'after ${bound.inMilliseconds} ms',
      ),
    );
  } finally {
    pages.callMethod<JSAny?>('dispose'.toJS);
  }
  print('gallery: ${routes.length} routes shown, then quit');
  if (failed.isNotEmpty) {
    throw StateError('pages showed an error:\n${failed.join('\n')}');
  }
  print('pages: none showed an error');
  print('done');
}
