import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] (the clock stopped at 2 s) in a terminal
/// of [size], a frame for the route's focus after the first.
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = (120, 36),
}) async {
  final at = route.contains('?') ? '$route&t=2000' : '$route?t=2000';
  await t.pumpWidget(galleryApp(route: GalleryRoute.parse(at)), size: size);
  await t.pump();
}

/// Presses [keys] (apart by commas), a frame after each.
Future<void> keys(TwkTester t, String keys) async {
  for (final k in keys.split(',')) {
    await t.press(k);
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 100));
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

/// Each page of the group, and what its stage shows as it opens.
const _pages = {
  'sparkline': '48 × 4',
  'gauge-linegauge': 'used 29%',
  'barchart': 'Q2',
  'chart': '2π',
  'dotcanvas': 'dots',
  'calendar': 'October 2026',
  'table': 'box.dart',
  'treeview': 'table.dart',
  'tasklist': 'Fetch dependencies',
};

void main() {
  group('every Data page', () {
    for (final size in const [(120, 36), (80, 24)]) {
      for (final MapEntry(key: page, value: shows) in _pages.entries) {
        testTwk('$page at ${size.$1}x${size.$2}', (t) async {
          await open(t, '#/data/$page', size: size);
          final s = screen(t);
          expect(s, isNot(contains('drawn in the next part')));
          expect(s, contains(shows));
          expect(problems(t), isEmpty);
        });
      }
    }
  });

  // the Code tab's stage is as tall as the widget's, as the design's
  // size(ctx).h says: the options under a narrow stage take the rest
  testTwk('Calendar: the Code tab is as tall as the calendar at 80x24', (
    t,
  ) async {
    await open(t, '#/data/calendar?tab=code', size: (80, 24));
    expect(screen(t), contains('today: DateTime(2026, 10, 19),'));
    expect(screen(t), contains('outside days'));
    expect(problems(t), isEmpty);
  });

  group('the options apply', () {
    testTwk('Sparkline: rows', (t) async {
      await open(t, '#/data/sparkline?o=rows:2');
      expect(screen(t), contains('48 × 2'));
    });

    testTwk('Gauge: a ratio standing still, a line of its type', (t) async {
      await open(t, '#/data/gauge-linegauge?o=live:false;ratio:50;line:double');
      expect(screen(t), contains('used 50% ════'));
    });

    testTwk('BarChart: across', (t) async {
      await open(t, '#/data/barchart?o=direction:horizontal;live:false');
      expect(screen(t), contains('40 × 21'));
    });

    testTwk('Chart: no legend', (t) async {
      await open(t, '#/data/chart');
      expect(screen(t), contains('│sin│'));
      await open(t, '#/data/chart?o=legend:none');
      expect(screen(t), isNot(contains('│sin│')));
    });

    testTwk('DotCanvas: the marker', (t) async {
      await open(t, '#/data/dotcanvas?o=marker:block;live:false');
      expect(screen(t), contains('█'));
    });

    testTwk('Calendar: week numbers, Sunday first', (t) async {
      await open(t, '#/data/calendar?o=weeks:true;firstWeekday:sunday');
      expect(screen(t), contains('Su Mo Tu'));
      expect(screen(t), contains('43'));
    });

    testTwk('Table: 10 000 rows, no border', (t) async {
      await open(t, '#/data/table?o=rows:10 000;border:none');
      final s = screen(t);
      expect(s, contains('file_0000.dart'));
      expect(s, isNot(contains('┼')));
    });

    testTwk('TreeView: no guides', (t) async {
      await open(t, '#/data/treeview');
      expect(screen(t), contains('├─'));
      await open(t, '#/data/treeview?o=guides:false');
      expect(screen(t), isNot(contains('├─')));
    });

    testTwk('TaskList: the times of the gallery clock, which a route stops, '
        'not of the frames the list saw', (t) async {
      // at 2 s the fetch took 1.4 s and the compile has run 0.6 s
      await open(t, '#/data/tasklist');
      await t.pump(const Duration(seconds: 3));
      var s = screen(t);
      expect(s, contains('✓ Fetch dependencies 1.4 s'));
      expect(s, contains(' Compile 00:00'));
      expect(s, contains(' lib/core.dart 00:00'));
      // a step chosen has run since it was chosen
      await open(t, '#/data/tasklist?o=step:compile');
      await t.pump(const Duration(seconds: 3));
      s = screen(t);
      expect(s, contains('✓ Fetch dependencies  '));
      expect(s, contains(' Compile 00:00'));
    });

    testTwk('TaskList: a step that failed', (t) async {
      await open(t, '#/data/tasklist?o=step:compile;failed:true');
      final s = screen(t);
      expect(s, contains('✗ Compile'));
      expect(s, contains('↓ Run the tests'));
    });
  });

  group('the keys', () {
    testTwk('Calendar: the arrows move, Enter selects', (t) async {
      await open(t, '#/data/calendar');
      expect(screen(t), contains('selected: nothing'));
      await keys(t, 'tab');
      expect(
        t.lines.last.trim(),
        '←↑↓→ move   pgup pgdn month   enter select   tab next   '
        'shift+tab back   esc pages',
      );
      await keys(t, 'right,down,enter');
      expect(screen(t), contains('selected: 2026-10-27'));
      await keys(t, 'pagedown,enter');
      expect(screen(t), contains('November 2026'));
      expect(screen(t), contains('selected: 2026-11-27'));
    });

    testTwk('Table: down selects, s sorts, Enter toasts', (t) async {
      await open(t, '#/data/table');
      await keys(t, 'tab,down,s');
      expect(screen(t), contains('name ▴'));
      await keys(t, 's');
      expect(screen(t), contains('name ▾'));
      await keys(t, 'enter');
      expect(screen(t), contains('Activated text.dart'));
    });

    testTwk('TreeView: Left selects the parent, then collapses', (t) async {
      await open(t, '#/data/treeview');
      expect(screen(t), contains('box.dart'));
      await keys(t, 'tab,left,left');
      expect(screen(t), isNot(contains('box.dart')));
      expect(screen(t), contains('src'));
      await keys(t, 'left,left');
      expect(screen(t), isNot(contains('src')));
    });

    testTwk('Gauge: the ratio moved stops it', (t) async {
      await open(t, '#/data/gauge-linegauge');
      expect(screen(t), contains('used 29%'));
      await keys(t, 'tab,tab,right');
      expect(screen(t), contains('used 76%'));
    });
  });
}
