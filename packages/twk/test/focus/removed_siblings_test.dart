// The focus moved off a node removed in the same frame as its previous
// sibling, and a controller handed from one widget to another while the
// old one is still mounted.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget _field(String label) => Focus(
  key: ValueKey(label),
  debugLabel: label,
  child: Text(label),
);

final class _Rows extends StatefulWidget {
  const _Rows(this.labels, {super.key});

  final List<String> labels;

  @override
  State<_Rows> createState() => _RowsState();
}

final class _RowsState extends State<_Rows> {
  var labels = <String>[];

  @override
  void initState() {
    super.initState();
    labels = widget.labels;
  }

  void show(List<String> to) => setState(() => labels = to);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [for (final l in labels) _field(l)],
  );
}

final class _View extends StatefulWidget {
  const _View(this.hosts, {super.key});

  final ControllerHost<State> hosts;

  @override
  State<_View> createState() => _ViewState();
}

final class _ViewState extends State<_View> {
  @override
  void initState() {
    super.initState();
    widget.hosts.attach(this);
  }

  @override
  void dispose() {
    widget.hosts.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('view');
}

Widget _views(ControllerHost<State> hosts, List<String> keys) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [for (final k in keys) _View(hosts, key: ValueKey(k))],
);

void main() {
  testTwk('the focus moves off a node removed in the same frame as its '
      'previous sibling', (t) async {
    final rows = GlobalKey<_RowsState>();
    await t.pumpWidget(
      _Rows(const ['a', 'b', 'c', 'd'], key: rows),
      size: (10, 4),
    );
    for (var i = 0; i < 3; i++) {
      await t.press('tab');
      await t.pump();
    }
    expect(t.binding.focusManager.primaryFocus?.debugLabel, 'c');
    rows.currentState!.show(const ['a', 'd']);
    await t.pump();
    expect(t.binding.focusManager.primaryFocus?.debugLabel, 'd');
  });

  testTwk('an old host kept mounted for a while by a fade-out is no mistake', (
    t,
  ) async {
    final hosts = ControllerHost<State>();
    await t.pumpWidget(_views(hosts, ['a']), size: (10, 2));
    // the new host is built while the old one is still mounted
    await t.pumpWidget(_views(hosts, ['a', 'b']), size: (10, 2));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpWidget(_views(hosts, ['b']), size: (10, 2));
    await t.pump(const Duration(seconds: 5));
    expect(t.takeErrors(), isEmpty);
    hosts.dispose();
  });

  testTwk('two views that stay mounted are logged as an error, the app '
      'goes on', (t) async {
    final hosts = ControllerHost<State>();
    await t.pumpWidget(_views(hosts, ['a', 'b']), size: (10, 2));
    await t.pump(const Duration(seconds: 5));
    final [error] = t.takeErrors();
    expect('${error.error}', contains('two hosts'));
    hosts.dispose();
  });

  testTwk('an app that quits within the grace leaves no timer', (t) async {
    final hosts = ControllerHost<State>();
    await t.pumpWidget(_views(hosts, ['a', 'b']), size: (10, 2));
    // the test ends here: failOnPendingTimers fails it if one is left
    hosts.dispose();
  });

  testTwk('a host that is no State needs the mounted callback to be '
      'checked', (t) async {
    await t.pumpWidget(const Text('x'), size: (10, 1));
    final unknown = ControllerHost<String>();
    final live = ControllerHost<String>(mounted: (_) => true);
    await t.act(() {
      unknown
        ..attach('a')
        ..attach('b');
      live
        ..attach('a')
        ..attach('b');
    });
    await t.pump(const Duration(seconds: 5));
    expect(t.takeErrors(), hasLength(1), reason: 'only the one that can tell');
    expect(unknown.host, 'b');
    expect(live.host, 'b');
    unknown.dispose();
    live.dispose();
  });
}
