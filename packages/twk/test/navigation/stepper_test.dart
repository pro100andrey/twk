// Stepper: the headers on a row with their marks, the current step's
// content, its refusal and Back and Next; validation sync and async (on
// the tester's fake clock), the input ignored and a spinner in Next while
// it runs; finishing; linear and not, by clicks and goTo; disabled steps
// skipped; the current step alone where the row does not fit; the
// vertical layout; PageDown and PageUp from the content, hinted; the
// focus into the new step's content; read as a list of steps; where ─
// and the marks are two columns wide.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

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

/// A cell drawn in [theme]'s selection, as a focused row is.
Matcher selected(ThemeData theme) => switch (theme.selection.bg) {
  final bg? => hasBg(bg),
  null => hasAttr(theme.selection.attrs),
};

Future<void> click(TwkTester t, int x, int y) async {
  await t.click(x, y);
  await t.pump();
}

/// The screen's lines, the blanks at their ends trimmed.
List<String> lines(TwkTester t) => [
  for (final line in t.lines) line.trimRight(),
];

/// A project's setup: its name, refused while empty; the dependencies,
/// checked by a server that answers after a second with
/// [registry]'s message; and a confirmation with a field of its own.
final class Setup {
  final name = TextEditingController();
  final names = FocusNode(debugLabel: 'name');
  final notes = FocusNode(debugLabel: 'notes');
  final picks = FocusNode(debugLabel: 'pick');
  var picked = 0;
  String? registry;
  late ThemeData theme;
  var checks = 0;
  var finished = 0;
  final changes = <int>[];

  void dispose() {
    name.dispose();
    names.dispose();
    notes.dispose();
    picks.dispose();
  }

  List<Step> steps({StepState? second, String? subtitle, bool pick = false}) =>
      [
        Step(
          title: 'Project Info',
          subtitle: subtitle,
          content: TextField(controller: name, focusNode: names),
          validate: () => name.text.isEmpty ? 'The project needs a name' : null,
        ),
        Step(
          title: 'Dependencies',
          state: second,
          content: pick
              ? Button('pick', focusNode: picks, onPressed: () => picked++)
              : const Text('Select packages to install: …'),
          validate: () async {
            checks++;
            // app code: the stepper calls validate on the tester's clock
            // ignore: twk_lints/wall_time_in_tests
            await Future<void>.delayed(const Duration(seconds: 1));
            return registry;
          },
        ),
        Step(
          title: 'Confirmation',
          content: TextField(focusNode: notes, placeholder: 'notes'),
        ),
      ];

  Widget build({
    StepperController? controller,
    Axis direction = Axis.horizontal,
    bool linear = true,
    StepState? second,
    String? subtitle,
    bool showControls = true,
    bool pick = false,
  }) => Builder(
    builder: (context) {
      theme = Theme.of(context);
      return Stepper(
        steps: steps(second: second, subtitle: subtitle, pick: pick),
        controller: controller,
        direction: direction,
        linear: linear,
        showControls: showControls,
        onFinished: () => finished++,
        onStepChanged: changes.add,
      );
    },
  );
}

const full = '● 1. Project Info ── ○ 2. Dependencies ── ○ 3. Confirmation';

void main() {
  late Setup setup;
  setUp(() => setup = Setup());
  tearDown(() => setup.dispose());

  testTwk('the headers on a row, the current one marked ● in the primary '
      'color, its title bold, the others ○ muted; the content; Back '
      'disabled and Next', (t) async {
    await t.pumpWidget(setup.build(), size: (70, 4));
    expect(lines(t)[0], full);
    expect(lines(t)[2], startsWith(' Back '));
    expect(lines(t)[2], endsWith(' Next'));
    final theme = setup.theme;
    expect(
      t,
      styleAt(0, 0, allOf(hasFg(theme.primary.fg!), hasAttr(Attr.bold))),
    );
    expect(t, styleAt(5, 0, hasAttr(Attr.bold)));
    expect(t, styleAt(21, 0, hasFg(theme.muted.fg!)));
    expect(t, styleAt(23, 0, isNot(hasAttr(Attr.bold))));
    expect(t, styleAt(18, 0, hasFg(theme.muted.fg!)));
  });

  testTwk('Next refuses an invalid step: the message under the content in '
      "the theme's error, the header ✗; taken once valid, the step before "
      '✔ in the success color', (t) async {
    final controller = StepperController();
    addTearDown(controller.dispose);
    await t.pumpWidget(setup.build(controller: controller), size: (70, 5));
    await press(t, 'pagedown');
    final theme = setup.theme;
    expect(controller.current, 0);
    expect(controller.error, 'The project needs a name');
    expect(lines(t)[0], startsWith('✗ 1. Project Info'));
    expect(t, styleAt(0, 0, hasFg(theme.error.fg!)));
    expect(t, styleAt(5, 0, hasFg(theme.error.fg!)));
    expect(lines(t)[2], 'The project needs a name');
    expect(t, styleAt(0, 2, hasFg(theme.error.fg!)));
    await t.type('app');
    await t.pump();
    await press(t, 'pagedown');
    expect(controller.current, 1);
    expect(controller.error, isNull);
    expect(
      lines(t)[0],
      '✔ 1. Project Info ── ● 2. Dependencies ── ○ 3. Confirmation',
    );
    expect(t, styleAt(0, 0, hasFg(theme.success.fg!)));
    expect(setup.changes, [1]);
  });

  testTwk('an async validation: a spinner in Next and the keys and the '
      'mouse ignored while it runs; refused, the focus back on Next; taken, '
      "into the next step's content", (t) async {
    final controller = StepperController(initialStep: 1);
    addTearDown(controller.dispose);
    setup.registry = 'The registry is unreachable';
    await t.pumpWidget(setup.build(controller: controller), size: (70, 4));
    expect(focused(t), 'Stepper next');
    await press(t, 'enter');
    expect(controller.validating, isTrue);
    expect(lines(t)[2], endsWith('⠋ Next'));
    expect(focused(t), 'Stepper');
    // ignored: the keys, Back clicked, a header clicked
    await press(t, 'pageup');
    await press(t, 'tab');
    expect(focused(t), 'Stepper');
    await click(t, 1, 2);
    await click(t, 2, 0);
    expect(controller.current, 1);
    expect(await controller.next(), isFalse);
    expect(setup.checks, 1);
    await t.pump(const Duration(seconds: 1));
    expect(controller.validating, isFalse);
    expect(controller.error, 'The registry is unreachable');
    expect(lines(t)[2], 'The registry is unreachable');
    expect(lines(t)[3], endsWith(' Next'));
    await t.pump();
    expect(focused(t), 'Stepper next');
    setup.registry = null;
    await press(t, 'enter');
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(controller.current, 2);
    expect(focused(t), 'notes');
    expect(lines(t)[2], endsWith(' Finish'));
  });

  testTwk('while an async validation started from the content runs, the '
      'content takes neither the keys nor the mouse; refused, the focus goes '
      'back where it was', (t) async {
    final controller = StepperController(initialStep: 1);
    addTearDown(controller.dispose);
    setup.registry = 'No such package';
    await t.pumpWidget(
      setup.build(controller: controller, pick: true),
      size: (70, 4),
    );
    expect(focused(t), 'pick');
    await press(t, 'pagedown');
    expect(controller.validating, isTrue);
    expect(focused(t), 'Stepper');
    await press(t, 'enter');
    await press(t, 'space');
    await click(t, 2, 1);
    expect(setup.picked, 0);
    expect(focused(t), 'Stepper');
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(controller.current, 1);
    expect(focused(t), 'pick');
    await press(t, 'enter');
    expect(setup.picked, 1);
  });

  testTwk('Next on the last step finishes once it is taken; Back goes to the '
      'step before without validating', (t) async {
    final controller = StepperController(initialStep: 2);
    addTearDown(controller.dispose);
    await t.pumpWidget(setup.build(controller: controller), size: (70, 4));
    expect(lines(t)[2], endsWith(' Finish'));
    expect(await controller.next(), isTrue);
    expect(setup.finished, 1);
    expect(controller.current, 2);
    await click(t, 1, 2);
    expect(controller.current, 1);
    expect(setup.checks, 0);
    controller.back();
    await t.pump();
    expect(controller.current, 0);
    controller.back();
    expect(controller.current, 0);
    expect(setup.changes, [1, 0]);
  });

  testTwk('linear: a click goes back only; goTo validates every step on the '
      'way and stops at the first refused', (t) async {
    final controller = StepperController();
    addTearDown(controller.dispose);
    await t.pumpWidget(setup.build(controller: controller), size: (70, 4));
    await click(t, 43, 0);
    expect(controller.current, 0);
    setup.name.text = 'app';
    final going = controller.goTo(2);
    await t.pump(const Duration(seconds: 1));
    expect(await going, isTrue);
    // the frame of the step, which takes the mouse again
    await t.pump();
    expect(controller.current, 2);
    expect(setup.checks, 1);
    await click(t, 2, 0);
    expect(controller.current, 0);
    setup.name.text = '';
    expect(await controller.goTo(2), isFalse);
    expect(controller.current, 0);
    expect(controller.error, 'The project needs a name');
    setup.name.text = 'app';
    setup.registry = 'No such package';
    final refused = controller.goTo(2);
    await t.pump(const Duration(seconds: 1));
    expect(await refused, isFalse);
    expect(controller.current, 1);
    expect(controller.error, 'No such package');
    expect(await controller.goTo(5), isFalse);
    expect(await controller.goTo(-1), isFalse);
  });

  testTwk('not linear: any header clicked, nothing validated; Finish '
      'validates every step and goes to the first refused', (t) async {
    final controller = StepperController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      setup.build(controller: controller, linear: false),
      size: (70, 4),
    );
    await click(t, 43, 0);
    expect(controller.current, 2);
    expect(setup.checks, 0);
    expect(await controller.next(), isFalse);
    expect(controller.current, 0);
    expect(controller.error, 'The project needs a name');
    expect(setup.finished, 0);
    await t.pump();
    setup.name.text = 'app';
    expect(await controller.goTo(2), isTrue);
    final finishing = controller.next();
    await t.pump(const Duration(seconds: 1));
    expect(await finishing, isTrue);
    expect(setup.finished, 1);
  });

  testTwk('a disabled step is muted, skipped by Next and Back and not '
      'clicked', (t) async {
    final controller = StepperController();
    addTearDown(controller.dispose);
    setup.name.text = 'app';
    await t.pumpWidget(
      setup.build(
        controller: controller,
        second: StepState.disabled,
        linear: false,
      ),
      size: (70, 4),
    );
    expect(t, styleAt(23, 0, hasFg(setup.theme.muted.fg!)));
    await click(t, 23, 0);
    expect(controller.current, 0);
    expect(await controller.goTo(1), isFalse);
    await press(t, 'pagedown');
    expect(controller.current, 2);
    expect(setup.checks, 0);
    await press(t, 'pageup');
    expect(controller.current, 0);
  });

  testTwk('too narrow for the headers: the current step alone, `Step 2 of 3 '
      '· Dependencies`; the subtitle under it, muted', (t) async {
    final controller = StepperController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      setup.build(controller: controller, subtitle: 'The name of it'),
      size: (40, 5),
    );
    expect(lines(t)[0], 'Step 1 of 3 · Project Info');
    expect(lines(t)[1], 'The name of it');
    expect(t, styleAt(0, 1, hasFg(setup.theme.muted.fg!)));
    expect(t, styleAt(14, 0, hasAttr(Attr.bold)));
    await t.resize(70, 5);
    await t.pump();
    expect(lines(t)[0], full);
  });

  testTwk('vertical: the headers in a column, the content and the controls '
      'under the current one, two columns in, read in the list', (t) async {
    final controller = StepperController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      SizedBox(
        width: 40,
        child: setup.build(
          controller: controller,
          direction: Axis.vertical,
          subtitle: 'The name',
        ),
      ),
      size: (40, 8),
    );
    expect(lines(t)[0], '● 1. Project Info');
    expect(lines(t)[1], '  The name');
    expect(lines(t)[3], startsWith('   Back '));
    expect(lines(t)[3], endsWith(' Next'));
    expect(lines(t)[4], '○ 2. Dependencies');
    expect(lines(t)[5], '○ 3. Confirmation');
    expect(t.binding.semantics.lines, [
      'list',
      'listitem 1. Project Info, selected',
      'The name',
      'textbox',
      'button Back, disabled',
      'button Next',
      'listitem 2. Dependencies',
      'listitem 3. Confirmation',
    ]);
    setup.name.text = 'app';
    await press(t, 'pagedown');
    expect(lines(t)[0], '✔ 1. Project Info');
    expect(lines(t)[1], '  The name');
    expect(lines(t)[2], '● 2. Dependencies');
    expect(lines(t)[3], '  Select packages to install: …');
    await click(t, 0, 0);
    expect(controller.current, 0);
  });

  testTwk('vertical: PageDown focuses the first stop of the new step, drawn '
      'focused; Space toggles it; PageUp back into the field', (t) async {
    final boxes = [
      for (final label in ['args', 'http', 'path'])
        FocusNode(debugLabel: label),
    ];
    for (final node in boxes) {
      addTearDown(node.dispose);
    }
    final checked = ValueNotifier(<String>{});
    addTearDown(checked.dispose);
    late ThemeData theme;
    await t.pumpWidget(
      SizedBox(
        width: 40,
        child: Builder(
          builder: (context) {
            theme = Theme.of(context);
            return Stepper(
              direction: Axis.vertical,
              steps: [
                Step(
                  title: 'Project Info',
                  content: TextField(
                    controller: setup.name,
                    focusNode: setup.names,
                  ),
                ),
                Step(
                  title: 'Dependencies',
                  content: ValueListenableBuilder(
                    valueListenable: checked,
                    builder: (context, on, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final node in boxes)
                          Checkbox(
                            value: on.contains(node.debugLabel),
                            label: node.debugLabel!,
                            focusNode: node,
                            onChanged: (v) => checked.value = {
                              for (final l in on)
                                if (l != node.debugLabel) l,
                              if (v) node.debugLabel!,
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const Step(title: 'Confirmation', content: Text('Create it?')),
              ],
            );
          },
        ),
      ),
      size: (40, 9),
    );
    expect(focused(t), 'name');
    await press(t, 'pagedown');
    expect(lines(t)[1], '● 2. Dependencies');
    expect(lines(t)[2], '  [ ] args');
    expect(focused(t), 'args');
    expect(boxes[0].hasPrimaryFocus, isTrue);
    expect(t, styleAt(2, 2, selected(theme)));
    expect(t, styleAt(2, 3, isNot(selected(theme))));
    await press(t, 'space');
    expect(checked.value, {'args'});
    await press(t, 'tab');
    expect(focused(t), 'http');
    expect(t, styleAt(2, 3, selected(theme)));
    await press(t, 'pageup');
    expect(focused(t), 'name');
    expect(setup.names.hasPrimaryFocus, isTrue);
  });

  testTwk('PageDown and PageUp come up from a field, which keeps Enter; '
      'hinted, PageUp from the second step on, PageDown `finish` on the '
      'last', (t) async {
    final controller = StepperController();
    addTearDown(controller.dispose);
    await t.pumpWidget(setup.build(controller: controller), size: (70, 4));
    expect(focused(t), 'name');
    expect(hints(t), contains('pagedown next step'));
    expect(hints(t).where((h) => h.startsWith('pageup')), isEmpty);
    await t.type('app');
    await press(t, 'enter');
    expect(controller.current, 0);
    await press(t, 'pagedown');
    expect(controller.current, 1);
    expect(focused(t), 'Stepper next');
    expect(hints(t), contains('pageup previous step'));
    await press(t, 'pageup');
    expect(controller.current, 0);
    expect(focused(t), 'name');
    await controller.goTo(2).then((_) {});
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(controller.current, 2);
    expect(focused(t), 'notes');
    expect(hints(t), contains('pagedown finish'));
  });

  testTwk('without the controls, Back and Next are left out and the keys '
      'still move', (t) async {
    final controller = StepperController();
    addTearDown(controller.dispose);
    setup.name.text = 'app';
    await t.pumpWidget(
      setup.build(controller: controller, showControls: false),
      size: (70, 4),
    );
    expect(lines(t)[2], '');
    await press(t, 'pagedown');
    expect(controller.current, 1);
  });

  testTwk('read as a list of the steps, the current one selected, a done '
      'one complete and a refused one with its message', (t) async {
    final controller = StepperController();
    addTearDown(controller.dispose);
    setup.registry = 'No such package';
    await t.pumpWidget(setup.build(controller: controller), size: (70, 4));
    setup.name.text = 'app';
    final going = controller.next().then((_) => controller.next());
    await t.pump(const Duration(seconds: 1));
    await going;
    await t.pump();
    expect(t.binding.semantics.lines.take(4), [
      'list',
      'listitem 1. Project Info, complete',
      'listitem 2. Dependencies, selected, No such package',
      'listitem 3. Confirmation',
    ]);
  });

  testTwk('a controller serving no stepper moves nowhere; a stepper built '
      'with another controller serves it', (t) async {
    final a = StepperController(initialStep: 2);
    final b = StepperController();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    expect(await a.next(), isFalse);
    expect(await a.goTo(0), isFalse);
    a.back();
    expect(a.current, 2);
    await t.pumpWidget(setup.build(controller: a), size: (70, 4));
    expect(lines(t)[0], startsWith('✔ 1. Project Info'));
    await t.pumpWidget(setup.build(controller: b), size: (70, 4));
    expect(lines(t)[0], full);
    a.back();
    expect(a.current, 2);
    b.back();
    expect(b.current, 0);
  });

  testTwk('a stepper of no steps shows nothing; one of fewer steps than the '
      'controller says shows its last', (t) async {
    final controller = StepperController(initialStep: 7);
    addTearDown(controller.dispose);
    await t.pumpWidget(const Stepper(steps: []), size: (20, 2));
    expect(lines(t), ['', '']);
    await t.pumpWidget(setup.build(controller: controller), size: (70, 4));
    expect(lines(t)[0], startsWith('✔ 1. Project Info'));
    expect(lines(t)[2], endsWith(' Finish'));
  });

  group('where ─ and the marks are two columns wide (ambiguous width 2)', () {
    List<Step> steps() => const [
      Step(title: 'Project Info', content: Text('name')),
      Step(title: 'Dependencies', content: Text('packages')),
      Step(title: 'Confirmation', content: Text('done')),
    ];

    test('a click hits the header drawn where it is, not columns off '
        'for each mark and ─ before it', () async {
      final controller = StepperController();
      addTearDown(controller.dispose);
      final app = await WideApp.start(
        Stepper(steps: steps(), controller: controller, linear: false),
        width: 70,
        height: 4,
      );
      expect(
        app.lines().first,
        '● 1. Project Info ── ○ 2. Dependencies ── ○ 3. Confirmation',
      );
      // the blank before the second ○, then the n of Confirmation
      await app.click(47, 0);
      expect(controller.current, 0);
      await app.click(60, 0);
      expect(controller.current, 2);
      await app.quit();
    });

    test(
      'too narrow for the headers as drawn: the current step alone',
      () async {
        final app = await WideApp.start(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 62,
              height: 4,
              child: Stepper(steps: steps()),
            ),
          ),
          width: 70,
          height: 4,
        );
        expect(app.lines().first, 'Step 1 of 3 · Project Info');
        await app.quit();
      },
    );
  });
}
