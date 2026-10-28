/// Keys bound to what they do, as layers of the focus tree: [KeyBindings]
/// bind keys and sequences of keys to callbacks, [Shortcuts] to [Intent]s,
/// which the [Action]s that [Actions] give do; the keys they handle now,
/// with their hints ([FocusManagerKeys.activeKeys]).
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show KeyEvent, KeyKind;

import '../foundation/change_notifier.dart' show VoidCallback;
import '../framework/framework.dart';
import 'focus_tree.dart';
import 'key_combo.dart';

/// What a key bound by [Shortcuts] asks for: the [Action] for its type in
/// the [Actions] above the focused node does it.
///
/// An intent is a class of its own, whose type finds the action:
///
/// ```dart
/// final class SaveIntent extends Intent {
///   const SaveIntent();
/// }
/// ```
@immutable
abstract class Intent {
  /// An intent; a subclass says what of.
  const Intent();
}

/// Does what the [Intent]s of type [T] ask for, while it [isEnabled].
abstract class Action<T extends Intent> {
  /// Whether this action does [intent] now: the [Actions] above a disabled
  /// one are looked in next, and a key bound to an intent no enabled
  /// action does passes on ([Shortcuts]). [Actions] built with other
  /// actions tell what lists the keys ([FocusManager.keysChanged]); an
  /// action whose answer changes on its own tells it with
  /// [FocusNode.markKeysChanged] of a node above its [Actions].
  bool isEnabled(T intent) => true;

  /// Does what [intent] asks for.
  void invoke(T intent);
}

/// An [Action] that calls [onInvoke], while [enabled].
///
/// See [Shortcuts] for one in use.
final class CallbackAction<T extends Intent> extends Action<T> {
  /// An action that calls [onInvoke], enabled unless [enabled] is false.
  CallbackAction({required this.onInvoke, this.enabled = true});

  /// Does the intent.
  // called with the intents of the type it is looked up by, its own T
  // ignore: unsafe_variance
  final void Function(T intent) onInvoke;

  /// Whether it does the intents; a key bound to one passes on while it
  /// does not.
  final bool enabled;

  @override
  bool isEnabled(T intent) => enabled;

  @override
  void invoke(T intent) => onInvoke(intent);
}

/// Gives the widgets below it [actions]: for a type of [Intent], the
/// [Action] that does the intents of that type.
///
/// Of the [Actions] above a widget, the nearest one's enabled action for an
/// intent's type does it. A list whose own action deletes the item, under
/// the app's, which does nothing where nothing is selected:
///
/// ```dart
/// final class DeleteIntent extends Intent {
///   const DeleteIntent();
/// }
///
/// final list = Actions(
///   {
///     DeleteIntent: CallbackAction<DeleteIntent>(
///       onInvoke: (_) => print('item deleted'),
///     ),
///   },
///   child: const Focus(autofocus: true, child: Text('items')),
/// );
/// ```
///
/// See [Shortcuts] for the keys bound to them.
final class Actions extends InheritedWidget {
  /// Gives [actions] to the widgets below.
  const Actions(this.actions, {required super.child, super.key});

  /// The action for each type of intent, an `Action<T>` for the type `T`.
  final Map<Type, Action<Intent>> actions;

  /// The action that does [intent] from [context]: of the [Actions] above
  /// it (its own widget too), the nearest one's action for the type of
  /// [intent] that [Action.isEnabled]; null if there is none.
  static Action<Intent>? maybeFind(BuildContext context, Intent intent) {
    for (
      var element = context.getElementForInheritedWidgetOfExactType<Actions>();
      element != null;
      element = _above(element)
    ) {
      final action = (element.widget as Actions).actions[intent.runtimeType];
      if (action != null && action.isEnabled(intent)) {
        return action;
      }
    }
    return null;
  }

  /// Invokes the action [maybeFind] finds for [intent]; returns whether
  /// there is one.
  static bool maybeInvoke(BuildContext context, Intent intent) {
    final action = maybeFind(context, intent);
    action?.invoke(intent);
    return action != null;
  }

  static InheritedElement? _above(Element element) {
    InheritedElement? found;
    element.visitAncestorElements((parent) {
      found = parent.getElementForInheritedWidgetOfExactType<Actions>();
      return false;
    });
    return found;
  }

  @override
  InheritedElement createElement() => _ActionsElement(this);

  @override
  bool updateShouldNotify(Actions oldWidget) => false;
}

/// Tells [FocusManager.keysChanged] when its [Actions] is built with other
/// actions.
final class _ActionsElement extends InheritedElement {
  _ActionsElement(Actions super.widget);

  @override
  void updated(Actions oldWidget) {
    if (!identical((widget as Actions).actions, oldWidget.actions)) {
      Focus.maybeOf(this, createDependency: false)?.markKeysChanged();
    }
    super.updated(oldWidget);
  }
}

/// Names the key that `leader` stands for in the sequences of the
/// [KeyBindings] and [Shortcuts] below it, as [KeyCombo.parse] reads it:
/// `LeaderKey(',', child: ...)`, then `'leader w'`. Without one above, it
/// is `space`. Another leader rebuilds the layers; a name that is not one
/// key fails their build.
///
/// Comma as the leader, so that `, w` saves:
///
/// ```dart
/// LeaderKey(
///   ',',
///   child: KeyBindings(
///     {'leader w': () => print('saved')},
///     child: const Focus(autofocus: true, child: Text('editor')),
///   ),
/// )
/// ```
final class LeaderKey extends InheritedWidget {
  /// Names [leader] the leader key below it.
  const LeaderKey(this.leader, {required super.child, super.key});

  /// The name of the leader key.
  final String leader;

  @override
  bool updateShouldNotify(LeaderKey oldWidget) => leader != oldWidget.leader;
}

/// What a layer does with the first keys of a sequence it holds when the
/// next key does not go on with them, or [KeyBindings.sequenceTimeout]
/// passes, and no binding of their first keys alone takes them
/// ([KeyBindings.unmatched]).
enum UnmatchedKeys {
  /// They are dropped, and the key that does not go on with them too: a
  /// key such as Escape lets a sequence go, as in Emacs and most terminal
  /// apps.
  drop,

  /// They go on in turn, as in Vim: the first to the nodes above the
  /// layer, a sequence there taking it too, and the others pressed anew,
  /// none of them reaching the `InputListener`s; then the key that does
  /// not go on with them is pressed anew, the focused node getting it
  /// first.
  replay,
}

/// A key the layers on the key path handle now, as
/// [FocusManagerKeys.activeKeys] lists them: its [combo] and, for a
/// sequence, the keys [then] pressed after it; what its layer binds it to
/// ([binding]), and the [hint] its layer gives it, if one does.
@immutable
final class ActiveKey {
  /// A key [combo], then the keys [then], bound to [binding] with [hint].
  const ActiveKey(
    this.combo, {
    required this.binding,
    this.hint,
    this.then = const [],
  });

  /// The key to press now.
  final KeyCombo combo;

  /// The keys to press after [combo], in turn, for [binding]: none for a
  /// key bound alone, the rest of a sequence for one.
  final List<KeyCombo> then;

  /// What the layer that takes the key binds it to: the callback of a
  /// [KeyBindings], the [Intent] of a [Shortcuts]. A layer built with a key
  /// bound to another callback alone, as a closure made in each build is,
  /// does not tell [FocusManager.keysChanged].
  final Object binding;

  /// What the key does, in a few words: `save`, `quit`.
  final String? hint;

  @override
  bool operator ==(Object other) =>
      other is ActiveKey &&
      other.combo == combo &&
      _same(other.then, then) &&
      other.binding == binding &&
      other.hint == hint;

  @override
  int get hashCode => Object.hash(combo, Object.hashAll(then), binding, hint);

  /// The keys to press, [combo] and [then], each named by [keyLabel]
  /// ([KeyCombo.toString] when null), apart by a space as
  /// [KeyCombo.parseSequence] reads them: `ctrl+x ctrl+s`, `g g`. A
  /// `KeyHintsBar`, the menus and a `CommandPalette` show it.
  String label([String Function(KeyCombo combo)? keyLabel]) => [
    for (final key in [combo, ...then]) keyLabel?.call(key) ?? '$key',
  ].join(' ');

  /// The keys and the hint: `ctrl+s save`, `g g top`.
  @override
  String toString() => hint == null ? label() : '${label()} $hint';
}

/// Whether [a] and [b] are the same keys.
bool _same(List<KeyCombo> a, List<KeyCombo> b) =>
    a.length == b.length && _startsWith(a, b);

/// Whether [keys] start with [first].
bool _startsWith(List<KeyCombo> keys, List<KeyCombo> first) {
  if (keys.length < first.length) {
    return false;
  }
  for (var i = 0; i < first.length; i++) {
    if (keys[i] != first[i]) {
      return false;
    }
  }
  return true;
}

/// The keys the layers of an app's focus tree handle now.
extension FocusManagerKeys on FocusManager {
  /// The keys the [KeyBindings] and [Shortcuts] on the [keyPath] handle
  /// now, with what they are bound to and their hints: the nearest layer's
  /// first, each layer's in the order of its map, a sequence by its first
  /// key and the keys [ActiveKey.then] after it. A binding is listed unless
  /// a nearer layer takes its first key: a key bound to null, or to an
  /// intent that no enabled action does, passes on, as when it is pressed,
  /// to be listed from a layer above. While a layer holds the first keys
  /// of a sequence, the keys that can follow them are listed, and nothing
  /// else. The keys a node takes in its own [FocusNode.onKeyEvent] are not
  /// listed. [keysChanged] tells when this may have changed. A `MenuItem`
  /// shows the first key bound to what it does ([ActiveKey.binding]).
  List<ActiveKey> get activeKeys {
    final keys = <ActiveKey>[];
    final taken = <KeyCombo>{};
    for (final node in keyPath) {
      if (node is _LayerNode && node.layer._list(node, keys, taken)) {
        break;
      }
    }
    return keys;
  }
}

/// Binds keys to callbacks for the nodes below it.
///
/// A key bound to null passes on, as one that is not bound. Keys that save
/// and quit wherever the focus is, and `g g` that goes to the top:
///
/// ```dart
/// KeyBindings(
///   {
///     'ctrl+s': () => print('saved'),
///     'q': () => print('bye'),
///     'g g': () => print('top'),
///   },
///   hints: const {'ctrl+s': 'save', 'q': 'quit', 'g g': 'top'},
///   child: const Focus(autofocus: true, child: Text('document')),
/// )
/// ```
///
/// KeyBindings and [Shortcuts] are layers of the focus tree: each puts a
/// node in it, which cannot take the focus and which Tab passes by, and a
/// key goes to the nodes of [FocusManager.keyPath] in turn until one
/// handles it: the layers right below the focused node, as a control puts
/// below its [Focus], from the moment it has the focus, then the focused
/// node and the nodes above it. The layer nearest the focus goes first,
/// then: one around a list before one around the whole app, which gets
/// every key the others leave, wherever the focus is. A key starts at the
/// deepest node all of the focused node's nodes are below, so a layer
/// around a part of what it shows does not get it; with no node focused,
/// at the deepest node all of the app's nodes are below, so the layers
/// around the whole app get it and those around a part of it do not; so
/// does a [FocusScope] that has the focus itself, for the layers around
/// all of it. A key no node handles goes on to the `InputListener`s; then
/// Tab and Shift+Tab move the focus, and Ctrl+C quits (`AppBinding`).
///
/// The keys are named as [KeyCombo.parseSequence] reads them; a name that
/// is not one fails the build, naming the typo, as do two names of the
/// same keys. [hints] say what the keys do, for what lists them
/// ([FocusManagerKeys.activeKeys]); a hint for keys the layer does not
/// bind fails the build too.
///
/// A name of keys pressed one after another binds a sequence: `'g g'`,
/// `'ctrl+x ctrl+s'`, `'leader f'` ([LeaderKey]). The layer holds the
/// first keys of a sequence it binds: the next keys go to it first
/// ([FocusNode.holdKeys]), the key that ends the sequence does it, and
/// [FocusManagerKeys.activeKeys] lists those that can follow. A key bound
/// alone that also starts a sequence (`g` and `g g`) waits for the next:
/// one that does not go on with the sequence does the shorter binding and
/// is pressed anew, as [sequenceTimeout] passing without a key does it.
/// Keys held that no binding takes then are dropped or replayed
/// ([unmatched]); the focus moving drops them. A key a nearer layer binds
/// alone is done at once and hides the sequences above that start with it;
/// a sequence holds its first key from the bindings above, which only a
/// replay reaches.
///
/// See also:
///
///  * [Shortcuts], keys bound to intents that actions do.
///  * `KeyHintsBar`, which shows the keys bound and their hints.
final class KeyBindings extends StatefulWidget {
  /// Binds the keys and sequences named in [bindings] for the nodes below
  /// [child].
  const KeyBindings(
    this.bindings, {
    required this.child,
    this.hints = const {},
    this.sequenceTimeout = const Duration(seconds: 1),
    this.unmatched = UnmatchedKeys.drop,
    this.debugLabel,
    super.key,
  }) : combos = const {},
       comboHints = const {};

  /// Binds the keys of [combos], each alone; its `hints` are [comboHints].
  const KeyBindings.combos(
    this.combos, {
    required this.child,
    Map<KeyCombo, String> hints = const {},
    this.debugLabel,
    super.key,
  }) : bindings = const {},
       hints = const {},
       comboHints = hints,
       sequenceTimeout = null,
       unmatched = UnmatchedKeys.drop;

  /// The callback for each key or sequence, by name.
  final Map<String, VoidCallback?> bindings;

  /// The callback for each key.
  final Map<KeyCombo, VoidCallback?> combos;

  /// What the keys do, a few words for each, by name: `{'ctrl+s': 'save'}`.
  final Map<String, String> hints;

  /// What the keys of [combos] do.
  final Map<KeyCombo, String> comboHints;

  /// How long the layer holds the first keys of a sequence without the
  /// next; null holds them until it comes.
  final Duration? sequenceTimeout;

  /// What becomes of the first keys of a sequence that no binding takes:
  /// they are dropped by default.
  final UnmatchedKeys unmatched;

  /// What the keys are bound for: the nodes below the layer.
  final Widget child;

  /// Names the node of the layer ([FocusNode.debugLabel]).
  final String? debugLabel;

  @override
  State<KeyBindings> createState() => _KeyBindingsState();
}

/// Binds keys to [Intent]s for the nodes below it, which the [Action]s of
/// the [Actions] above the focused node do.
///
/// Of the [Actions] above the node a key started at (the first of
/// [FocusManager.keyPath]), the nearest one's enabled action for the
/// intent's type does it ([Actions.maybeFind]); a key whose intent no
/// enabled action does passes on. So one key does what the part of the
/// app with the focus says.
///
/// A layer of the focus tree, as [KeyBindings] is; the keys and sequences
/// are named, hinted and held as there. The action for the intent of a
/// sequence is found from the node its first key started at.
///
/// Ctrl+S bound once around the app, saving what the editor below has:
///
/// ```dart
/// final class SaveIntent extends Intent {
///   const SaveIntent();
/// }
///
/// final save = CallbackAction<SaveIntent>(
///   onInvoke: (_) => print('saved'),
/// );
/// final app = Shortcuts(
///   const {'ctrl+s': SaveIntent()},
///   hints: const {'ctrl+s': 'save'},
///   child: Actions(
///     {SaveIntent: save},
///     child: const Focus(autofocus: true, child: Text('editor')),
///   ),
/// );
/// ```
final class Shortcuts extends StatefulWidget {
  /// Binds the keys and sequences named in [shortcuts] for the nodes below
  /// [child].
  const Shortcuts(
    this.shortcuts, {
    required this.child,
    this.hints = const {},
    this.sequenceTimeout = const Duration(seconds: 1),
    this.unmatched = UnmatchedKeys.drop,
    this.debugLabel,
    super.key,
  }) : combos = const {},
       comboHints = const {};

  /// Binds the keys of [combos], each alone; its `hints` are [comboHints].
  const Shortcuts.combos(
    this.combos, {
    required this.child,
    Map<KeyCombo, String> hints = const {},
    this.debugLabel,
    super.key,
  }) : shortcuts = const {},
       hints = const {},
       comboHints = hints,
       sequenceTimeout = null,
       unmatched = UnmatchedKeys.drop;

  /// The intent for each key or sequence, by name.
  final Map<String, Intent> shortcuts;

  /// The intent for each key.
  final Map<KeyCombo, Intent> combos;

  /// What the keys do, by name, as [KeyBindings.hints].
  final Map<String, String> hints;

  /// What the keys of [combos] do.
  final Map<KeyCombo, String> comboHints;

  /// See [KeyBindings.sequenceTimeout].
  final Duration? sequenceTimeout;

  /// See [KeyBindings.unmatched].
  final UnmatchedKeys unmatched;

  /// What the keys are bound for: the nodes below the layer.
  final Widget child;

  /// Names the node of the layer ([FocusNode.debugLabel]).
  final String? debugLabel;

  @override
  State<Shortcuts> createState() => _ShortcutsState();
}

/// The node of a layer, by which [FocusManagerKeys.activeKeys] finds it.
final class _LayerNode extends FocusNode {
  _LayerNode(this.layer)
    : super(
        onKeyEvent: layer._onKeyEvent,
        canRequestFocus: false,
        skipTraversal: true,
      );

  final _LayerState<StatefulWidget, Object?> layer;
}

/// Keys bound to a [V], one or a sequence, and their hint.
final class _Binding<V> {
  _Binding(this.keys, this.value);

  final List<KeyCombo> keys;
  final V value;
  String? hint;
}

/// What [KeyBindings] and [Shortcuts] share: the keys bound to a [V] each
/// and their hints, parsed as the widget's maps change, the node they are
/// handled by, and the first keys of a sequence it holds.
abstract class _LayerState<W extends StatefulWidget, V> extends State<W> {
  Map<String, V> get _named;
  Map<KeyCombo, V> get _combos;
  Map<String, String> get _namedHints;
  Map<KeyCombo, String> get _comboHints;
  Duration? get _timeout;
  UnmatchedKeys get _unmatched;
  Widget get _child;
  String? get _debugLabel;

  /// Whether a key bound to [value] that reached [node] is taken rather
  /// than passed on; with [invoke], it is done. The one rule of a key
  /// pressed and of the keys listed ([FocusManagerKeys.activeKeys]).
  bool _take(FocusNode node, V value, {required bool invoke});

  /// Whether a key bound to [a] is listed as one bound to [b] is.
  bool _listedAlike(V a, V b);

  late final _node = _LayerNode(this);

  // the bindings in the order of the maps, those of one key by it, and the
  // first keys of the sequences
  List<_Binding<V>>? _bound;
  var _alone = <KeyCombo, _Binding<V>>{};
  var _sequences = <_Binding<V>>[];
  var _starts = <KeyCombo>{};

  Map<String, V>? _parsedNamed;
  Map<KeyCombo, V>? _parsedCombos;
  Map<String, String>? _parsedNamedHints;
  Map<KeyCombo, String>? _parsedComboHints;
  String? _parsedLeader;

  // the first keys of a sequence held, the node they started at, and the
  // time they are held until
  var _held = <KeyEvent>[];
  FocusNode? _heldFrom;
  Timer? _timer;

  void _parse(String leaderName) {
    final named = _named;
    final combos = _combos;
    final namedHints = _namedHints;
    final comboHints = _comboHints;
    if (identical(named, _parsedNamed) &&
        identical(combos, _parsedCombos) &&
        identical(namedHints, _parsedNamedHints) &&
        identical(comboHints, _parsedComboHints) &&
        leaderName == _parsedLeader) {
      return;
    }
    final leader = KeyCombo.parse(leaderName);
    Never twice(String before, String name, List<KeyCombo> keys) =>
        throw ArgumentError(
          '"$before" and "$name" are the same key${keys.length > 1 ? 's' : ''}',
        );
    // by the keys as text
    final bound = <String, _Binding<V>>{
      for (final MapEntry(key: combo, :value) in combos.entries)
        '$combo': _Binding([combo], value),
    };
    final names = <String, String>{};
    for (final MapEntry(key: name, :value) in named.entries) {
      final keys = KeyCombo.parseSequence(name, leader: leader);
      final id = keys.join(' ');
      if (names[id] ?? (bound.containsKey(id) ? id : null) case final before?) {
        twice(before, name, keys);
      }
      names[id] = name;
      bound[id] = _Binding(keys, value);
    }
    for (final MapEntry(key: combo, value: hint) in comboHints.entries) {
      final binding = bound['$combo'];
      if (binding == null) {
        throw FormatException('"$combo" has a hint but is not bound', '$combo');
      }
      binding.hint = hint;
    }
    final hinted = <String, String>{};
    for (final MapEntry(key: name, value: hint) in namedHints.entries) {
      final keys = KeyCombo.parseSequence(name, leader: leader);
      final id = keys.join(' ');
      final binding = bound[id];
      if (hinted[id] ?? (binding?.hint != null ? id : null)
          case final before?) {
        twice(before, name, keys);
      }
      if (binding == null) {
        throw FormatException('"$name" has a hint but is not bound', name);
      }
      hinted[id] = name;
      binding.hint = hint;
    }
    final all = bound.values.toList();
    if (_bound case final before? when !_listsAlike(before, all)) {
      _node.markKeysChanged();
    }
    _bound = all;
    _alone = {
      for (final b in all)
        if (b.keys.length == 1) b.keys.single: b,
    };
    _sequences = [
      for (final b in all)
        if (b.keys.length > 1) b,
    ];
    _starts = {for (final b in _sequences) b.keys.first};
    _parsedNamed = named;
    _parsedCombos = combos;
    _parsedNamedHints = namedHints;
    _parsedComboHints = comboHints;
    _parsedLeader = leaderName;
  }

  /// Whether [now] lists the keys that [before] does, in the same order.
  bool _listsAlike(List<_Binding<V>> before, List<_Binding<V>> now) {
    if (before.length != now.length) {
      return false;
    }
    for (var i = 0; i < before.length; i++) {
      final (a, b) = (before[i], now[i]);
      if (!_same(a.keys, b.keys) ||
          !_listedAlike(a.value, b.value) ||
          a.hint != b.hint) {
        return false;
      }
    }
    return true;
  }

  /// Whether the layer holds the first keys of a sequence: the focus
  /// moving, or another node holding the keys, lets go of them.
  bool get _holding => _held.isNotEmpty && _node.holdsKeys;

  /// The node the keys started at: the first of the key path, or the one
  /// it was while the layer holds keys.
  FocusNode? _keysFrom(FocusNode node) =>
      _holding ? _heldFrom : node.manager?.keyPath.first;

  /// The binding of exactly [keys].
  _Binding<V>? _find(List<KeyCombo> keys) {
    if (keys.length == 1) {
      return _alone[keys.single];
    }
    for (final b in _sequences) {
      if (_same(b.keys, keys)) {
        return b;
      }
    }
    return null;
  }

  /// Whether a sequence that goes on after [keys] is taken.
  bool _leadsOn(FocusNode node, List<KeyCombo> keys) {
    for (final b in _sequences) {
      if (b.keys.length > keys.length &&
          _startsWith(b.keys, keys) &&
          _take(node, b.value, invoke: false)) {
        return true;
      }
    }
    return false;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (_bound == null || event.kind == KeyKind.release) {
      return KeyEventResult.ignored;
    }
    if (_held.isNotEmpty && !_holding) {
      _letGo();
    }
    final combo = KeyCombo.fromEvent(event);
    if (_held.isEmpty) {
      if (_starts.contains(combo) && _leadsOn(node, [combo])) {
        _hold(node, event);
        return KeyEventResult.handled;
      }
      final alone = _alone[combo];
      return alone != null && _take(node, alone.value, invoke: true)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    final keys = [for (final e in _held) KeyCombo.fromEvent(e), combo];
    if (_leadsOn(node, keys)) {
      _hold(node, event);
      return KeyEventResult.handled;
    }
    final held = _letGo();
    final done = _find(keys);
    if (done != null && _take(node, done.value, invoke: true)) {
      return KeyEventResult.handled;
    }
    return _unmatchedKeys(node, held, event);
  }

  /// Holds [event], one more of the first keys of a sequence.
  void _hold(FocusNode node, KeyEvent event) {
    if (_held.isEmpty) {
      _heldFrom = node.manager?.keyPath.first;
      node.holdKeys();
    } else {
      node.markKeysChanged();
    }
    _held.add(event);
    _timer?.cancel();
    _timer = switch (_timeout) {
      final timeout? => Timer(timeout, () => _expired(node)),
      null => null,
    };
  }

  /// Lets go of the keys held, and returns them.
  List<KeyEvent> _letGo() {
    final held = _held;
    _held = [];
    _heldFrom = null;
    _timer?.cancel();
    _timer = null;
    _node.releaseKeys();
    return held;
  }

  void _expired(FocusNode node) {
    _timer = null;
    if (_holding) {
      _unmatchedKeys(node, _letGo(), null);
    } else if (_held.isNotEmpty) {
      _letGo();
    }
  }

  /// [held], let go of, do not go on with a sequence: [event] does not, or
  /// their time ran out. The longest of their first keys bound alone are
  /// done, and the keys after them pressed anew; with none, [_unmatched]
  /// tells. Returns what became of [event].
  KeyEventResult _unmatchedKeys(
    FocusNode node,
    List<KeyEvent> held,
    KeyEvent? event,
  ) {
    final keys = [for (final e in held) KeyCombo.fromEvent(e)];
    for (var n = keys.length; n > 0; n--) {
      final bound = _find(keys.sublist(0, n));
      if (bound != null && _take(node, bound.value, invoke: true)) {
        return _pressAnew(node, held.sublist(n), event);
      }
    }
    if (_unmatched == UnmatchedKeys.drop) {
      return KeyEventResult.handled;
    }
    _send([for (var n = node.parent; n != null; n = n.parent) n], held.first);
    return _pressAnew(node, held.sublist(1), event);
  }

  /// Presses [keys] anew, each to the key path, then [event], the key
  /// handled now: to the nodes of the key path below [node] first, then to
  /// this layer, whose answer is returned; the binding gives a key it
  /// ignores to the nodes above.
  KeyEventResult _pressAnew(
    FocusNode node,
    List<KeyEvent> keys,
    KeyEvent? event,
  ) {
    final manager = node.manager;
    if (manager == null) {
      return KeyEventResult.handled;
    }
    for (final key in keys) {
      _send(manager.keyPath, key);
    }
    if (event == null) {
      return KeyEventResult.handled;
    }
    for (final n in manager.keyPath) {
      if (identical(n, node)) {
        return _onKeyEvent(node, event);
      }
      if (n.onKeyEvent?.call(n, event) == KeyEventResult.handled) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.handled;
  }

  /// Gives [key] to [nodes] in turn, until one handles it.
  static void _send(Iterable<FocusNode> nodes, KeyEvent key) {
    for (final n in nodes) {
      if (n.onKeyEvent?.call(n, key) == KeyEventResult.handled) {
        return;
      }
    }
  }

  /// Adds to [keys] those of this layer, which [node] is, that are taken
  /// now and whose first key no nearer layer takes ([taken]), then their
  /// first keys to [taken]. While the layer holds the first keys of a
  /// sequence, it adds the keys that can follow them instead, and returns
  /// true.
  bool _list(FocusNode node, List<ActiveKey> keys, Set<KeyCombo> taken) {
    final bound = _bound;
    if (bound == null) {
      return false;
    }
    if (_holding) {
      final held = [for (final e in _held) KeyCombo.fromEvent(e)];
      for (final b in bound) {
        if (b.keys.length > held.length &&
            _startsWith(b.keys, held) &&
            _take(node, b.value, invoke: false)) {
          keys.add(
            ActiveKey(
              b.keys[held.length],
              then: b.keys.sublist(held.length + 1),
              binding: b.value!,
              hint: b.hint,
            ),
          );
        }
      }
      return true;
    }
    final mine = <KeyCombo>[];
    for (final b in bound) {
      final first = b.keys.first;
      if (!taken.contains(first) && _take(node, b.value, invoke: false)) {
        mine.add(first);
        keys.add(
          ActiveKey(
            first,
            then: b.keys.length == 1 ? const [] : b.keys.sublist(1),
            binding: b.value!,
            hint: b.hint,
          ),
        );
      }
    }
    taken.addAll(mine);
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _parse(
      context.dependOnInheritedWidgetOfExactType<LeaderKey>()?.leader ??
          'space',
    );
    _node.debugLabel = _debugLabel;
    return Focus(focusNode: _node, child: _child);
  }
}

final class _KeyBindingsState extends _LayerState<KeyBindings, VoidCallback?> {
  @override
  Map<String, VoidCallback?> get _named => widget.bindings;

  @override
  Map<KeyCombo, VoidCallback?> get _combos => widget.combos;

  @override
  Map<String, String> get _namedHints => widget.hints;

  @override
  Map<KeyCombo, String> get _comboHints => widget.comboHints;

  @override
  Duration? get _timeout => widget.sequenceTimeout;

  @override
  UnmatchedKeys get _unmatched => widget.unmatched;

  @override
  Widget get _child => widget.child;

  @override
  String? get _debugLabel => widget.debugLabel;

  @override
  bool _take(FocusNode node, VoidCallback? value, {required bool invoke}) {
    if (value == null) {
      return false;
    }
    if (invoke) {
      value();
    }
    return true;
  }

  @override
  bool _listedAlike(VoidCallback? a, VoidCallback? b) =>
      (a == null) == (b == null);
}

final class _ShortcutsState extends _LayerState<Shortcuts, Intent> {
  @override
  Map<String, Intent> get _named => widget.shortcuts;

  @override
  Map<KeyCombo, Intent> get _combos => widget.combos;

  @override
  Map<String, String> get _namedHints => widget.hints;

  @override
  Map<KeyCombo, String> get _comboHints => widget.comboHints;

  @override
  Duration? get _timeout => widget.sequenceTimeout;

  @override
  UnmatchedKeys get _unmatched => widget.unmatched;

  @override
  Widget get _child => widget.child;

  @override
  String? get _debugLabel => widget.debugLabel;

  @override
  bool _take(FocusNode node, Intent value, {required bool invoke}) {
    final from = _keysFrom(node)?.context ?? context;
    final action = Actions.maybeFind(from, value);
    if (action == null) {
      return false;
    }
    if (invoke) {
      action.invoke(value);
    }
    return true;
  }

  @override
  bool _listedAlike(Intent a, Intent b) => a == b;
}
