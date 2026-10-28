// How a test runs a Terminal over an in-memory link on a clock of its
// own, for the tests of such terminals.

import 'package:test/test.dart' show addTearDown;
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

/// Code run on a [FakeClock], for a Terminal over an in-memory link: its
/// probe, its escape and paste timeouts and its refreshes are timers that
/// fire as the test moves the clock, however long the machine takes.
extension RunOnClock on FakeClock {
  /// What [body], run in the clock's zone, completes with, once the clock
  /// has moved on until it did ([FakeClock.elapseUntil], [within] at
  /// most).
  Future<T> runUntil<T>(
    Future<T> Function() body, {
    Duration within = const Duration(seconds: 1),
  }) => elapseUntil(run(body), within: within);

  /// A Terminal over [link] opened in the clock's zone, so that its timers
  /// are the clock's: with the probe's answers typed before, it opens
  /// without the clock moving; unanswered, once the clock reached the
  /// probe's timeout. Closed in the zone when the test ends, if it has not
  /// been.
  Future<Terminal> open(
    TerminalLink link, [
    TerminalOptions options = const TerminalOptions(),
  ]) async {
    final term = await runUntil(
      () => Terminal.overLink(link, options),
      within: options.probeTimeout * 2,
    );
    addTearDown(() => runUntil(term.close));
    return term;
  }
}
