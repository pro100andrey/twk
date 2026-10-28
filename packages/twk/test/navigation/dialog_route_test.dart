// Dialogs as routes: with a Navigator above, showDialog pushes a route
// that Navigator.pop and the back key close; the focus given back; one
// under another taken off; the root navigator or the nearest; the page
// under it dimmed, also where it repaints on its own.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A [Focus] shown as its [label], after `>` while it has the primary
/// focus and ` ` while not.
final class Field extends StatelessWidget {
  const Field(this.label, {this.autofocus = false, super.key});

  final String label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: autofocus,
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

/// Presses [key] and pumps a frame.
Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump();
}

/// [content] with `d` showing the dialog [Ask] over it, `r` the same on
/// the nearest navigator alone; their results go to [results].
final class Home extends StatelessWidget {
  const Home(
    this.results,
    this.content, {
    this.dismissible = true,
    this.asked,
    super.key,
  });

  final List<Object?> results;
  final Widget content;
  final bool dismissible;
  final List<BuildContext>? asked;

  @override
  Widget build(BuildContext context) => KeyBindings({
    'd': () => unawaited(
      showDialog<String>(
        context,
        (_) => Ask(results, 1, asked: asked),
        dismissible: dismissible,
        fadeIn: Duration.zero,
      ).then(results.add),
    ),
    'r': () => unawaited(
      showDialog<String>(
        context,
        (_) => Ask(results, 1, asked: asked),
        useRootNavigator: false,
        fadeIn: Duration.zero,
      ).then(results.add),
    ),
  }, child: content);
}

/// A dialog titled with its [depth], with fields `c` and `e` after it: `x`
/// pops it with `done` and the depth, `d` shows the next one over it,
/// whose result goes to [results]; its context goes to [asked].
final class Ask extends StatelessWidget {
  const Ask(this.results, this.depth, {this.asked, super.key});

  final List<Object?> results;
  final int depth;
  final List<BuildContext>? asked;

  @override
  Widget build(BuildContext context) {
    asked?.add(context);
    return Dialog(
      look: PanelLook.bordered,
      title: 'Ask $depth',
      child: KeyBindings({
        'x': () => Navigator.pop(context, 'done $depth'),
        'd': () => unawaited(
          showDialog<String>(
            context,
            (_) => Ask(results, depth + 1, asked: asked),
            fadeIn: Duration.zero,
          ).then(results.add),
        ),
      }, child: column([Field('c$depth'), Field('e$depth')])),
    );
  }
}

/// The fields `a` and `b`, `a` focused first.
final Column fields = column([
  const Field('a', autofocus: true),
  const Field('b'),
]);

void main() {
  testTwk('with a Navigator above, a dialog is a route on it: '
      'Navigator.pop closes it with a result, and the focus goes back '
      'where it was', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(home: Home(results, fields)),
      size: (20, 7),
    );
    await press(t, 'tab');
    expect(focused(t), 'b');
    await press(t, 'd');
    expect(focused(t), 'dialog');
    final context = t.binding.focusManager.primaryFocus!.context!;
    expect(Navigator.canPop(context), isTrue);
    expect(Route.of(context).opaque, isFalse);
    expect(
      t,
      matchesScreen('''
 a
 b   ┌ Ask 1 ┐
     │  c1   │
     │  e1   │
     └───────┘'''),
    );
    expect(t, styleAt(1, 0, hasAttr(Attr.dim)));
    await press(t, 'tab');
    await press(t, 'x');
    expect(results, ['done 1']);
    expect(focused(t), 'b');
    expect(Navigator.canPop(context), isFalse);
    expect(t, matchesScreen(' a\n>b'));
  });

  testTwk("the navigator's back key closes a dialog that is dismissible; "
      'one that is not lets it go on past the navigator', (t) async {
    final results = <Object?>[];
    final log = <String>[];
    Widget app({required bool dismissible}) => KeyBindings(
      {'q': () => log.add('app q')},
      child: Navigator(
        backKey: 'q',
        home: Home(results, fields, dismissible: dismissible),
      ),
    );
    await t.pumpWidget(app(dismissible: true), size: (20, 7));
    await press(t, 'd');
    await press(t, 'q');
    expect(results, [null]);
    expect(log, isEmpty);
    expect(focused(t), 'a');

    await t.pumpWidget(app(dismissible: false));
    await press(t, 'd');
    await press(t, 'q');
    await press(t, 'escape');
    expect(results, [null]);
    expect(log, ['app q']);
    expect(t, hasTextAt(5, 2, '│  c1   │'));
    await press(t, 'x');
    expect(results, [null, 'done 1']);
  });

  testTwk('closeDialog takes a dialog under another off, which keeps the '
      'focus; that one closed gives it back to the page', (t) async {
    final results = <Object?>[];
    final asked = <BuildContext>[];
    await t.pumpWidget(
      Navigator(home: Home(results, fields, asked: asked)),
      size: (20, 7),
    );
    await press(t, 'tab');
    await press(t, 'd');
    await press(t, 'tab');
    await press(t, 'd');
    await press(t, 'tab');
    expect(focused(t), 'c2');
    closeDialog(asked.first, 'under');
    await t.pump();
    expect(results, ['under']);
    expect(focused(t), 'c2');
    expect(t, hasTextAt(5, 1, '┌ Ask 2 ┐'));
    await press(t, 'escape');
    expect(results, ['under', null]);
    expect(focused(t), 'b');
    expect(t, matchesScreen(' a\n>b'));
  });

  testTwk('a dialog from a nested navigator is a route on the root one, '
      'over all of it; with useRootNavigator false on the nested one', (
    t,
  ) async {
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        home: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 8, child: Text('left')),
            Expanded(
              child: Navigator(home: Home(results, fields)),
            ),
          ],
        ),
      ),
      size: (24, 7),
    );
    await press(t, 'd');
    expect(
      t,
      matchesScreen('''
left     a
       ┌ Ask 1 ┐
       │  c1   │
       │  e1   │
       └───────┘'''),
    );
    expect(t, styleAt(0, 0, hasAttr(Attr.dim)));
    await press(t, 'x');
    await press(t, 'r');
    expect(
      t,
      matchesScreen('''
left     a
         b ┌ Ask 1 ┐
           │  c1   │
           │  e1   │
           └───────┘'''),
    );
    expect(t, styleAt(0, 0, isNot(hasAttr(Attr.dim))));
    expect(t, styleAt(8, 0, hasAttr(Attr.dim)));
    await press(t, 'x');
    expect(results, ['done 1', 'done 1']);
    expect(focused(t), 'a');
  });

  testTwk('what repaints on its own on the page under a dialog route is '
      'dimmed again', (t) async {
    final bars = GlobalKey<BarsState>();
    final results = <Object?>[];
    await t.pumpWidget(
      Navigator(
        home: Home(results, column([Bars(key: bars)])),
      ),
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

  testTwk('a click on the barrier of a dialog under a route that leaves it '
      'uncovered takes the dialog off, the route staying; a PopScope in it '
      'that cannot pop keeps it and is told', (t) async {
    final navigator = GlobalKey<NavigatorState>();
    final told = <bool>[];
    final canPop = ValueNotifier(false);
    late BuildContext home;
    await t.pumpWidget(
      Navigator(
        key: navigator,
        home: Builder(
          builder: (context) {
            home = context;
            return const Text('home');
          },
        ),
      ),
      size: (20, 6),
    );
    final result = showDialog<String>(
      home,
      (_) => ValueListenableBuilder(
        valueListenable: canPop,
        builder: (_, can, _) => PopScope<Object?>(
          canPop: can,
          onPopInvoked: told.add,
          child: const Text('dialog'),
        ),
      ),
      fadeIn: Duration.zero,
    );
    await t.pump();
    unawaited(navigator.currentState!.push(_Note('note')));
    await t.pump();
    expect(t, containsLine(startsWith('note')));
    await t.click(10, 5);
    await t.pump();
    expect(told, [false]);
    expect(t, containsLine(contains('dialog')));
    canPop.value = true;
    await t.pump();
    await t.click(10, 5);
    await t.pump();
    expect(await result, isNull);
    expect(t, isNot(containsLine(contains('dialog'))));
    expect(t, containsLine(startsWith('note')));
  });
}

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
      style: const Style(fg: green, bg: blue),
    ),
  );
}

/// A route that is not opaque: [text] at the top left over the routes
/// under it, which the mouse reaches elsewhere.
final class _Note extends Route<void> {
  _Note(this.text);

  final String text;

  @override
  bool get opaque => false;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topLeft, child: Text(text));
}
