// Opens the process's terminal twice at once, a terminal over a link of its
// own between the two, and writes to the file its argument names what became
// of each. double_open_test.dart runs it in a pseudo-terminal.
import 'dart:io';

import 'package:twk_core/twk_core.dart';

/// A link to nothing, that is no terminal of the process's.
final class _NoLink implements TerminalLink {
  @override
  Stream<List<int>> get input => const Stream.empty();
  @override
  int get columns => 80;
  @override
  int get lines => 24;
  @override
  bool get windows => false;
  @override
  Map<String, String> get environment => const {};
  @override
  int? get eraseChar => 0x7F;
  @override
  Stream<void> get resizes => const Stream.empty();
  @override
  void enterRaw() {}
  @override
  void restore() {}
  @override
  void restoreWith(List<int> bytes) {}
  @override
  void add(List<int> bytes) {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

Future<Object> _opened(Future<Terminal> open) =>
    open.then<Object>((t) => t, onError: (Object e) => e);

Future<void> main(List<String> args) async {
  final results = await Future.wait([
    _opened(Terminal.open()),
    // what is no terminal of the process's says nothing of the first
    _opened(Terminal.overLink(_NoLink(), const TerminalOptions(plain: true))),
    _opened(Terminal.open()),
  ]);
  final said = [
    for (final r in results)
      if (r is Terminal) 'opened' else '${r.runtimeType}',
  ];
  for (final t in results.whereType<Terminal>()) {
    await t.close();
  }
  File(args.single).writeAsStringSync(said.join(' '));
  exit(0);
}
