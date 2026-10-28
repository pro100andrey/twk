// The theming guide's app (doc/guides/theming.md): a status panel in
// Catppuccin, dark or light as the terminal's background is, its text in
// the theme's styles; q quits.
//
//   dart run example/guides/theming.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(
  // Catppuccin's dark flavor on a dark terminal, its light one on a light
  // one, switched when the terminal reports another color scheme; without
  // a Theme, ThemeData.dark and ThemeData.light
  const Theme.adaptive(
    dark: ThemeData.catppuccinMocha,
    light: ThemeData.catppuccinLatte,
    child: Status(),
  ),
);

final class Status extends StatelessWidget {
  const Status({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KeyBindings(
      {'q': () => AppBinding.of(context).quit()},
      child: Box(
        border: .all(type: .rounded, style: theme.border),
        titles: [BorderTitle(' Services ', style: theme.primary)],
        padding: const .all(1),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text.rich([Span('● ', theme.success), const Span('api      up')]),
            Text.rich([Span('● ', theme.warning), const Span('worker   slow')]),
            Text.rich([Span('● ', theme.error), const Span('mail     down')]),
            Text('q quits', style: theme.muted),
          ],
        ),
      ),
    );
  }
}
