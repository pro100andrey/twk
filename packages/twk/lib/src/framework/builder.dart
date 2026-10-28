/// Widgets built by a function: [Builder], and [StatefulBuilder] with state
/// of its own.
library;

import '../foundation/change_notifier.dart' show VoidCallback;
import 'framework.dart';

/// What builds a widget at a [BuildContext]: a [Builder]'s.
typedef WidgetBuilder = Widget Function(BuildContext context);

/// The widget [builder] returns, built with this widget's own context: what
/// a widget built inline reads from above it (`Theme.of`,
/// `DefaultTextStyle.of`, `Scrollable.of`, …) without a class of its own,
/// or from below a widget that puts it there in the same build. A rebuild
/// of the widget above calls [builder] again, as does a change of what it
/// depends on through its context. Flutter's Builder.
///
/// A text in the color of the theme above, without a class of its own:
///
/// ```dart
/// Builder(
///   builder: (context) => Text('Saved', style: Theme.of(context).primary),
/// )
/// ```
///
/// See also:
///
///  * [StatefulBuilder], which builds again when its function says so.
///  * [LayoutBuilder], which builds with the constraints too, in the
///    layout.
final class Builder extends StatelessWidget {
  /// Shows what [builder] returns.
  const Builder({required this.builder, super.key});

  /// Builds the child with this widget's context.
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

/// What changes a [StatefulBuilder]'s state: [State.setState] of it.
typedef StateSetter = void Function(VoidCallback fn);

/// What builds a [StatefulBuilder]'s widget: with its context and what
/// builds it again.
typedef StatefulWidgetBuilder = Widget Function(
  BuildContext context,
  StateSetter setState,
);

/// The widget [builder] returns, built again when the `setState` it is
/// handed is called: a part of a build with a state of its own, without a
/// [StatefulWidget] class for it. Flutter's StatefulBuilder.
///
/// What the state is lives outside [builder], which is called on each
/// build: in the [State] around it, or in a variable the function closes
/// over that outlives its calls. A `setState` called after the widget left
/// the tree asserts, as [State.setState] does.
///
/// A button that counts its presses, in a dialog whose builder is called
/// once:
///
/// ```dart
/// var count = 0;
/// final counter = StatefulBuilder(
///   builder: (context, setState) => Button(
///     'pressed $count times',
///     onPressed: () => setState(() => count++),
///   ),
/// );
/// ```
///
/// See also:
///
///  * [Builder], without the state.
///  * `ValueListenableBuilder`, which builds again as a value changes,
///    the value held apart from the widget.
final class StatefulBuilder extends StatefulWidget {
  /// Shows what [builder] returns, built again by its `setState`.
  const StatefulBuilder({required this.builder, super.key});

  /// Builds the child with this widget's context and what builds it again.
  final StatefulWidgetBuilder builder;

  @override
  State<StatefulBuilder> createState() => _StatefulBuilderState();
}

final class _StatefulBuilderState extends State<StatefulBuilder> {
  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
}
