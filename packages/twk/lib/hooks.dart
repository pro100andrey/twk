/// Hooks for widgets of the twk package, in the flutter_hooks style:
/// state, effects, memoized values, listenables, streams, futures,
/// animations and controllers that a build keeps by calling functions
/// (`useState`, `useEffect`, …), over the framework's elements.
///
/// The build of a `HookWidget`, of the state of a `StatefulHookWidget` or
/// of a `HookBuilder` calls them; a hook of one's own is a `Hook` and its
/// `HookState`, which `use` puts to work.
library;

export 'src/hooks/animation.dart';
export 'src/hooks/async.dart';
export 'src/hooks/controllers.dart';
export 'src/hooks/hook.dart';
export 'src/hooks/listenables.dart';
export 'src/hooks/primitives.dart';
