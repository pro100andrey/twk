/// [AnimatedBuilder]: Flutter's name for a [ListenableBuilder] over an
/// animation, so that code written for Flutter ports as it is.
library;

import '../foundation/change_notifier.dart';
import '../foundation/listenable_builder.dart';
import 'animation_controller.dart' show AnimationController;

// Examples can assume:
// late AnimationController controller;

/// Shows what [builder] returns, built again whenever [animation] notifies,
/// as an [AnimationController] does each frame it moves: a
/// [ListenableBuilder] of [animation], under the name Flutter gives it.
/// [child] is built once by the parent and handed to [builder] each time.
///
/// ```dart
/// AnimatedBuilder(
///   animation: controller,
///   builder: (context, child) =>
///       Opacity(opacity: controller.value, child: child),
///   child: const Text('hello'),
/// )
/// ```
class AnimatedBuilder extends ListenableBuilder {
  /// Builds [builder] whenever [animation] notifies, handing it [child].
  const AnimatedBuilder({
    required Listenable animation,
    required super.builder,
    super.child,
    super.key,
  }) : super(listenable: animation);

  /// What this widget listens to: its [listenable].
  Listenable get animation => listenable;
}
