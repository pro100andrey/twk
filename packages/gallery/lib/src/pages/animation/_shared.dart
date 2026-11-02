// What the pages of the group share.
part of 'animation.dart';

/// The theme colours the Animation pages offer, in the design's order.
const _colors = ['primary', 'accent', 'success', 'warning', 'info'];

/// How long a widget of the group takes to run to a new value.
const _duration = Duration(milliseconds: 600);

/// The timer that gives a widget its next value while the page cycles: a
/// run of [_duration], then as long at rest.
const _cycle = 1200;

/// The curves the pages offer, by name.
const _curves = <String, Curve>{
  'linear': Curves.linear,
  'ease': Curves.ease,
  'easeIn': Curves.easeIn,
  'easeOut': Curves.easeOut,
  'easeInOut': Curves.easeInOut,
  'fastOutSlowIn': Curves.fastOutSlowIn,
  'decelerate': Curves.decelerate,
  'bounceOut': Curves.bounceOut,
  'elasticOut': Curves.elasticOut,
};

/// Each of [Curves], by name.
const _curveOption = ChoiceOption<String>(
  'curve',
  'curve',
  values: [
    'linear',
    'ease',
    'easeIn',
    'easeOut',
    'easeInOut',
    'fastOutSlowIn',
    'decelerate',
    'bounceOut',
    'elasticOut',
  ],
  initial: 'easeInOut',
);

const _cycleOption = SwitchOption('cycle', 'cycle', initial: true);

Curve _curveOf(Options o) => _curves[o(_curveOption)]!;

/// [builder] with the index of the value of option [option] (one of
/// [values]) the widget is given: the option's own, or while the page's
/// `cycle` switch is on, the next one every [_cycle] ms, as the Code's
/// timer gives it, the option moved along with it. The timer runs on the
/// gallery's clock: from when the page was built (0 while the clock
/// stands still, so a still at a route's `t=` has stepped as far as the
/// page would have), from when the switch was turned on; a value chosen
/// by hand while it cycles turns the cycle off, so the pick stays.
final class _Cycled extends StatefulWidget {
  const _Cycled(this.options, this.option, this.values, this.builder);

  final Options options;
  final PageOption<Object?> option;
  final List<Object?> values;
  final Widget Function(BuildContext context, int i) builder;

  @override
  State<_Cycled> createState() => _CycledState();
}

final class _CycledState extends State<_Cycled> with MotionState {
  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final w = widget;
    final control = PageControl.of(context);
    final kept = control.state;
    final now = motion.now;
    final n = w.values.length;
    final chosen = w.values.indexOf(w.options(w.option));
    final c = chosen < 0 ? 0 : chosen;
    var on = w.options(_cycleOption);
    final born = kept['born'] as Duration? ?? (motion.frozen ? .zero : now);
    kept['born'] = born;
    final name = 'drive:${w.option.key}';
    var d = kept[name] as Drive?;
    if (on && d != null && d.on && c != d.last) {
      scheduleMicrotask(() => control.setOption(_cycleOption, false));
      on = false;
    }
    if (d == null) {
      d = Drive(on: on, since: born, from: c);
      kept[name] = d;
    } else if (d.on != on) {
      d
        ..on = on
        ..since = now
        ..from = c;
    }
    var i = c;
    if (on) {
      final k = (now - d.since).inMilliseconds ~/ _cycle;
      final steps = k < 0 ? 0 : k;
      i = (d.from + steps) % n;
      motion.wakeAt(
        d.since + const Duration(milliseconds: _cycle) * (steps + 1),
      );
    }
    d.last = c;
    if (on && i != c) {
      final value = w.values[i];
      scheduleMicrotask(() => control.setOption(w.option, value));
      d.last = i;
    }
    motion.end();
    return w.builder(context, i);
  }
}

// ------------------------------------------------------------ code

const _dur = 'const Duration(milliseconds: 600)';

/// A number as JavaScript's String() writes it: `0.5`, `1`.
String _js(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// The curve argument at [n] columns, none for Curves.linear, the
/// default.
List<String> _curveLine(Options o, int n) {
  final curve = o(_curveOption);
  return curve == 'linear' ? [] : ['${' ' * n}curve: Curves.$curve,'];
}

List<String> _indent(List<String> lines, int n) => [
  for (final l in lines)
    if (l.isEmpty) l else '${' ' * n}$l',
];

/// The State's members around a build whose value a timer moves on every
/// [_cycle] ms: [fields], the timer, initState and dispose, then the
/// build with [body] in it.
List<String> _ticking(
  List<String> fields,
  String tick,
  String comment,
  List<String> body,
) => [
  ...fields,
  'late final Timer _timer;',
  '',
  '@override',
  'void initState() {',
  '  super.initState();',
  '  // $comment',
  '  _timer = Timer.periodic(',
  '    const Duration(milliseconds: $_cycle),',
  '    (_) => setState($tick),',
  '  );',
  '}',
  '',
  '@override',
  'void dispose() {',
  '  _timer.cancel();',
  '  super.dispose();',
  '}',
  '',
  '@override',
  ..._buildOf(body),
];

/// A build of [body]: an arrow to what it returns where it is just that.
List<String> _buildOf(List<String> body) {
  final top = body.where((l) => l.isNotEmpty && l[0] != ' ').length;
  if (body.first.startsWith('return ') && top == 2) {
    return [
      body.first.replaceFirst(
        'return ',
        'Widget build(BuildContext context) => ',
      ),
      ...body.skip(1),
    ];
  }
  return ['Widget build(BuildContext context) {', ..._indent(body, 2), '}'];
}

String _nextOf(String list) => '() => _i = (_i + 1) % $list.length';

/// `return` [child] at the top left of a SizedBox of [room], the room it
/// grows in ([what], and with elasticOut its overshoot).
List<String> _framed(
  Options o,
  (int, int) room,
  String what,
  List<String> child,
) => [
  codeLine([
    '// the room it grows in: $what',
    if (o(_curveOption) == 'elasticOut') ', and elasticOut beyond it',
  ]),
  'return SizedBox(',
  '  width: ${room.$1},',
  '  height: ${room.$2},',
  '  child: Align(',
  '    alignment: .topLeft,',
  '    child: ${child.first}',
  ..._indent(child.sublist(1, child.length - 1), 4),
  '    ${child.last},',
  '  ),',
  ');',
];

/// The room a widget that grows to [w] × [h] takes: elasticOut overshoots
/// by a quarter, [dw] × [dh] beyond it.
(int, int) _overshoot(Options o, int w, int h, int dw, int dh) =>
    o(_curveOption) == 'elasticOut' ? (w + dw, h + dh) : (w, h);

/// [child] at the top left of a SizedBox of [room].
Widget _inFrame((int, int) room, Widget child) => SizedBox(
  width: room.$1,
  height: room.$2,
  child: Align(alignment: .topLeft, child: child),
);

const _frames = <String, SpinnerFrames>{
  'dots': SpinnerFrames.dots,
  'line': SpinnerFrames.line,
  'arc': SpinnerFrames.arc,
};

// ---------------------------------------------------- AnimatedOpacity, Opacity

const _opacities = [0.0, 0.25, 0.5, 0.75, 1.0];

const _fractions = ['0', '¼', '½', '¾', '1'];
