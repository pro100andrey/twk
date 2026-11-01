// The glyphs of the theme: the set as a value, in ThemeData; and widgets
// drawing with the set they find, Glyphs.unicode as they always did,
// Glyphs.ascii with ASCII alone, a set of an app's own with its marks, and
// the parameter a widget has of its own above the set.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [child] in the dark theme with [glyphs].
Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

/// Whether every character on [lines] is ASCII.
bool isAscii(List<String> lines) =>
    lines.every((l) => l.runes.every((r) => r < 0x80));

void main() {
  group('the set', () {
    test('Glyphs.unicode is the default of every theme', () {
      expect(ThemeData.dark.glyphs, same(Glyphs.unicode));
      expect(ThemeData.light.glyphs, same(Glyphs.unicode));
      expect(const ThemeData.terminal(Brightness.dark).glyphs, Glyphs.unicode);
      expect(ThemeData.terminalOn(0x101010).glyphs, Glyphs.unicode);
    });

    test('copyWith changes the marks given and no other', () {
      final set = Glyphs.unicode.copyWith(check: '+');
      expect(set.check, '+');
      expect(set.cross, Glyphs.unicode.cross);
      expect(set, isNot(Glyphs.unicode));
      expect(set.copyWith(check: Glyphs.unicode.check), Glyphs.unicode);
      expect(Glyphs.ascii.copyWith(), Glyphs.ascii);
      expect(Glyphs.ascii.copyWith().hashCode, Glyphs.ascii.hashCode);
    });

    test('a theme holds it in copyWith, ==, hashCode and lerp', () {
      final ascii = ThemeData.dark.copyWith(glyphs: Glyphs.ascii);
      expect(ascii.glyphs, Glyphs.ascii);
      expect(ascii, isNot(ThemeData.dark));
      expect(ascii.hashCode, isNot(ThemeData.dark.hashCode));
      expect(ascii.copyWith(handPointer: true).glyphs, Glyphs.ascii);
      // the marks do not blend: the other's past halfway
      expect(ThemeData.lerp(ThemeData.dark, ascii, 0.4).glyphs, Glyphs.unicode);
      expect(ThemeData.lerp(ThemeData.dark, ascii, 0.6).glyphs, Glyphs.ascii);
    });

    test('Glyphs.ascii has nothing but ASCII', () {
      const all = Glyphs.ascii;
      final marks = [
        all.cursor,
        all.accent,
        all.check,
        all.checkBold,
        all.cross,
        all.info,
        all.warning,
        all.checkboxOn,
        all.checkboxOff,
        all.switchStart,
        all.switchEnd,
        all.dot,
        all.ring,
        all.expanded,
        all.collapsed,
        all.up,
        all.down,
        all.previous,
        all.next,
        all.first,
        all.last,
        all.close,
        all.maximise,
        all.restore,
        all.minimise,
        all.bullet,
        all.taskPending,
        all.taskSkipped,
        all.separator,
        all.capOpen,
        all.capClose,
        all.trackVertical,
        all.trackHorizontal,
        all.thumbVertical,
        all.thumbHorizontal,
        all.thumbEdge,
        all.gaugeFilled,
        all.gaugeHalf,
        all.gaugeEmpty,
        ...all.spinner.frames,
      ];
      expect(isAscii(marks), isTrue);
    });
  });

  group('checks and crosses', () {
    testTwk('a StatusMessage draws the icon of its kind from the set', (
      t,
    ) async {
      Widget kinds() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final k in StatusKind.values) StatusMessage('m', kind: k),
        ],
      );
      await t.pumpWidget(kinds(), size: (6, 4));
      expect(t.lines, ['ℹ m', '✓ m', '⚠ m', '✗ m']);
      await t.pumpWidget(themed(Glyphs.ascii, kinds()), size: (6, 4));
      expect(t.lines, ['i m', 'v m', '! m', 'x m']);
      await t.pumpWidget(
        themed(Glyphs.unicode.copyWith(check: '+', cross: '-'), kinds()),
        size: (6, 4),
      );
      expect(t.lines, ['ℹ m', '+ m', '⚠ m', '- m']);
      // the widget's own icon stays above the set
      await t.pumpWidget(
        themed(Glyphs.ascii, const StatusMessage('m', icon: '*')),
        size: (6, 1),
      );
      expect(t.lines, ['* m']);
    });

    testTwk('a Checkbox draws its brackets and mark from the set', (t) async {
      Widget boxes() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(value: true, onChanged: (_) {}, label: 'a'),
          Checkbox(value: false, onChanged: (_) {}, label: 'b'),
        ],
      );
      await t.pumpWidget(boxes(), size: (8, 2));
      expect(t.lines, ['[x] a', '[ ] b']);
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(checkboxOn: '[✓]', checkboxOff: '[·]'),
          boxes(),
        ),
        size: (8, 2),
      );
      expect(t.lines, ['[✓] a', '[·] b']);
    });

    testTwk('a Switch draws its ends and knob from the set', (t) async {
      Widget pill() => Switch(value: true, onChanged: (_) {});
      await t.pumpWidget(pill(), size: (8, 1));
      expect(t.lines.single, '▐  ●▌');
      await t.pumpWidget(themed(Glyphs.ascii, pill()), size: (8, 1));
      expect(t.lines.single, '[  *]');
    });

    testTwk('a RadioGroup marks its choice with the dot, its own mark above '
        'the set', (t) async {
      Widget group({String? mark}) => RadioGroup<String>(
        choices: const [Choice('a', 'A'), Choice('b', 'B')],
        value: 'a',
        onChanged: (_) {},
        mark: mark,
      );
      await t.pumpWidget(themed(Glyphs.ascii, group()), size: (8, 2));
      expect(t.lines, ['(*) A', '( ) B']);
      await t.pumpWidget(themed(Glyphs.ascii, group(mark: '@')), size: (8, 2));
      expect(t.lines, ['(@) A', '( ) B']);
    });
  });

  group('arrows and disclosure', () {
    testTwk('an ExpansionTile draws expanded and collapsed from the set', (
      t,
    ) async {
      Widget tiles() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExpansionTile(
            title: Text('open'),
            initiallyExpanded: true,
            duration: Duration.zero,
            child: Text('body'),
          ),
          ExpansionTile(
            title: Text('shut'),
            duration: Duration.zero,
            child: Text('body'),
          ),
        ],
      );
      await t.pumpWidget(themed(Glyphs.unicode, tiles()), size: (10, 4));
      expect(t.lines.first, startsWith('▾ open'));
      expect(t.lines.firstWhere((l) => l.contains('shut')), startsWith('▸ '));
      await t.pumpWidget(themed(Glyphs.ascii, tiles()), size: (10, 4));
      expect(t.lines.first, startsWith('v open'));
      expect(t.lines.firstWhere((l) => l.contains('shut')), startsWith('> '));
    });

    testTwk('a TreeView draws its expanders from the set', (t) async {
      Widget tree() => TreeView<String>(
        roots: const ['a', 'c'],
        children: (n) => n == 'a' ? const ['b'] : const [],
        hasChildren: (n) => n == 'a',
        nodeKey: (n) => n,
        label: (context, entry) => Text(entry.node),
        controller: TreeController(expanded: const ['a']),
      );
      await t.pumpWidget(themed(Glyphs.unicode, tree()), size: (10, 3));
      expect(t.lines.first, startsWith('▾ a'));
      await t.pumpWidget(themed(Glyphs.ascii, tree()), size: (10, 3));
      expect(t.lines.first, startsWith('v a'));
    });

    testTwk('a Pagination draws its arrows from the set', (t) async {
      Widget pages() => Pagination(page: 1, pageCount: 3, onChanged: (_) {});
      await t.pumpWidget(pages(), size: (30, 1));
      expect(t.lines.single, '« ‹ 1 [2] 3 › »');
      await t.pumpWidget(themed(Glyphs.ascii, pages()), size: (30, 1));
      expect(t.lines.single, '<< < 1 [2] 3 > >>');
    });

    testTwk('a ValueStepper draws its arrows from the set', (t) async {
      Widget stepper() => ValueStepper<String>(
        values: const [Choice('a', 'A'), Choice('b', 'B')],
        value: 'a',
        onChanged: (_) {},
      );
      await t.pumpWidget(themed(Glyphs.ascii, stepper()), size: (10, 1));
      expect(t.lines.single, startsWith('< A '));
      expect(t.lines.single.trimRight(), endsWith('>'));
    });
  });

  group('lines and bars', () {
    testTwk('a LineGauge draws the filled, half and empty marks of the set; '
        'its type above it', (t) async {
      Widget gauge({BorderType? type}) => LineGauge(ratio: 0.5, type: type);
      await t.pumpWidget(gauge(), size: (6, 1));
      expect(t.lines.single, '──────');
      await t.pumpWidget(themed(Glyphs.ascii, gauge()), size: (6, 1));
      expect(t.lines.single, '===---');
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(gaugeFilled: '━', gaugeHalf: '╸'),
          const LineGauge(ratio: 0.25),
        ),
        size: (6, 1),
      );
      expect(t.lines.single, '━╸────');
      await t.pumpWidget(
        themed(Glyphs.ascii, gauge(type: BorderType.heavy)),
        size: (6, 1),
      );
      expect(t.lines.single, '━━━━━━');
    });

    testTwk('a Scrollbar draws its thumb and track from the set: # on a | '
        'track in ASCII, in whole cells even under the mouse', (t) async {
      Widget bar() => Scrollbar(
        slim: true,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (var i = 0; i < 30; i++) Text('item $i')],
          ),
        ),
      );
      await t.pumpWidget(themed(Glyphs.unicode, bar()), size: (20, 10));
      final unicode = [for (var y = 0; y < 10; y++) t.cell(19, y).text];
      expect(unicode, containsAll(['┃', '│']));
      await t.pumpWidget(themed(Glyphs.ascii, bar()), size: (20, 10));
      final ascii = [for (var y = 0; y < 10; y++) t.cell(19, y).text];
      expect(ascii.toSet(), {'#', '|'});
      await t.mouse(MouseKind.move, 19, 0);
      await t.pump();
      final hovered = [for (var y = 0; y < 10; y++) t.cell(19, y).text];
      expect(hovered, contains('#'));
      expect(hovered.where((c) => !'#| '.contains(c)), isEmpty);
    });

    testTwk('a Spinner shows the frames of the set, its own above it', (
      t,
    ) async {
      await t.pumpWidget(themed(Glyphs.ascii, const Spinner()), size: (3, 1));
      expect(t.lines.single.trim(), '-');
      await t.pumpWidget(
        themed(
          Glyphs.ascii,
          const Spinner(
            frames: SpinnerFrames(['a'], interval: Duration(seconds: 1)),
          ),
        ),
        size: (3, 1),
      );
      expect(t.lines.single.trim(), 'a');
    });

    testTwk('a TaskList draws the marks of the statuses from the set', (
      t,
    ) async {
      Widget tasks() => const TaskList(
        tasks: [
          TaskItem('p'),
          TaskItem('d', status: TaskStatus.done),
          TaskItem('f', status: TaskStatus.failed),
          TaskItem('s', status: TaskStatus.skipped),
        ],
        showElapsed: false,
      );
      await t.pumpWidget(tasks(), size: (6, 4));
      expect(t.lines.map((l) => l.trimRight()), ['◦ p', '✓ d', '✗ f', '↓ s']);
      await t.pumpWidget(themed(Glyphs.ascii, tasks()), size: (6, 4));
      expect(t.lines.map((l) => l.trimRight()), ['. p', 'v d', 'x f', '- s']);
    });
  });

  group('buttons and chips', () {
    testTwk('a one row Button draws its edges from the set', (t) async {
      Widget button() => Button.outlined('Go', onPressed: () {});
      await t.pumpWidget(button(), size: (8, 1));
      expect(t.lines.single, startsWith('▕  Go  ▏'));
      await t.pumpWidget(themed(Glyphs.ascii, button()), size: (8, 1));
      expect(t.lines.single, startsWith('[  Go  ]'));
    });

    testTwk('a removable Chip draws the close mark of the set', (t) async {
      Widget chip() => const Chip('tag', removable: true);
      await t.pumpWidget(chip(), size: (10, 1));
      expect(t.lines.single.trimRight(), ' tag ×');
      await t.pumpWidget(themed(Glyphs.ascii, chip()), size: (10, 1));
      expect(t.lines.single.trimRight(), ' tag x');
    });

    testTwk('a TabBar overflowing marks its edges with previous and next', (
      t,
    ) async {
      final controller = TabController(length: 4);
      addTearDown(controller.dispose);
      Widget tabs() => TabBar(
        tabs: const ['alpha', 'beta', 'gamma', 'delta'],
        controller: controller,
      );
      await t.pumpWidget(themed(Glyphs.ascii, tabs()), size: (12, 1));
      expect(isAscii(t.lines), isTrue);
      expect(t.lines.single, endsWith('>'));
    });

    testTwk('a masked TextField shows the bullet of the set', (t) async {
      Widget field({String? mask}) => TextField(
        controller: TextEditingController(text: 'abc'),
        obscureText: true,
        obscuringCharacter: mask,
      );
      await t.pumpWidget(field(), size: (6, 1));
      expect(t.lines.single.trimRight(), '•••');
      await t.pumpWidget(themed(Glyphs.ascii, field()), size: (6, 1));
      expect(t.lines.single.trimRight(), '***');
      await t.pumpWidget(themed(Glyphs.ascii, field(mask: '#')), size: (6, 1));
      expect(t.lines.single.trimRight(), '###');
    });
  });
}
