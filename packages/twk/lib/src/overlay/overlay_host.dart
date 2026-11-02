/// What tells an `Overlay` whether it is a navigator's.
library;

import '../framework/framework.dart';

/// Put by a `Navigator` around its own `Overlay` (above the navigator's
/// back key), and reset by every `Overlay` below its own: the `Overlay`
/// right below [navigator] true is a navigator's, and finds the node above
/// the navigator in this widget's context. Not exported.
final class OverlayHost extends InheritedWidget {
  /// Tells the `Overlay` below whether it is a navigator's.
  const OverlayHost({required this.navigator, required super.child, super.key});

  /// Whether the `Overlay` right below is a navigator's.
  final bool navigator;

  @override
  bool updateShouldNotify(OverlayHost oldWidget) =>
      navigator != oldWidget.navigator;
}
