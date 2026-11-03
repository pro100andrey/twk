// The page's own state, which outlives a visit to another page
// (PageControl.state), as the States of its widget keep it.
import 'package:twk/twk.dart';

import '../../page.dart';

/// A State of a page's widget that keeps what it shows in the page's
/// state ([PageControl.state]), so that it is still there when the page
/// is left and come back to.
///
/// [kept] is asked of the page's control each time rather than held:
/// "Reset the options" in the palette gives the page a fresh one. The
/// control is held, so that a callback after the widget left the tree (a
/// focus lost as it goes) still finds it.
mixin KeptState<W extends StatefulWidget> on State<W> {
  late final PageControl _control = PageControl.of(context);

  /// The page's state.
  Map<String, Object?> get kept => _control.state;

  /// [key] of the kept state, [or] while it has none.
  V keptOr<V>(String key, V or) => kept[key] as V? ?? or;

  /// [key] of the kept state, made by [create] the first time.
  T keptPut<T>(String key, T Function() create) =>
      kept.putIfAbsent(key, create) as T;

  /// Sets [key] of the kept state to [value], and counts the change.
  void keep(String key, Object? value) => setState(() {
    kept[key] = value;
    kept['serial'] = serial + 1;
  });

  /// How often the kept state changed.
  int get serial => keptOr('serial', 0);
}

/// [key] of the page's state at [context], made by [create] the first
/// time: what outlives a visit to another page.
T keptAt<T>(BuildContext context, String key, T Function() create) =>
    PageControl.of(context).state.putIfAbsent(key, create) as T;
