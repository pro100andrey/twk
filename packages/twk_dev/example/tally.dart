// A tally of a few things, to try the twk command on: Up and Down choose a
// line, + and - count, q quits; each count goes to the app's log. From
// packages/twk_dev (README.md walks through the tools with it):
//
//   dart run twk_dev:twk run example/tally.dart   # hot reloaded
//   dart run example/tally.dart                   # on its own
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Tally(['coffee', 'tea', 'water']));

/// A count of each of [names]: Up and Down choose one, + and - count it,
/// q quits. Each count goes to the app's log.
final class Tally extends StatefulWidget {
  const Tally(this.names, {super.key});

  final List<String> names;

  @override
  State<Tally> createState() => _TallyState();
}

final class _TallyState extends State<Tally> {
  late final List<int> _counts = List.filled(widget.names.length, 0);
  var _chosen = 0;

  void _choose(int by) =>
      setState(() => _chosen = (_chosen + by) % widget.names.length);

  void _count(int by) {
    final count = _counts[_chosen] + by;
    if (count < 0) {
      return;
    }
    setState(() => _counts[_chosen] = count);
    log('${widget.names[_chosen]}: $count');
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'up': () => _choose(-1),
      'down': () => _choose(1),
      '+': () => _count(1),
      '-': () => _count(-1),
      'q': () => AppBinding.of(context).quit(),
    },
    child: Box(
      border: const .all(type: .rounded),
      titles: const [
        BorderTitle(' tally '),
        BorderTitle(' + - count  q quit ', alignment: .bottomRight),
      ],
      padding: const .x(1),
      child: Column(
        children: [
          for (final (i, name) in widget.names.indexed)
            _Line(name, _counts[i], chosen: i == _chosen),
        ],
      ),
    ),
  );
}

/// [name], its [count] and a bar as long; the line [chosen] marked.
final class _Line extends StatelessWidget {
  const _Line(this.name, this.count, {required this.chosen});

  final String name;
  final int count;
  final bool chosen;

  @override
  Widget build(BuildContext context) => Row(
    gap: 1,
    children: [
      SizedBox(width: 1, child: chosen ? const Text('›') : null),
      SizedBox(
        width: 8,
        child: Text(name, style: Style(attrs: chosen ? Attr.bold : 0)),
      ),
      SizedBox(width: 3, child: Text('$count', align: .right)),
      Text('■' * count, style: const Style(fg: Color.green)),
    ],
  );
}
