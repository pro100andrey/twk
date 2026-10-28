// WindowBackend: a backend that wraps a terminal and passes the window's
// title and the desktop notifications on keeps both, as the terminal it
// wraps would; twk asks the backend for the interface, not for one of the
// core's classes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show TerminalInfo, WindowBackend, titleSequence;
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'harness.dart' show FrameLoop;

/// A title and a notification as n is pressed.
final class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => WindowTitle(
    title: 'Editor',
    child: KeyBindings({
      'n': () => AppBinding.of(context).notify('Build', 'done'),
    }, child: const Text('n notifies')),
  );
}

/// [terminal], wrapped, as a backend that adds to a terminal's input
/// would be, passing the window on.
final class _Wrapped implements WindowBackend {
  _Wrapped(this.terminal);

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

  @override
  void setTitle(String title) => terminal.setTitle(title);

  @override
  void notify(String title, String body) => terminal.notify(title, body);
}

void main() {
  test('a terminal wrapped by a backend that passes the window on keeps '
      'its title and its notifications', () async {
    final clock = FakeClock();
    final term = clock.run(
      () => HeadlessTerminal(
        width: 20,
        height: 2,
        notifications: NotificationProtocol.osc777,
      ),
    );
    final binding = clock.run(
      () => AppBinding(_Wrapped(term), maxFps: 1000, clock: clock.stopwatch),
    );
    final done = clock.run(() => binding.run(const _App()));
    await clock.settle();
    term.type('n');
    await clock.settle();
    binding.quit();
    await clock.elapseUntil(done);
    final written = utf8.decode([for (final f in term.frames) ...f]);
    expect(written, contains(titleSequence('Editor')));
    expect(written, contains('\x1b]777;notify;Build;done\x1b\\'));
  });
}
