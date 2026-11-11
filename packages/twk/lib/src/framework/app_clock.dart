/// [AppClock]: the clock of the app, for the framework layer to ask for.
library;

import 'framework.dart' show InheritedWidget, StartTimer, State;

/// The clock of the app, put above it by the binding (`runApp`, a `Cli`,
/// a tester), not exported by `twk.dart`: what a [State] asks for as
/// [State.appTimer], for work that waits on the app's time — a grace, a
/// delay — without this layer knowing the binding.
final class AppClock extends InheritedWidget {
  /// Gives [startTimer] to everything under [child].
  const AppClock(this.startTimer, {required super.child, super.key});

  /// The app's `AppBinding.startTimer`.
  final StartTimer startTimer;

  @override
  bool updateShouldNotify(AppClock oldWidget) =>
      !identical(startTimer, oldWidget.startTimer);
}
