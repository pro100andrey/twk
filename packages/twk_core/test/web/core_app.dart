// A core app with nothing of a process: a TwkApp on a HeadlessTerminal,
// then a Terminal opened over a link of its own, as a browser's would be.
// What tool/web_check.dart compiles for the web and runs, handing it its
// bound (main's one argument, in milliseconds): it prints a line per part,
// then `done` unless the bound passed first, which it says with the part it
// stopped at.

// a browser has no stdout: print is its console
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:twk_core/twk_core.dart';

Future<void> main(List<String> args) async {
  // tool/web_check.dart's, which waits for the run a while longer
  final bound = Duration(milliseconds: int.parse(args.single));
  final watch = Stopwatch()..start();
  // [part], unless the bound passes first: then a StateError saying where
  Future<T> by<T>(Future<T> part, String Function() stopped) => part.timeout(
    bound - watch.elapsed,
    onTimeout: () =>
        throw StateError('after ${bound.inMilliseconds} ms ${stopped()}'),
  );
  final headless = HeadlessTerminal(width: 20, height: 2);
  String painted() => headless.frames.map(utf8.decode).join();
  final app = TwkApp(headless);
  await by(
    app.run(
      RenderParagraph([('hello web', const Pen())]),
      (_) {},
      afterPresent: app.quit,
    ),
    () =>
        'the headless app had not ended, having written: '
        '${painted().replaceAll(_sequence, '')}',
  );
  print('headless: ${painted().contains('hello web') ? 'painted' : 'blank'}');

  // the answer to the probe's DA1 waits in the input
  final link = _Link().._input.add(utf8.encode('\x1b[?62;22c'));
  final terminal = await by(
    Terminal.overLink(link),
    () => 'the terminal over the link was not open',
  );
  print(
    'link: ${terminal.width}x${terminal.height} '
    'answered=${terminal.info.answeredQueries}',
  );
  await by(terminal.close(), () => 'the terminal was not closed');
  print('link: ${link.closed ? 'closed' : 'open'}');
  print('done');
}

/// A CSI, OSC or other escape sequence.
final _sequence = RegExp(
  r'\x1b(\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(\x07|\x1b\\)|[()][0-9A-Za-z]|.)',
);

/// A terminal in memory: what a browser's terminal is to a `Terminal`.
final class _Link implements TerminalLink {
  @override
  Map<String, String> get environment => const {'TERM': 'xterm-256color'};

  @override
  bool get windows => false;

  @override
  int get columns => 40;

  @override
  int get lines => 10;

  @override
  int? get eraseChar => 0x7F;

  @override
  void enterRaw() {}

  @override
  void restore() {}

  final _input = StreamController<List<int>>();

  @override
  Stream<List<int>> get input => _input.stream;

  final written = <int>[];

  @override
  void add(List<int> bytes) => written.addAll(bytes);

  @override
  Future<void> flush() async {}

  @override
  Stream<void> get resizes => const Stream.empty();

  @override
  void restoreWith(List<int> bytes) {}

  var closed = false;

  @override
  Future<void> close() async {
    closed = true;
    await _input.close();
  }
}
