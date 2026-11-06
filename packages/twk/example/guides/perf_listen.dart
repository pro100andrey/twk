// The performance guide's first app (doc/guides/performance.md): the
// counter is the only widget a key builds again; the hint is the child
// the builder is handed.
//
//   dart run example/guides/perf_listen.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Dashboard());

final class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

final class _DashboardState extends State<Dashboard> {
  final ValueNotifier<int> _count = ValueNotifier(0);

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      '+': () => _count.value++,
      'q': () => AppBinding.of(context).quit(),
    },
    child: Focus(
      autofocus: true,
      child: ValueListenableBuilder<int>(
        valueListenable: _count,
        child: const Text('+ counts, q quits'),
        builder: (context, count, hint) => Column(
          children: [Text('count: $count'), hint!],
        ),
      ),
    ),
  );
}
