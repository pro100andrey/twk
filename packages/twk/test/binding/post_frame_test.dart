// A post-frame callback that throws ends the app, as an error of the app's
// code does (doc/guides/running.md): run throws the error, the states
// disposed and no timer left, the callbacks after it in the frame not
// called. A frame callback's is in unmount_test.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  test('a post-frame callback that throws ends run with the error, the '
      'states disposed', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(Probe(key: key, (_) => const Label('app')));
    await run.settle();
    final calls = <String>[];
    AppBinding.of(key.currentContext!)
      ..addPostFrameCallback((_) {
        calls.add('a');
        throw StateError('a failed');
      })
      ..addPostFrameCallback((_) => calls.add('b'));
    final error = await run.ended().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect(error, isStateError);
    expect(calls, ['a']);
    expect(key.currentState, isNull, reason: 'the state is disposed');
    await run.settle();
    expect(run.clock.pendingTimers, 0);
  });
}
