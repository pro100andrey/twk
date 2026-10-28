/// Output that takes plain text only: stdout piped to another program or
/// a file, or a CI log ([runsInCi]). A `Terminal` there runs over a
/// [PlainLink] (`TerminalOptions.plain`, `TerminalInfo.plain`): it asks
/// nothing, sets no mode and writes no sequence of its own, and `TwkApp`
/// writes no frame as it comes, only the last one as text when it ends.
/// Nothing here needs dart:io.
library;

import 'link.dart';

// Examples can assume:
// import 'dart:io';

/// What `TWK_PLAIN` in [env] asks for: true for `1` or `true`, false for
/// `0` or `false`, null for anything else or nothing.
///
/// `Terminal.open` goes by it before anything else: true makes the output
/// plain text, false never, not even in CI. A program that writes to the
/// terminal beside twk asks the environment what the core asks it:
///
/// ```dart
/// final plain = plainAsked(Platform.environment) ??
///     runsInCi(Platform.environment);
/// ```
bool? plainAsked(Map<String, String> env) => switch (env['TWK_PLAIN']) {
  '1' || 'true' => true,
  '0' || 'false' => false,
  _ => null,
};

/// Whether [env] says the program runs in CI, as the is-in-ci and ci-info
/// packages tell: `CI`, `CONTINUOUS_INTEGRATION`, `BUILD_NUMBER` or `RUN_ID`
/// set to anything but an empty string, `0` or `false`, unless `CI` is
/// `0` or `false`.
///
/// Where `TWK_PLAIN` says nothing ([plainAsked]), `Terminal.open` writes
/// plain text there; and nobody is there to answer a question.
bool runsInCi(Map<String, String> env) {
  bool set(String name) => switch (env[name]) {
    null || '' || '0' || 'false' => false,
    _ => true,
  };
  final ci = env['CI'];
  if (ci == '0' || ci == 'false') {
    return false;
  }
  return set('CI') ||
      set('CONTINUOUS_INTEGRATION') ||
      set('BUILD_NUMBER') ||
      set('RUN_ID');
}

/// Output that takes plain text only, as a [TerminalLink]: [add] and
/// [flush] are its sink's (`stdout.add`, `stdout.flush`). Its size is
/// fixed, `COLUMNS` x `LINES` from [environment] where each is a positive
/// number, else 80 x 24; it has no console modes and no resizes, and no
/// input but [input] (stdin where it is a terminal, read as the terminal
/// hands it on, a line at a time).
final class PlainLink implements TerminalLink {
  /// Plain output to the sink [add] writes to and [flush] flushes, sized
  /// by [environment], reading [input] (none by default).
  PlainLink(
    this.environment, {
    required this._add,
    required this._flush,
    Stream<List<int>>? input,
  }) : input = input ?? const Stream.empty(),
       columns = _size(environment['COLUMNS'], 80),
       lines = _size(environment['LINES'], 24);

  final void Function(List<int> bytes) _add;
  final Future<void> Function() _flush;

  static int _size(String? value, int otherwise) {
    final n = int.tryParse(value ?? '');
    return n != null && n > 0 ? n : otherwise;
  }

  @override
  final Map<String, String> environment;

  @override
  bool get windows => false;

  @override
  final int columns;

  @override
  final int lines;

  @override
  int? get eraseChar => null;

  @override
  void enterRaw() {}

  @override
  void restore() {}

  @override
  final Stream<List<int>> input;

  @override
  void add(List<int> bytes) => _add(bytes);

  @override
  Future<void> flush() => _flush();

  @override
  Stream<void> get resizes => const Stream.empty();

  @override
  void restoreWith(List<int> bytes) {}

  @override
  Future<void> close() async {}
}
