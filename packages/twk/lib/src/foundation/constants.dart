/// Whether the program runs in release or debug mode, known when it is
/// compiled.
library;

/// Whether the program was compiled for release (`dart compile exe`, or
/// run with `-Ddart.vm.product=true`).
///
/// A constant, so what it guards is dropped from a release build:
///
/// ```dart
/// kReleaseMode ? const SizedBox() : const Text('not for release')
/// ```
// The compiler's own constants, which Flutter's kReleaseMode reads too.
// ignore: do_not_use_environment
const kReleaseMode = bool.fromEnvironment('dart.vm.product');

/// Whether the program runs in debug mode: neither release nor profile, as
/// it does under `dart run` and `dart test`.
///
/// A constant, so what it guards is dropped from a release build:
///
/// ```dart
/// kDebugMode ? const Text('debug build') : const SizedBox()
/// ```
const bool kDebugMode =
    // The compiler's constant, as kReleaseMode's.
    // ignore: do_not_use_environment
    !kReleaseMode && !bool.fromEnvironment('dart.vm.profile');

/// Whether the program runs with asserts on (`dart run --enable-asserts`,
/// which `twk run` and `dart test` do; plain `dart run` does not).
///
/// [kDebugMode] does not imply it: a plain `dart run` is in debug mode with
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
