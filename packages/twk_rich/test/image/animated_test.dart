// AnimatedImage's timing: indexAt and nextChangeAfter agree.
import 'package:test/test.dart';
import 'package:twk_rich/image.dart';

void main() {
  test('a zero last delay: the change to it is announced, then none', () {
    final a = AnimatedImage([
      ImageFrame(Bitmap(1, 1), const Duration(milliseconds: 100)),
      ImageFrame(Bitmap(1, 1), Duration.zero),
    ], loops: 1);
    expect(a.indexAt(const Duration(milliseconds: 50)), 0);
    expect(a.indexAt(const Duration(milliseconds: 100)), 1);
    expect(
      a.nextChangeAfter(const Duration(milliseconds: 50)),
      const Duration(milliseconds: 100),
      reason: 'indexAt switches to the last frame there',
    );
    expect(a.nextChangeAfter(const Duration(milliseconds: 100)), isNull);
  });

  test('every change indexAt makes is announced by nextChangeAfter', () {
    for (final loops in [0, 1, 2]) {
      for (final delays in [
        [100, 0],
        [100, 200, 0],
        [0, 100],
        [100, 0, 100],
        [100, 100],
      ]) {
        final a = AnimatedImage([
          for (final ms in delays)
            ImageFrame(Bitmap(1, 1), Duration(milliseconds: ms)),
        ], loops: loops);
        var at = Duration.zero;
        for (var n = 0; n < 12; n++) {
          final next = a.nextChangeAfter(at);
          final here = a.indexAt(at);
          if (next == null) {
            // nothing follows: the index no longer changes
            for (final ms in [0, 1, 99, 100, 250, 1000, 5000]) {
              expect(
                a.indexAt(at + Duration(milliseconds: ms)),
                here,
                reason: 'loops $loops, delays $delays, at $at',
              );
            }
            break;
          }
          expect(next, greaterThan(at));
          expect(
            a.indexAt(next - const Duration(microseconds: 1)),
            here,
            reason: 'loops $loops, delays $delays, before $next',
          );
          at = next;
        }
      }
    }
  });
}
