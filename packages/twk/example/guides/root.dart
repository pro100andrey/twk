// The state guide's root swap (doc/guides/state.md): Enter replaces the
// whole app with another widget, `AppBinding.attachRootWidget`; q quits.
//
//   dart run example/guides/root.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Welcome());

final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      // the app from the next frame on is Home; Welcome is unmounted
      'enter': () => AppBinding.of(context).attachRootWidget(const Home()),
      'q': () => AppBinding.of(context).quit(),
    },
    child: const Focus(autofocus: true, child: Text('Welcome. Enter goes on.')),
  );
}

final class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    child: const Focus(autofocus: true, child: Text('Home. q quits.')),
  );
}
