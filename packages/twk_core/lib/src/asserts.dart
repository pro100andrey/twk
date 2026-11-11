/// Whether asserts are on.
library;

/// Whether the program runs with asserts on (`dart run --enable-asserts`,
/// which `twk run` and `dart test` do; plain `dart run` does not).
///
/// Debug mode does not imply it: a plain `dart run` is in debug mode with
/// every `assert`, the framework's checks of the layout contract and the
/// overflow warnings among them, skipped. Read when the app starts, not a
/// constant, as asserts are on or off for the whole program:
///
/// ```dart
/// debugAssertsEnabled ? 'checked' : 'unchecked'
/// ```
bool get debugAssertsEnabled {
  var on = false;
  assert(on = true, 'an assert that runs only where asserts are on');
  return on;
}
