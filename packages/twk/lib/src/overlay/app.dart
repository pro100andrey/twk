/// The root of an app: [App], its theme over the [Overlay] its dialogs
/// show in, in the order they go.
library;

import '../framework/framework.dart';
import '../style/theme.dart';
import 'layer.dart';

// Examples can assume:
// final class Home extends StatelessWidget {
//   const Home({super.key});
//   @override
//   Widget build(BuildContext context) => const Text('home');
// }

/// [child] under [theme] and the [Overlay] that its dialogs, toasts,
/// menus and tooltips show in, which `runApp` leaves to the app to place.
///
/// The theme goes above the overlay, so that what shows in it is in the
/// theme too; the overlay above the app's own `KeyBindings`, which [child]
/// puts at its root, so that they hear only the keys a dialog leaves, not
/// its `q` and `s` while it is open. What the dialogs read, the app's
/// providers and a [Theme] of its own, goes above [App]: an [App] under a
/// [Theme] has its dialogs in that theme. Without [theme] it places none,
/// and the widgets below take [Theme.of]'s.
///
/// A theme given or taken away keeps the state below, as a new one does.
///
/// ```dart
/// Future<void> main() => runApp(
///   const App(theme: ThemeData.nord, child: Home()),
/// );
/// ```
///
/// See also:
///
///  * [Overlay] and [Theme], which it places, for an app that places them
///    itself.
final class App extends StatefulWidget {
  /// [child] under [theme] and an overlay.
  const App({required this.child, super.key, this.theme});

  /// The theme of the app; null for none of its own, [Theme.of]'s.
  final ThemeData? theme;

  /// The app, its own `KeyBindings` at its root.
  final Widget child;

  @override
  State<App> createState() => _AppState();
}

final class _AppState extends State<App> {
  // the overlay keeps its entries and the app its state when a theme is
  // given or taken away
  final GlobalKey _overlay = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final overlay = Overlay(key: _overlay, child: widget.child);
    return theme == null ? overlay : Theme(data: theme, child: overlay);
  }
}
