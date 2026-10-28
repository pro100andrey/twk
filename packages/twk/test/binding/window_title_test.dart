// WindowTitle: the title of the terminal's window or tab as the one
// mounted last says, set again when its title changes or it goes, through
// Terminal.setTitle, which gives the user's title back when the app ends;
// on a HeadlessTerminal, the sequence that sets it written to its frames.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show
        Terminal,
        TerminalLink,
        popTitleSequence,
        pushTitleSequence,
        titleSequence;
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'harness.dart' show FrameLoop;

/// What a test shows: [title] around a line of text, which
/// [_ShownState.show] changes.
final class _Shown extends StatefulWidget {
  const _Shown(this.title, {super.key});

  final Widget Function(Widget child) title;

  @override
  State<_Shown> createState() => _ShownState();
}

final class _ShownState extends State<_Shown> {
  late Widget Function(Widget child) _title = widget.title;

  void show(Widget Function(Widget child) title) =>
      setState(() => _title = title);

  @override
  Widget build(BuildContext context) => _title(const Text('working'));
}

/// An app showing a title, run full screen on a terminal in memory, on
/// [clock].
final class _Run {
  _Run(Widget Function(Widget child) title) {
    clock.run(() {
      term = HeadlessTerminal(width: 20, height: 2);
      binding = AppBinding(term, maxFps: 1000, clock: clock.stopwatch);
      done = binding.run(_Shown(title, key: key));
    });
  }

  /// The time of the app.
  final clock = FakeClock();
  late final HeadlessTerminal term;
  late final AppBinding binding;
  late final Future<void> done;
  final key = GlobalKey<_ShownState>();
  var _read = 0;

  /// The status of the app.
  TerminalStatus get status => TerminalStatus.of(key.currentContext!)!;

  /// The titles the app set since the last call.
  List<String> titles() {
    final s = utf8.decode([for (final f in term.frames.skip(_read)) ...f]);
    _read = term.frames.length;
    return [
      for (final m in RegExp('\x1b]2;([^\x1b]*)\x1b\\\\').allMatches(s)) m[1]!,
    ];
  }

  /// Lets the frame loop run for 30 ms of the app's clock.
  Future<void> settle() => clock.settle();

  /// Shows [title] from the next frame on.
  Future<void> show(Widget Function(Widget child) title) async {
    key.currentState!.show(title);
    await settle();
  }

  /// Ends the app and runs it until it has ended.
  Future<void> quit() async {
    binding.quit();
    await clock.elapseUntil(done);
  }
}

/// A terminal in memory a [Terminal] runs over, as a browser's or an SSH
/// channel would be: it answers the probe, and keeps what is written.
final class _Link implements TerminalLink {
  _Link() {
    // the answer to the probe's DA1 waits in the input
    _input.add(utf8.encode('\x1b[?62;22c'));
  }

  final _input = StreamController<List<int>>();
  final _bytes = <int>[];

  /// Everything written to the terminal.
  String get written => utf8.decode(_bytes);

  @override
  Map<String, String> get environment => const {'TERM': 'xterm-256color'};

  @override
  bool get windows => false;

  @override
  int get columns => 20;

  @override
  int get lines => 2;

  @override
  int? get eraseChar => 0x7F;

  @override
  void enterRaw() {}

  @override
  void restore() {}

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void add(List<int> bytes) => _bytes.addAll(bytes);

  @override
  Future<void> flush() async {}

  @override
  Stream<void> get resizes => const Stream.empty();

  @override
  void restoreWith(List<int> bytes) {}

  @override
  Future<void> close() => _input.close();
}

void main() {
  test('sets the title as the app starts, again when it changes, not when '
      'it is built the same', () async {
    final run = _Run((child) => WindowTitle(title: 'build', child: child));
    await run.settle();
    expect(run.titles(), ['build']);
    expect(run.status.title, 'build');

    await run.show((child) => WindowTitle(title: 'test', child: child));
    expect(run.titles(), ['test']);
    expect(run.status.title, 'test');

    await run.show((child) => WindowTitle(title: 'test', child: child));
    expect(run.titles(), isEmpty);
    await run.quit();
  });

  test('the one mounted last sets it, the innermost of nested ones; once '
      'it goes, the one before it sets its own again', () async {
    final run = _Run((child) => WindowTitle(title: 'app', child: child));
    await run.settle();
    expect(run.titles(), ['app']);

    await run.show(
      (child) => WindowTitle(
        title: 'app',
        child: WindowTitle(title: 'page', child: child),
      ),
    );
    expect(run.titles(), ['page']);

    // the outer one changes under the inner one, which stays shown
    await run.show(
      (child) => WindowTitle(
        title: 'app 2',
        child: WindowTitle(title: 'page', child: child),
      ),
    );
    expect(run.titles(), isEmpty);
    expect(run.status.title, 'page');

    await run.show((child) => WindowTitle(title: 'app 2', child: child));
    expect(run.titles(), ['app 2']);

    // none: the title stays as the last one set it
    await run.show((child) => child);
    expect(run.titles(), isEmpty);
    expect(run.status.title, 'app 2');
    await run.quit();
  });

  test("on a Terminal, the user's title is saved before the first and "
      'given back when the app ends', () async {
    final clock = FakeClock();
    final link = clock.run(_Link.new);
    final terminal = await clock.elapseUntil(
      clock.run(
        () => Terminal.overLink(link, const TerminalOptions(mouse: false)),
      ),
    );
    final binding = clock.run(
      () => AppBinding(terminal, maxFps: 1000, clock: clock.stopwatch),
    );
    final done = clock.run(
      () => binding.run(
        const WindowTitle(title: 'twk · chat', child: Text('working')),
      ),
    );
    await clock.settle();
    final written = link.written;
    expect(
      written,
      contains('$pushTitleSequence${titleSequence('twk · chat')}'),
    );
    expect(pushTitleSequence.allMatches(written), hasLength(1));
    expect(written, isNot(contains(popTitleSequence)));

    binding.quit();
    await clock.elapseUntil(done);
    expect(link.written, endsWith(popTitleSequence));
  });
}
