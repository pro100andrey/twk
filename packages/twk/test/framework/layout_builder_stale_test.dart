// What is dirty below a LayoutBuilder that has a build to do waits for it,
// and so never builds with the widget above it from before; below one with
// none it rebuilds before the layout as anything does; one that is not laid
// out asks for no frames.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  group('what is dirty below a LayoutBuilder that will build', () {
    testTwk('waits for that build, so it never sees the widget above it '
        'from before', (t) async {
      final rows = ['a', 'b', 'c'];
      final tick = ValueNotifier(0);
      addTearDown(tick.dispose);
      final seen = <int>[];
      final host = GlobalKey<_HostState>();
      await t.pumpWidget(
        _Host(
          key: host,
          build: (context) {
            final count = rows.length;
            return LayoutBuilder(
              builder: (_, _) => _Reader(
                count: count,
                tick: tick,
                read: (i) => rows[i],
                seen: seen,
              ),
            );
          },
        ),
      );
      expect(seen, [3]);
      seen.clear();
      // the list shrinks and the row is told in the same frame, as a filter
      // moving a cursor does
      rows.removeLast();
      host.currentState!.again();
      tick.value++;
      await t.pump();
      expect(seen, [2], reason: 'built once, with the new widget');
      expect(t.logs.records, isEmpty);
    });

    testTwk('rebuilds as ever where the LayoutBuilder has no build to do, '
        'before the layout', (t) async {
      final tick = ValueNotifier(0);
      addTearDown(tick.dispose);
      final seen = <int>[];
      await t.pumpWidget(
        LayoutBuilder(
          builder: (_, _) => _Reader(
            count: 1,
            tick: tick,
            read: (_) => 'a',
            seen: seen,
          ),
        ),
      );
      seen.clear();
      tick.value++;
      await t.pump();
      expect(seen, [1]);
    });

    testTwk('one in a LayoutBuilder that is not laid out asks for no frames', (
      t,
    ) async {
      final tick = ValueNotifier(0);
      addTearDown(tick.dispose);
      final seen = <int>[];
      final host = GlobalKey<_HostState>();
      var shown = true;
      await t.pumpWidget(
        _Host(
          key: host,
          build: (_) => Offstage(
            offstage: !shown,
            child: LayoutBuilder(
              builder: (_, _) => _Reader(
                count: 1,
                tick: tick,
                read: (_) => 'a',
                seen: seen,
              ),
            ),
          ),
        ),
      );
      shown = false;
      host.currentState!.again();
      await t.pump();
      seen.clear();
      host.currentState!.again();
      tick.value++;
      final before = t.binding.framesBegun;
      await t.pump();
      await t.pump();
      await t.pump();
      expect(t.binding.framesBegun - before, lessThanOrEqualTo(1));
      shown = true;
      host.currentState!.again();
      await t.pump();
      expect(seen, isNotEmpty, reason: 'it builds once it is laid out');
    });
  });
}

/// Builds [build] again on [_HostState.again].
final class _Host extends StatefulWidget {
  const _Host({required this.build, super.key});

  final Widget Function(BuildContext context) build;

  @override
  State<_Host> createState() => _HostState();
}

final class _HostState extends State<_Host> {
  void again() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.build(context);
}

/// Reads the last of [count] rows through [read] each time it builds, as a
/// row of a list does, and is made dirty by [tick] on its own.
final class _Reader extends StatefulWidget {
  const _Reader({
    required this.count,
    required this.tick,
    required this.read,
    required this.seen,
  });

  final int count;
  final ValueNotifier<int> tick;
  final String Function(int i) read;
  final List<int> seen;

  @override
  State<_Reader> createState() => _ReaderState();
}

final class _ReaderState extends State<_Reader> {
  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_changed);
  }

  @override
  void dispose() {
    widget.tick.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    widget.seen.add(widget.count);
    return Text(widget.read(widget.count - 1));
  }
}
