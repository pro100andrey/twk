// Tooltips: shown once the mouse has rested on the child, fading in on a
// chip, gone when it leaves or the child goes; under the child, above it
// near the bottom edge, moved in from the sides; the bordered look; no
// Overlay. Shown once the focus has rested in the child, gone when it
// leaves or on Escape; by a TooltipController; neither trigger when turned
// off; the message read as the hint of the child.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData dark = ThemeData.dark;

/// 'Help' at [left], [top] of a 40 × 10 overlay in the dark theme, with a
/// tooltip saying [message], in the [look] given, fading in over [fadeIn].
Widget helpAt(
  int left,
  int top, {
  String message = 'Opens help',
  PanelLook look = PanelLook.raised,
  Duration fadeIn = const Duration(milliseconds: 100),
}) => Theme(
  data: dark,
  child: Overlay(
    child: Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: Tooltip(
            message: message,
            look: look,
            fadeIn: fadeIn,
            child: const Text('Help'),
          ),
        ),
      ],
    ),
  ),
);

const ms = Duration(milliseconds: 1);

/// Buttons 'Help' and, two rows below, 'Next' at the top left of a 40 × 10
/// overlay,
/// 'Help' with a tooltip saying 'Opens help', shown by [controller] and as
/// [showOnHover] and [showOnFocus] say; Escape the page does not take
/// adds 'page esc' to [log].
Widget buttons({
  TooltipController? controller,
  bool showOnHover = true,
  bool showOnFocus = true,
  List<String>? log,
}) => Theme(
  data: dark,
  child: Overlay(
    child: KeyBindings(
      {'escape': () => log?.add('page esc')},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: 'Opens help',
            controller: controller,
            showOnHover: showOnHover,
            showOnFocus: showOnFocus,
            fadeIn: Duration.zero,
            child: Button('Help', onPressed: () {}),
          ),
          const SizedBox(height: 2),
          Button('Next', onPressed: () {}),
        ],
      ),
    ),
  ),
);

/// What the screen shows of the tooltip, under 'Help'.
String? tip(TwkTester t) {
  final line = t.lines.length > 1 ? t.lines[1].trim() : '';
  return line.isEmpty ? null : line;
}

/// Moves the clock on by [time], then by a frame, which shows what changed
/// at the end of [time].
Future<void> wait(TwkTester t, Duration time) async {
  await t.pump(time);
  await t.pump();
}

void main() {
  testTwk('a tooltip shows under its child once the mouse has rested on '
      'it, fading in on a chip, and goes when the mouse leaves', (t) async {
    await t.pumpWidget(helpAt(10, 2), size: (40, 10));
    await t.mouse(MouseKind.move, 11, 2);
    await wait(t, ms * 400);
    expect(t, matchesScreen('\n\n          Help'));
    await wait(t, ms * 250);
    // light on a dark theme: the surface a fifth of the way to the text
    final chip = Color.rgb(
      (0x22 + (0xe6 - 0x22) * 0.2).round(),
      (0x25 + (0xe8 - 0x25) * 0.2).round(),
      (0x2c + (0xeb - 0x2c) * 0.2).round(),
    );
    expect(t, matchesScreen('\n\n          Help\n       Opens help'));
    expect(t, styleAt(6, 3, hasBg(chip)));
    expect(t, styleAt(7, 3, allOf(hasFg(dark.text.fg!), hasBg(chip))));
    expect(t, styleAt(17, 3, hasBg(chip)));
    await t.mouse(MouseKind.move, 12, 2);
    await t.pump();
    expect(t, hasTextAt(7, 3, 'Opens help'));
    await t.mouse(MouseKind.move, 30, 8);
    await t.pump();
    expect(t, matchesScreen('\n\n          Help'));
  });

  testTwk('the chip fades in over fadeIn, from what is under it', (t) async {
    await t.pumpWidget(helpAt(10, 2), size: (40, 10));
    await t.mouse(MouseKind.move, 11, 2);
    await t.pump(ms * 500);
    await t.pump(ms * 40);
    final chip = Tooltip.chipStyleOf(dark).bg!;
    expect(t, styleAt(6, 3, isNot(hasBg(chip))));
    await wait(t, ms * 80);
    expect(t, styleAt(6, 3, hasBg(chip)));
  });

  test('on a light theme the chip is dark, its text the background', () {
    const light = ThemeData.light;
    final style = Tooltip.chipStyleOf(light);
    expect(style.fg, light.background.bg);
    expect(
      style.bg,
      Color.rgb(
        (0x1f + (0xfa - 0x1f) * 0.08).round(),
        (0x23 + (0xfa - 0x23) * 0.08).round(),
        (0x28 + (0xfb - 0x28) * 0.08).round(),
      ),
    );
  });

  testTwk('the bordered look without a fade shows the message in a '
      'bordered box at once', (
    t,
  ) async {
    await t.pumpWidget(
      helpAt(10, 2, look: PanelLook.bordered, fadeIn: Duration.zero),
      size: (40, 10),
    );
    await t.mouse(MouseKind.move, 11, 2);
    await wait(t, ms * 500);
    expect(
      t,
      matchesScreen('''


          Help
     ┌────────────┐
     │ Opens help │
     └────────────┘'''),
    );
  });

  testTwk('a tooltip goes above its child when there is no room below, and '
      'moves in from the sides of the overlay', (t) async {
    await t.pumpWidget(helpAt(36, 9), size: (40, 10));
    await t.mouse(MouseKind.move, 37, 9);
    await wait(t, ms * 650);
    expect(t.lines.skip(8), [
      '                             Opens help',
      '                                    Help',
    ]);

    await t.pumpWidget(helpAt(0, 0));
    await t.mouse(MouseKind.move, 0, 0);
    await wait(t, ms * 650);
    expect(t.lines.take(2), ['Help', ' Opens help']);
  });

  testTwk('the mouse leaving before the wait shows nothing', (t) async {
    await t.pumpWidget(helpAt(10, 2), size: (40, 10));
    await t.mouse(MouseKind.move, 11, 2);
    await wait(t, ms * 300);
    await t.mouse(MouseKind.move, 30, 8);
    expect(t.clock.pendingTimers, 0);
    await wait(t, ms * 1000);
    expect(t, matchesScreen('\n\n          Help'));
  });

  testTwk('a tooltip goes with its child, in the same frame; a new message '
      'shows in it', (t) async {
    await t.pumpWidget(helpAt(10, 2), size: (40, 10));
    await t.mouse(MouseKind.move, 11, 2);
    await wait(t, ms * 650);
    await t.pumpWidget(helpAt(10, 2, message: 'Opens docs'));
    expect(t, hasTextAt(6, 3, ' Opens docs '));
    // a region kept: the terminal goes on reporting the mouse, nothing
    // written but frames
    final frames = t.terminal.frames.length;
    await t.pumpWidget(
      Theme(
        data: dark,
        child: Overlay(
          child: MouseRegion(onEnter: (_) {}, child: const Text('gone')),
        ),
      ),
    );
    expect(t, matchesScreen('gone'));
    expect(t.terminal.frames.length - frames, 1);
  });

  testTwk('a Tooltip without an Overlay above fails to build, saying where '
      'to place one', (t) async {
    await t.pumpWidget(const Tooltip(message: 'm', child: Text('Help')));
    const failed =
        'Tooltip failed to build: Bad state: Tooltip: no Overlay above it: '
        'place an Overlay above it, as around the whole app: '
        'Overlay(child: …)';
    expect(
      [
        for (final r in t.logs.records)
          if (r.level == LogLevel.error) '${r.message}: ${r.error}',
      ],
      [failed],
    );
  });

  testTwk('a tooltip shows once the focus has rested in its child, at once '
      'on no fade, and goes when the focus leaves', (t) async {
    await t.pumpWidget(buttons(), size: (40, 10));
    await t.press('tab');
    await wait(t, ms * 400);
    expect(tip(t), isNull);
    await wait(t, ms * 100);
    expect(tip(t), 'Opens help');
    await t.press('tab');
    await t.pump();
    expect(tip(t), isNull);
    await wait(t, ms * 1000);
    expect(tip(t), isNull);
    // back before the wait is over, then away: nothing shows
    await t.press('shift+tab');
    await wait(t, ms * 300);
    await t.press('tab');
    await wait(t, ms * 1000);
    expect(tip(t), isNull);
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('Escape hides a tooltip the focus showed, and is not left to the '
      'page; with none shown it is', (t) async {
    final log = <String>[];
    await t.pumpWidget(buttons(log: log), size: (40, 10));
    await t.press('tab');
    await wait(t, ms * 500);
    expect(tip(t), 'Opens help');
    await t.press('escape');
    await t.pump();
    expect(tip(t), isNull);
    expect(log, isEmpty);
    await t.press('escape');
    await t.pump();
    expect(log, ['page esc']);
    // it stays hidden while the focus stays; back again, it shows
    await wait(t, ms * 1000);
    expect(tip(t), isNull);
    await t.press('tab');
    await t.pump();
    await t.press('shift+tab');
    await wait(t, ms * 500);
    expect(tip(t), 'Opens help');
  });

  testTwk('a tooltip the focus holds stays as the mouse leaves; one the '
      'mouse holds stays as the focus leaves', (t) async {
    await t.pumpWidget(buttons(), size: (40, 10));
    await t.press('tab');
    await t.mouse(MouseKind.move, 2, 0);
    await wait(t, ms * 500);
    await t.mouse(MouseKind.move, 30, 8);
    await t.pump();
    expect(tip(t), 'Opens help');
    await t.mouse(MouseKind.move, 2, 0);
    await t.press('tab');
    await t.pump();
    expect(tip(t), 'Opens help');
    await t.mouse(MouseKind.move, 30, 8);
    await t.pump();
    expect(tip(t), isNull);
  });

  testTwk('showOnFocus false: the focus shows nothing; showOnHover false: '
      'the mouse shows nothing', (t) async {
    await t.pumpWidget(buttons(showOnFocus: false), size: (40, 10));
    await t.press('tab');
    await wait(t, ms * 1000);
    expect(tip(t), isNull);
    await t.mouse(MouseKind.move, 2, 0);
    await wait(t, ms * 500);
    expect(tip(t), 'Opens help');

    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(buttons(showOnHover: false));
    await t.mouse(MouseKind.move, 30, 8);
    await t.mouse(MouseKind.move, 2, 0);
    await wait(t, ms * 1000);
    expect(tip(t), isNull);
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('a TooltipController shows it at once and hides it, whatever the '
      'mouse and the focus do, and says whether it shows', (t) async {
    final controller = TooltipController();
    addTearDown(controller.dispose);
    final told = <bool>[];
    controller.addListener(() => told.add(controller.isShown));
    await t.pumpWidget(
      buttons(controller: controller, showOnHover: false, showOnFocus: false),
      size: (40, 10),
    );
    expect(controller.isShown, isFalse);
    controller.show();
    await t.pump();
    expect(tip(t), 'Opens help');
    expect(controller.isShown, isTrue);
    controller.show();
    await t.mouse(MouseKind.move, 2, 0);
    await t.mouse(MouseKind.move, 30, 8);
    await t.press('tab');
    await t.press('tab');
    await t.pump();
    expect(tip(t), 'Opens help');
    controller.hide();
    await t.pump();
    expect(tip(t), isNull);
    expect(controller.isShown, isFalse);
    expect(told, [true, false]);
  });

  testTwk('a TooltipController tells of what the mouse and the focus show; '
      'shown before its tooltip is built, it shows once built; Escape '
      'hides it', (t) async {
    final controller = TooltipController()..show();
    addTearDown(controller.dispose);
    expect(controller.isShown, isTrue);
    await t.pumpWidget(buttons(controller: controller), size: (40, 10));
    await t.pump();
    expect(tip(t), 'Opens help');
    await t.press('tab');
    await t.press('escape');
    await t.pump();
    expect(tip(t), isNull);
    expect(controller.isShown, isFalse);
    await t.press('tab');
    await t.mouse(MouseKind.move, 2, 0);
    await wait(t, ms * 500);
    expect(controller.isShown, isTrue);
    await t.mouse(MouseKind.move, 30, 8);
    await t.pump();
    expect(controller.isShown, isFalse);

    // another controller: the first no longer shows anything
    final other = TooltipController();
    addTearDown(other.dispose);
    controller.show();
    await t.pumpWidget(buttons(controller: other));
    await t.pump();
    expect(controller.isShown, isFalse);
    expect(tip(t), isNull);
    other.show();
    await t.pump();
    expect(tip(t), 'Opens help');
    controller
      ..show()
      ..hide();
    await t.pump();
    expect(tip(t), 'Opens help');
  });

  testTwk('the screen reader reads the message after the child, once, '
      'shown or not', (t) async {
    final controller = TooltipController();
    addTearDown(controller.dispose);
    await t.pumpWidget(buttons(controller: controller), size: (40, 10));
    await t.press('tab');
    await t.pump();
    final reading = ['button Help, Opens help', 'button Next'];
    expect(t.binding.semantics.lines, reading);
    expect(t.binding.semantics.focusedLine, 0);
    controller.show();
    await t.pump();
    expect(tip(t), 'Opens help');
    expect(t.binding.semantics.lines, reading);
  });

  testTwk('a tooltip its controller shows, moved in the tree with a '
      'GlobalKey, shows its message by its child in its new place', (
    t,
  ) async {
    final key = GlobalKey();
    final controller = TooltipController();
    addTearDown(controller.dispose);
    Widget app({required bool moved}) {
      final tooltip = Tooltip(
        key: key,
        message: 'tip',
        controller: controller,
        fadeIn: Duration.zero,
        look: PanelLook.bordered,
        child: const Text('Help'),
      );
      return Overlay(
        child: Align(
          alignment: Alignment.topLeft,
          child: moved
              ? Padding(padding: const EdgeInsets.only(left: 6), child: tooltip)
              : tooltip,
        ),
      );
    }

    await t.pumpWidget(app(moved: false), size: (20, 5));
    controller.show();
    await t.pump();
    expect(t, containsLine(contains('tip')));
    await t.pumpWidget(app(moved: true));
    await t.pump();
    expect(controller.isShown, isTrue);
    expect(t.lines.first, '      Help');
    expect(t, containsLine(contains('tip')));
  });
}
