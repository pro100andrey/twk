// A widget named Tile; tile_a.dart has another of that name.
import 'package:twk/twk.dart';

final class Tile extends StatelessWidget {
  const Tile({super.key});

  @override
  Widget build(BuildContext context) => const Text('b');
}
