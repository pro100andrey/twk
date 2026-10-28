// ExpansionTile and Accordion: the header's keys (Enter and Space toggle,
// Right expands, Left collapses) and click; its look at rest, expanded,
// focused and under the mouse; the controller, and onExpansionChanged
// told of each change; the child built only while shown, unfolding and
// folding a row at a time on the app's clock, at once with no duration or
// outside an app; a focus inside a section that collapses given to its
// header; the screen reader's line; the accordion's one open section and
// Up and Down between its headers.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'view.dart';

const ThemeData theme = ThemeData.dark;

/// [children] at the top left, one below another, in the dark theme.
Widget dark(List<Widget> children) => Theme(
  data: theme,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  ),
);

/// A body of [rows] lines, `1` to [rows].
Widget lines(int rows) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [for (var i = 1; i <= rows; i++) Text('line $i')],
);

/// A tile titled [title] with a body of [rows] lines that folds at once.
ExpansionTile tile(
  String title, {
  int rows = 1,
  bool initiallyExpanded = false,
  ExpansionController? controller,
  FocusNode? focusNode,
  void Function(bool expanded)? onExpansionChanged,
  Duration duration = Duration.zero,
  Widget? child,
}) => ExpansionTile(
  title: Text(title),
  initiallyExpanded: initiallyExpanded,
  controller: controller,
  focusNode: focusNode,
  onExpansionChanged: onExpansionChanged,
  duration: duration,
  child: child ?? lines(rows),
);

/// Asserts that the app asks for no more frames and starts no timer.
Future<void> expectIdle(TwkTester t) async {
  expect(t.clock.pendingTimers, 0);
  final written = t.frames.length;
  await t.pump(const Duration(seconds: 10));
  expect(t.frames, hasLength(written));
}

/// Counts the times it is built, and whether its state is mounted.
final class Probe extends StatefulWidget {
  const Probe({super.key});

  static var builds = 0;
  static var mounted = 0;

  @override
  State<Probe> createState() => _ProbeState();
}

final class _ProbeState extends State<Probe> {
  @override
  void initState() {
    super.initState();
    Probe.mounted++;
  }

  @override
  void dispose() {
    Probe.mounted--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Probe.builds++;
    return const Text('probe');
  }
}

void main() {
  testTwk('collapsed it shows its header alone; Enter and Space toggle '
      'it, Right expands and Left collapses, each told once', (t) async {
    final told = <bool>[];
    final node = FocusNode();
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark([
        ExpansionTile(
          title: const Text('Security'),
          focusNode: node,
          onExpansionChanged: told.add,
          duration: Duration.zero,
          child: lines(2),
        ),
        const Text('after'),
      ]),
      size: (20, 4),
    );
    expect(t.lines, ['▶ Security', 'after', '', '']);
    await t.press('tab');
    await t.press('enter');
    await t.pump();
    expect(t.lines, ['▼ Security', '  line 1', '  line 2', 'after']);
    await t.press('space');
    await t.pump();
    expect(t.lines.first, '▶ Security');
    expect(t.lines[1], 'after');
    await t.press('right');
    await t.pump();
    await t.press('right');
    await t.pump();
    expect(t.lines[1], '  line 1');
    await t.press('left');
    await t.pump();
    await t.press('left');
    await t.pump();
    expect(t.lines[1], 'after');
    expect(told, [true, false, true, false]);
  });

  testTwk('a click on the header toggles it and gives it the focus', (
    t,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await t.pumpWidget(
      dark([tile('Network', focusNode: node, rows: 2)]),
      size: (20, 4),
    );
    await t.click(4, 0);
    await t.pump();
    expect(node.hasPrimaryFocus, isTrue);
    expect(t.lines.take(3), ['▼ Network', '  line 1', '  line 2']);
    await t.click(4, 0);
    await t.pump();
    expect(t.lines.take(2), ['▶ Network', '']);
    // a click in the body is not on the header
    await t.click(4, 0);
    await t.pump();
    await t.click(4, 1);
    await t.pump();
    expect(t.lines[1], '  line 1');
  });

  testTwk('the marker muted while collapsed, primary while expanded; the '
      'header on the selection while focused, on the surface under the '
      'mouse; its styles over the text', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final c = ExpansionController();
    addTearDown(c.dispose);
    await t.pumpWidget(
      dark([
        ExpansionTile(
          title: const Text('Logs'),
          trailing: const Text('12'),
          controller: c,
          focusNode: node,
          duration: Duration.zero,
          headerStyle: const Style(attrs: Attr.italic),
          expandedHeaderStyle: const Style(attrs: Attr.bold),
          child: const Text('body'),
        ),
        const SizedBox(height: 2),
      ]),
      size: (12, 4),
    );
    expect(t.lines.first, '▶ Logs    12');
    expect(t, styleAt(0, 0, hasFg(theme.muted.fg!)));
    expect(
      t,
      styleAt(2, 0, allOf(hasAttr(Attr.italic), isNot(hasAttr(Attr.bold)))),
    );
    expect(t, styleAt(2, 0, isNot(hasBg(theme.hover.bg!))));
    c.expand();
    await t.pump();
    expect(t, styleAt(0, 0, hasFg(theme.primary.fg!)));
    expect(t, styleAt(2, 0, allOf(hasAttr(Attr.italic), hasAttr(Attr.bold))));
    await t.mouse(MouseKind.move, 3, 0);
    await t.pump();
    for (final x in [2, 7, 11]) {
      expect(t, styleAt(x, 0, hasBg(theme.hover.bg!)));
    }
    expect(t, styleAt(2, 1, isNot(hasBg(theme.hover.bg!))));
    await t.mouse(MouseKind.move, 3, 3);
    await t.pump();
    expect(t, styleAt(2, 0, isNot(hasBg(theme.surface.bg!))));
    node.requestFocus();
    await t.pump();
    for (final x in [0, 2, 7, 11]) {
      expect(t, styleAt(x, 0, hasBg(theme.selection.bg!)));
    }
  });

  testTwk('a subtitle below the title, muted', (t) async {
    await t.pumpWidget(
      dark([
        const ExpansionTile(
          title: Text('Disk'),
          subtitle: Text('3 volumes'),
          child: Text('body'),
        ),
      ]),
      size: (14, 2),
    );
    expect(t.lines, ['▶ Disk', '  3 volumes']);
    expect(t, styleAt(2, 1, hasFg(theme.muted.fg!)));
  });

  testTwk('the controller expands and collapses it, telling '
      'onExpansionChanged; another controller is followed as it stands, '
      'nobody told', (t) async {
    final a = ExpansionController();
    final b = ExpansionController(expanded: true);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final told = <bool>[];
    final which = ValueNotifier(a);
    await t.pumpWidget(
      ValueListenableBuilder(
        valueListenable: which,
        builder: (_, c, _) =>
            dark([tile('Info', controller: c, onExpansionChanged: told.add)]),
      ),
      size: (12, 2),
    );
    expect(t.lines, ['▶ Info', '']);
    a.expand();
    await t.pump();
    expect(t.lines, ['▼ Info', '  line 1']);
    a.toggle();
    await t.pump();
    expect(t.lines, ['▶ Info', '']);
    expect(a.expanded, isFalse);
    which.value = b;
    await t.pump();
    expect(t.lines, ['▼ Info', '  line 1']);
    a.expand();
    await t.pump();
    expect(told, [true, false]);
    await t.press('tab');
    await t.press('enter');
    await t.pump();
    expect(b.expanded, isFalse);
    expect(told, [true, false, false]);
  });

  testTwk('initiallyExpanded starts it expanded, at once', (t) async {
    await t.pumpWidget(
      dark([
        tile(
          'Open',
          initiallyExpanded: true,
          duration: const Duration(seconds: 1),
        ),
      ]),
      size: (12, 2),
    );
    expect(t.lines, ['▼ Open', '  line 1']);
  });

  testTwk('it unfolds a row at a time on the app clock, and folds back up, '
      'the child built only while it shows and as it folds; then it asks '
      'for no frame', (t) async {
    final c = ExpansionController();
    addTearDown(c.dispose);
    Probe.builds = 0;
    Probe.mounted = 0;
    await t.pumpWidget(
      dark([
        ExpansionTile(
          title: const Text('Log'),
          controller: c,
          duration: const Duration(milliseconds: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const Probe(), lines(3)],
          ),
        ),
        const Text('end'),
      ]),
      size: (12, 6),
      maxFps: 100,
    );
    expect(Probe.mounted, 0);
    expect(Probe.builds, 0);
    c.expand();
    final open = <int>[];
    for (var i = 0; i < 5; i++) {
      await t.pump();
      open.add(t.lines.indexOf('end'));
    }
    // the row of `end`: below the header and the rows shown, fast at
    // first, as the run eases out
    expect(open, [3, 4, 5, 5, 5]);
    expect(t.lines, [
      '▼ Log',
      '  probe',
      '  line 1',
      '  line 2',
      '  line 3',
      'end',
    ]);
    expect(Probe.mounted, 1);
    await expectIdle(t);
    c.collapse();
    final shut = <List<String>>[];
    for (var i = 0; i < 5; i++) {
      await t.pump();
      shut.add(t.lines);
    }
    expect([for (final s in shut) s.indexOf('end')], [5, 4, 3, 1, 1]);
    // the marker at once; the child shows as it folds, its top rows
    // first
    expect(shut[0].first, '▶ Log');
    expect(shut[2].take(3), ['▶ Log', '  probe', '  line 1']);
    expect(Probe.mounted, 0);
    await expectIdle(t);
  });

  testTwk('with a duration of zero it unfolds at once', (t) async {
    final c = ExpansionController();
    addTearDown(c.dispose);
    await t.pumpWidget(
      dark([tile('Now', controller: c, rows: 3), const Text('end')]),
      size: (12, 5),
      maxFps: 100,
    );
    c.expand();
    await t.pump();
    expect(t.lines, ['▼ Now', '  line 1', '  line 2', '  line 3', 'end']);
    await expectIdle(t);
  });

  test('outside an app it is shown as it stands, at once', () {
    final c = ExpansionController();
    addTearDown(c.dispose);
    final view = View(12, 4)
      ..pump(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExpansionTile(
              title: const Text('Plain'),
              controller: c,
              child: lines(2),
            ),
            const Text('end'),
          ],
        ),
      );
    expect(view.rows(), ['▶ Plain', 'end', '', '']);
    c.expand();
    view.frame();
    expect(view.rows(), ['▼ Plain', '  line 1', '  line 2', 'end']);
    c.collapse();
    view.frame();
    expect(view.rows(), ['▶ Plain', 'end', '', '']);
  });

  testTwk('a focus in the section as it collapses goes to its header; '
      'Tab passes a section that folds by', (t) async {
    final header = FocusNode(debugLabel: 'header');
    final inside = FocusNode(debugLabel: 'inside');
    final after = FocusNode(debugLabel: 'after');
    addTearDown(header.dispose);
    addTearDown(inside.dispose);
    addTearDown(after.dispose);
    final c = ExpansionController(expanded: true);
    addTearDown(c.dispose);
    await t.pumpWidget(
      dark([
        ExpansionTile(
          title: const Text('Form'),
          controller: c,
          focusNode: header,
          duration: const Duration(milliseconds: 40),
          child: Button('OK', focusNode: inside, onPressed: () {}),
        ),
        Button('Next', focusNode: after, onPressed: () {}),
      ]),
      size: (12, 3),
      maxFps: 100,
    );
    inside.requestFocus();
    await t.pump();
    expect(inside.hasPrimaryFocus, isTrue);
    c.collapse();
    await t.pump();
    expect(header.hasPrimaryFocus, isTrue);
    // still folding: Tab goes past it
    await t.press('tab');
    await t.pump();
    expect(after.hasPrimaryFocus, isTrue);
    await t.pump(const Duration(milliseconds: 100));
    // expanded, the section's nodes take the focus again
    c.expand();
    header.requestFocus();
    await t.pump(const Duration(milliseconds: 100));
    await t.press('tab');
    await t.pump();
    expect(inside.hasPrimaryFocus, isTrue);
  });

  testTwk('a screen reader reads the header as a button, expanded or '
      'collapsed, without its marker', (t) async {
    final c = ExpansionController();
    addTearDown(c.dispose);
    await t.pumpWidget(
      dark([tile('Security Settings', controller: c)]),
      size: (24, 2),
    );
    expect(
      t.binding.semantics.lines,
      contains('button Security Settings, collapsed'),
    );
    c.expand();
    await t.pump();
    expect(
      t.binding.semantics.lines,
      contains('button Security Settings, expanded'),
    );
  });

  group('Accordion', () {
    testTwk('opening one closes the one open; initiallyExpanded opens one '
        'at the start', (t) async {
      final told = <String>[];
      await t.pumpWidget(
        dark([
          Accordion(
            initiallyExpanded: 1,
            children: [
              for (final name in ['A', 'B', 'C'])
                tile(
                  name,
                  onExpansionChanged: (e) => told.add('$name $e'),
                ),
            ],
          ),
        ]),
        size: (12, 5),
      );
      expect(t.lines, ['▶ A', '▼ B', '  line 1', '▶ C', '']);
      await t.click(2, 3);
      await t.pump();
      expect(t.lines, ['▶ A', '▶ B', '▼ C', '  line 1', '']);
      expect(told, unorderedEquals(['C true', 'B false']));
      await t.click(2, 2);
      await t.pump();
      expect(t.lines, ['▶ A', '▶ B', '▶ C', '', '']);
    });

    testTwk('without initiallyExpanded the first tile that says so opens; '
        'with allowMultiple each that says so, and opening one leaves the '
        'others', (t) async {
      await t.pumpWidget(
        dark([
          Accordion(
            children: [
              tile('A'),
              tile('B', initiallyExpanded: true),
              tile('C', initiallyExpanded: true),
            ],
          ),
        ]),
        size: (12, 5),
      );
      expect(t.lines, ['▶ A', '▼ B', '  line 1', '▶ C', '']);
      await t.pumpWidget(
        dark([
          Accordion(
            key: const ValueKey('multiple'),
            allowMultiple: true,
            children: [
              tile('A'),
              tile('B', initiallyExpanded: true),
              tile('C', initiallyExpanded: true),
            ],
          ),
        ]),
        size: (12, 5),
      );
      expect(t.lines, ['▶ A', '▼ B', '  line 1', '▼ C', '  line 1']);
      await t.click(2, 0);
      await t.pump();
      expect(t.lines, ['▼ A', '  line 1', '▼ B', '  line 1', '▼ C']);
    });

    testTwk('a tile with a controller of its own keeps it, collapsed by '
        'the accordion as the others', (t) async {
      final c = ExpansionController(expanded: true);
      addTearDown(c.dispose);
      await t.pumpWidget(
        dark([
          Accordion(
            children: [
              tile('A', controller: c),
              tile('B'),
            ],
          ),
        ]),
        size: (12, 4),
      );
      expect(t.lines, ['▼ A', '  line 1', '▶ B', '']);
      await t.click(2, 2);
      await t.pump();
      expect(c.expanded, isFalse);
      expect(t.lines, ['▶ A', '▼ B', '  line 1', '']);
      c.expand();
      await t.pump();
      expect(t.lines, ['▼ A', '  line 1', '▶ B', '']);
    });

    testTwk('Up and Down move between the headers, and stop at the ends', (
      t,
    ) async {
      final first = FocusNode(debugLabel: 'first');
      addTearDown(first.dispose);
      await t.pumpWidget(
        dark([
          Accordion(
            children: [
              tile('A', focusNode: first),
              tile('B', rows: 2),
              tile('C'),
            ],
          ),
        ]),
        size: (12, 5),
      );
      first.requestFocus();
      await t.pump();
      await t.press('down');
      await t.press('enter');
      await t.pump();
      expect(t.lines, ['▶ A', '▼ B', '  line 1', '  line 2', '▶ C']);
      await t.press('down');
      await t.press('down');
      await t.press('enter');
      await t.pump();
      expect(t.lines, ['▶ A', '▶ B', '▼ C', '  line 1', '']);
      await t.press('up');
      await t.press('up');
      await t.press('up');
      await t.pump();
      expect(first.hasPrimaryFocus, isTrue);
    });

    testTwk('a tile in a section of another is no tile of the accordion', (
      t,
    ) async {
      await t.pumpWidget(
        dark([
          Accordion(
            initiallyExpanded: 0,
            children: [
              ExpansionTile(
                title: const Text('Outer'),
                duration: Duration.zero,
                child: tile('Inner'),
              ),
              tile('Next'),
            ],
          ),
        ]),
        size: (14, 4),
      );
      expect(t.lines, ['▼ Outer', '  ▶ Inner', '▶ Next', '']);
      await t.click(4, 1);
      await t.pump();
      expect(t.lines, ['▼ Outer', '  ▼ Inner', '    line 1', '▶ Next']);
    });
  });
}
