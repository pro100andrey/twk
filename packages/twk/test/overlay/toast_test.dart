// Toasts: shown for their time on the fake clock, three at a time and the
// rest queued, where their alignment puts them; their time stopped with
// their overlay; no Overlay; in the bordered look. The raised look: the
// bar and the icon of the kind, the shadow and the row between two, the
// slide in and the fade out.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Shows the toasts [toasts] gives for each key as it is pressed.
final class Toaster extends StatelessWidget {
  const Toaster(this.toasts, {super.key, this.look = PanelLook.bordered});

  final Map<String, List<(String, int, Alignment)>> toasts;
  final PanelLook look;

  @override
  Widget build(BuildContext context) => KeyBindings({
    for (final MapEntry(:key, value: shown) in toasts.entries)
      key: () {
        for (final (message, seconds, alignment) in shown) {
          showToast(
            context,
            message,
            duration: Duration(seconds: seconds),
            alignment: alignment,
            look: look,
          );
        }
      },
  }, child: const SizedBox.expand());
}

const second = Duration(seconds: 1);

/// Moves the clock on by [time], then by a frame, which shows what changed
/// at the end of [time].
Future<void> wait(TwkTester t, Duration time) async {
  await t.pump(time);
  await t.pump();
}

void main() {
  testTwk('a toast shows at the bottom right for its time on the clock', (
    t,
  ) async {
    await t.pumpWidget(
      const Overlay(
        child: Toaster({
          's': [('Saved', 3, Alignment.bottomRight)],
        }),
      ),
      size: (20, 6),
    );
    await t.press('s');
    await t.pump();
    expect(
      t,
      matchesScreen('''


          ┌───────┐
          │ Saved │
          └───────┘'''),
    );
    await wait(t, second * 2);
    expect(t, hasTextAt(10, 3, '│ Saved │'));
    await wait(t, second);
    expect(t, matchesScreen(''));
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('three toasts show at a time, one under another; the next waits '
      'until one has gone, its time running from then', (t) async {
    await t.pumpWidget(
      const Overlay(
        child: Toaster({
          'a': [
            ('one', 1, Alignment.topLeft),
            ('two', 3, Alignment.topLeft),
            ('six', 3, Alignment.topLeft),
            ('ten', 3, Alignment.topLeft),
          ],
        }),
      ),
      size: (20, 12),
    );
    List<String> shown() => [
      for (final line in t.lines)
        if (line.startsWith(' │ ')) line.substring(3, 6),
    ];

    await t.press('a');
    await t.pump();
    expect(shown(), ['one', 'two', 'six']);
    await wait(t, second);
    expect(shown(), ['two', 'six', 'ten']);
    await wait(t, second);
    expect(shown(), ['two', 'six', 'ten']);
    await wait(t, second);
    expect(shown(), ['ten']);
    await wait(t, second);
    expect(shown(), isEmpty);
  });

  testTwk('toasts stand where their alignment puts them, a cell in from the '
      'edges', (t) async {
    await t.pumpWidget(
      const Overlay(
        child: Toaster({
          'a': [
            ('nw', 3, Alignment.topLeft),
            ('c', 3, Alignment.center),
            ('se', 3, Alignment.bottomRight),
          ],
        }),
      ),
      size: (20, 11),
    );
    await t.press('a');
    await t.pump();
    expect(
      t,
      matchesScreen('''

 ┌────┐
 │ nw │
 └────┘
       ┌───┐
       │ c │
       └───┘
             ┌────┐
             │ se │
             └────┘'''),
    );
  });

  testTwk('the time of the toasts stops with their overlay', (t) async {
    await t.pumpWidget(
      const Overlay(
        child: Toaster({
          's': [('Saved', 3, Alignment.bottomRight)],
        }),
      ),
    );
    await t.press('s');
    await t.pump();
    expect(t.clock.pendingTimers, 1);
    await t.pumpWidget(const Text('gone'));
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('showToast without an Overlay above says where to place one', (
    t,
  ) async {
    final key = GlobalKey();
    await t.pumpWidget(SizedBox(key: key, width: 1, height: 1));
    expect(
      () => showToast(key.currentContext!, 'Saved'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'showToast: no Overlay above SizedBox: place an Overlay above it, '
              'as around the whole app: Overlay(child: …)',
        ),
      ),
    );
  });

  group('raised toasts', () {
    const theme = ThemeData.dark;
    const ms = Duration(milliseconds: 1);

    /// Shows a toast in the style of each kind on `s`, and one in no
    /// style on `n`.
    Widget kinds({Alignment alignment = Alignment.bottomRight}) => Theme(
      data: theme,
      child: Box(
        style: theme.background,
        child: Overlay(
          child: Builder(
            builder: (context) => KeyBindings({
              's': () {
                for (final (message, style) in [
                  ('Saved', theme.success),
                  ('Error', theme.error),
                ]) {
                  showToast(
                    context,
                    message,
                    style: style,
                    alignment: alignment,
                  );
                }
              },
              'n': () => showToast(context, 'Plain', alignment: alignment),
            }, child: const SizedBox.expand()),
          ),
        ),
      ),
    );

    testTwk('a toast is a raised panel: a bar and an icon in the color of '
        'its kind, the message in the text, a row of room, the shadow, a row '
        'between two', (t) async {
      await t.pumpWidget(kinds(), size: (20, 10));
      await t.press('s');
      await t.pump(ms * 300);
      expect(t.lines.sublist(1, 9), [
        '      ▌',
        '      ▌ ✓ Saved',
        '      ▌',
        '',
        '      ▌',
        '      ▌ ✗ Error',
        '      ▌',
        '',
      ]);
      expect(t, styleAt(6, 2, hasFg(theme.success.fg!)));
      expect(t, styleAt(8, 2, hasFg(theme.success.fg!)));
      expect(t, styleAt(10, 2, hasFg(theme.text.fg!)));
      expect(t, styleAt(16, 2, hasBg(theme.surface.bg!)));
      expect(t, styleAt(6, 6, hasFg(theme.error.fg!)));
      // the shadow: two columns at the right, the row between the toasts
      final background = theme.background.bg!;
      final shaded = Color.rgb(
        (background.r * 115 / 255).round(),
        (background.g * 115 / 255).round(),
        (background.b * 115 / 255).round(),
      );
      expect(t, styleAt(17, 2, hasBg(shaded)));
      expect(t, styleAt(18, 3, hasBg(shaded)));
      expect(t, styleAt(12, 4, hasBg(shaded)));
      expect(t, styleAt(5, 2, hasBg(background)));
    });

    testTwk("a toast in no kind's style has no icon, its bar primary", (
      t,
    ) async {
      await t.pumpWidget(kinds(), size: (20, 6));
      await t.press('n');
      await t.pump(ms * 300);
      expect(t, hasTextAt(8, 2, '▌ Plain'));
      expect(t, styleAt(8, 2, hasFg(theme.primary.fg!)));
    });

    testTwk('a toast slides in from the right over 200 ms and fades out '
        'over the last 260 ms of its time', (t) async {
      await t.pumpWidget(kinds(), size: (20, 6));
      await t.press('n');
      await t.pump();
      expect(t.lines[2], '');
      await t.pump(ms * 60);
      final x = t.lines[2].indexOf('▌');
      expect(x, greaterThan(8));
      await t.pump(ms * 200);
      expect(t, hasTextAt(8, 2, '▌ Plain'));
      await t.pump(ms * 2400);
      expect(t, styleAt(10, 2, hasBg(theme.surface.bg!)));
      // three seconds in all, the last 260 ms fading
      await t.pump(ms * 200);
      expect(t, isNot(styleAt(10, 2, hasBg(theme.surface.bg!))));
      expect(t, isNot(styleAt(10, 2, hasBg(theme.background.bg!))));
      await t.pump(ms * 200);
      await t.pump();
      expect(t.lines[2], '');
      expect(t.clock.pendingTimers, 0);
    });

    testTwk('one centred at the bottom slides up from the bottom edge', (
      t,
    ) async {
      await t.pumpWidget(
        kinds(alignment: Alignment.bottomCenter),
        size: (20, 6),
      );
      await t.press('n');
      await t.pump();
      await t.pump(ms * 60);
      expect(t.lines[2], isNot(contains('Plain')));
      await t.pump(ms * 200);
      expect(t.lines[2], contains('▌ Plain'));
    });

    testTwk('a toast shorter than its fade fades out from the start', (
      t,
    ) async {
      final key = GlobalKey();
      await t.pumpWidget(
        Theme(
          data: theme,
          child: Box(
            style: theme.background,
            child: Overlay(child: SizedBox.expand(key: key)),
          ),
        ),
        size: (20, 6),
      );
      showToast(
        key.currentContext!,
        'Brief',
        duration: const Duration(milliseconds: 200),
      );
      await t.pump();
      await t.pump(ms * 100);
      expect(t, containsLine(contains('Brief')));
      expect(
        t,
        isNot(styleAt(10, 2, hasBg(theme.surface.bg!))),
        reason: 'fading already',
      );
      await t.pump(ms * 150);
      await t.pump();
      expect(t, isNot(containsLine(contains('Brief'))));
    });

    testTwk("a toast's bar takes the color of the theme it is shown in as "
        'that changes', (t) async {
      final key = GlobalKey();
      Widget app(ThemeData theme) => Theme(
        data: theme,
        child: Overlay(child: SizedBox.expand(key: key)),
      );
      await t.pumpWidget(app(theme), size: (20, 6));
      showToast(key.currentContext!, 'Plain');
      await t.pump(ms * 300);
      expect(t, styleAt(8, 2, hasFg(theme.primary.fg!)));
      const light = ThemeData.light;
      await t.pumpWidget(app(light));
      expect(t, styleAt(8, 2, hasFg(light.primary.fg!)));
    });
  });
}
