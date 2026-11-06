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
