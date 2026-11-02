// The theming guide's glyphs (doc/guides/theming.md): the same report in
// the default marks and in ASCII with a check of its own; q quits.
//
//   dart run example/guides/glyphs.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(
  // ASCII all through, but a plus for a check: the marks widgets draw
  // are the theme's Glyphs
  Theme(
    data: ThemeData.dark.copyWith(
      glyphs: Glyphs.ascii.copyWith(check: '+'),
    ),
    child: const Report(),
  ),
);

final class Report extends StatelessWidget {
  const Report({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    child: const Column(
      crossAxisAlignment: .start,
      children: [
        StatusMessage('Built in 2 s', kind: StatusKind.success),
        StatusMessage('3 files skipped', kind: StatusKind.warning),
        LineGauge(ratio: 0.6, label: 'upload '),
        Checkbox(value: true, onChanged: null, label: 'Publish'),
      ],
    ),
  );
}
