// A list and a route: the Coming from Flutter guide.
import 'package:twk/twk.dart';

final class Items extends StatelessWidget {
  const Items({super.key});

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: 100,
    itemBuilder: (context, i) => ListTile(
      title: Text('Item $i'),
      onTap: () => Navigator.push<void>(
        context,
        PageRoute(builder: (context) => Text('Item $i')),
      ),
    ),
  );
}
