// Panels: raised by default, a cell of room and the theme's shadow; the
// bordered look as big, a border where the room was.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData dark = ThemeData.dark;

Widget themed(Widget child, {ThemeData theme = dark}) => Theme(
  data: theme,
  child: Box(
    style: theme.background,
    child: Align(alignment: Alignment.topLeft, child: child),
  ),
);

void main() {
  testTwk('a panel is raised: the surface, a cell of room, no outline, and '
      'a shadow two columns right and a row down', (t) async {
    await t.pumpWidget(
      themed(const Panel(child: Text('hi'))),
      size: (8, 5),
    );
    expect(t, matchesScreen('\n hi'));
    final surface = dark.surface.bg!;
    final background = dark.background.bg!;
    expect(t, styleAt(0, 0, hasBg(surface)));
    expect(t, styleAt(3, 2, hasBg(surface)));
    // the shadow: the background darkened by black at 55 %
    final shaded = Color.rgb(
      (0x16 * 0.45).round(),
      (0x18 * 0.45).round(),
      (0x1d * 0.45).round(),
    );
    expect(t, styleAt(4, 1, hasBg(shaded)));
    expect(t, styleAt(5, 3, hasBg(shaded)));
    expect(t, styleAt(1, 3, hasBg(background)));
    expect(t, styleAt(6, 1, hasBg(background)));
  });

  testTwk('the shadow is lighter on a light theme', (t) async {
    await t.pumpWidget(
      themed(const Panel(child: Text('hi')), theme: ThemeData.light),
      size: (8, 5),
    );
    final bg = ThemeData.light.background.bg!;
    final shaded = Color.rgb(
      (bg.r * 0.82).round(),
      (bg.g * 0.82).round(),
      (bg.b * 0.82).round(),
    );
    expect(t, styleAt(4, 1, hasBg(shaded)));
  });

  testTwk('the shadow takes the cells under it exactly 55 % and 18 % of '
      'the way to black, not a whole number of 255ths', (
    t,
  ) async {
    expect(Panel.shadowOf(dark).opacity, 0.55);
    expect(Panel.shadowOf(ThemeData.light).opacity, 0.18);
    // 101 at 55 % is 45.45, at 140 of 255 45.55; 25 at 18 % is 20.5, at
    // 46 of 255 20.49
    for (final (theme, under, shaded) in [
      (dark, 101, 45),
      (ThemeData.light, 25, 21),
    ]) {
      await t.pumpWidget(
        themed(
          const Panel(child: Text('hi')),
          theme: theme.copyWith(
            background: Style(bg: Color.rgb(under, under, under)),
          ),
        ),
        size: (8, 5),
      );
      final c = Color.rgb(shaded, shaded, shaded);
      expect(t, styleAt(4, 1, hasBg(c)), reason: '${theme.brightness}');
      expect(t, styleAt(2, 3, hasBg(c)), reason: '${theme.brightness}');
    }
  });

  testTwk('the bordered look is as big, its border where the room was, and '
      'casts no shadow when asked not to', (t) async {
    await t.pumpWidget(
      themed(
        const Panel(
          look: PanelLook.bordered,
          shadow: false,
          padding: EdgeInsets.x(1),
          child: Text('hi'),
        ),
      ),
      size: (8, 4),
    );
    expect(
      t,
      matchesScreen('''
┌────┐
│ hi │
└────┘'''),
    );
    expect(t, styleAt(0, 0, hasFg(dark.border.fg!)));
    expect(t, styleAt(6, 1, hasBg(dark.background.bg!)));
  });

  testTwk('padding goes inside the room, and style over the surface', (
    t,
  ) async {
    await t.pumpWidget(
      themed(
        const Panel(
          shadow: false,
          padding: EdgeInsets.x(1),
          style: Style(bg: Color.rgb(1, 2, 3)),
          child: Text('hi'),
        ),
      ),
      size: (8, 4),
    );
    expect(t, hasTextAt(2, 1, 'hi'));
    expect(t, styleAt(5, 2, hasBg(const Color.rgb(1, 2, 3))));
    expect(t, styleAt(6, 1, hasBg(dark.background.bg!)));
  });
}
