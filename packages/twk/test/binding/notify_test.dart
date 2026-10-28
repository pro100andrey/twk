// AppBinding.notify: a desktop notification written in the protocol the
// terminal shows them in, on a HeadlessTerminal and on a Terminal, through
// tmux, nothing where none is known to show or on a backend that is no
// WindowBackend.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show Terminal, TerminalInfo, TerminalLink;
import 'package:twk_test/twk_test.dart';

import 'harness.dart' show FrameLoop;

/// Notifies that the build is done as n is pressed.
final class _Build extends StatelessWidget {
  const _Build();

  @override
  Widget build(BuildContext context) => KeyBindings({
    'n': () => AppBinding.of(context).notify('Build', 'done; 3 tests'),
  }, child: const Text('n notifies'));
}

void main() {
  testTwk('in the protocol the terminal shows notifications in, between '
      'frames, the screen left as it was', (t) async {
    await t.pumpWidget(
      const _Build(),
      size: (20, 2),
      notifications: NotificationProtocol.osc777,
    );
    await t.press('n');
    await t.pump();
    expect(t.written(), endsWith('\x1b]777;notify;Build;done, 3 tests\x1b\\'));
    expect(t, matchesScreen('n notifies\n'));
  });

  test('on a Terminal, in the protocol its TERM shows them in', () async {
    final clock = FakeClock();
    final link = clock.run(() => _Link({'TERM': 'xterm-ghostty'}));
    final terminal = await clock.elapseUntil(
      clock.run(
        () => Terminal.overLink(link, const TerminalOptions(mouse: false)),
      ),
    );
    final binding = clock.run(
      () => AppBinding(terminal, maxFps: 1000, clock: clock.stopwatch),
    );
    final done = clock.run(() => binding.run(const _Build()));
    await clock.settle();
    link.type('n');
    await clock.settle();
    binding.quit();
    await clock.elapseUntil(done);
    expect(link.written, contains('\x1b]777;notify;Build;done, 3 tests\x1b\\'));
  });

  testTwk('inside tmux, wrapped for it, each under an id of its own', (
    t,
  ) async {
    await t.pumpWidget(
      const _Build(),
      size: (20, 2),
      notifications: NotificationProtocol.osc99,
      multiplexer: Multiplexer.tmux,
    );
    await t.press('n');
    await t.press('n');
    await t.pump();
    final s = t.written();
    for (final id in ['1', '2']) {
      expect(
        s,
        contains(
          '\x1bPtmux;\x1b\x1b]99;i=$id:d=0;Build\x1b\x1b\\'
          '\x1b\x1b]99;i=$id:p=body;done; 3 tests\x1b\x1b\\\x1b\\',
        ),
      );
    }
  });

  testTwk('nothing where the terminal is not known to show them', (t) async {
    await t.pumpWidget(const _Build(), size: (20, 2));
    await t.press('n');
    await t.pump();
    expect(t.written(), isNot(contains('Build')));
  });

  test('nothing on a backend that is no WindowBackend, though the terminal '
      'it wraps shows them', () async {
    final clock = FakeClock();
    final term = clock.run(
      () => HeadlessTerminal(
        width: 20,
        height: 2,
        notifications: NotificationProtocol.osc777,
      ),
    );
    final binding = clock.run(
      () => AppBinding(_Bare(term), maxFps: 1000, clock: clock.stopwatch),
    );
    final done = clock.run(() => binding.run(const _Build()));
    await clock.settle();
    term.type('n');
    await clock.settle();
    binding.quit();
    await clock.elapseUntil(done);
    expect(
      utf8.decode([for (final f in term.frames) ...f]),
      allOf(contains('n notifies'), isNot(contains('Build'))),
    );
  });
}

/// [terminal], wrapped by a backend that passes on what any backend does
/// and nothing more.
final class _Bare implements TerminalBackend {
  _Bare(this.terminal);

  final HeadlessTerminal terminal;

  @override
  Stream<InputEvent> get events => terminal.events;

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
}

/// A terminal at the far end of a link, of [environment], 20 × 2, that
/// answers the probe as a VT220 does.
final class _Link implements TerminalLink {
  _Link(this.environment) {
    _input.add(utf8.encode('\x1b[?62;22c'));
  }

  final _input = StreamController<List<int>>();
  final _bytes = <int>[];

  /// Everything written to the terminal.
  String get written => utf8.decode(_bytes);

  /// Types [text] at the terminal.
  void type(String text) => _input.add(utf8.encode(text));

  @override
  final Map<String, String> environment;

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
