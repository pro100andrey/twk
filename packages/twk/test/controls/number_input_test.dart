// NumberInput: the number shown with its decimals; Up, Down, Page Up and
// Page Down that step it within min and max; text typed taken on Enter and
// as the focus leaves, rounded, clamped or given up when it is no number,
// shown in the error style meanwhile and put back by Escape; the mouse on
// the field, on the arrows and the wheel; a disabled input; an input in a
// FormField.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// Presses each key of [keys], pumping a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pump();
}

Future<void> mouse(TwkTester t, MouseKind kind, int x, [int y = 0]) async {
  await t.mouse(kind, x, y);
  await t.pump();
}

/// A [NumberInput] whose value [value] holds, 10 cells wide, above a node
/// `next`; [changes] gets each value it gives, [entered] each Enter that
/// goes on to the nodes above.
Widget input(
  ValueNotifier<double> value, {
  List<double>? changes,
  List<String>? entered,
  double? min,
  double? max,
  double step = 1,
  int decimals = 0,
  bool enabled = true,
  bool autofocus = false,
}) {
  final node = FocusNode(debugLabel: 'input');
  addTearDown(node.dispose);
  return KeyBindings(
    {'enter': () => entered?.add('enter')},
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 10,
          child: ValueListenableBuilder<double>(
            valueListenable: value,
            builder: (context, v, _) => NumberInput(
              value: v,
              min: min,
              max: max,
              step: step,
              decimals: decimals,
              onChanged: enabled
                  ? (next) {
                      changes?.add(next);
                      value.value = next;
                    }
                  : null,
              focusNode: node,
              autofocus: autofocus,
            ),
          ),
        ),
        const Focus(debugLabel: 'next', child: Text('next')),
      ],
    ),
  );
}

void main() {
  testTwk("a field without a box: sunk in the theme's well, and on the "
      "terminal's colors, whose well is the background, a line under it in "
      "the border's color; a form's field in a bordered dialog too", (t) async {
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 12,
            child: NumberInput(value: 1, onChanged: (_) {}),
          ),
        ),
      ),
      size: (20, 1),
    );
    expect(t, styleAt(3, 0, hasBg(ThemeData.dark.well.bg!)));
    await t.pumpWidget(
      Theme.terminal(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 30,
            child: Box(
              border: const Border.all(),
              child: Form(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('name'),
                    TextFormField(placeholder: 'who'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      size: (30, 4),
    );
    expect(t, styleAt(10, 2, hasAttr(Attr.underline)));
    expect(t.cell(10, 2).ul, const Color.indexed(240).value);
  });

  testTwk('shows the value with its decimals, rounded, before ▴▾, muted '
      'at rest; while it has the focus ▴▾ in the primary color and the '
      'field on the selection color', (t) async {
    final value = ValueNotifier<double>(3.14159);
    addTearDown(value.dispose);
    await t.pumpWidget(
      Theme(data: ThemeData.dark, child: input(value, decimals: 2)),
      size: (20, 3),
    );
    expect(t.lines, ['3.14    ▴▾', 'next', '']);
    expect(t.cell(8, 0).fg, ThemeData.dark.muted.fg);
    expect(t.cell(9, 0).fg, ThemeData.dark.muted.fg);
    expect(t.cell(0, 0).bg, ThemeData.dark.well.bg);
    await press(t, 'tab');
    expect(t.cell(8, 0).fg, ThemeData.dark.primary.fg);
    expect(t.cell(0, 0).bg, ThemeData.dark.selection.bg);
    expect(t.cell(6, 0).bg, ThemeData.dark.selection.bg);
    await press(t, 'tab');
    expect(t.cell(8, 0).fg, ThemeData.dark.muted.fg);
    expect(t.cell(0, 0).bg, ThemeData.dark.well.bg);
    value.value = -0.001;
    await t.pump();
    expect(t.lines.first, '0.00    ▴▾');
    value.value = 2.5;
    await t.pumpWidget(Theme(data: ThemeData.dark, child: input(value)));
    expect(t.lines.first, '3       ▴▾');
  });

  testTwk('focusedStyle and arrowStyle give a plain look: the field '
      'on the surface while it has the focus, ▴▾ always primary', (t) async {
    const dark = ThemeData.dark;
    await t.pumpWidget(
      Theme(
        data: dark,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 10,
            child: NumberInput(
              value: 3,
              onChanged: (_) {},
              focusedStyle: const Style(),
              arrowStyle: dark.primary,
            ),
          ),
        ),
      ),
      size: (20, 1),
    );
    expect(t.cell(8, 0).fg, dark.primary.fg);
    await press(t, 'tab');
    expect(t.cell(8, 0).fg, dark.primary.fg);
    expect(t.cell(0, 0).bg, dark.well.bg);
  });

  testTwk('Enter and the focus leaving take nothing while nothing is '
      'typed', (t) async {
    final value = ValueNotifier<double>(3.14159);
    addTearDown(value.dispose);
    final changes = <double>[];
    await t.pumpWidget(
      input(value, changes: changes, decimals: 2, autofocus: true),
      size: (20, 3),
    );
    await press(t, 'enter tab');
    expect(focused(t), 'next');
    expect(changes, isEmpty);
    expect(value.value, 3.14159);
  });

  testTwk('taken out of the tree with the focus and text typed, it takes '
      'nothing', (t) async {
    final changes = <double>[];
    final shown = ValueNotifier<bool>(true);
    addTearDown(shown.dispose);
    await t.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, on, _) => on
            ? NumberInput(value: 1, onChanged: changes.add, autofocus: true)
            : const Text('gone'),
      ),
      size: (20, 3),
    );
    await type(t, '2');
    shown.value = false;
    await t.pump();
    expect(t.lines, contains('gone'));
    expect(changes, isEmpty);
  });

  testTwk('moved in the tree by a global key with text typed, it takes the '
      'text as the focus leaves it', (t) async {
    final changes = <double>[];
    final boxed = ValueNotifier<bool>(false);
    addTearDown(boxed.dispose);
    final key = GlobalKey();
    final node = FocusNode(debugLabel: 'input');
    addTearDown(node.dispose);
    await t.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: boxed,
        builder: (context, inBox, _) {
          final field = SizedBox(
            key: key,
            width: 10,
            child: NumberInput(
              value: 1,
              onChanged: changes.add,
              focusNode: node,
              autofocus: true,
            ),
          );
          return Column(
            children: [
              if (inBox) Box(child: field) else field,
              const Focus(debugLabel: 'next', child: Text('next')),
            ],
          );
        },
      ),
      size: (20, 5),
    );
    await type(t, '2');
    boxed.value = true;
    await t.pump();
    node.unfocus();
    await t.pump();
    expect(changes, [12]);
  });

  testTwk('Escape is among the keys it takes while text is typed', (t) async {
    await t.pumpWidget(
      Column(
        children: [
          NumberInput(value: 1, onChanged: (_) {}, autofocus: true),
          const KeyHintsBar(showUnhinted: true),
        ],
      ),
      size: (60, 3),
    );
    expect(t.lines[1], isNot(contains('esc')));
    await type(t, '2');
    expect(t.lines[1], contains('esc'));
    await press(t, 'escape');
    expect(t.lines[1], isNot(contains('esc')));
  });

  testTwk('another focusNode takes the place of the one before', (t) async {
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final changes = <double>[];
    Widget app(FocusNode node) => Column(
      children: [
        NumberInput(value: 1, onChanged: changes.add, focusNode: node),
        const Focus(debugLabel: 'next', child: Text('next')),
      ],
    );
    await t.pumpWidget(app(a), size: (20, 3));
    await t.pumpWidget(app(b));
    b.requestFocus();
    await t.pump();
    expect(hints(t), ['up increase', 'down decrease']);
    await type(t, '5');
    await press(t, 'tab');
    expect(focused(t), 'next');
    expect(changes, [15]);
  });

  group('the keys', () {
    testTwk('Up and Down step it, Page Up and Page Down ten steps, only '
        'while it has the focus; within min and max, giving nothing there; '
        'Up and Down hinted', (t) async {
      final value = ValueNotifier<double>(5);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        input(value, changes: changes, min: -20, max: 20),
        size: (20, 3),
      );
      await press(t, 'up');
      expect(changes, isEmpty);
      await press(t, 'tab');
      expect(focused(t), 'input');
      expect(hints(t), ['up increase', 'down decrease']);
      await press(t, 'up up down');
      expect(changes, [6, 7, 6]);
      expect(t.lines.first, '6       ▴▾');
      await press(t, 'pageup pageup');
      expect(changes.skip(3), [16, 20]);
      await press(t, 'up pagedown pagedown pagedown pagedown down');
      expect(changes.skip(5), [10, 0, -10, -20]);
      expect(t.lines.first, '-20     ▴▾');
    });

    testTwk('typed right after Tab, in one read, step it', (t) async {
      final value = ValueNotifier<double>(5);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(input(value, changes: changes), size: (20, 3));
      await t.input('\t\x1b[A\x1b[A'.codeUnits);
      await t.pump();
      expect(focused(t), 'input');
      expect(changes, [6, 7]);
    });

    testTwk('that walk down to it from above while nothing has the focus go '
        'on', (t) async {
      final changes = <double>[];
      final above = <String>[];
      await t.pumpWidget(
        KeyBindings(
          {
            'up': () => above.add('up'),
            'pagedown': () => above.add('pagedown'),
            'escape': () => above.add('escape'),
          },
          child: NumberInput(value: 1, onChanged: changes.add),
        ),
        size: (20, 3),
      );
      await press(t, 'up pagedown escape');
      expect(above, ['up', 'pagedown', 'escape']);
      expect(changes, isEmpty);
    });

    testTwk('step by the step, rounded to the decimals', (t) async {
      final value = ValueNotifier<double>(0.1);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        input(
          value,
          changes: changes,
          step: 0.1,
          decimals: 1,
          autofocus: true,
        ),
        size: (20, 3),
      );
      await press(t, 'up up up');
      expect(changes, [0.2, 0.3, 0.4]);
      expect(t.lines.first, '0.4     ▴▾');
    });

    testTwk('step a value beyond the bounds into them', (t) async {
      final value = ValueNotifier<double>(50);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        input(value, changes: changes, max: 10, autofocus: true),
        size: (20, 3),
      );
      expect(t.lines.first, '50      ▴▾');
      await press(t, 'down down');
      expect(changes, [10, 9]);
    });

    testTwk('that come before the app builds it again step from the value '
        'the last one gave', (t) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        input(value, changes: changes, autofocus: true),
        size: (20, 3),
      );
      // three keys in one read
      await t.input('\x1b[A\x1b[A\x1b[A'.codeUnits);
      await t.pump();
      expect(changes, [1, 2, 3]);
      expect(t.lines.first, '3       ▴▾');
    });
  });

  group('the text typed', () {
    testTwk('is taken on Enter, which goes on to the nodes above, rounded '
        'to the decimals', (t) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      final changes = <double>[];
      final entered = <String>[];
      await t.pumpWidget(
        input(
          value,
          changes: changes,
          entered: entered,
          decimals: 1,
          autofocus: true,
        ),
        size: (20, 3),
      );
      await press(t, 'backspace backspace backspace');
      await type(t, ' 42.26');
      expect(changes, isEmpty);
      expect(t.lines.first, ' 42.26  ▴▾');
      await press(t, 'enter');
      expect(changes, [42.3]);
      expect(entered, ['enter']);
      expect(t.lines.first, '42.3    ▴▾');
      await press(t, 'enter');
      expect(changes, [42.3]);
      expect(entered, ['enter', 'enter']);
    });

    testTwk('is taken as the focus leaves the field', (t) async {
      final value = ValueNotifier<double>(1);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        input(value, changes: changes, autofocus: true),
        size: (20, 3),
      );
      await type(t, '5');
      await press(t, 'tab');
      expect(focused(t), 'next');
      expect(changes, [15]);
      expect(t.lines.first, '15      ▴▾');
    });

    testTwk('beyond the bounds is taken as the nearest bound, and shown in '
        'the error style until then', (t) async {
      final value = ValueNotifier<double>(5);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: input(
            value,
            changes: changes,
            min: 1,
            max: 9,
            autofocus: true,
          ),
        ),
        size: (20, 3),
      );
      final error = ThemeData.dark.error.fg;
      expect(t.cell(0, 0).fg, isNot(error));
      await type(t, '0');
      expect(t.lines.first, '50      ▴▾');
      expect(t.cell(0, 0).fg, error);
      await press(t, 'enter');
      expect(changes, [9]);
      expect(t.cell(0, 0).fg, isNot(error));
      await press(t, 'backspace');
      await type(t, '-3');
      expect(t.cell(0, 0).fg, error);
      await press(t, 'enter');
      expect(changes, [9, 1]);
      expect(t.lines.first, '1       ▴▾');
    });

    testTwk('that is no number gives way to the value, in the error style '
        'until then', (t) async {
      final value = ValueNotifier<double>(7);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: input(value, changes: changes, autofocus: true),
        ),
        size: (20, 3),
      );
      for (final wrong in ['x', 'e', '-', '+', ',']) {
        await type(t, wrong);
        expect(t.cell(0, 0).fg, ThemeData.dark.error.fg, reason: wrong);
        await press(t, 'enter');
        expect(t.lines.first, '7       ▴▾', reason: wrong);
      }
      await press(t, 'backspace');
      await type(t, 'NaN');
      await press(t, 'up');
      expect(t.lines.first, 'NaN     ▴▾');
      await press(t, 'tab');
      expect(t.lines.first, '7       ▴▾');
      expect(changes, isEmpty);
    });

    testTwk('is stepped from by Up and Down', (t) async {
      final value = ValueNotifier<double>(1);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        input(value, changes: changes, max: 30, autofocus: true),
        size: (20, 3),
      );
      await type(t, '2');
      await press(t, 'up');
      expect(changes, [13]);
      await type(t, '0');
      await press(t, 'down');
      expect(changes, [13, 29]);
    });

    testTwk('is put back by Escape, which goes on to the nodes above once '
        'nothing is typed', (t) async {
      final value = ValueNotifier<double>(4);
      addTearDown(value.dispose);
      final escaped = <String>[];
      await t.pumpWidget(
        KeyBindings(
          {'escape': () => escaped.add('escape')},
          child: input(value, autofocus: true),
        ),
        size: (20, 3),
      );
      await type(t, '2');
      expect(hints(t), ['up increase', 'down decrease']);
      await press(t, 'escape');
      expect(t.lines.first, '4       ▴▾');
      expect(escaped, isEmpty);
      await press(t, 'escape');
      expect(escaped, ['escape']);
      expect(value.value, 4);
    });

    testTwk('gives way to the value the app builds it with', (t) async {
      final value = ValueNotifier<double>(4);
      addTearDown(value.dispose);
      await t.pumpWidget(input(value, autofocus: true), size: (20, 3));
      await type(t, '2');
      value.value = 8;
      await t.pump();
      expect(t.lines.first, '8       ▴▾');
      await press(t, 'up');
      expect(value.value, 9);
    });
  });

  testTwk('an app that builds it again with its value has it shown', (
    t,
  ) async {
    final changes = <double>[];
    await t.pumpWidget(
      Stubborn(
        (rebuild) => Column(
          children: [
            NumberInput(
              value: 3,
              onChanged: (v) {
                changes.add(v);
                rebuild();
              },
              autofocus: true,
            ),
          ],
        ),
      ),
      size: (20, 3),
    );
    await press(t, 'up up');
    await type(t, '1');
    expect(t.lines.first, startsWith('31 '));
    await press(t, 'enter');
    expect(changes, [4, 4, 31]);
    expect(t.lines.first, startsWith('3 '));
  });

  group('the mouse', () {
    testTwk('a press on the field focuses it; on ▴ and ▾ steps it too', (
      t,
    ) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(input(value, changes: changes), size: (20, 3));
      await t.click(3, 0);
      await t.pump();
      expect(focused(t), 'input');
      expect(changes, isEmpty);
      await press(t, 'tab');
      await t.click(8, 0);
      await t.pump();
      expect(focused(t), 'input');
      await t.click(8, 0);
      await t.click(9, 0);
      await t.click(9, 0);
      await t.click(9, 0);
      await t.click(7, 0);
      await t.pump();
      expect(changes, [1, 2, 1, 0, -1]);
      await t.click(8, 0, button: 2);
      await t.pump();
      expect(changes, [1, 2, 1, 0, -1]);
    });

    testTwk('the wheel steps it while it has the focus, and goes to the '
        'views around while it has not', (t) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      final changes = <double>[];
      final wheel = <int>[];
      await t.pumpWidget(
        Listener(
          onScroll: (e) => wheel.add(e.scrollY),
          child: input(value, changes: changes),
        ),
        size: (20, 3),
      );
      await mouse(t, MouseKind.wheelUp, 2);
      expect(wheel, [-1]);
      await press(t, 'tab');
      await mouse(t, MouseKind.wheelUp, 2);
      await mouse(t, MouseKind.wheelUp, 9);
      await mouse(t, MouseKind.wheelDown, 2);
      expect(changes, [1, 2, 1]);
      expect(wheel, [-1]);
    });
  });

  testTwk('disabled, with no onChanged, it is muted and takes neither the '
      'focus, which Tab passes by, nor the mouse', (t) async {
    final value = ValueNotifier<double>(5);
    addTearDown(value.dispose);
    await t.pumpWidget(
      Theme(data: ThemeData.dark, child: input(value, enabled: false)),
      size: (20, 3),
    );
    final muted = ThemeData.dark.muted.fg;
    expect([t.cell(0, 0).fg, t.cell(8, 0).fg], [muted, muted]);
    await press(t, 'tab');
    expect(focused(t), 'next');
    await t.click(1, 0);
    await t.click(8, 0);
    await mouse(t, MouseKind.wheelUp, 8);
    expect(focused(t), 'next');
    expect(value.value, 5);
    expect(t.lines.first, '5       ▴▾');
    expect(t.terminal.mouseTracking, MouseTracking.off);
  });

  testTwk('in a FormField: Enter takes the text typed, then moves to the '
      'next field or submits; validated, saved and reset', (t) async {
    final form = GlobalKey<FormState>();
    final saved = <double?>[];
    var submitted = 0;
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    Widget field(FocusNode node) => FormField<double>(
      initialValue: 1,
      validator: (v) => v! > 10 ? 'too many' : null,
      onSaved: saved.add,
      builder: (field) => SizedBox(
        width: 8,
        child: NumberInput(
          value: field.value!,
          onChanged: field.didChange,
          focusNode: node,
        ),
      ),
    );
    await t.pumpWidget(
      Form(
        key: form,
        onSubmitted: () => submitted++,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [field(a), field(b)],
        ),
      ),
      size: (20, 6),
    );
    await press(t, 'tab');
    expect(focused(t), 'a');
    await type(t, '2');
    await press(t, 'enter');
    expect(focused(t), 'b');
    await press(t, 'up enter');
    expect(submitted, 0);
    expect(focused(t), 'a');
    expect(t.lines, ['12    ▴▾', 'too many', '2     ▴▾', '', '', '']);
    await press(t, 'backspace backspace');
    await type(t, '3');
    await press(t, 'tab enter');
    expect(t.lines.take(2), ['3     ▴▾', '2     ▴▾']);
    expect(submitted, 1);
    expect(saved, [3, 2]);
    await type(t, '9');
    form.currentState!.reset();
    await t.pump();
    expect(t.lines.take(2), ['1     ▴▾', '1     ▴▾']);
  });
}

/// Builds [builder] again, with the same widget, when the function it is
/// given is called.
final class Stubborn extends StatefulWidget {
  const Stubborn(this.builder, {super.key});

  final Widget Function(void Function() rebuild) builder;

  @override
  State<Stubborn> createState() => _StubbornState();
}

final class _StubbornState extends State<Stubborn> {
  @override
  Widget build(BuildContext context) => widget.builder(() => setState(() {}));
}
