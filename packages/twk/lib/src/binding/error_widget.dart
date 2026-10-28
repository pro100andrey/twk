/// What a widget shows in place of what it builds when that threw:
/// [ErrorWidget].
library;

import 'package:twk_core/twk_core.dart' show Brightness, Color, RenderErrorBox;

import '../framework/framework.dart';
import '../style/style.dart';

// Examples can assume:
// late Future<String> answer;

/// A red block with the message of an error (`RenderErrorBox`), which an
/// app run by `runApp` shows in place of what a widget builds when its
/// build throws, or what it builds throws as it is created or updated
/// ([BuildOwner.onBuildError]). Its text is the terminal's bright white on
/// a dark theme and plain white on a light one, whose palette may make
/// bright white dark.
///
/// It is as big as its constraints allow, and its message is cut off
/// where it does not fit. A widget shows one itself for an error it
/// caught:
///
/// ```dart
/// FutureBuilder<String>(
///   future: answer,
///   builder: (context, snapshot) => snapshot.hasError
///       ? ErrorWidget(snapshot.error!)
///       : Text(snapshot.data ?? '…'),
/// )
/// ```
final class ErrorWidget extends LeafRenderObjectWidget {
  /// Shows [error]'s message.
  const ErrorWidget(this.error, {super.key});

  /// What failed; the block shows it as a string ([message]).
  final Object error;

  /// What the block says: the error as a string.
  String get message => '$error';

  @override
  RenderErrorBox createRenderObject(BuildContext context) =>
      RenderErrorBox(message, color: _color(context));

  @override
  void updateRenderObject(BuildContext context, RenderErrorBox renderObject) {
    renderObject
      ..message = message
      ..color = _color(context);
  }

  static Color _color(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? const Color.rgb(0xff, 0xff, 0xff)
      : Color.brightWhite;
}
