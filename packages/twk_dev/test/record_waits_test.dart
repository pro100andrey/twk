// The waits of `twk record --replay` leave no timer behind: one still
// pending keeps the process alive after the recording is over.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_dev/src/record.dart' show sleepUnless;

void main() {
  test('a wait that its other side ended cancels its timer', () async {
    final live = <Timer>{};
    final done = Completer<void>();
    await runZoned(
      () async {
        final wait = sleepUnless(const Duration(seconds: 20), done.future);
        done.complete();
        await wait;
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          late final Timer timer;
          timer = parent.createTimer(zone, duration, () {
            live.remove(timer);
            callback();
          });
          live.add(timer);
          return _Tracked(timer, live);
        },
      ),
    );
    expect(live.where((t) => t.isActive), isEmpty);
    // not left to the test: nothing of it may outlive it either
    for (final t in live) {
      t.cancel();
    }
  });

  test('a wait that ran out is over', () async {
    await sleepUnless(Duration.zero, Completer<void>().future);
  });
}

final class _Tracked implements Timer {
  _Tracked(this._timer, this._live);
  final Timer _timer;
  final Set<Timer> _live;

  @override
  void cancel() {
    _live.remove(_timer);
    _timer.cancel();
  }

  @override
  bool get isActive => _timer.isActive;

  @override
  int get tick => _timer.tick;
}
