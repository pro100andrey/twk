// A notifier and its builder: the Coming from Flutter guide.
import 'package:twk/twk.dart';

final counter = ValueNotifier<int>(0);
final built = ValueListenableBuilder<int>(
  valueListenable: counter,
  builder: (context, n, _) => Text('$n'),
);
