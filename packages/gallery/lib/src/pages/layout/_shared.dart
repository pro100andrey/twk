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

List<PageOption> _alignOptions(int x, int y) => [
  ChoiceOption(
    'ax',
    'alignment x',
    values: const [-1, 0, 1],
    labels: const ['left', 'center', 'right'],
    initial: x,
  ),
  ChoiceOption(
    'ay',
    'alignment y',
    values: const [-1, 0, 1],
    labels: const ['top', 'center', 'bottom'],
    initial: y,
  ),
];

/// The name of the alignment options' Alignment.
String _alignmentOf(Options o) =>
    _alignments[(o.choice<int>('ay') + 1) * 3 + o.choice<int>('ax') + 1];

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
