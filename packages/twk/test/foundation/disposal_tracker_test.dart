import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  test('a tracker reports what was made after start and not disposed, with '
      'the stack that made it, in the order they were made', () {
    final before = ValueNotifier(0);
    final tracker = DisposalTracker.start();
    final first = ValueNotifier(1);
    final second = ScrollController();
    FocusNode().dispose();
    final leaked = tracker.stop();
    expect(leaked.map((l) => l.object), [first, second]);
    expect(leaked.first.createdAt.toString(), contains('main'));
    expect(leaked.first.toString(), startsWith('ValueNotifier<int> created'));
    before.dispose();
    first.dispose();
    second.dispose();
  });

  test('a notifier made before start, and one disposed, are not reported', () {
    final before = ValueNotifier(0);
    final tracker = DisposalTracker.start();
    TextEditingController().dispose();
    before.dispose();
    expect(tracker.stop(), isEmpty);
  });

  test('a stopped tracker tracks nothing more; with none, nothing is kept', () {
    expect(DisposalTracker.isTracking, isFalse);
    final tracker = DisposalTracker.start();
    expect(DisposalTracker.isTracking, isTrue);
    tracker.stop();
    expect(DisposalTracker.isTracking, isFalse);
    ValueNotifier(0).dispose();
    expect(tracker.stop(), isEmpty);
  });

  test('forget drops an object an app owns for its whole life', () {
    final tracker = DisposalTracker.start();
    final root = ValueNotifier(0);
    DisposalTracker.forget(root);
    expect(tracker.stop(), isEmpty);
  });
}
