// A color animated on the fake clock: TweenAnimationBuilder<Color> with
// ColorTween runs each RGB channel to the new color a frame at a time, and
// switches halfway to or from a color that is not RGB; a widget of the
// app's own on ImplicitlyAnimatedWidget visits a Color tween.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

/// The channels of [c], `r,g,b`, or what it is when it is not RGB.
String rgb(Color c) => c.isRgb
    ? '${c.r},${c.g},${c.b}'
    : (c.isDefault ? 'default' : 'palette ${c.index}');

/// Starts an app at 100 frames a second, a frame each 10 ms, that shows
/// what [build] makes of the color of the notifier it returns.
Future<ValueNotifier<Color>> start(
  TwkTester t,
  Color first,
  Widget Function(Color value) build,
) async {
  final value = ValueNotifier(first);
  await t.pumpWidget(
    ValueListenableBuilder<Color>(
      valueListenable: value,
      builder: (_, v, _) => build(v),
    ),
    size: (20, 1),
    maxFps: 100,
  );
  return value;
}

/// The first line after each of [count] frames.
Future<List<String>> frames(TwkTester t, int count) async => [
  for (var i = 0; i < count; i++) await t.pump().then((_) => t.lines.single),
];

/// A cell of [color] that runs to each new one; a widget of the app's own.
final class Swatch extends ImplicitlyAnimatedWidget {
  const Swatch({required this.color, required super.duration, super.key});

  final Color color;

  @override
  State<Swatch> createState() => _SwatchState();
}

final class _SwatchState extends ImplicitlyAnimatedWidgetState<Swatch> {
  Tween<Color>? _color;

  @override
  void forEachTween(TweenVisitor visit) =>
      _color = visit(_color, widget.color, ColorTween.new);

  @override
  Widget build(BuildContext context) => Text(rgb(_color!.transform(progress)));
}

void main() {
  testTwk('TweenAnimationBuilder<Color> runs each channel to the new color '
      'from the one it shows', (t) async {
    final value = await start(
      t,
      const Color.rgb(0, 0, 0),
      (value) => TweenAnimationBuilder<Color>(
        value: value,
        tween: ColorTween.new,
        duration: ms * 40,
        builder: (_, color, _) => Text(rgb(color)),
      ),
    );
    expect(t.lines.single, '0,0,0');
    value.value = const Color.rgb(100, 200, 40);
    expect(await frames(t, 5), [
      '0,0,0',
      '25,50,10',
      '50,100,20',
      '75,150,30',
      '100,200,40',
    ]);
  });

  testTwk('TweenAnimationBuilder<Color> switches halfway to a palette color '
      'or the default', (t) async {
    final value = await start(
      t,
      const Color.rgb(0, 0, 0),
      (value) => TweenAnimationBuilder<Color>(
        value: value,
        from: const Color.rgb(200, 0, 0),
        tween: ColorTween.new,
        duration: ms * 40,
        builder: (_, color, _) => Text(rgb(color)),
      ),
    );
    expect(await frames(t, 4), ['150,0,0', '100,0,0', '50,0,0', '0,0,0']);
    await t.pump(const Duration(seconds: 1));
    value.value = Color.blue;
    expect(await frames(t, 5), [
      '0,0,0',
      '0,0,0',
      'palette 4',
      'palette 4',
      'palette 4',
    ]);
    await t.pump(const Duration(seconds: 1));
    value.value = Color.defaultColor;
    expect(await frames(t, 4), [
      'palette 4',
      'palette 4',
      'default',
      'default',
    ]);
  });

  testTwk("a widget of the app's own visits a Color tween", (t) async {
    final value = await start(
      t,
      const Color.rgb(0, 0, 0),
      (value) => Swatch(color: value, duration: ms * 20),
    );
    expect(t.lines.single, '0,0,0');
    value.value = const Color.rgb(0, 100, 0);
    expect(await frames(t, 3), ['0,0,0', '0,50,0', '0,100,0']);
  });
}
