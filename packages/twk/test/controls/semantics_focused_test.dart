// RadioGroup, SegmentedButton, TabBar and Breadcrumbs: a screen reader finds
// no item focused while the control has not the focus, and the current one
// once it has.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const List<Choice<String>> _choices = [
  Choice('a', 'alpha'),
  Choice('b', 'beta'),
  Choice('c', 'gamma'),
];

/// [build]'s control, whose items read from line [first] on and whose
/// focused one is on [line]: no item focused before the focus and after
/// unfocus (the line of the list itself may be, or none), [line] while it
/// has it.
Future<void> _check(
  TwkTester t,
  Widget Function(FocusNode node) build,
  int first,
  int line,
) async {
  final node = FocusNode(debugLabel: 'control');
  addTearDown(node.dispose);
  await t.pumpWidget(Theme.terminal(child: build(node)), size: (40, 4));
  void noItem() {
    final at = t.binding.semantics.focusedLine;
    expect(at == null || at < first, isTrue, reason: 'focused line $at');
  }

  expect(node.hasFocus, isFalse);
  noItem();
  node.requestFocus();
  await t.pump();
  expect(t.binding.semantics.focusedLine, line);
  node.unfocus();
  await t.pump();
  noItem();
}

void main() {
  testTwk('a screen reader finds no radio focused while the group has not the '
      'focus', (t) async {
    await _check(
      t,
      (node) => RadioGroup<String>(
        choices: _choices,
        value: 'b',
        onChanged: (_) {},
        focusNode: node,
      ),
      0,
      1,
    );
  });

  testTwk('a screen reader finds no segment focused while the button has not '
      'the focus', (t) async {
    await _check(
      t,
      (node) => SegmentedButton<String>(
        segments: _choices,
        selected: const {'a'},
        onSelectionChanged: (_) {},
        focusNode: node,
      ),
      0,
      0,
    );
  });

  testTwk('a screen reader finds no tab focused while the bar has not the '
      'focus', (t) async {
    final controller = TabController(length: 3, initialIndex: 1);
    addTearDown(controller.dispose);
    await _check(
      t,
      (node) => TabBar(
        controller: controller,
        tabs: const ['one', 'two', 'three'],
        focusNode: node,
      ),
      1,
      2,
    );
  });

  testTwk('a screen reader finds no crumb focused while the path has not the '
      'focus', (t) async {
    await _check(
      t,
      (node) => Breadcrumbs(
        items: const ['home', 'docs', 'api'],
        current: 2,
        onSelected: (_) {},
        focusNode: node,
      ),
      1,
      2,
    );
  });
}
