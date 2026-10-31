// Dialogs: the focus taken, kept in and given back; Escape and the barrier
// closing one that is dismissible; one over another; the barrier's blend
// in the emulator's colours, also over a repaint boundary that repaints
// on its own; keys not reaching the widgets under it; no Overlay. The
// raised dialog: its title inside in bold, the barrier from the theme,
// both fading in, Escape hinted.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A [Focus] shown as its [label], after `>` while it has the primary
/// focus and ` ` while not.
final class Field extends StatelessWidget {
  const Field(this.label, {this.autofocus = false, this.onKeyEvent, super.key});

  final String label;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: autofocus,
    onKeyEvent: onKeyEvent,
    debugLabel: label,
    child: _Mark(label),
  );
}

final class _Mark extends StatelessWidget {
  const _Mark(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label');
}

/// [children] one below another at their left edge.
Column column(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

/// The label of the node with the primary focus.
String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// Presses each key of [keys] and pumps a frame after it; the labels
/// focused after each.
Future<List<String?>> tab(TwkTester t, String keys) async => [
  for (final key in keys.split(' '))
    await t.press(key).then((_) => t.pump()).then((_) => focused(t)),
];

/// Presses [key] and pumps a frame.
Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump();
}

/// [content] with `d` opening the dialog [Ask] over it, its result added
/// to [results].
final class Home extends StatelessWidget {
  const Home(this.results, this.content, {this.dismissible = true, super.key});

  final List<Object?> results;
  final Widget content;
  final bool dismissible;

  @override
  Widget build(BuildContext context) => KeyBindings({
    'd': () => unawaited(
      showDialog<String>(
        context,
        (_) => Ask(results, 1),
        dismissible: dismissible,
        fadeIn: Duration.zero,
      ).then(results.add),
    ),
  }, child: content);
}

/// A dialog titled with its [depth], with fields `c` and `e` after it:
/// `x` closes it with `done` and the depth, `d` opens the next one over
/// it, whose result goes to [results].
final class Ask extends StatelessWidget {
  const Ask(this.results, this.depth, {super.key});

  final List<Object?> results;
  final int depth;

  @override
  Widget build(BuildContext context) => Dialog(
    look: PanelLook.bordered,
    title: 'Ask $depth',
    child: KeyBindings({
      'x': () => closeDialog(context, 'done $depth'),
      'd': () => unawaited(
        showDialog<String>(
          context,
          (_) => Ask(results, depth + 1),
          fadeIn: Duration.zero,
        ).then(results.add),
      ),
    }, child: column([Field('c$depth'), Field('e$depth')])),
  );
}

/// The fields `a` and `b`, `a` focused first.
final Column fields = column([
  const Field('a', autofocus: true),
  const Field('b'),
]);

void main() {
  testTwk('a dialog takes the focus, keeps Tab in it and gives the focus '
      'back where it was when closed', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(Overlay(child: Home(results, fields)), size: (20, 7));
    expect(await tab(t, 'tab'), ['b']);
    await press(t, 'd');
    expect(focused(t), 'dialog');
    expect(
      t,
      matchesScreen('''
 a
 b   ┌ Ask 1 ┐
     │  c1   │
     │  e1   │
     └───────┘'''),
    );
    expect(await tab(t, 'tab tab tab shift+tab'), ['c1', 'e1', 'c1', 'e1']);
    await press(t, 'x');
    expect(results, ['done 1']);
    expect(focused(t), 'b');
    expect(t, matchesScreen(' a\n>b'));
  });

  testTwk('a node in the dialog with autofocus takes the focus from it', (
    t,
  ) async {
    await t.pumpWidget(Overlay(child: fields));
    final context = t.binding.focusManager.primaryFocus!.context!;
    unawaited(
      t.clock.run(
        () => showDialog<void>(
          context,
          (_) => column([const Field('c'), const Field('e', autofocus: true)]),
        ),
      ),
    );
    await t.pump();
    expect(focused(t), 'e');
    expect(await tab(t, 'tab tab'), ['c', 'e']);
  });

  testTwk('Escape and a click on the barrier close a dismissible dialog '
      'with null; neither closes one that is not', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(Overlay(child: Home(results, fields)), size: (20, 7));
    await press(t, 'd');
    await press(t, 'escape');
    expect(results, [null]);
    expect(focused(t), 'a');
    await press(t, 'd');
    await t.click(19, 0);
    await t.pump();
    expect(results, [null, null]);
    expect(t, matchesScreen('>a\n b'));

    await t.pumpWidget(
      Overlay(child: Home(results, fields, dismissible: false)),
    );
    await press(t, 'd');
    await press(t, 'escape');
    await t.click(19, 0);
    await t.pump();
    expect(results, [null, null]);
    expect(t, hasTextAt(5, 2, '│  c1   │'));
    await press(t, 'x');
    expect(results, [null, null, 'done 1']);
  });

  testTwk('a dialog shown over another covers it, and closed gives the '
      'focus back to it', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(Overlay(child: Home(results, fields)), size: (20, 7));
    await press(t, 'd');
    expect(await tab(t, 'tab tab'), ['c1', 'e1']);
    await press(t, 'd');
    expect(focused(t), 'dialog');
    expect(t, hasTextAt(5, 1, '┌ Ask 2 ┐'));
    expect(await tab(t, 'tab tab tab'), ['c2', 'e2', 'c2']);
    await press(t, 'escape');
    expect(results, [null]);
    expect(focused(t), 'e1');
    expect(t, hasTextAt(5, 1, '┌ Ask 1 ┐'));
    await press(t, 'x');
    expect(results, [null, 'done 1']);
    expect(focused(t), 'a');
  });

  testTwk('the keys go to the dialog and to the nodes above the overlay, '
      'not to the widgets under the dialog', (t) async {
    final log = <String>[];
    final results = <Object?>[];
    KeyEventResult record(FocusNode node, KeyEvent event) {
      log.add('${node.debugLabel} ${event.char}');
      return KeyEventResult.ignored;
    }

    await t.pumpWidget(
      KeyBindings(
        {'z': () => log.add('app z')},
        child: Overlay(
          child: Home(results, Field('a', autofocus: true, onKeyEvent: record)),
        ),
      ),
    );
    await press(t, 'd');
    await press(t, 'y');
    await press(t, 'z');
    await press(t, 'x');
    await press(t, 'y');
    expect(log, ['a d', 'app z', 'a y']);
  });

  testTwk('the barrier dims the cells under it: their background and text '
      'blended with its colour, default text faint while its colour is not '
      'known; they are as they were once it is gone', (t) async {
    const hot = Style(fg: Color.rgb(255, 255, 255), bg: Color.rgb(200, 100, 0));
    final results = <Object?>[];
    await t.pumpWidget(
      Overlay(
        child: Home(
          results,
          column(const [Text('hi', style: hot), Text('lo')]),
        ),
      ),
      size: (20, 7),
      backgroundRgb: 0x204060,
    );
    expect(
      t,
      styleAt(
        0,
        0,
        allOf(hasFg(const Color.rgb(255, 255, 255)), hasBg(hot.bg!)),
      ),
    );
    await press(t, 'd');
    expect(t, hasTextAt(0, 0, 'hi'));
    // the theme's black at half: 255 half of the way to 0 is 127.5, 128
    expect(
      t,
      styleAt(
        0,
        0,
        allOf(
          hasFg(const Color.rgb(128, 128, 128)),
          hasBg(const Color.rgb(100, 50, 0)),
          isNot(hasAttr(Attr.dim)),
        ),
      ),
    );
    expect(t, hasTextAt(0, 1, 'lo'));
    expect(
      t,
      styleAt(
        0,
        1,
        allOf(
          hasAttr(Attr.dim),
          hasFg(Color.defaultColor),
          hasBg(const Color.rgb(16, 32, 48)),
        ),
      ),
    );
    expect(t, styleAt(19, 6, hasBg(const Color.rgb(16, 32, 48))));
    // the terminal tells its text color: default text blends with it
    await t.input(utf8.encode('\x1b]10;rgb:ffff/ffff/ffff\x1b\\'));
    await t.pump();
    expect(
      t,
      styleAt(
        0,
        1,
        allOf(hasFg(const Color.rgb(128, 128, 128)), isNot(hasAttr(Attr.dim))),
      ),
    );
    await press(t, 'escape');
    expect(
      t,
      styleAt(
        0,
        0,
        allOf(hasFg(const Color.rgb(255, 255, 255)), hasBg(hot.bg!)),
      ),
    );
    expect(t, styleAt(0, 1, allOf(hasFg(Color.defaultColor), hasBg(none))));
  });

  testTwk('what repaints on its own under the barrier is dimmed again', (
    t,
  ) async {
    final bars = GlobalKey<BarsState>();
    final results = <Object?>[];
    await t.pumpWidget(
      Overlay(child: Home(results, column([Bars(key: bars)]))),
      size: (20, 7),
    );
    await press(t, 'd');
    expect(t, hasTextAt(0, 0, '█ '));
    expect(t, styleAt(1, 0, allOf(hasBg(dimBlue), hasFg(dimGreen))));
    bars.currentState!.grow();
    await t.pump();
    expect(t, hasTextAt(0, 0, '██ '));
    expect(t, styleAt(1, 0, allOf(hasBg(dimBlue), hasFg(dimGreen))));
    expect(t, styleAt(2, 0, hasBg(dimBlue)));
  });

  testTwk('a dialog completes with null when it leaves the tree with its '
      'overlay', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(Overlay(child: Home(results, fields)));
    await press(t, 'd');
    await t.pumpWidget(const Text('gone'));
    expect(results, [null]);
    expect(focused(t), 'root');
  });

  testTwk('showDialog without an Overlay above says where to place one; '
      'closeDialog outside a dialog that it is in none', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(SizedBox(key: key, width: 1, height: 1));
    final context = key.currentContext!;
    expect(
      () => showDialog<void>(context, (_) => const Text('?')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'showDialog: no Overlay above SizedBox: place an Overlay above it, '
              'as around the whole app: Overlay(child: …)',
        ),
      ),
    );
    expect(
      () => closeDialog(context),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'closeDialog: SizedBox is in no dialog: showDialog shows one',
        ),
      ),
    );
  });

  group('raised', () {
    const ms = Duration(milliseconds: 1);

    /// Opens a dialog titled Delete on `d`, in [theme] with a background.
    Widget asking(ThemeData theme, List<String> keys) => Theme(
      data: theme,
      child: Box(
        style: theme.background,
        child: Overlay(
          child: Builder(
            builder: (context) => KeyBindings({
              'd': () => unawaited(
                showDialog<void>(
                  context,
                  (_) => const Dialog(
                    title: 'Delete',
                    child: Text('Delete 3 files?'),
                  ),
                ),
              ),
            }, child: const Field('under', autofocus: true)),
          ),
        ),
      ),
    );

    testTwk('a dialog is a raised panel: no outline, its title inside in '
        'bold, a cell of room and the padding around', (t) async {
      const theme = ThemeData.dark;
      await t.pumpWidget(asking(theme, []), size: (21, 7));
      await press(t, 'd');
      await t.pump(ms * 200);
      expect(t.lines.sublist(1, 6), [
        '',
        '   Delete',
        '   Delete 3 files?',
        '',
        '',
      ]);
      expect(
        t,
        styleAt(3, 2, allOf(hasAttr(Attr.bold), hasFg(theme.text.fg!))),
      );
      expect(t, styleAt(3, 3, isNot(hasAttr(Attr.bold))));
      expect(t, styleAt(1, 1, hasBg(theme.surface.bg!)));
      expect(t, styleAt(19, 4, hasBg(theme.surface.bg!)));
    });

    testTwk('the barrier is the shade of the theme, lighter on a light theme; '
        'it and the dialog fade in over 160 ms', (t) async {
      const theme = ThemeData.light;
      Color shaded(Color c, int alpha) => Color.rgb(
        (c.r * (255 - alpha) / 255).round(),
        (c.g * (255 - alpha) / 255).round(),
        (c.b * (255 - alpha) / 255).round(),
      );
      final background = theme.background.bg!;
      await t.pumpWidget(asking(theme, []), size: (21, 7));
      await press(t, 'd');
      expect(t, styleAt(0, 0, hasBg(background)));
      expect(t, styleAt(3, 2, hasBg(background)));
      await t.pump(ms * 60);
      expect(t, styleAt(0, 0, isNot(hasBg(background))));
      expect(t, styleAt(0, 0, isNot(hasBg(shaded(background, 71)))));
      await t.pump(ms * 120);
      await t.pump();
      expect(t, styleAt(0, 0, hasBg(shaded(background, 71))));
      expect(t, styleAt(3, 2, hasBg(theme.surface.bg!)));
    });

    testTwk('Escape closes it, bound with the hint close', (t) async {
      await t.pumpWidget(asking(ThemeData.dark, []), size: (21, 7));
      await press(t, 'd');
      expect(
        [for (final k in t.binding.focusManager.activeKeys) '$k'],
        contains('escape close'),
      );
      await press(t, 'escape');
      await t.pump(ms * 200);
      expect(t.lines.sublist(1), everyElement(''));
      expect(focused(t), 'under');
    });

    testTwk('the bordered look titles the top edge of its border', (
      t,
    ) async {
      await t.pumpWidget(
        const Dialog(
          look: PanelLook.bordered,
          title: 'Delete',
          child: Text('Sure?'),
        ),
        size: (12, 3),
      );
      expect(t, matchesScreen('┌ Delete ──┐\n│ Sure?    │\n└──────────┘'));
    });
  });

  testTwk('a dialog whose child takes the width keeps to 72 columns, or '
      'the screen where narrower; maxWidth sets another, null none', (
    t,
  ) async {
    const wide = Row(children: [Expanded(child: Text('wide'))]);
    Widget app(Dialog dialog) => Overlay(
      child: Builder(
        builder: (context) => KeyBindings({
          'd': () => unawaited(
            showDialog<void>(context, (_) => dialog, fadeIn: Duration.zero),
          ),
        }, child: const Focus(autofocus: true, child: Text('app'))),
      ),
    );
    Future<int> borderWidth(Dialog dialog, int width) async {
      await t.pumpWidget(app(dialog), size: (width, 10));
      await press(t, 'd');
      final top = t.lines.firstWhere((l) => l.contains('┌'));
      await press(t, 'escape');
      return top.lastIndexOf('┐') - top.indexOf('┌') + 1;
    }

    const bordered = PanelLook.bordered;
    expect(
      await borderWidth(const Dialog(look: bordered, child: wide), 100),
      72,
    );
    expect(
      await borderWidth(const Dialog(look: bordered, child: wide), 40),
      40,
    );
    expect(
      await borderWidth(
        const Dialog(look: bordered, maxWidth: 30, child: wide),
        100,
      ),
      30,
    );
    expect(
      await borderWidth(
        const Dialog(look: bordered, maxWidth: null, child: wide),
        100,
      ),
      100,
    );
  });
}

/// No color: the terminal's default.
const Color none = Color.defaultColor;

/// Green and blue, and them blended half and half with black.
const green = Color.rgb(0, 200, 0);
const blue = Color.rgb(0, 0, 200);
const dimGreen = Color.rgb(0, 100, 0);
const dimBlue = Color.rgb(0, 0, 100);

/// A sparkline of full bars, a repaint boundary: [BarsState.grow] adds one.
final class Bars extends StatefulWidget {
  const Bars({super.key});

  @override
  State<Bars> createState() => BarsState();
}

final class BarsState extends State<Bars> {
  var _data = const [8.0];

  void grow() => setState(() => _data = [..._data, 8]);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 6,
    child: Sparkline(
      data: _data,
      max: 8,
      fromRight: false,
      style: const Style(fg: green, bg: blue),
    ),
  );
}
