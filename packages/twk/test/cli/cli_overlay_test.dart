import 'package:test/test.dart';
import 'package:twk/cli.dart';
import 'package:twk/src/cli/lines.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/cli.dart';

const _frame = Duration(milliseconds: 60);

const _texts = ['hover me', 'anchor', 'right click', 'bar body'];

Widget _anchors() => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    const Tooltip(message: 'tip', child: Text('hover me')),
    const Popover(
      open: false,
      popover: Text('pop'),
      child: Text('anchor'),
    ),
    ContextMenu(
      items: [MenuItem('Copy', onSelected: () {})],
      child: const Text('right click'),
    ),
    MenuBar(
      menus: [
        Menu('File', items: [MenuItem('Open', onSelected: () {})]),
      ],
      child: const Text('bar body'),
    ),
  ],
);

void main() {
  test('widgetLines shows the children of widgets that need an Overlay', () {
    final lines = widgetLines(_anchors(), 30, onLog: (_) {});
    final text = lines.join('\n');
    for (final shown in _texts) {
      expect(text, contains(shown));
    }
  });

  test('the interactive session shows them too', () async {
    final clock = FakeClock();
    final terminal = FakeCliTerminal.interactive(
      width: 30,
      height: 10,
      fakeClock: clock,
    );
    final cli = Cli(terminal: terminal);
    await clock.elapseUntil(
      cli.show(_anchors()),
      step: _frame,
      within: _frame * 100,
    );
    await clock.elapseUntil(cli.close(), step: _frame, within: _frame * 100);
    final screen = terminal.screenLines.join('\n');
    for (final shown in _texts) {
      expect(screen, contains(shown));
    }
  });
}
