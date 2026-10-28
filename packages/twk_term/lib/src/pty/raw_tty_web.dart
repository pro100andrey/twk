/// [RawTty] on the web, which has no terminal on stdin: the same members
/// as on the VM (`raw_tty.dart`), [RawTty.enter] answering null, so that
/// what uses it compiles for the browser too.
library;

/// The terminal on stdin in raw mode; on the web there is none, and
/// [RawTty.enter] answers null.
///
/// ```dart
/// final tty = RawTty.enter(); // null in a browser
/// tty?.restore();
/// ```
final class RawTty {
  RawTty._();

  /// Null: a browser has no terminal on stdin.
  static RawTty? enter() => null;

  /// Whether the terminal is as [enter] left it; there is none on the web.
  bool get isRaw => true;

  /// Puts the terminal in raw mode again; nothing on the web.
  void reenter() {}

  /// Puts back the modes [enter] found; nothing on the web.
  void restore({bool discardInput = false}) {}
}
