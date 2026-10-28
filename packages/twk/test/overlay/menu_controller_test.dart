// MenuController: a MenuBar's menus and a ContextMenu's opened along a
// path and closed by it; the path following the keys and the mouse, the
// listeners told once per change; the context menu at a cell, under the
// widget focused in it or under itself; the errors of a path, of `at` on
// a bar and of a controller given to no widget; a controller swapped or
// its widget gone.
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
  Widget build(BuildContext context) =>
      Focus(autofocus: autofocus, debugLabel: label, child: _Mark(label));
}

final class _Mark extends StatelessWidget {
  const _Mark(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text('${Focus.of(context).hasPrimaryFocus ? '>' : ' '}$label');
}

/// The label of the node with the primary focus.
String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

/// Presses [keys] and pumps a frame.
Future<void> press(TwkTester t, String keys) async {
  await t.press(keys);
  await t.pump();
}

/// The text of each run of highlighted cells, on the selection's
/// background, under the first row, top to bottom and left to right:
/// the entries highlighted.
List<String> highlighted(TwkTester t) {
  final runs = <String>[];
  for (var y = 1; y < t.terminal.height; y++) {
    final run = StringBuffer();
    for (var x = 0; x <= t.terminal.width; x++) {
      final cell = x < t.terminal.width ? t.cell(x, y) : null;
      if (cell != null && cell.bg == const Color.indexed(237).value) {
        run.write(cell.text);
      } else if (run.isNotEmpty) {
        runs.add('$run'.trim());
        run.clear();
      }
    }
  }
  return runs;
}

/// File (with Recent and its More), Edit, which cannot open, and View,
/// each item adding its name to [log].
List<Menu> menus(List<String> log) {
  MenuItem item(String label) =>
      MenuItem(label, onSelected: () => log.add(label));
  return [
    Menu(
      '&File',
      items: [
        item('New'),
        const MenuDivider(),
        Menu(
          '&Recent',
          items: [
            item('a.txt'),
            Menu('&More', items: [item('c.txt')]),
          ],
        ),
        const Menu('&Shared', items: [], enabled: false),
      ],
    ),
    Menu('&Edit', items: [item('Cut')], enabled: false),
    Menu('&View', items: [item('Wrap')]),
  ];
}

/// The paths [controller] has had, each time it told its listeners: `-`
/// for closed.
List<String> follow(MenuController controller) {
  final seen = <String>[];
  controller.addListener(
    () => seen.add(controller.isOpen ? '${controller.path}' : '-'),
  );
  return seen;
}

Widget bar(MenuController? controller, List<String> log) => Overlay(
  child: MenuBar(
    look: PanelLook.bordered,
    controller: controller,
    menus: menus(log),
    child: const Field('editor', autofocus: true),
  ),
);

void main() {
  testTwk('open() opens the first menu that can open, its first item '
      'highlighted and the keys in it; close() closes it, the focus back', (
    t,
  ) async {
    final controller = MenuController();
    final seen = follow(controller);
    await t.pumpWidget(
      Theme.terminal(child: bar(controller, [])),
      size: (40, 10),
    );
    expect(controller.isOpen, isFalse);
    expect(controller.path, isEmpty);
    controller.open();
    await t.pump();
    expect(controller.isOpen, isTrue);
    expect(controller.path, [0]);
    expect(highlighted(t), ['New']);
    expect(focused(t), 'menu');
    controller.close();
    await t.pump();
    expect(controller.isOpen, isFalse);
    expect(t, matchesScreen(' File  Edit  View\n>editor'));
    expect(focused(t), 'editor');
    controller.close();
    expect(seen, ['[0]', '-']);
  });

  testTwk("open(path) opens the bar's menu and the submenus down the "
      'path, the first entry of the innermost highlighted, in place of '
      'the menus open; Enter chooses there', (t) async {
    final log = <String>[];
    final controller = MenuController();
    final seen = follow(controller);
    await t.pumpWidget(
      Theme.terminal(child: bar(controller, log)),
      size: (40, 10),
    );
    controller.open([2]);
    await t.pump();
    expect(highlighted(t), ['Wrap']);
    controller.open([0, 2, 1]);
    await t.pump();
    expect(controller.path, [0, 2, 1]);
    expect(highlighted(t), ['Recent  ▸', 'More   ▸', 'c.txt']);
    await press(t, 'enter');
    expect(log, ['c.txt']);
    expect(seen, ['[2]', '[0, 2, 1]', '-']);
  });

  testTwk("a path opens as far as its menus can: a bar's menu that cannot "
      'open opens nothing, a submenu that cannot stops there', (t) async {
    final controller = MenuController();
    final seen = follow(controller);
    await t.pumpWidget(
      Theme.terminal(child: bar(controller, [])),
      size: (40, 10),
    );
    controller.open([1]);
    await t.pump();
    expect(controller.isOpen, isFalse);
    controller.open([0, 3]);
    await t.pump();
    expect(controller.path, [0]);
    expect(highlighted(t), ['New']);
    controller.open([1]);
    await t.pump();
    expect(controller.path, [0]);
    expect(seen, ['[0]']);
  });

  testTwk('the path follows the keys and the mouse, the listeners told once '
      'per change and not as the highlight moves within a menu', (t) async {
    final controller = MenuController();
    final seen = follow(controller);
    await t.pumpWidget(
      Theme.terminal(child: bar(controller, [])),
      size: (40, 10),
    );
    await press(t, 'f10');
    await press(t, 'down');
    await press(t, 'right');
    expect(controller.path, [0, 2]);
    await press(t, 'down');
    expect(controller.path, [0, 2]);
    await press(t, 'right');
    await press(t, 'escape');
    await press(t, 'left');
    await press(t, 'down');
    await press(t, 'right');
    expect(controller.path, [2]);
    await press(t, 'f10');
    await t.click(14, 0);
    await t.pump();
    await press(t, 'escape');
    expect(seen, [
      '[0]',
      '[0, 2]',
      '[0, 2, 1]',
      '[0, 2]',
      '[0]',
      '[2]',
      '-',
      '[2]',
      '-',
    ]);
  });

  testTwk('a path past the entries is a RangeError, one through an entry '
      'that is no Menu an ArgumentError, as is `at` for a bar; a controller '
      'given to no widget throws a StateError on open and closes nothing', (
    t,
  ) async {
    final controller = MenuController();
    expect(
      controller.open,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'MenuController.open: the controller is given to no widget: give '
              'it as controller: to a MenuBar or a ContextMenu',
        ),
      ),
    );
    controller.close();
    await t.pumpWidget(
      Theme.terminal(child: bar(controller, [])),
      size: (40, 10),
    );
    expect(() => controller.open([3]), throwsRangeError);
    expect(() => controller.open([0, 4]), throwsRangeError);
    expect(() => controller.open([0, 0]), throwsArgumentError);
    expect(() => controller.open([0, 2, 0]), throwsArgumentError);
    expect(() => controller.open([0], (1, 1)), throwsArgumentError);
    await t.pump();
    expect(controller.isOpen, isFalse);
    expect(t, matchesScreen(' File  Edit  View\n>editor'));
  });

  testTwk("a ContextMenu's controller opens its menu at a cell of its "
      'child, under the widget focused in it, or under the child when the '
      'focus is outside; its path is the rows of the submenus open', (
    t,
  ) async {
    final log = <String>[];
    final controller = MenuController();
    final seen = follow(controller);
    await t.pumpWidget(
      Theme.terminal(
        child: Overlay(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Field('outside', autofocus: true),
              const SizedBox(height: 2),
              ContextMenu(
                look: PanelLook.bordered,
                controller: controller,
                items: [
                  MenuItem('&Cut', onSelected: () => log.add('cut')),
                  Menu(
                    '&Share',
                    items: [
                      MenuItem('&Mail', onSelected: () => log.add('mail')),
                    ],
                  ),
                ],
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Field('a'),
                    Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Field('b'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      size: (40, 12),
    );
    controller.open(null, (10, 1));
    await t.pump();
    expect(controller.isOpen, isTrue);
    expect(controller.path, isEmpty);
    expect(highlighted(t), ['Cut']);
    expect(t, hasTextAt(10, 4, '┌──────────┐'));
    controller.open();
    await t.pump();
    expect(t, hasTextAt(0, 4, '┌──────────┐'));
    controller.close();
    await t.pump();
    expect(focused(t), 'outside');
    await press(t, 'tab');
    await press(t, 'tab');
    expect(focused(t), 'b');
    controller.open([1]);
    await t.pump();
    expect(controller.path, [1]);
    expect(t, hasTextAt(6, 5, '┌──────────┐'));
    expect(highlighted(t), ['Share  ▸', 'Mail']);
    await press(t, 'enter');
    expect(log, ['mail']);
    expect(focused(t), 'b');
    expect(() => controller.open([0]), throwsArgumentError);
    expect(() => controller.open([2]), throwsRangeError);
    await press(t, 'shift+f10');
    await press(t, 'escape');
    await t.click(3, 3, button: 2);
    await t.pump();
    expect(highlighted(t), isEmpty);
    expect(seen, ['[]', '-', '[1]', '-', '[]', '-', '[]']);
  });

  testTwk('a controller taken from its widget reads closed, the new one '
      'what is open; the widget gone, its controller reads closed', (
    t,
  ) async {
    final first = MenuController();
    final second = MenuController();
    await t.pumpWidget(Theme.terminal(child: bar(first, [])), size: (40, 10));
    first.open([2]);
    await t.pump();
    await t.pumpWidget(Theme.terminal(child: bar(second, [])), size: (40, 10));
    expect(first.isOpen, isFalse);
    expect(second.path, [2]);
    expect(first.open, throwsStateError);
    second.open([0, 2]);
    await t.pump();
    expect(second.path, [0, 2]);
    await t.pumpWidget(
      const Theme.terminal(child: Text('gone')),
      size: (40, 10),
    );
    expect(second.isOpen, isFalse);
    expect(second.path, isEmpty);
    first.dispose();
    second.dispose();
  });
}
