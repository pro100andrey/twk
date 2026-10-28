/// What a program's output leaves turned on in the terminal it goes to.
library;

/// Follows a program's output for what it turns on in the terminal and
/// leaves on: DEC private modes (`CSI ? n h`, `CSI ? n l`), the kitty
/// keyboard flags pushed and popped and the cursor's shape; [off] turns
/// it back. A sequence split between two pieces is put together.
final class ModeTracker {
  static final _sequence = RegExp(
    r'\x1b\[(?:\?([0-9;]*)([hl])|([<>])([0-9]*)u|([0-9]*) q)',
  );

  // a sequence cut off at the end of a piece: ESC, or CSI up to its final
  static final _cut = RegExp(r'\x1b(?:\[[0-?]*[ -/]*)?$');

  // the modes as the output left them, on or off
  final _modes = <int, bool>{};
  var _kitty = 0;
  var _shaped = false;
  var _tail = '';

  /// Follows [text], the next piece of the output.
  void add(String text) {
    final s = _tail.isEmpty ? text : '$_tail$text';
    for (final m in _sequence.allMatches(s)) {
      if (m[2] case final set?) {
        for (final n in m[1]!.split(';')) {
          if (int.tryParse(n) case final mode?) {
            _modes[mode] = set == 'h';
          }
        }
      } else if (m[3] case final kitty?) {
        final n = int.tryParse(m[4]!) ?? 1;
        _kitty = kitty == '>' ? _kitty + 1 : (_kitty - n).clamp(0, _kitty);
      } else {
        _shaped = (int.tryParse(m[5]!) ?? 0) != 0;
      }
    }
    final cut = _cut.firstMatch(s.length > 64 ? s.substring(s.length - 64) : s);
    _tail = cut == null ? '' : cut[0]!;
  }

  /// What turns off everything the output left on, empty when it left
  /// nothing on: the modes it turned on turned off, the cursor shown and
  /// autowrap on again, its keyboard flags popped, the cursor's shape and
  /// the colours reset, the alternate screen left last.
  String get off {
    const cursor = 25;
    const autowrap = 7;
    const screens = {1049, 1047, 47};
    final on = [
      for (final MapEntry(key: mode, value: set) in _modes.entries)
        if (set &&
            mode != cursor &&
            mode != autowrap &&
            !screens.contains(mode))
          mode,
    ]..sort();
    final shown = _modes[cursor] == false;
    final wraps = _modes[autowrap] == false;
    final screen = screens.where((m) => _modes[m] ?? false).toList();
    if (on.isEmpty &&
        !shown &&
        !wraps &&
        screen.isEmpty &&
        _kitty == 0 &&
        !_shaped) {
      return '';
    }
    return [
      '\x1b[0m',
      for (final mode in on) '\x1b[?${mode}l',
      if (_kitty > 0) '\x1b[<${_kitty}u',
      if (_shaped) '\x1b[0 q',
      if (wraps) '\x1b[?7h',
      if (shown) '\x1b[?25h',
      for (final mode in screen) '\x1b[?${mode}l',
    ].join();
  }
}
