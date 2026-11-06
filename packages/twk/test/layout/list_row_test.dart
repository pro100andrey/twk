// The rows apps wrote for themselves out of LayoutBuilder and stringWidth,
// built from what twk has: a flexible left part cut with `…` and a fixed
// right one (Row, Expanded, Text.line), columns of a fixed width
// (SizedBox, Text.line, TextAlign.right), such rows in a SelectionList with
// its bar and its idle selection, and a list that loads more when its end
// is near (a NotificationListener over a ListView, ScrollMetrics).
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const files = [
  ('a-very-long-file-name.dart', '12 KB'),
  ('short.md', '1 KB'),
  ('日本語のファイル名前.txt', '3 MB'),
];

/// A row: the name takes what the size leaves and is cut with `…`.
Widget row((String, String) f) => Row(
  children: [
    Expanded(child: Text.line(f.$1)),
    Text(' ${f.$2}'),
  ],
);

/// A row of columns of fixed widths: name, kind and size aligned right.
Widget columns((String, String) f) => Row(
  children: [
    SizedBox(width: 12, child: Text.line(f.$1)),
    const SizedBox(width: 1),
    SizedBox(width: 4, child: Text.line(f.$1.split('.').last)),
    SizedBox(
      width: 6,
      child: Text(f.$2, textAlign: TextAlign.right, wrap: TextWrap.none),
    ),
  ],
);

Widget list(
  Widget Function((String, String)) build, {
  SelectionController<String>? controller,
}) => SelectionList<String>(
  controller: controller,
  itemCount: files.length,
  keyOf: (i) => files[i].$1,
  itemBuilder: (context, i) => build(files[i]),
);

void main() {
  group('a flexible left part and a fixed right one', () {
    testTwk('the left is cut with … where the right leaves it no room, '
        'in cells, wide letters too', (t) async {
      await t.pumpWidget(list(row), size: (24, 3));
      expect(t.lines, [
        ' a-very-long-file… 12 KB',
        ' short.md           1 KB',
        ' 日本語のファイル…  3 MB',
      ]);
    });

    testTwk('the same row with spans, and as wide as the room is', (t) async {
      for (final width in [14, 30]) {
        await t.pumpWidget(
          Row(
            children: [
              Expanded(
                child: Text.richLine([
                  'name-of-a-file'.bold,
                  const Span('.dart'),
                ]),
              ),
              const Text(' 5 KB'),
            ],
          ),
          size: (width, 1),
        );
        expect(
          t.lines.single,
          width == 14 ? 'name-of-… 5 KB' : 'name-of-a-file.dart       5 KB',
        );
      }
    });

    testTwk('in a SelectionList the bar is on the selected row while the '
        "list has not the focus, in the muted color, and on the cursor's "
        'when it has', (t) async {
      final controller = SelectionController<String>(
        selected: [files[1].$1],
      );
      const theme = ThemeData.nord;
      await t.pumpWidget(
        Theme(
          data: theme,
          child: list(row, controller: controller),
        ),
        size: (24, 3),
      );
      expect(t.lines[1], startsWith('▎short.md'));
      expect(t.lines[0], startsWith(' a-very'));
      expect(t, styleAt(0, 1, hasFg(theme.muted.fg!)));
      await t.press('tab');
      await t.pump();
      expect(t.lines[1], startsWith('▎short.md'));
      expect(t, styleAt(0, 1, hasFg(theme.primary.fg!)));
    });
  });

  group('columns of a fixed width', () {
    testTwk('each is cut or padded to its width, the last aligned right', (
      t,
    ) async {
      await t.pumpWidget(list(columns), size: (24, 3));
      expect(t.lines, [
        ' a-very-long… dart 12 KB',
        ' short.md     md    1 KB',
        ' 日本語のフ…  txt   3 MB',
      ]);
    });
  });

  group('a list that loads more near its end', () {
    /// [n]'s `extentAfter` of each update heard over [list], after [act].
    Future<List<int>> hear(
      TwkTester t,
      Widget list,
      Future<void> Function() act,
    ) async {
      final after = <int>[];
      await t.pumpWidget(
        NotificationListener<ScrollUpdateNotification>(
          onNotification: (n) {
            after.add(n.metrics.extentAfter);
            return false;
          },
          child: list,
        ),
        size: (12, 5),
      );
      await act();
      return after;
    }

    testTwk('a NotificationListener hears ScrollMetrics.extentAfter of a '
        "ListView the keys and the wheel scroll, as Flutter's does", (
      t,
    ) async {
      final after = await hear(
        t,
        ListView.builder(
          autofocus: true,
          itemCount: 20,
          itemBuilder: (context, i) => Text('item $i'),
        ),
        () async {
          await t.press('down');
          await t.mouse(MouseKind.wheelDown, 1, 1);
          await t.pump();
          await t.press('end');
        },
      );
      expect(after, [14, 11, 0]);
    });

    testTwk('and of a SelectionList the cursor scrolls, and of a list a '
        'ListController moves to an item', (t) async {
      final controller = ListController();
      final after = await hear(
        t,
        SelectionList<int>(
          autofocus: true,
          itemCount: 20,
          keyOf: (i) => i,
          itemBuilder: (context, i) => Text('item $i'),
        ),
        () async {
          for (var i = 0; i < 6; i++) {
            await t.press('down');
            await t.pump();
          }
        },
      );
      expect(after, [14, 13]);
      final moved = await hear(
        t,
        ListView.builder(
          controller: controller,
          itemCount: 20,
          itemBuilder: (context, i) => Text('item $i'),
        ),
        () async {
          controller.ensureIndexVisible(9);
          await t.pump();
          controller.jumpToIndex(2);
          await t.pump();
        },
      );
      expect(moved, [10, 13]);
    });
  });
}
