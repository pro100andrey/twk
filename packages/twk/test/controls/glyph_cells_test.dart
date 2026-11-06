// Marks of an app's own: an empty one draws nothing and breaks nothing, a
// wide or astral one is measured in cells and cut at code points, not by
// code units: tabs' edges, a slider's line and thumb, a slim scrollbar's
// line, a checkbox, a chip's close, the boxes of a MultiSelect and of a
// FilePicker.
import 'package:test/test.dart';
import 'package:twk/log.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../platform/native_paths.dart';

/// [child] in the dark theme with [glyphs].
Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

void main() {
  group('empty marks', () {
    testTwk('a TabBar with no previous or next mark scrolls and draws', (
      t,
    ) async {
      final c = TabController(length: 6);
      addTearDown(c.dispose);
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(previous: '', next: ''),
          TabBar(
            controller: c,
            tabs: const ['One', 'Two', 'Three', 'Four', 'Five', 'Six'],
          ),
        ),
        size: (14, 1),
      );
      expect(t.lines.first, startsWith(' One'));
      c.index = 5;
      await t.pump();
      expect(t.lines.first, contains('Six'));
    });

    testTwk('a Slider with an empty line and thumb draws', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(
            trackHorizontal: '',
            thumbHorizontal: '',
            partialBlocks: false,
          ),
          SizedBox(
            width: 8,
            height: 1,
            child: Slider(value: 0.5, onChanged: (_) {}),
          ),
        ),
        size: (8, 1),
      );
      // an empty track is a blank, an empty thumb Glyphs.ascii's
      expect(t.lines, ['    #']);
    });

    testTwk('a TreeView with no expanded or collapsed mark draws', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(expanded: '', collapsed: ''),
          TreeView<String>(
            roots: const ['a'],
            children: (n) => n == 'a' ? const ['b'] : const [],
            label: (context, entry) => Text(entry.node),
            showGuides: false,
          ),
        ),
        size: (10, 2),
      );
      expect(t.lines.first, '  a');
    });

    testTwk('a slim Scrollbar with an empty track and thumb draws', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(
            trackVertical: '',
            thumbVertical: '',
            partialBlocks: false,
          ),
          Scrollbar(
            slim: true,
            child: ListView.builder(
              itemCount: 30,
              itemBuilder: (_, i) => Text('item $i'),
            ),
          ),
        ),
        size: (10, 4),
      );
      // the line blank, the thumb the fallback #
      expect(t.lines, ['item 0   #', 'item 1', 'item 2', 'item 3']);
    });
  });

  group('wide and astral marks', () {
    testTwk('a checkbox of an astral mark is the ASCII one, whole', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(checkboxOn: '😀'),
          Checkbox(value: true, onChanged: (_) {}, label: 'Wrap'),
        ),
        size: (14, 1),
      );
      expect(t.lines.first, startsWith('[x] Wrap'));
      expect(t.lines.first.runes, isNot(contains(0xFFFD)));
    });

    testTwk('a chip with a close mark two columns wide shows the ASCII one, '
        'and is removed by a click on it', (t) async {
      final removed = <String>[];
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(close: '全'),
          ChipList<String>(
            chips: const [Choice('a', 'ab')],
            onSelectionChanged: (_) {},
            onDeleted: removed.add,
          ),
        ),
        size: (14, 1),
      );
      // ' ab x ': 0 blank, 1-2 ab, 3 blank, 4 the mark, 5 blank
      expect(t.lines.first.trimRight(), ' ab x');
      await t.click(4, 0);
      await t.pump();
      expect(removed, ['a']);
    });

    testTwk('a MultiSelect with wide boxes opens with the ASCII ones', (
      t,
    ) async {
      final values = ValueNotifier(<String>{'a'});
      addTearDown(values.dispose);
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(checkboxOn: '全', checkboxOff: '空'),
          Overlay(
            child: ValueListenableBuilder<Set<String>>(
              valueListenable: values,
              builder: (context, v, _) => MultiSelect<String>(
                choices: const [Choice('a', 'Apple'), Choice('b', 'Banana')],
                values: v,
                onChanged: (next) => values.value = next,
                hint: 'none',
                autofocus: true,
              ),
            ),
          ),
        ),
        size: (24, 4),
      );
      await t.press('enter');
      await t.pumpUntilIdle();
      expect(t, containsLine(contains('[x] Apple')));
      expect(t, containsLine(contains('[ ] Banana')));
    });

    testTwk('a FilePicker with wide boxes aligns a directory with a file', (
      t,
    ) async {
      final files = PickerFileSystem.memory([
        rooted('/home/dd/'),
        rooted('/home/ff'),
      ]);
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(checkboxOn: '全', checkboxOff: '空'),
          Overlay(
            child: FilePicker(
              onPicked: (_) {},
              fileSystem: files,
              directory: rooted('/home'),
              multiple: true,
              autofocus: true,
            ),
          ),
        ),
        size: (40, 12),
      );
      await t.pumpUntilIdle();
      final file = t.lines.firstWhere((l) => l.contains('[ ] ff'));
      final directory = t.lines.firstWhere((l) => l.contains('dd'));
      // a directory has no box, a blank as wide as one in its place: the
      // names stand in one column, in cells
      final segmenter = TextSegmenter();
      expect(
        segmenter.width(directory.substring(0, directory.indexOf('dd'))),
        segmenter.width(file.substring(0, file.indexOf('ff'))),
      );
    });
  });

  group('a mark not one cell wide', () {
    String tooWide(String field, String fallback) =>
        "Glyphs.$field '🔽' is 2 cells wide, not 1; "
        "Glyphs.ascii's '$fallback' is drawn in its place.";

    List<String> warnings(TwkTester t) => [
      for (final r in t.logs.records)
        if (r.level == LogLevel.warning && r.message.startsWith('Glyphs.'))
          r.message,
    ];

    testTwk('in a TabBar is the ascii edge, warned of once', (t) async {
      final c = TabController(length: 6);
      addTearDown(c.dispose);
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(previous: '🔽', next: '🔽'),
          TabBar(
            controller: c,
            tabs: const ['One', 'Two', 'Three', 'Four', 'Five', 'Six'],
          ),
        ),
        size: (14, 1),
      );
      expect(t.lines.first, endsWith('>'));
      c.index = 5;
      await t.pump();
      await t.pump();
      expect(t.lines.first, startsWith('<'));
      expect(warnings(t), [
        tooWide('next', '>'),
        tooWide('previous', '<'),
      ]);
    });

    testTwk('in a Slider is the ascii line and thumb, warned of once', (
      t,
    ) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(
            trackHorizontal: '🔽',
            thumbHorizontal: '🔽',
            partialBlocks: false,
          ),
          SizedBox(
            width: 8,
            height: 1,
            child: Slider(value: 0.5, onChanged: (_) {}),
          ),
        ),
        size: (8, 1),
      );
      await t.pump();
      expect(t.lines, ['----#---']);
      expect(warnings(t), hasLength(2));
      expect(warnings(t).first, contains('trackHorizontal'));
      expect(warnings(t).last, contains('thumbHorizontal'));
    });

    testTwk('in a slim Scrollbar is the ascii line and thumb, warned of '
        'once', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(
            trackVertical: '🔽',
            thumbVertical: '🔽',
            partialBlocks: false,
          ),
          Scrollbar(
            slim: true,
            child: ListView.builder(
              itemCount: 30,
              itemBuilder: (_, i) => Text('item $i'),
            ),
          ),
        ),
        size: (10, 4),
      );
      await t.pump();
      expect(t.lines, ['item 0   #', 'item 1   |', 'item 2   |', 'item 3   |']);
      expect(warnings(t), hasLength(2));
    });

    testTwk('in a TreeView is the ascii expander, warned of once', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(expanded: '🔽', collapsed: '🔽'),
          TreeView<String>(
            roots: const ['a', 'c'],
            children: (n) => n == 'a' || n == 'c' ? const ['b'] : const [],
            label: (context, entry) => Text(entry.node),
            showGuides: false,
          ),
        ),
        size: (10, 3),
      );
      await t.pump();
      expect(t.lines.first, '> a');
      expect(warnings(t), [
        tooWide('collapsed', '>'),
      ]);
    });

    testTwk('in an OptionList is the ascii cursor and thumb, warned of '
        'once', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(cursor: '🔽', thumbSlim: '🔽'),
          Align(
            alignment: Alignment.topLeft,
            child: OptionList(
              options: [for (var i = 0; i < 6; i++) Option('item $i')],
              highlighted: 1,
              rows: 3,
            ),
          ),
        ),
        size: (10, 3),
      );
      await t.pump();
      expect(t.lines[1], startsWith('>item 1'));
      expect(t.lines[0], endsWith('#'));
      expect(t, isNot(containsLine(contains('🔽'))));
      expect(warnings(t), hasLength(2));
    });

    testTwk('in a menu are the ascii check, submenu mark and cursor, '
        'warned of once', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(check: '🔽', collapsed: '🔽', cursor: '🔽'),
          const Overlay(
            child: MenuBar(
              menus: [
                Menu(
                  '&View',
                  items: [
                    MenuItem('&Wrap', checked: true),
                    Menu('&More', items: [MenuItem('&One')]),
                  ],
                ),
              ],
              child: Focus(autofocus: true, child: SizedBox.expand()),
            ),
          ),
        ),
        size: (20, 6),
      );
      await t.press('f10');
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
      expect(t, isNot(containsLine(contains('🔽'))));
      expect(t, containsLine(contains('v Wrap')));
      expect(t, containsLine(contains('More')));
      expect(warnings(t).map((m) => m.split(' ')[0]).toSet(), {
        'Glyphs.check',
        'Glyphs.collapsed',
        'Glyphs.cursor',
      });
    });

    testTwk('in a toast is the ascii accent, warned of once', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(accent: '🔽'),
          const Overlay(child: _Toaster()),
        ),
        size: (20, 6),
      );
      await t.press('s');
      await t.pump(const Duration(seconds: 1));
      expect(t, isNot(containsLine(contains('🔽'))));
      expect(t, containsLine(contains('|')));
      expect(warnings(t), hasLength(1));
    });

    testTwk('a window bar button two cells wide is the ASCII one, the title '
        'cut before it', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(close: '🔽'),
          WindowLayer(
            windows: [
              Window(
                title: 'A long title cut off here',
                controller: WindowController(
                  width: 16,
                  height: 3,
                ),
                onClose: () {},
                minimisable: false,
                maximisable: false,
                child: const Text('c'),
              ),
            ],
            child: const Text('app'),
          ),
        ),
        size: (20, 4),
      );
      await t.pump();
      // the title ends before the one column of the ASCII button
      expect(t.lines.first, '  A long ti… x');
      expect(warnings(t), hasLength(1));
    });
  });
}

/// Shows a toast on `s`.
final class _Toaster extends StatelessWidget {
  const _Toaster();

  @override
  Widget build(BuildContext context) => KeyBindings({
    's': () => showToast(context: context, message: 'Saved'),
  }, child: const SizedBox.expand());
}
