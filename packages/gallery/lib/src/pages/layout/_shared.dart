// What the pages of the group share.
part of 'layout.dart';

/// [call] as the layout pages' Codes write it: to the whole 80 columns.
List<String> _call(int indent, String head, List<String> args, String tail) =>
    call(indent, head, args, tail, width: 80);

/// A rounded border in the theme's border style.
Border _rounded(ThemeData theme, {bool merge = false}) =>
    Border.all(type: BorderType.rounded, style: theme.border, merge: merge);

// twk's Alignments' names, row by row, and an Alignment's x and y as two
// choices
final List<String> _alignments = alignmentByName.keys.toList();

/// The alignment options, starting at [x] and [y].
List<PageOption<Object?>> _alignOptions(int x, int y) => [
  ChoiceOption<int>(
    _alignX.key,
    _alignX.label,
    values: _alignX.values,
    labels: _alignX.labels,
    initial: x,
  ),
  ChoiceOption<int>(
    _alignY.key,
    _alignY.label,
    values: _alignY.values,
    labels: _alignY.labels,
    initial: y,
  ),
];

/// What the alignment options are read by: x from -1 to 1.
const _alignX = ChoiceOption<int>(
  'ax',
  'alignment x',
  values: [-1, 0, 1],
  labels: ['left', 'center', 'right'],
);

/// See [_alignX]: y.
const _alignY = ChoiceOption<int>(
  'ay',
  'alignment y',
  values: [-1, 0, 1],
  labels: ['top', 'center', 'bottom'],
);

/// The name of the alignment options' Alignment.
String _alignmentOf(Options o) {
  final (x, y) = (o(_alignX), o(_alignY));
  return _alignments[(y + 1) * 3 + x + 1];
}

const _main = [
  'start',
  'end',
  'center',
  'spaceBetween',
  'spaceAround',
  'spaceEvenly',
];

/// The steps a timer of [ms] started with the page has ticked, on the
/// gallery's clock (0 while it stands still, as the design's born):
/// [builder] given them, built again at the next.
final class _Ticks extends StatefulWidget {
  const _Ticks({required this.ms, required this.builder});

  final int ms;
  final Widget Function(BuildContext context, int steps) builder;

  @override
  State<_Ticks> createState() => _TicksState();
}

final class _TicksState extends State<_Ticks> with MotionState {
  @override
  Widget build(BuildContext context) {
    motion.begin(context);
    final now = motion.now.inMilliseconds;
    final born = keptAt<int>(context, 'born', () => motion.frozen ? 0 : now);
    final steps = math.max(0, (now - born) ~/ widget.ms);
    motion
      ..wakeAt(Duration(milliseconds: born + (steps + 1) * widget.ms))
      ..end();
    return widget.builder(context, steps);
  }
}
