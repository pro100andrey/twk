// Frame callbacks and post-frame callbacks that throw: the error is logged,
// the others of the frame are called, the frame ends as usual.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('a post-frame callback that throws is logged, the others of the '
      'frame are called and the next frame is asked for', (t) async {
    await t.pumpWidget(const Text('x'), size: (10, 1), maxFps: 100);
    final calls = <String>[];
    t.binding
      ..addPostFrameCallback((_) {
        calls.add('a');
        throw StateError('a failed');
      })
      ..addPostFrameCallback((_) => calls.add('b'));
    await t.pump(const Duration(milliseconds: 10));
    expect(calls, ['a', 'b']);
    final failed = t.logs.records.where(
      (r) => r.message == 'a post-frame callback failed',
    );
    expect(failed, hasLength(1));
    expect(failed.single.level, LogLevel.error);
    expect(failed.single.error, isA<StateError>());
    // a callback added after goes on being called
    t.binding.addPostFrameCallback((_) => calls.add('c'));
    await t.pump(const Duration(milliseconds: 10));
    expect(calls, ['a', 'b', 'c']);
  });

  testTwk('a frame callback that throws is logged and the others due are '
      'called', (t) async {
    await t.pumpWidget(const Text('x'), size: (10, 1), maxFps: 100);
    final calls = <String>[];
    t.binding
      ..scheduleFrameCallback((_) {
        calls.add('a');
        throw StateError('a failed');
      })
      ..scheduleFrameCallback((_) => calls.add('b'));
    await t.pump(const Duration(milliseconds: 10));
    expect(calls, ['a', 'b']);
    expect(
      t.logs.records.where((r) => r.message == 'a frame callback failed'),
      hasLength(1),
    );
    await t.pump(const Duration(seconds: 1));
    expect(calls, ['a', 'b'], reason: 'each is called once');
  });
}
