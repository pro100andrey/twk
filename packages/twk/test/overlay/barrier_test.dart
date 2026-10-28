// ModalBarrier: the theme's shade by default, lighter on a light theme,
// each channel of the text, background and underline colours that far to
// the shade, rounded once; a colour and an alpha given are as given; a
// dialog's barrier is the theme's shade too, as it fades in; an
// AnimatedModalBarrier fades its shade in and out with an animation.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const black = Color.rgb(0, 0, 0);
const ul = Color.rgb(200, 100, 51);

/// [theme]'s surface under [barrier], with its muted text, underlined in
/// [ul], in the first cells.
Widget over(ThemeData theme, Widget barrier) => Theme(
  data: theme,
  child: Box(
    style: theme.surface,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Text(
          'ab',
          style: theme.muted.merge(
            const Style(attrs: Attr.underline, underlineColor: ul),
          ),
        ),
        barrier,
      ],
    ),
  ),
);

/// [c] blended with black, [alpha] of 255 of it.
Color shaded(Color c, int alpha) => Color.rgb(
  (c.r * (255 - alpha) / 255).round(),
  (c.g * (255 - alpha) / 255).round(),
  (c.b * (255 - alpha) / 255).round(),
);

/// [c] taken [k] of the way to [to], channel by channel, each rounded
/// once.
Color mixed(Color c, Color to, double k) {
  int channel(int a, int b) => (a + (b - a) * k).round();
  return Color.rgb(channel(c.r, to.r), channel(c.g, to.g), channel(c.b, to.b));
}

/// The cell at 0, 0 in [theme]'s muted text on its surface, underlined in
/// [ul], all [k] of the way to [theme]'s shade.
Matcher shadedCell(ThemeData theme, double k) => styleAt(
  0,
  0,
  allOf(
    hasBg(mixed(theme.surface.bg!, black, k)),
    hasFg(mixed(theme.muted.fg!, black, k)),
  ),
);

/// The underline colour of the cell at 0, 0.
int ulAt(TwkTester t) => t.cell(0, 0).ul;

void main() {
  testTwk('by default the barrier is the shade of the theme: black at half '
      'on a dark theme, at 28 % on a light one, the text, background and '
      'underline colours each taken that far to it, rounded once', (
    t,
  ) async {
    for (final theme in [ThemeData.dark, ThemeData.light]) {
      await t.pumpWidget(over(theme, const ModalBarrier()), size: (4, 2));
      final k = theme.shadeAlpha;
      expect(t, shadedCell(theme, k), reason: '${theme.brightness}');
      expect(ulAt(t), mixed(ul, black, k).value);
      // the shade at 1/255 more or less is not it
      expect(
        mixed(theme.surface.bg!, black, k),
        isNot(shaded(theme.surface.bg!, (k * 255).round())),
      );
    }
  });

  testTwk("a dialog's barrier is the theme's shade, mixed as far as it "
      'has faded in', (t) async {
    const theme = ThemeData.dark;
    final key = GlobalKey();
    await t.pumpWidget(
      Overlay(child: over(theme, SizedBox(key: key))),
      size: (8, 4),
    );
    final context = key.currentContext!;
    unawaited(
      t.clock.run(
        () => showDialog<void>(
          context,
          (_) => const SizedBox(width: 1, height: 1),
          fadeIn: const Duration(milliseconds: 100),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 50));
    // how far it has faded in, as the dialog shows it
    final k = t.widget<Opacity>(find.byType(Opacity).last).opacity;
    expect(k, inExclusiveRange(0, 1));
    expect(t, shadedCell(theme, theme.shadeAlpha * k));
    await t.pump(const Duration(milliseconds: 100));
    expect(t, shadedCell(theme, theme.shadeAlpha));
  });

  testTwk('the theme gives its own shade', (t) async {
    final theme = ThemeData.dark.copyWith(
      shade: const Style(bg: Color.rgb(200, 0, 0)),
      shadeAlpha: 1,
    );
    await t.pumpWidget(over(theme, const ModalBarrier()), size: (4, 2));
    expect(t, styleAt(0, 0, hasBg(const Color.rgb(200, 0, 0))));
    expect(t, styleAt(0, 0, hasFg(const Color.rgb(200, 0, 0))));
  });

  testTwk('a colour and an alpha given are as given on any theme: black at '
      '0x80 on a light one', (t) async {
    const light = ThemeData.light;
    await t.pumpWidget(
      over(light, const ModalBarrier(color: Color.rgb(0, 0, 0), alpha: 0x80)),
      size: (4, 2),
    );
    expect(t, styleAt(0, 0, hasBg(shaded(light.surface.bg!, 0x80))));
    expect(t, styleAt(0, 0, hasFg(shaded(light.muted.fg!, 0x80))));
  });

  testTwk('an AnimatedModalBarrier takes its shade as far as its animation '
      'has run, along its curve, in and out again; a click on it dismisses '
      'at any point', (t) async {
    const theme = ThemeData.dark;
    final fade = ValueNotifier<double>(0);
    var dismissed = 0;
    Widget app({Curve curve = Curves.linear, double? opacity}) => over(
      theme,
      AnimatedModalBarrier(
        animation: fade,
        curve: curve,
        opacity: opacity,
        onDismiss: () => dismissed++,
      ),
    );
    await t.pumpWidget(app(), size: (4, 2));
    expect(t, shadedCell(theme, 0));
    fade.value = 0.5;
    await t.pump();
    expect(t, shadedCell(theme, theme.shadeAlpha * 0.5));
    fade.value = 1;
    await t.pump();
    expect(t, shadedCell(theme, theme.shadeAlpha));
    fade.value = 0;
    await t.pump();
    expect(t, shadedCell(theme, 0));
    await t.click(2, 1);
    expect(dismissed, 1);

    fade.value = 0.5;
    await t.pumpWidget(app(curve: Curves.easeOut, opacity: 0.4));
    expect(t, shadedCell(theme, 0.4 * Curves.easeOut.transform(0.5)));
    // a value past the bounds, as an animation that overshoots, is held
    // to them
    fade.value = 1.5;
    await t.pump();
    expect(t, shadedCell(theme, 0.4));
  });

  testTwk('an AnimatedModalBarrier given another animation follows that '
      'one; a barrier built with another colour shades in it', (t) async {
    const theme = ThemeData.dark;
    final first = ValueNotifier<double>(1);
    final second = ValueNotifier<double>(0);
    await t.pumpWidget(
      over(theme, AnimatedModalBarrier(animation: first)),
      size: (4, 2),
    );
    expect(t, shadedCell(theme, theme.shadeAlpha));
    await t.pumpWidget(over(theme, AnimatedModalBarrier(animation: second)));
    expect(t, shadedCell(theme, 0));
    first.value = 0.5;
    await t.pump();
    expect(t, shadedCell(theme, 0), reason: 'the first one no more');
    second.value = 1;
    await t.pump();
    expect(t, shadedCell(theme, theme.shadeAlpha));
    const red = Color.rgb(255, 0, 0);
    await t.pumpWidget(over(theme, const ModalBarrier(color: red, alpha: 255)));
    expect(t, styleAt(0, 0, hasBg(red)));
    await t.pumpWidget(
      over(theme, const ModalBarrier(color: black, alpha: 255)),
    );
    expect(t, styleAt(0, 0, hasBg(black)));
  });

  testTwk('the render tree says the colour and the opacity of a barrier', (
    t,
  ) async {
    await t.pumpWidget(
      over(ThemeData.dark, const ModalBarrier(color: black, opacity: 0.25)),
      size: (4, 2),
    );
    final shade = t.renderObject<RenderObject>(find.byType(ModalBarrier));
    expect(shade.describe().toString(), contains('/25%'));
  });
}
