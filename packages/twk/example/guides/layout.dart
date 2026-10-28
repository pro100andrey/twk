// The layout guide's app (doc/guides/layout.md): a title row, two boxes
// side by side that share the rest, and a row of hints; q quits.
//
//   dart run example/guides/layout.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Layout());

final class Layout extends StatelessWidget {
  const Layout({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    child: Column(
      // each child as wide as the column, not centred across it
      crossAxisAlignment: .stretch,
      children: [
        Text.rich([' twk'.bold, ' · layout'.dim]),
        // the rows the title and the hints leave
        const Expanded(
          child: Row(
            crossAxisAlignment: .stretch,
            children: [
              // a fixed width
              SizedBox(
                width: 20,
                child: Box(
                  border: .all(type: .rounded),
                  titles: [BorderTitle(' Files ')],
                  padding: EdgeInsets.x(1),
                  child: Text('lib/\ntest/\npubspec.yaml'),
                ),
              ),
              // the columns the files leave
              Expanded(
                child: Box(
                  border: .all(type: .rounded),
                  titles: [BorderTitle(' Preview ')],
                  padding: EdgeInsets.x(1),
                  child: Text(
                    'Everything is measured in cells. A Row gives its '
                    'fixed children their width first, then shares what '
                    'is left among the Expanded ones.',
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(' q quits', style: Theme.of(context).muted),
      ],
    ),
  );
}
