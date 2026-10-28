// The hooks of controllers: useFocusNode, useFocusScopeNode,
// useTextEditingController, useScrollController and useListController,
// each through mounting with the widget it controls, rebuilding with the
// same and with other keys, and unmounting.
import 'package:test/test.dart';
import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'matchers.dart';

void main() {
  testTwk('useFocusNode is the node of the first build, set up by each '
      'build, and disposed with the element', (t) async {
    final nodes = <FocusNode>[];
    Widget focused({required bool canRequestFocus}) => HookBuilder(
      builder: (context) {
        final node = useFocusNode(
          debugLabel: 'field',
          canRequestFocus: canRequestFocus,
          skipTraversal: !canRequestFocus,
        );
        nodes.add(node);
        return Focus(focusNode: node, autofocus: true, child: const Text('x'));
      },
    );
    await t.pumpWidget(focused(canRequestFocus: true), size: (10, 1));
    final node = nodes.last;
    expect(node.hasPrimaryFocus, isTrue);
    expect('$node', 'FocusNode(field)');
    expect(node.skipTraversal, isFalse);
    await t.pumpWidget(focused(canRequestFocus: false));
    expect(nodes.toSet(), {node});
    expect(node.skipTraversal, isTrue);
    expect(node.hasPrimaryFocus, isFalse);
    await t.pumpWidget(const Text('gone'));
    expect(node, isDisposed);
  });

  testTwk('useFocusScopeNode is the scope node of the first build, disposed '
      'with the element', (t) async {
    final nodes = <FocusScopeNode>[];
    Widget scope() => HookBuilder(
      builder: (context) {
        final node = useFocusScopeNode(debugLabel: 'scope');
        nodes.add(node);
        return FocusScope(
          node: node,
          child: const Focus(autofocus: true, child: Text('x')),
        );
      },
    );
    await t.pumpWidget(scope(), size: (10, 1));
    await t.pumpWidget(scope());
    expect(nodes.toSet(), hasLength(1));
    expect(nodes.last.hasFocus, isTrue);
    await t.pumpWidget(const Text('gone'));
    expect(nodes.last, isDisposed);
  });

  testTwk('useTextEditingController is the controller of the first build, '
      'the text of later ones ignored, made anew when the keys change, the '
      'old one disposed', (t) async {
    final controllers = <TextEditingController>[];
    Widget field(String text, int key) => HookBuilder(
      builder: (context) {
        final controller = useTextEditingController(text: text, keys: [key]);
        controllers.add(controller);
        return TextField(controller: controller, autofocus: true);
      },
    );
    await t.pumpWidget(field('hi', 1), size: (10, 1));
    expect(t.lines, ['hi']);
    await t.type('!');
    await t.pump();
    await t.pumpWidget(field('ho', 1));
    expect(controllers.toSet(), hasLength(1));
    expect(controllers.last.text, 'hi!');
    await t.pumpWidget(field('ho', 2));
    expect(controllers[1], isDisposed);
    expect(controllers.last.text, 'ho');
    expect(t.lines, ['ho']);
    await t.pumpWidget(const Text('gone'));
    expect(controllers.last, isDisposed);
  });

  testTwk('useTextEditingController.fromValue is a controller of the value', (
    t,
  ) async {
    late TextEditingController controller;
    await t.pumpWidget(
      HookBuilder(
        builder: (context) {
          controller = useTextEditingController.fromValue(
            const TextEditingValue(
              text: 'abc',
              selection: TextSelection.collapsed(offset: 1),
            ),
          );
          return const Text('x');
        },
      ),
      size: (10, 1),
    );
    expect(controller.text, 'abc');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
    await t.pumpWidget(const Text('gone'));
    expect(controller, isDisposed);
  });

  testTwk('useScrollController is the controller of the first build, given '
      'to its scrollable from the initial offset, made anew when the keys '
      'change, and disposed with the element', (t) async {
    final controllers = <ScrollController>[];
    Widget scrolled(int key) => HookBuilder(
      builder: (context) {
        final controller = useScrollController(initialOffset: 2, keys: [key]);
        controllers.add(controller);
        return ListView(
          controller: controller,
          children: [for (var i = 0; i < 10; i++) Text('$i')],
        );
      },
    );
    await t.pumpWidget(scrolled(1), size: (10, 3));
    expect(controllers.last.offset, 2);
    expect(t.lines, ['2', '3', '4']);
    await t.pumpWidget(scrolled(1));
    expect(controllers.toSet(), hasLength(1));
    await t.pumpWidget(scrolled(2));
    expect(controllers[1], isDisposed);
    expect(controllers.last.hasClients, isTrue);
    await t.pumpWidget(const Text('gone'));
    expect(controllers.last, isDisposed);
  });

  testTwk('useListController is a list controller of the first build, '
      'disposed with the element', (t) async {
    late ListController controller;
    await t.pumpWidget(
      HookBuilder(
        builder: (context) {
          controller = useListController();
          return ListView.builder(
            controller: controller,
            itemCount: 100,
            itemBuilder: (context, i) => Text('$i'),
          );
        },
      ),
      size: (10, 3),
    );
    controller.jumpToIndex(50);
    await t.pump();
    expect(t.lines, ['50', '51', '52']);
    await t.pumpWidget(const Text('gone'));
    expect(controller, isDisposed);
  });
}
