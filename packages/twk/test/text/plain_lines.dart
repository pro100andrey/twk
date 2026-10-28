/// An app run for a moment on plain output, a terminal that takes text
/// only, in the inline mode: what the tests of a widget's plain form read.
library;

import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show Terminal, TerminalLink, TerminalOptions;
import 'package:twk_test/twk_test.dart' show FakeClock;

/// The lines [app] leaves on plain output [width] columns wide, run for
/// 100 ms of its clock in the inline mode by the binding [onRun] is given.
///
/// It runs on a [FakeClock]: its frames are timers, which fire as the
/// clock is moved on, however long the machine takes to run them.
Future<List<String>> plainLines(
  Widget app, {
  void Function(AppBinding binding)? onRun,
  int width = 40,
}) async {
  final clock = FakeClock();
  final out = BytesBuilder();
  final terminal = await clock.elapseUntil(
    clock.run(
      () => Terminal.overLink(
        _Pipe(width, out),
        const TerminalOptions(plain: true, alternateScreen: false),
      ),
    ),
  );
  final binding = clock.run(
    () => AppBinding(terminal, maxFps: 1000, clock: clock.stopwatch),
  );
  onRun?.call(binding);
  final running = clock.run(() => binding.run(app));
  await clock.elapse(const Duration(milliseconds: 100));
  clock.run(binding.quit);
  await clock.elapseUntil(running);
  return const LineSplitter().convert(utf8.decode(out.toBytes()));
}

/// Output that takes plain text only, [columns] wide, into [out].
final class _Pipe implements TerminalLink {
  _Pipe(this.columns, this.out);

  final BytesBuilder out;

  @override
  final int columns;

  @override
  int get lines => 24;

  @override
  Map<String, String> get environment => const {};

  @override
  bool get windows => false;

  @override
  int? get eraseChar => null;

  @override
  void enterRaw() {}

  @override
  void restore() {}

  @override
  Stream<List<int>> get input => const Stream.empty();

  @override
  void add(List<int> bytes) => out.add(bytes);

  @override
  Future<void> flush() async {}

  @override
  Stream<void> get resizes => const Stream.empty();

  @override
  void restoreWith(List<int> bytes) {}

  @override
  Future<void> close() async {}
}
