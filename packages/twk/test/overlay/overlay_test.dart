// The layer of an Overlay: its entries over its child in the order they
// were inserted, above and below one another; one entry rebuilt on its
// own; removed and inserted again; entries filling the overlay or placed;
// the mouse reaching through where an entry paints nothing; the fades in
// and out; no Overlay.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// An entry that shows [text] at column [left] of row [top], at once and
/// gone at once (no fades) unless [fades].
OverlayEntry at(int left, int top, String text, {bool fades = false}) => fades
    ? OverlayEntry(
        builder: (_) => Positioned(left: left, top: top, child: Text(text)),
      )
    : OverlayEntry(
        builder: (_) => Positioned(left: left, top: top, child: Text(text)),
        fadeIn: Duration.zero,
        fadeOut: Duration.zero,
      );

const ms = Duration(milliseconds: 1);

/// Counts its builds in [builds] under [name].
final class Counted extends StatelessWidget {
  const Counted(this.builds, this.name, {super.key});

  final Map<String, int> builds;
  final String name;

  @override
  Widget build(BuildContext context) {
    builds[name] = (builds[name] ?? 0) + 1;
    return Text(name);
  }
}

void main() {
  testTwk('entries show over the child, each over those inserted before '
      'it, or right above or below the one given', (t) async {
    final overlay = GlobalKey<OverlayState>();
    await t.pumpWidget(
      Overlay(key: overlay, child: const Text('abcdefgh')),
      size: (10, 2),
    );
    final state = overlay.currentState!;
    final a = at(0, 0, 'AAAA');
    final b = at(2, 0, 'BB');
    final c = at(3, 0, 'CCC');
    final d = at(1, 0, 'D');
    state.insert(a);
    await t.pump();
    expect(t.lines.first, 'AAAAefgh');
    state.insert(b);
    await t.pump();
    expect(t.lines.first, 'AABBefgh');
    state.insert(c, below: b);
    await t.pump();
    expect(t.lines.first, 'AABBCCgh');
    state.insert(d, above: a);
    await t.pump();
    expect(t.lines.first, 'ADBBCCgh');
    expect(state.entries, [a, d, c, b]);
    b.remove();
    await t.pump();
    expect(t.lines.first, 'ADACCCgh');
    expect(state.entries, [a, d, c]);
    expect([a.mounted, b.mounted], [true, false]);
    expect(
      () => state.insert(at(0, 0, 'E'), above: b),
      throwsA(isA<ArgumentError>()),
    );
  });

  testTwk('the overlay is as big as its child, laid out as without it; an '
      'entry that is not positioned fills it', (t) async {
    final overlay = GlobalKey<OverlayState>();
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: Overlay(
          key: overlay,
          child: const SizedBox(width: 6, height: 3, child: Text('child')),
        ),
      ),
      size: (10, 5),
    );
    overlay.currentState!.insert(
      OverlayEntry(
        builder: (_) => const Align(
          alignment: Alignment.bottomRight,
          child: Text('X'),
        ),
        fadeIn: Duration.zero,
      ),
    );
    await t.pump();
    expect(t.lines, ['child', '', '     X', '', '']);
  });

  testTwk('an entry marked builds again on its own: not the others, nor '
      'the child; nor does inserting one build those there', (t) async {
    final overlay = GlobalKey<OverlayState>();
    final builds = <String, int>{};
    await t.pumpWidget(
      Overlay(key: overlay, child: Counted(builds, 'child')),
      size: (10, 3),
    );
    final a = OverlayEntry(
      builder: (_) => Positioned(top: 1, child: Counted(builds, 'a')),
      fadeIn: Duration.zero,
    );
    final b = OverlayEntry(
      builder: (_) => Positioned(top: 2, child: Counted(builds, 'b')),
      fadeIn: Duration.zero,
    );
    overlay.currentState!.insert(a);
    await t.pump();
    overlay.currentState!.insert(b);
    await t.pump();
    expect(builds, {'child': 1, 'a': 1, 'b': 1});
    a.markNeedsBuild();
    await t.pump();
    expect(builds, {'child': 1, 'a': 2, 'b': 1});
    expect(t.lines, ['child', 'a', 'b']);
  });

  testTwk('a removed entry is gone from the next frame on, and may be '
      'inserted again, in the same frame too', (t) async {
    final overlay = GlobalKey<OverlayState>();
    await t.pumpWidget(
      Overlay(key: overlay, child: const Text('under')),
      size: (10, 2),
    );
    final state = overlay.currentState!;
    final a = at(0, 0, 'A');
    final b = at(1, 0, 'B');
    state
      ..insert(a)
      ..insert(b);
    await t.pump();
    expect(t.lines.first, 'ABder');
    a.remove();
    await t.pump();
    expect(t.lines.first, 'uBder');
    state.insert(a);
    await t.pump();
    expect(t.lines.first, 'ABder');
    expect(state.entries, [b, a]);
    a.remove();
    state.insert(a, below: b);
    await t.pump();
    expect(t.lines.first, 'ABder');
    expect(state.entries, [a, b]);
    a
      ..remove()
      ..remove();
    await t.pump();
    expect(t.lines.first, 'uBder');
  });

  testTwk('the mouse reaches what is under an entry where the entry is not '
      'hit', (t) async {
    final overlay = GlobalKey<OverlayState>();
    final log = <String>[];
    await t.pumpWidget(
      Overlay(
        key: overlay,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onDown: (e) => log.add('child ${e.x},${e.y}'),
          child: const SizedBox.expand(),
        ),
      ),
      size: (10, 5),
    );
    overlay.currentState!.insert(
      OverlayEntry(
        builder: (_) => Center(
          child: Listener(
            onDown: (e) => log.add('entry ${e.x},${e.y}'),
            child: const Text('[]'),
          ),
        ),
        fadeIn: Duration.zero,
      ),
    );
    await t.pump();
    await t.click(4, 2);
    await t.click(0, 0);
    expect(log, ['entry 0,0', 'child 0,0']);
  });

  testTwk('an entry fades in over 160 ms, easing out of what is under it, '
      'and once removed fades out over 120 ms before it is gone', (t) async {
    final overlay = GlobalKey<OverlayState>();
    const theme = ThemeData.dark;
    await t.pumpWidget(
      Theme(
        data: theme,
        child: Box(
          style: theme.background,
          child: Overlay(key: overlay, child: const SizedBox.expand()),
        ),
      ),
      size: (10, 2),
    );
    final surface = theme.surface.bg!;
    final background = theme.background.bg!;
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        child: Box(style: theme.surface, child: const Text('AB')),
      ),
    );
    expect([entry.fadeIn, entry.fadeOut], [ms * 160, ms * 120]);
    overlay.currentState!.insert(entry);
    await t.pump();
    // the first frame of the fade: none of it yet
    expect(t, styleAt(0, 0, hasBg(background)));
    await t.pump(ms * 60);
    expect(t, styleAt(0, 0, isNot(anyOf(hasBg(background), hasBg(surface)))));
    await t.pump(ms * 100);
    await t.pump();
    expect(t, styleAt(0, 0, hasBg(surface)));
    expect(t.lines.first, 'AB');

    entry.remove();
    expect(entry.mounted, isFalse);
    expect(overlay.currentState!.entries, isEmpty);
    await t.pump(ms * 60);
    expect(t, styleAt(0, 0, isNot(anyOf(hasBg(background), hasBg(surface)))));
    await t.pump(ms * 60);
    await t.pump();
    expect(t, styleAt(0, 0, hasBg(background)));
    expect(t.lines.first, '');
    await t.pumpUntilIdle();
  });

  testTwk('an entry inserted again while it fades out fades back in', (
    t,
  ) async {
    final overlay = GlobalKey<OverlayState>();
    await t.pumpWidget(
      Overlay(key: overlay, child: const Text('under')),
      size: (10, 2),
    );
    final state = overlay.currentState!;
    final a = at(0, 0, 'A', fades: true);
    state.insert(a);
    await t.pump(ms * 200);
    await t.pump();
    a.remove();
    await t.pump(ms * 40);
    state.insert(a);
    expect(state.entries, [a]);
    await t.pump(ms * 200);
    await t.pump();
    expect(t.lines.first, 'Ander');
    expect(a.mounted, isTrue);
  });

  testTwk('Overlay.of without an Overlay above says where to place one', (
    t,
  ) async {
    final key = GlobalKey();
    await t.pumpWidget(SizedBox(key: key, width: 1, height: 1));
    expect(Overlay.maybeOf(key.currentContext!), isNull);
    expect(
      () => Overlay.of(key.currentContext!),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'no Overlay above SizedBox: place an Overlay above it, as around '
              'the whole app: Overlay(child: …)',
        ),
      ),
    );
  });

  test('an entry says it is one, with a short hash of its own', () {
    final a = OverlayEntry(builder: (_) => const Text(''));
    final b = OverlayEntry(builder: (_) => const Text(''));
    expect('$a', matches(RegExp(r'^OverlayEntry#[0-9a-f]{5}$')));
    expect('$a', isNot('$b'));
  });
}
