// What the tests share: a counter that notifies, widgets that log their
// builds, and the errors an app logged.
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A count that notifies its listeners when it changes, and knows whether
/// it was disposed.
final class Counter extends ChangeNotifier {
  Counter([this._count = 0]);

  int _count;
  var disposed = false;

  int get count => _count;

  set count(int value) {
    _count = value;
    notifyListeners();
  }

  void increment() => count = _count + 1;

  /// Whether anything listens.
  bool get listened => hasListeners;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Lays [children] out in a column, [log] told of each build.
final class Logged extends StatelessWidget {
  const Logged(this.name, this.log, this.children, {super.key});

  final String name;
  final List<String> log;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    log.add(name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Shows what [builder] returns, [log] told of each build as [name].
final class Built extends StatelessWidget {
  const Built(this.name, this.log, this.builder, {super.key});

  final String name;
  final List<String> log;
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) {
    log.add(name);
    return builder(context);
  }
}

/// Shows what [builder] returns: a context for it.
final class Show extends StatelessWidget {
  const Show(this.builder, {super.key});

  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

/// The errors the app logged, the builds that threw.
List<Object?> loggedErrors(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level == LogLevel.error) r.error,
];
