/// The hints of the keys a widget takes in its own `onKeyEvent`:
/// [HintedKeys]. Not exported: what twk's scroll views and fields put
/// above their [Focus].
library;

import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import 'focus_tree.dart';
import 'shortcuts.dart';

/// Lists the keys of [hints] that [node] takes now in its own
/// [FocusNode.onKeyEvent], with their hints, among the keys of the key
/// path ([FocusManagerKeys.activeKeys]): those a `KeyHintsBar` shows.
///
/// Placed above [node]'s `Focus`, it is a layer of [Shortcuts] that binds
/// each key of [hints] while [node] has the focus and [takes] says that
/// the node takes the key now; a key the node takes never reaches it, and
/// one it leaves to the nodes above is one [takes] says no to: the layer
/// takes no key itself, and the keys go as they would without it. So
/// [takes] has to say exactly what the node's `onKeyEvent` does with the
/// key, pressed alone (`'up'`, `'ctrl+z'`, as [hints] names it).
///
/// [takes] is asked at each key and each time the keys are listed; the
/// listing looks again ([FocusNode.markKeysChanged]) when [changes]
/// notifies and what [takes] says of a key has changed, or when it is
/// built with other hints. With [hints] empty it lists nothing.
final class HintedKeys extends StatefulWidget {
  /// Lists the keys of [hints] that [node] [takes], above [child].
  const HintedKeys({
    required this.node,
    required this.hints,
    required this.takes,
    required this.child,
    this.changes,
    super.key,
  });

  /// The node that takes the keys, below this widget.
  final FocusNode node;

  /// What each key does, by its name; a map kept from build to build.
  final Map<String, String> hints;

  /// Whether [node] takes the key of [hints] named so now.
  final bool Function(String key) takes;

  /// Notifies when what [takes] says may have changed.
  final Listenable? changes;

  /// What holds [node]'s `Focus`.
  final Widget child;

  @override
  State<HintedKeys> createState() => _HintedKeysState();
}

final class _HintedKeysState extends State<HintedKeys> {
  late final Map<Type, Action<Intent>> _actions = {
    _HintedKey: _HintedAction(this),
  };

  // the intents of the keys of the hints they were made for
  Map<String, String>? _madeFor;
  var _intents = const <String, Intent>{};

  // what takes said of each key, a bit each, when it was last asked
  var _said = 0;

  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_changed);
    _said = _ask();
  }

  @override
  void didUpdateWidget(HintedKeys oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.changes, oldWidget.changes)) {
      oldWidget.changes?.removeListener(_changed);
      widget.changes?.addListener(_changed);
    }
    _changed();
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_changed);
    super.dispose();
  }

  /// What [HintedKeys.takes] says of each key now, a bit each.
  int _ask() {
    var said = 0;
    var bit = 1;
    for (final key in widget.hints.keys) {
      if (widget.takes(key)) {
        said |= bit;
      }
      bit <<= 1;
    }
    return said;
  }

  void _changed() {
    final said = _ask();
    if (said != _said) {
      _said = said;
      widget.node.markKeysChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hints = widget.hints;
    if (!identical(hints, _madeFor)) {
      _madeFor = hints;
      _intents = {for (final key in hints.keys) key: _HintedKey(this, key)};
    }
    return Actions(
      _actions,
      child: Shortcuts(_intents, hints: hints, child: widget.child),
    );
  }
}

/// A key of a [HintedKeys], by its name.
final class _HintedKey extends Intent {
  const _HintedKey(this.layer, this.key);

  final _HintedKeysState layer;
  final String key;
}

/// Enabled for the keys its [HintedKeys]'s node takes now; doing nothing,
/// since those never reach it.
final class _HintedAction extends Action<_HintedKey> {
  _HintedAction(this.layer);

  final _HintedKeysState layer;

  @override
  bool isEnabled(_HintedKey intent) {
    if (!identical(intent.layer, layer) || !layer.mounted) {
      return false;
    }
    final widget = layer.widget;
    return widget.node.hasFocus && widget.takes(intent.key);
  }

  @override
  void invoke(_HintedKey intent) {}
}
