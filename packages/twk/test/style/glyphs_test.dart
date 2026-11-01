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

    test('the partial blocks are off and the gauge has no half in ASCII', () {
      expect(Glyphs.unicode.partialBlocks, isTrue);
      expect(Glyphs.ascii.partialBlocks, isFalse);
      expect(Glyphs.unicode.gaugeHalf, '╴');
      expect(Glyphs.ascii.gaugeHalf, isNull);
    });

    test('gaugeHalf is cleared by clearGaugeHalf alone, kept otherwise', () {
      final none = Glyphs.unicode.copyWith(clearGaugeHalf: true);
      expect(none.gaugeHalf, isNull);
      expect(none.copyWith(check: '+').gaugeHalf, isNull);
      expect(none.copyWith(gaugeHalf: '╸').gaugeHalf, '╸');
      expect(Glyphs.unicode.copyWith(check: '+').gaugeHalf, '╴');
      expect(none, isNot(Glyphs.unicode));
      expect(none.hashCode, isNot(Glyphs.unicode.hashCode));
    });

    test('the tuple marks compare by value in ==', () {
      expect(
        Glyphs.unicode.copyWith(buttonEdges: ('▕', '▏')),
        Glyphs.unicode,
      );
      expect(
        Glyphs.unicode.copyWith(buttonEdges: ('<', '>')),
        isNot(Glyphs.unicode),
      );
      expect(
        Glyphs.unicode.copyWith(radioBrackets: ('', '')),
        isNot(Glyphs.unicode),
      );
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
        all.radioOn,
        all.radioOff,
        all.radioBrackets.$1,
        all.radioBrackets.$2,
        all.switchStart,
        all.switchEnd,
        all.switchKnob,
        all.stepCurrent,
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
        all.buttonEdges.$1,
        all.buttonEdges.$2,
        all.trackVertical,
        all.trackHorizontal,
        all.thumbVertical,
        all.thumbHorizontal,
        all.thumbSlim,
        all.gaugeFilled,
        ?all.gaugeHalf,
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

    testTwk('the switch knob and the stepper step in hand are two marks', (
      t,
    ) async {
      final set = Glyphs.unicode.copyWith(switchKnob: 'S', stepCurrent: 'C');
      await t.pumpWidget(
        themed(set, Switch(value: true, onChanged: (_) {})),
        size: (8, 1),
      );
      expect(t.lines.single, '▐  S▌');
      await t.pumpWidget(
        themed(
          set,
          const Stepper(
            steps: [Step(title: 'One', content: Text('a'))],
            direction: Axis.vertical,
          ),
        ),
        size: (20, 4),
      );
      expect(t.lines.join('\n'), allOf(contains('C 1.'), isNot(contains('S'))));
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

  group('radio marks', () {
    testTwk('a RadioGroup draws radioOn and radioOff between radioBrackets, '
        'bracketless too', (t) async {
      Widget group({String? mark}) => RadioGroup<String>(
        choices: const [Choice('a', 'A'), Choice('b', 'B')],
        value: 'a',
        onChanged: (_) {},
        mark: mark,
      );
      await t.pumpWidget(themed(Glyphs.unicode, group()), size: (8, 2));
      expect(t.lines, ['(●) A', '( ) B']);
      final rings = Glyphs.unicode.copyWith(
        radioOn: '◉',
        radioOff: '○',
        radioBrackets: ('', ''),
      );
      await t.pumpWidget(themed(rings, group()), size: (8, 2));
      expect(t.lines, ['◉ A', '○ B']);
      // a mark above the set replaces the on mark
      await t.pumpWidget(themed(rings, group(mark: '@')), size: (8, 2));
      expect(t.lines, ['@ A', '○ B']);
      // brackets of the set's own, the mark in the middle
      final square = Glyphs.unicode.copyWith(radioBrackets: ('[', ']'));
      await t.pumpWidget(themed(square, group(mark: '@')), size: (8, 2));
      expect(t.lines, ['[@] A', '[ ] B']);
      // one bracket alone
      final left = Glyphs.unicode.copyWith(radioBrackets: ('<', ''));
      await t.pumpWidget(themed(left, group()), size: (8, 2));
      expect(t.lines, ['<● A', '<  B']);
    });

    testTwk('the brackets are in bracketStyle, the chosen mark in the '
        "mark's, an unchosen one in the brackets'", (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(radioOff: '○'),
          RadioGroup<String>(
            choices: const [Choice('a', 'A'), Choice('b', 'B')],
            value: 'a',
            onChanged: (_) {},
            bracketStyle: const Style(fg: Color.red),
          ),
        ),
        size: (8, 2),
      );
      expect(t, styleAt(0, 0, hasFg(Color.red)));
      expect(t, styleAt(2, 0, hasFg(Color.red)));
      expect(t, styleAt(1, 0, isNot(hasFg(Color.red))));
      expect(t, styleAt(0, 1, hasFg(Color.red)));
      expect(t, styleAt(1, 1, hasFg(Color.red)));
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

    testTwk('a LineGauge with the half cleared fills in whole cells', (
      t,
    ) async {
      final whole = Glyphs.unicode.copyWith(clearGaugeHalf: true);
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(gaugeFilled: '━'),
          const LineGauge(ratio: 0.25),
        ),
        size: (6, 1),
      );
      expect(t.lines.single, '━╴────');
      await t.pumpWidget(
        themed(whole.copyWith(gaugeFilled: '━'), const LineGauge(ratio: 0.25)),
        size: (6, 1),
      );
      expect(t.lines.single, '━━────');
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

    testTwk('a one row Button draws buttonEdges, a pair, from the set', (
      t,
    ) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(buttonEdges: ('<', '>')),
          Button.outlined('Go', onPressed: () {}),
        ),
        size: (8, 1),
      );
      expect(t.lines.single, startsWith('<  Go  >'));
      // an edge not one column wide: the separator at both ends
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(buttonEdges: ('<', '>>')),
          Button.outlined('Go', onPressed: () {}),
        ),
        size: (8, 1),
      );
      expect(t.lines.single, startsWith('│  Go  │'));
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

  group('fields and lists', () {
    testTwk('a Select draws its arrow from the set, a MultiSelect its '
        'checkboxes', (t) async {
      Widget select() => Select<String>(
        choices: const [Choice('a', 'Apple'), Choice('b', 'Banana')],
        value: 'a',
        onChanged: (_) {},
        hint: 'fruit?',
        inline: true,
      );
      await t.pumpWidget(themed(Glyphs.unicode, select()), size: (12, 1));
      expect(t.lines.single, endsWith('▾'));
      await t.pumpWidget(themed(Glyphs.ascii, select()), size: (12, 1));
      expect(t.lines.single, endsWith('v'));
      await t.pumpWidget(
        themed(Glyphs.unicode.copyWith(down: '+'), select()),
        size: (12, 1),
      );
      expect(t.lines.single, endsWith('+'));
      // in a decoration too
      Widget decorated() => Select<String>(
        choices: const [Choice('a', 'Apple')],
        value: 'a',
        onChanged: (_) {},
        decoration: const InputDecoration(labelText: 'Fruit'),
      );
      await t.pumpWidget(
        themed(Glyphs.ascii, Overlay(child: decorated())),
        size: (20, 4),
      );
      expect(t.lines.join('\n'), contains('Apple'));
      expect(t.lines.join('\n'), contains(' v'));
      expect(t.lines.join('\n'), isNot(contains('▾')));
    });

    testTwk('a NumberInput draws its arrows from the set', (t) async {
      Widget input() => NumberInput(value: 1, onChanged: (_) {});
      await t.pumpWidget(themed(Glyphs.unicode, input()), size: (12, 1));
      expect(t.lines.single, contains('▴▾'));
      await t.pumpWidget(themed(Glyphs.ascii, input()), size: (12, 1));
      expect(t.lines.single, contains('^v'));
    });

    testTwk('a multiple SelectionList draws its boxes and cursor bar from '
        'the set', (t) async {
      final controller = SelectionController<String>(multiple: true);
      addTearDown(controller.dispose);
      Widget list() => SelectionList<String>(
        itemCount: 2,
        keyOf: (i) => 'k$i',
        itemBuilder: (context, i) => Text('item $i'),
        controller: controller,
        autofocus: true,
      );
      await t.pumpWidget(themed(Glyphs.unicode, list()), size: (12, 2));
      expect(t.lines.first, '▎[ ] item 0');
      await t.pumpWidget(
        themed(
          Glyphs.ascii.copyWith(checkboxOn: '(x)', checkboxOff: '( )'),
          list(),
        ),
        size: (12, 2),
      );
      expect(t.lines.first, '>( ) item 0');
    });

    testTwk('a sorted Table draws the sort arrow from the set', (t) async {
      final controller = TableController(sortColumn: 0);
      addTearDown(controller.dispose);
      Widget table() => Table<String>(
        rows: const ['a', 'b'],
        controller: controller,
        columns: [
          TableColumn<String>(
            title: 'Name',
            cell: TableCell.new,
            compare: (a, b) => a.compareTo(b),
          ),
        ],
      );
      await t.pumpWidget(themed(Glyphs.unicode, table()), size: (12, 3));
      expect(t.lines.first, contains('Name ▴'));
      await t.pumpWidget(themed(Glyphs.ascii, table()), size: (12, 3));
      expect(t.lines.first, contains('Name ^'));
    });

    testTwk('a dismissible Callout draws the close mark of the set', (
      t,
    ) async {
      Widget callout() => Callout(
        kind: StatusKind.success,
        onDismissed: () {},
        child: const Text('Built'),
      );
      await t.pumpWidget(themed(Glyphs.ascii, callout()), size: (20, 3));
      expect(t.lines.join('\n'), contains('[x]'));
      expect(t.lines.join('\n'), contains('v '));
      await t.pumpWidget(themed(Glyphs.unicode, callout()), size: (20, 3));
      expect(t.lines.join('\n'), contains('[×]'));
    });

    testTwk('a Stepper draws its step marks from the set', (t) async {
      Widget stepper() => const Stepper(
        steps: [
          Step(title: 'One', content: Text('a'), state: StepState.complete),
          Step(title: 'Two', content: Text('b'), state: StepState.error),
          Step(title: 'Three', content: Text('c')),
        ],
        direction: Axis.vertical,
      );
      await t.pumpWidget(themed(Glyphs.unicode, stepper()), size: (20, 8));
      final unicode = t.lines.join('\n');
      expect(unicode, allOf(contains('✔ 1.'), contains('✗ 2.')));
      await t.pumpWidget(themed(Glyphs.ascii, stepper()), size: (20, 8));
      final ascii = t.lines.join('\n');
      expect(ascii, allOf(contains('v 1.'), contains('x 2.')));
      expect(isAscii(t.lines), isTrue);
    });
  });

  group('lists, sliders and segments', () {
    testTwk('an OptionList draws its cursor bar and thumb from the set', (
      t,
    ) async {
      Widget list() => const Align(
        alignment: Alignment.topLeft,
        child: OptionList(
          options: [
            Option('apple'),
            Option('banana'),
            Option('cherry'),
            Option('date'),
          ],
          highlighted: 0,
          rows: 2,
        ),
      );
      await t.pumpWidget(themed(Glyphs.unicode, list()), size: (14, 2));
      expect([t.cell(0, 0).text, t.cell(7, 0).text], ['▎', '▐']);
      await t.pumpWidget(themed(Glyphs.ascii, list()), size: (14, 2));
      expect([t.cell(0, 0).text, t.cell(7, 0).text], ['>', '#']);
    });

    testTwk('an OptionList thumb is thumbSlim, whatever thumbVertical is', (
      t,
    ) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(thumbSlim: 'T', thumbVertical: 'V'),
          const Align(
            alignment: Alignment.topLeft,
            child: OptionList(
              options: [Option('apple'), Option('banana'), Option('cherry')],
              highlighted: 0,
              rows: 2,
            ),
          ),
        ),
        size: (14, 2),
      );
      expect(t.cell(7, 0).text, 'T');
    });

    testTwk('without partialBlocks a Slider draws whole cells', (t) async {
      Widget slider() => Slider(value: 0.5, onChanged: (_) {});
      await t.pumpWidget(themed(Glyphs.unicode, slider()), size: (10, 1));
      final blocks = t.lines.single;
      await t.pumpWidget(
        themed(Glyphs.unicode.copyWith(partialBlocks: false), slider()),
        size: (10, 1),
      );
      expect(t.lines.single, isNot(blocks));
      expect(t.lines.single, contains('━'));
    });

    testTwk('a SegmentedButton draws its lines and checks from the set', (
      t,
    ) async {
      Widget segments() => SegmentedButton<int>(
        segments: const [Choice(1, 'One'), Choice(2, 'Two')],
        selected: const {2},
        showSelectedIcon: true,
        onSelectionChanged: (_) {},
      );
      await t.pumpWidget(themed(Glyphs.unicode, segments()), size: (24, 1));
      expect(t.lines.single, contains('│'));
      await t.pumpWidget(themed(Glyphs.ascii, segments()), size: (24, 1));
      expect(t.lines.single, contains('|'));
      expect(t.lines.single, contains('v Two'));
      expect(isAscii(t.lines), isTrue);
    });

    testTwk('a Slider draws its groove and thumb from the set', (t) async {
      Widget slider() => Slider(value: 0.5, onChanged: (_) {});
      await t.pumpWidget(themed(Glyphs.unicode, slider()), size: (10, 1));
      expect(t.lines.single, contains('─'));
      await t.pumpWidget(themed(Glyphs.ascii, slider()), size: (10, 1));
      expect(t.lines.single, contains('-'));
      expect(t.lines.single, contains('#'));
      expect(isAscii(t.lines), isTrue);
    });
  });

  group('toasts', () {
    testTwk('a raised toast draws its bar and icon from the set', (t) async {
      const data = ThemeData.dark;
      Widget toasts(Glyphs glyphs) => Theme(
        data: data.copyWith(glyphs: glyphs),
        child: Box(
          style: data.background,
          child: Overlay(
            child: Builder(
              builder: (context) => KeyBindings({
                's': () {
                  showToast(
                    context,
                    'Saved',
                    style: data.success,
                  );
                  showToast(
                    context,
                    'Warn',
                    style: data.warning,
                  );
                },
              }, child: const SizedBox.expand()),
            ),
          ),
        ),
      );
      await t.pumpWidget(toasts(Glyphs.ascii), size: (20, 10));
      await t.press('s');
      await t.pump(const Duration(milliseconds: 300));
      final screen = t.lines.join('\n');
      expect(screen, contains('| v Saved'));
      expect(screen, contains('| ! Warn'));
      expect(screen, isNot(contains('▌')));
    });
  });

  group('menus', () {
    testTwk('a menu draws its check and submenu marks from the set', (
      t,
    ) async {
      Widget menu(Glyphs glyphs) => Theme(
        data: ThemeData.dark.copyWith(glyphs: glyphs),
        child: const Overlay(
          child: MenuBar(
            look: PanelLook.bordered,
            menus: [
              Menu(
                'View',
                items: [
                  MenuItem('Wrap', checked: true),
                  MenuItem('Numbers', checked: false),
                  Menu('More', items: [MenuItem('Deep')]),
                ],
              ),
            ],
            child: Focus(autofocus: true, child: Text('editor')),
          ),
        ),
      );
      await t.pumpWidget(menu(Glyphs.unicode), size: (24, 8));
      await t.press('f10');
      await t.pump();
      expect(t.lines.join('\n'), allOf(contains('✓ Wrap'), contains('▸')));
      // still open: the set is the theme's, and a new theme repaints
      await t.pumpWidget(menu(Glyphs.ascii), size: (24, 8));
      expect(t.lines.join('\n'), allOf(contains('v Wrap'), contains('>')));
      expect(t.lines.join('\n'), isNot(contains('✓')));
    });
  });
}
