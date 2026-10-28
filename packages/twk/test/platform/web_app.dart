// A packages/twk app with nothing of a process: runApp on a Terminal over a
// link of its own, as a browser's would be, showing a FilePicker, which
// finds no file system there; then the log console saved, which fails.
// What tool/web_check.dart compiles for the web and runs, handing it its
// bound (main's one argument, in milliseconds): it prints a line per part,
// then `done` unless the bound passed first, which it says with the part it
// stopped at.

// a browser has no stdout: print is its console
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show Terminal, TerminalLink;

/// What the picker's list says on the web.
const _cannot = 'cannot list: no file system on the web';

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
  AppBinding? binding;
  late final _Link link;
  link = _Link(() {
    if (link.text.contains(_cannot)) {
      Timer.run(() => binding?.quit());
    }
  });
  // the answer to the probe's DA1 waits in the input
  link._input.add(utf8.encode('\x1b[?62;22c'));
  final terminal = await by(
    Terminal.overLink(link, const TerminalOptions(mouse: false)),
    () => 'the terminal over the link was not open',
  );
  await by(
    runApp(_App((b) => binding = b), terminal: terminal),
    () => 'the picker showed: ${link.text}',
  );
  print('picker: $_cannot');
  print('link: ${link.closed ? 'closed' : 'open'}');

  final sink = LogSink()..add(LogRecord(DateTime(2026), LogLevel.info, 'a'));
  final saved = await by(
    ConsoleController(
      sink,
    ).save('console.log').then((_) => 'saved', onError: (Object e) => '$e'),
    () => 'the console was not saved, nor did saving it fail',
  );
  print('console: $saved');
  print('done');
}

/// A [FilePicker] in an app, which tells [bound] its binding.
final class _App extends StatelessWidget {
  const _App(this.bound);

  final void Function(AppBinding binding) bound;

  @override
  Widget build(BuildContext context) {
    bound(AppBinding.of(context));
    return Theme(
      data: ThemeData.dark,
      child: Overlay(
        child: FilePicker(onPicked: (_) {}, autofocus: true),
      ),
    );
  }
}

/// A CSI, OSC or other escape sequence.
final _sequence = RegExp(
  r'\x1b(\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(\x07|\x1b\\)|[()][0-9A-Za-z]|.)',
);

/// A terminal in memory: what a browser's terminal is to a `Terminal`.
/// Calls [written] after each write; [text] is what was written, the
/// escape sequences left out.
final class _Link implements TerminalLink {
  _Link(this.written);

  final void Function() written;

  @override
  Map<String, String> get environment => const {'TERM': 'xterm-256color'};

  @override
  bool get windows => false;

  @override
  int get columns => 60;

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

  final _bytes = <int>[];

  String get text =>
      utf8.decode(_bytes, allowMalformed: true).replaceAll(_sequence, '');

  @override
  void add(List<int> bytes) {
    _bytes.addAll(bytes);
    written();
  }

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
