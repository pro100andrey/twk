// What a LogView looks at in its render tree: scrolled up at the cap, each
// line added drops the oldest, and the view finds the line at the top of
// its window again; with no current match, `n` starts from the window. The
// render objects it looks at for that are the items laid out past the
// edge of its window it starts from, no more in a window of 80 rows than
// in one of 10: not every line in the window, nor the tree down to its
// list each time.
//
// What it builds: scrolled up, a line added changes nothing in its window,
// below the cap or at it, wrapped or not, and none of the lines it has laid
// out, in the window and past its edges, is built again, frame after
// frame: at the cap, where the lines shown each move up an index, the list
// builds them where its window goes, not where it was.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show ListParentData, RenderList;
import 'package:twk_test/twk_test.dart';

/// A view of [c], its lines bare, focused, with no scrollbar.
Widget plain(LogController c, {bool wrap = false}) => LogView(
  controller: c,
  showTime: false,
  showLevel: false,
  autofocus: true,
  wrap: wrap,
  scrollbar: ScrollbarVisibility.never,
);

/// The render objects looked at per line added to a view [rows] tall,
/// scrolled up, at the cap of its controller.
Future<double> visitsPerAdd(TwkTester t, int rows, {bool wrap = false}) async {
  final c = LogController(maxLines: 1000)
    ..addAll([for (var i = 0; i < 1000; i++) 'line $i']);
  await t.pumpWidget(plain(c, wrap: wrap), size: (40, rows));
  // a few windows up: past the end, where the list lays out a window more
  for (var i = 0; i < 3; i++) {
    await t.press('pageup');
    await t.pump();
    await t.pump();
  }
  expect(c.following, isFalse);
  final top = t.lines.first;
  LogView.renderVisits = 0;
  for (var i = 0; i < 100; i++) {
    c.add('line ${1000 + i}');
  }
  final visits = LogView.renderVisits / 100;
  await t.pump();
  // it stayed on the lines it showed
  expect(t.lines.first, top);
  return visits;
}

/// The render objects of the items the list in [t]'s [LogView] has laid
/// out, its window's and those past its edges, top to bottom.
List<RenderObject> laidOut(TwkTester t) {
  RenderList? list;
  void visit(RenderObject o) {
    if (list == null && o is RenderList) {
      list = o;
    } else if (list == null) {
      o.visitChildren(visit);
    }
  }

  visit(t.renderObject<RenderObject>(find.byType(LogView)));
  final items = <RenderObject>[];
  for (var c = list!.firstChild; c != null;) {
    items.add(c);
    c = (c.parentData as ListParentData).nextSibling;
  }
  return items;
}

/// Adds [n] lines to a view [rows] tall of a controller of [maxLines],
/// scrolled up, a frame after each; returns how many of the items laid
/// out after a frame were not laid out before it.
Future<int> rebuiltScrolledUp(
  TwkTester t, {
  required int maxLines,
  int rows = 10,
  int n = 20,
  bool wrap = false,
}) async {
  final c = LogController(maxLines: maxLines)
    ..addAll([for (var i = 0; i < 1000; i++) 'line $i']);
  await t.pumpWidget(plain(c, wrap: wrap), size: (40, rows));
  for (var i = 0; i < 3; i++) {
    await t.press('pageup');
    await t.pump();
    await t.pump();
  }
  expect(c.following, isFalse);
  final lines = t.lines;
  var before = laidOut(t);
  var rebuilt = 0;
  for (var i = 0; i < n; i++) {
    c.add('line ${1000 + i}');
    await t.pump();
    final now = laidOut(t);
    final was = before.toSet();
    rebuilt += now.where((o) => !was.contains(o)).length;
    before = now;
  }
  // it stayed on the lines it showed; the indicator is on the last row
  expect(t.lines.take(rows - 1), lines.take(rows - 1));
  return rebuilt;
}

void main() {
  group('scrolled up, a line added builds none of the lines laid out', () {
    testTwk('below the cap', (t) async {
      expect(await rebuiltScrolledUp(t, maxLines: 5000), 0);
    });

    testTwk('at the cap, each dropping the oldest', (t) async {
      expect(await rebuiltScrolledUp(t, maxLines: 1000), 0);
    });

    testTwk('wrapped, at the cap', (t) async {
      expect(await rebuiltScrolledUp(t, maxLines: 1000, wrap: true), 0);
    });
  });

  testTwk('scrolled up at the cap, a line added looks at the edges of the '
      'window, whatever its height', (t) async {
    final short = await visitsPerAdd(t, 10);
    final tall = await visitsPerAdd(t, 80);
    expect(tall, lessThanOrEqualTo(short));
    expect(short, lessThanOrEqualTo(16));
  });

  testTwk('wrapped, the same', (t) async {
    final short = await visitsPerAdd(t, 10, wrap: true);
    final tall = await visitsPerAdd(t, 80, wrap: true);
    expect(tall, lessThanOrEqualTo(short));
    expect(short, lessThanOrEqualTo(16));
  });

  testTwk('n with no current match looks at the edges of the window', (
    t,
  ) async {
    Future<int> visitsOfN(int rows) async {
      final c = LogController()
        ..addAll([for (var i = 0; i < 1000; i++) 'line $i'])
        ..query = 'line 5';
      await t.pumpWidget(plain(c), size: (40, rows));
      LogView.renderVisits = 0;
      expect(c.nextMatch(), isTrue);
      return LogView.renderVisits;
    }

    final short = await visitsOfN(10);
    final tall = await visitsOfN(80);
    expect(tall, lessThanOrEqualTo(short));
    expect(short, lessThanOrEqualTo(16));
  });
}
