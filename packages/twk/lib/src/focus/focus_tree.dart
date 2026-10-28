/// The focus tree: the [FocusNode]s of the [Focus] and [FocusScope]
/// widgets in an app, the [FocusManager] that keeps the one with the
/// primary focus, and Tab and Shift+Tab moving it.
library;

import 'dart:collection';

import 'package:twk_core/twk_core.dart' show KeyEvent;

import '../foundation/change_notifier.dart';
import '../framework/framework.dart';

/// What a [FocusNode.onKeyEvent] did with a key.
enum KeyEventResult {
  /// It took the key: the nodes above it do not get it.
  handled,

  /// It left the key to the nodes above it.
  ignored,
}

/// What a [FocusNode] calls with each key that reaches it.
typedef FocusOnKeyEventCallback = KeyEventResult Function(
  FocusNode node,
  KeyEvent event,
);

/// A place in an app's focus tree: the node of a [Focus] widget, which
/// can have the focus and gets the keys.
///
/// It is attached while the widget is in the tree, under the node of the
/// nearest [Focus] or [FocusScope] above it. A [GlobalKey] that moves the
/// widget moves the node, with the focus it has.
///
/// One node of an app has the primary focus ([FocusManager.primaryFocus]).
/// The binding gives each key to the layers right below it that cannot
/// take the focus, then to it, then to each node above it in turn, until
/// an [onKeyEvent] returns [KeyEventResult.handled]: a walk up the focus
/// tree, as long as it is deep ([FocusManager.keyPath]). A node that holds
/// the keys ([holdKeys]) gets them first.
///
/// Its listeners are told at the start of the next build of the app when
/// [hasFocus] or [hasPrimaryFocus] changed ([FocusManager.flush]).
///
/// A node the app keeps to focus a search field from a key anywhere:
///
/// ```dart
/// final search = FocusNode(debugLabel: 'search');
/// final app = KeyBindings(
///   {'/': search.requestFocus},
///   child: Column(
///     children: [
///       TextField(focusNode: search),
///       const Expanded(child: Text('results')),
///     ],
///   ),
/// );
/// ```
///
/// The app disposes a node it made once the widget that has it is gone.
class FocusNode with ChangeNotifier {
  /// A node that takes the focus unless [canRequestFocus] is false, and
  /// that Tab stops at unless [skipTraversal].
  FocusNode({
    this.debugLabel,
    this.onKeyEvent,
    this._canRequestFocus = true,
    this.skipTraversal = false,
    this._descendantsAreFocusable = true,
  });

  /// Names the node in [toString].
  String? debugLabel;

  /// Called with each key that reaches this node: the primary focus, or a
  /// layer right below it, gets a key first, the nodes above it those it
  /// leaves to them.
  FocusOnKeyEventCallback? onKeyEvent;

  /// Whether Tab and Shift+Tab pass this node by; [requestFocus] still
  /// focuses it.
  bool skipTraversal;

  bool _canRequestFocus;
  bool _descendantsAreFocusable;

  FocusManager? _manager;
  Element? _element;
  FocusNode? _parent;
  final _children = <FocusNode>[];

  // the element of its widget is in the tree: false from its deactivation
  // until it is activated again, or for good
  var _active = false;

  // the scope whose history has this node
  FocusScopeNode? _historyScope;

  var _disposed = false;

  /// Whether this node can have the primary focus: set so, and no node
  /// above it keeps its [descendantsAreFocusable] from it; the nodes below
  /// it can anyway. Set to false while it has it, as a disabled button
  /// is, the focus passes on at the next [FocusManager.flush]: to the node
  /// after it in its scope that Tab stops at, else the one before it,
  /// else the scope itself.
  bool get canRequestFocus {
    if (!_canRequestFocus) {
      return false;
    }
    for (var n = _parent; n != null; n = n._parent) {
      if (!n._descendantsAreFocusable) {
        return false;
      }
    }
    return true;
  }

  set canRequestFocus(bool value) {
    if (value == _canRequestFocus) {
      return;
    }
    _canRequestFocus = value;
    if (!value && hasPrimaryFocus) {
      _manager!._scheduleFlush();
    }
    _manager?._mayChangeKeysBelow(_parent);
  }

  /// Whether the nodes below this one can have the primary focus: false
  /// keeps it from all of them ([canRequestFocus]), as from the tabs a tab
  /// view hides, this node itself keeping it. Tab and Shift+Tab pass them
  /// by, and a key with no node focused does not start below this node
  /// ([FocusManager.keyPath]). Set to false while one of them has the
  /// focus, as for a window minimised, the focus passes on at the next
  /// [FocusManager.flush], as from a node that can no longer take it
  /// ([canRequestFocus]): to the stop of the scope after this node's
  /// subtree, else the one before it (this node among them).
  bool get descendantsAreFocusable => _descendantsAreFocusable;

  set descendantsAreFocusable(bool value) {
    if (value == _descendantsAreFocusable) {
      return;
    }
    _descendantsAreFocusable = value;
    if (!value && hasFocus && !hasPrimaryFocus) {
      _manager!._scheduleFlush();
    }
    _manager?._mayChangeKeysBelow(_parent);
  }

  /// The element of the widget this node is attached by, while it is.
  BuildContext? get context => _element;

  /// The focus of the app this node is attached to, while it is.
  FocusManager? get manager => _manager;

  /// The node above this one, while it is attached under one.
  FocusNode? get parent => _parent;

  /// The nodes attached under this one.
  List<FocusNode> get children => UnmodifiableListView(_children);

  /// The nearest scope above this node.
  FocusScopeNode? get enclosingScope {
    for (var n = _parent; n != null; n = n._parent) {
      if (n is FocusScopeNode) {
        return n;
      }
    }
    return null;
  }

  /// This node if it is a scope, else the nearest scope above it: the one
  /// Tab moves the focus within.
  FocusScopeNode? get nearestScope => enclosingScope;

  /// Whether this node has the primary focus.
  bool get hasPrimaryFocus => identical(_manager?._primary, this);

  /// Whether this node or a node below it has the primary focus.
  bool get hasFocus {
    for (var n = _manager?._primary; n != null; n = n._parent) {
      if (identical(n, this)) {
        return true;
      }
    }
    return false;
  }

  /// Gives this node the primary focus, when it is attached to an app's
  /// focus tree and [canRequestFocus]. Each scope above it remembers the
  /// way to it ([FocusScopeNode.focusedChild]).
  void requestFocus() {
    final manager = _manager;
    if (manager != null && _active && canRequestFocus) {
      manager._setPrimary(this);
    }
  }

  /// Takes the primary focus from this node and the nodes below it: when
  /// one of them has it, the nearest scope above this node that
  /// [canRequestFocus] gets it, itself, as Flutter's
  /// `UnfocusDisposition.scope` does. The root scope keeps it. A node that
  /// can no longer take the focus passes it on to a neighbour instead
  /// ([canRequestFocus]).
  void unfocus() {
    final manager = _manager;
    if (manager == null || !hasFocus) {
      return;
    }
    for (
      var scope = enclosingScope;
      scope != null;
      scope = scope.enclosingScope
    ) {
      if (scope.canRequestFocus && scope._active) {
        manager._setPrimary(scope);
        return;
      }
    }
  }

  /// Moves the primary focus to the node after this one in the nearest
  /// scope, the first after the last; returns whether the scope has one.
  ///
  /// The nodes are those that [canRequestFocus] and do not [skipTraversal],
  /// in the order of the tree: depth first, the children of a widget in
  /// order, as a `Column` or a `Row` shows them. A scope inside is one of
  /// them, whose own nodes Tab does not reach from outside: moving to it
  /// focuses the node it focused last, or its first.
  bool nextFocus() => _manager?._traverse(this, forward: true) ?? false;

  /// Moves the primary focus to the node before this one in the nearest
  /// scope, the last before the first; see [nextFocus].
  bool previousFocus() => _manager?._traverse(this, forward: false) ?? false;

  /// Whether the keys go to this node first ([holdKeys]).
  bool get holdsKeys => _attached && identical(_manager!._holder, this);

  /// Has the keys go to this node first, then to the nodes above it, past
  /// the primary focus and the nodes between ([FocusManager.keyPath]), as a
  /// `KeyBindings` holding the first keys of a sequence has the next come
  /// to it. It lasts until [releaseKeys], another node holds them, the
  /// primary focus moves, or this node leaves the tree; a node not in an
  /// app's tree holds nothing.
  void holdKeys() {
    final manager = _manager;
    if (manager != null && _active && !holdsKeys) {
      manager
        .._holder = this
        .._scheduleFlush();
    }
  }

  /// Ends [holdKeys], if this node holds the keys.
  void releaseKeys() {
    if (holdsKeys) {
      _manager!._release();
    }
  }

  /// Tells [FocusManager.keysChanged] that the keys this node handles
  /// changed, as a layer of `KeyBindings` or `Shortcuts` does when it is
  /// built with other keys; it is told at the next flush, while this node
  /// is on the [FocusManager.keyPath].
  void markKeysChanged() {
    final manager = _manager;
    if (manager != null && manager._toldKeys.contains(this)) {
      manager
        .._keysMarked = true
        .._scheduleFlush();
    }
  }

  /// Detaches the node from the focus tree, if it is attached, and drops
  /// its listeners.
  @override
  void dispose() {
    _detach();
    _disposed = true;
    super.dispose();
  }

  @override
  String toString() =>
      '${this is FocusScopeNode ? 'FocusScopeNode' : 'FocusNode'}'
      '${debugLabel == null ? '' : '($debugLabel)'}';

  void _notify() => notifyListeners();

  bool get _attached => _manager != null;

  /// Attaches this node, by [element], under [parent], or moves it there;
  /// with no parent it is attached only as the root scope of its manager.
  void _attach(Element element, FocusNode? parent) {
    _element = element;
    _active = true;
    if (identical(parent, _parent)) {
      return;
    }
    assert(parent == null || !_isAbove(parent), '$this is above $parent');
    final hadFocus = hasFocus;
    _parent?._children.remove(this);
    _parent = parent;
    if (parent != null) {
      parent._children.add(this);
      _setManager(parent._manager);
    } else if (!_isRoot) {
      _setManager(null);
    }
    final manager = _manager;
    if (hadFocus && manager != null) {
      // the scopes above it remember the way to the focus anew
      manager._setPrimary(manager._primary!);
    }
    manager?._mayChangeKeysBelow(parent);
  }

  bool get _isRoot => identical(_manager?.rootScope, this);

  /// Whether the nodes below this one can have the focus: neither this
  /// node nor one above it keeps it from them.
  bool get _descendantsCanRequestFocus {
    for (FocusNode? n = this; n != null; n = n._parent) {
      if (!n._descendantsAreFocusable) {
        return false;
      }
    }
    return true;
  }

  bool _isAbove(FocusNode node) {
    for (FocusNode? n = node; n != null; n = n._parent) {
      if (identical(n, this)) {
        return true;
      }
    }
    return false;
  }

  void _setManager(FocusManager? manager) {
    if (identical(manager, _manager)) {
      return;
    }
    _manager = manager;
    for (final child in _children) {
      child._setManager(manager);
    }
  }

  /// The element of its widget left the tree: unless a [GlobalKey] puts it
  /// back elsewhere in the build, the focus moves off it once the build
  /// is done ([FocusManager.flush]).
  void _deactivate() {
    _active = false;
    releaseKeys();
    if (hasFocus) {
      _manager!._scheduleFlush();
    }
    _manager?._mayChangeKeysBelow(_parent);
  }

  /// The element of its widget is back in the tree, moved by a
  /// [GlobalKey].
  void _activate() {
    _active = true;
    _manager?._mayChangeKeysBelow(_parent);
  }

  /// Takes this node out of the focus tree, the focus off it first.
  void _detach() {
    releaseKeys();
    final manager = _manager;
    if (manager != null && hasFocus) {
      manager._moveOff(this);
    }
    _parent?._children.remove(this);
    _parent = null;
    _historyScope?._history.remove(this);
    _historyScope = null;
    for (final child in _children) {
      child
        .._parent = null
        .._setManager(null);
    }
    _children.clear();
    if (!_isRoot) {
      _manager = null;
    }
    _element = null;
    _active = false;
  }

  /// Takes the place of [old] in the focus tree: its parent, its children
  /// and the primary focus when it had it.
  void _replace(FocusNode old) {
    final element = old._element;
    final parent = old._parent;
    final children = List.of(old._children);
    final manager = old._manager;
    final hadPrimary = old.hasPrimaryFocus;
    final hadFocusBelow = !hadPrimary && old.hasFocus;
    if (manager != null && manager._toldKeys.contains(old)) {
      manager._scheduleFlush();
    }
    // the focus below it moves with its children, not off them
    for (final child in children) {
      child._parent = null;
    }
    old._children.clear();
    if (hadPrimary) {
      manager!._primary = null;
    }
    old._detach();
    if (element == null) {
      return;
    }
    _attach(element, parent);
    for (final child in children) {
      child._parent = this;
      _children.add(child);
      child._setManager(_manager);
    }
    if (hadPrimary) {
      requestFocus();
      if (!hasPrimaryFocus) {
        _manager?._moveOff(this);
      }
    } else if (hadFocusBelow) {
      // the scopes above it remember the way to the focus anew
      _manager?._setPrimary(_manager!._primary!);
    }
  }
}

/// A [FocusNode] that keeps the nodes below it together: Tab and
/// Shift+Tab move the focus among them only ([nextFocus]), and it
/// remembers the one it focused last ([focusedChild]), which gets the
/// focus back when the scope is focused, or when a scope inside it that
/// had the focus leaves the tree, as a dialog closed
/// ([FocusManager.flush]).
class FocusScopeNode extends FocusNode {
  /// A scope node; the parameters are a [FocusNode]'s.
  FocusScopeNode({
    super.debugLabel,
    super.onKeyEvent,
    super.canRequestFocus,
    super.skipTraversal,
    super.descendantsAreFocusable,
  });

  // the nodes of this scope (and scopes inside it) that had the focus, the
  // last most recently
  final _history = <FocusNode>[];

  /// The node of this scope, or the scope inside it, that had the primary
  /// focus last and still can: one in the tree, under this scope, that
  /// [canRequestFocus].
  FocusNode? get focusedChild {
    while (_history.isNotEmpty) {
      final last = _history.last;
      if (last._attached &&
          last._active &&
          last.canRequestFocus &&
          identical(last.enclosingScope, this)) {
        return last;
      }
      _history.removeLast();
      last._historyScope = null;
    }
    return null;
  }

  @override
  FocusScopeNode get nearestScope => this;

  /// Focuses the node this scope focused last ([focusedChild]), or the
  /// scope itself when there is none.
  @override
  void requestFocus() {
    final child = focusedChild;
    if (child != null) {
      child.requestFocus();
    } else {
      super.requestFocus();
    }
  }

  void _remember(FocusNode node) {
    node._historyScope?._history.remove(node);
    _history.add(node);
    node._historyScope = this;
  }
}

/// The focus of an app: the [rootScope] the binding puts above it, the
/// node with the [primaryFocus], and the listeners of the nodes whose
/// focus changed, told at each [flush].
///
/// The binding gives a key to the nodes of [keyPath] in turn, until one
/// handles it: the primary focus and the nodes above it, starting lower,
/// at the deepest node below it (below the root scope when no node has
/// it) that all of its nodes are below and that cannot take the focus,
/// such as a `KeyBindings` a control puts right below its `Focus`, or one
/// around the whole app. A node around a part of it does not get the key
/// until a node in that part is focused. While a node holds the keys
/// ([FocusNode.holdKeys]), they start at it.
final class FocusManager {
  /// The focus of an app, which calls [onFlushScheduled] as the focus
  /// changes; the binding makes one.
  FocusManager({this.onFlushScheduled}) {
    rootScope._manager = this;
  }

  /// Called when the focus changed while no [flush] is pending: the frame
  /// loop schedules one.
  final void Function()? onFlushScheduled;

  /// The scope above all the nodes of the app.
  final rootScope = FocusScopeNode(debugLabel: 'root');

  FocusNode? _primary;
  var _flushScheduled = false;

  // the node that holds the keys
  FocusNode? _holder;

  // nodes whose Focus asked for the focus as it was mounted, in that order
  final _autofocus = <FocusNode>[];

  // the nodes from the primary focus up, and the primary focus, as the
  // listeners were last told
  var _toldPath = <FocusNode>{};
  FocusNode? _toldPrimary;

  // the key path as keysChanged was last told, how many of its first nodes
  // the walk down from the focus gave then, the focus with them (the root
  // scope before the first flush), none while a node held the keys, and
  // whether a node on it marked its keys changed since
  late var _toldKeys = <FocusNode>[rootScope];
  var _keysWalked = 1;
  var _keysMarked = false;
  final _keysChanged = _Notifier();

  /// The node that gets the keys first; none until a node is focused.
  FocusNode? get primaryFocus => _primary;

  /// Told at a [flush] when the keys the nodes of [keyPath] handle may have
  /// changed since the last time: other nodes are on the path, as when a
  /// node holds the keys or lets them go ([FocusNode.holdKeys]), or a node
  /// on it marked its keys changed ([FocusNode.markKeysChanged]), as a
  /// layer of `KeyBindings` or `Shortcuts` built with other keys or hints,
  /// below `Actions` built with other actions, or holding one more key of
  /// a sequence, does. What shows the keys listens to it, as a
  /// `KeyHintsBar` does; a key event costs nothing more for it.
  Listenable get keysChanged => _keysChanged;

  /// Whether the focus changed since the last [flush].
  bool get needsFlush => _flushScheduled;

  /// The nodes a key goes to, in turn, until one handles it: the deepest
  /// node a walk down from the primary focus reaches, going on as long as a
  /// node has one node attached below it that cannot take the focus, is
  /// not a scope and lets the nodes below it take it
  /// ([FocusNode.descendantsAreFocusable]), then the nodes above it, the
  /// primary focus among them. So the layers right below a node get its
  /// keys from the moment it has the focus; so do those of a scope that
  /// has it itself, as after [FocusNode.unfocus] or once the node that had
  /// it left the tree, and those around the whole app while no node has it
  /// (the root scope stands for it then). A node that can take the focus
  /// gets no key it was not given. While a node holds the keys
  /// ([FocusNode.holdKeys]), it is the first.
  Iterable<FocusNode> get keyPath sync* {
    var node = _holder ?? _primary ?? rootScope;
    if (_holder == null) {
      for (;;) {
        FocusNode? only;
        for (final child in node._children) {
          if (child._active) {
            if (only != null) {
              only = null;
              break;
            }
            only = child;
          }
        }
        if (only == null ||
            only is FocusScopeNode ||
            only._canRequestFocus ||
            !only._descendantsAreFocusable) {
          break;
        }
        node = only;
      }
    }
    for (FocusNode? n = node; n != null; n = n._parent) {
      yield n;
    }
  }

  /// Settles the focus after a build and tells the listeners of the nodes
  /// whose [FocusNode.hasFocus] or [FocusNode.hasPrimaryFocus] changed
  /// since the last call. A node mounted with autofocus gets the focus
  /// when its scope has no [FocusScopeNode.focusedChild], the first such
  /// node of a scope. The binding calls it at the start of each build, and
  /// again after the build while that changed the focus, so a frame shows
  /// the focus where it is.
  ///
  /// A node that can no longer have the focus passes it on: one whose
  /// widget left the tree, that can no longer request it
  /// ([FocusNode.canRequestFocus]), or below one whose descendants no
  /// longer can ([FocusNode.descendantsAreFocusable]). The focus goes to
  /// the node of its scope that Tab stops at right after its place, else
  /// the one right before it, else the scope itself: a keyboard user keeps
  /// the place. When the scope went with it, or the node was a scope, as a
  /// dialog closed, the scope above gets it back as it was before the
  /// focus went in: the node it focused last
  /// ([FocusScopeNode.focusedChild]), else the stop beside the place, else
  /// itself. Flutter gives it to the node the scope focused last in each
  /// case (`UnfocusDisposition.previouslyFocusedChild`), else the scope;
  /// its traversal policy plays no part.
  void flush() {
    if (!_flushScheduled) {
      _recordPlace();
      return;
    }
    _flushScheduled = false;
    if (_autofocus.isNotEmpty) {
      final nodes = List.of(_autofocus);
      _autofocus.clear();
      for (final node in nodes) {
        final scope = node.enclosingScope;
        if (node._active && scope != null && scope.focusedChild == null) {
          node.requestFocus();
        }
      }
    }
    final primary = _primary;
    if (primary != null && (!primary._active || !primary.canRequestFocus)) {
      _moveOff(primary);
    }
    _recordPlace();
    final path = <FocusNode>{
      for (var n = _primary; n != null; n = n._parent) n,
    };
    final told = _toldPath;
    final changed = <FocusNode>{
      for (final n in told)
        if (!path.contains(n)) n,
      for (final n in path)
        if (!told.contains(n)) n,
      if (!identical(_primary, _toldPrimary)) ...[?_toldPrimary, ?_primary],
    };
    _toldPath = path;
    _toldPrimary = _primary;
    for (final node in changed) {
      if (!node._disposed) {
        node._notify();
      }
    }
    final keys = keyPath.toList();
    _keysWalked = _holder == null ? keys.indexOf(_primary ?? rootScope) + 1 : 0;
    if (_keysMarked || !_same(keys, _toldKeys)) {
      _keysMarked = false;
      _toldKeys = keys;
      _keysChanged._notify();
    }
  }

  static bool _same(List<FocusNode> a, List<FocusNode> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }

  /// A node attached under [parent], or that leaves or comes back, may
  /// change the [keyPath] where it walks down from the focus past [parent]:
  /// a flush tells.
  void _mayChangeKeysBelow(FocusNode? parent) {
    for (var i = 0; i < _keysWalked; i++) {
      if (identical(_toldKeys[i], parent)) {
        _scheduleFlush();
        return;
      }
    }
  }

  /// The keys no longer go to [_holder] first.
  void _release() {
    _holder = null;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (!_flushScheduled) {
      _flushScheduled = true;
      onFlushScheduled?.call();
    }
  }

  void _setPrimary(FocusNode node) {
    if (_holder != null && !identical(node, _primary)) {
      _release();
    }
    _primary = node;
    var child = node;
    for (
      var scope = node.enclosingScope;
      scope != null;
      scope = scope.enclosingScope
    ) {
      scope._remember(child);
      child = scope;
    }
    _scheduleFlush();
  }

  /// Moves the focus off [node], which has it or a node below it and can
  /// no longer, as [flush] says: in the nearest scope above it still in
  /// the tree, to the stop beside the place of the primary focus, or to
  /// the scope; a scope above one that left, what it focused last first.
  void _moveOff(FocusNode node) {
    final lost = _primary ?? node;
    final place = _placeOf(lost);
    // the scope the place is in; none when the focus was on a scope
    // itself, which went as a closed dialog goes
    final own = lost is FocusScopeNode ? null : lost.enclosingScope;
    _primary = null;
    if (_holder != null) {
      _release();
    }
    _scheduleFlush();
    for (
      var scope = node.enclosingScope;
      scope != null;
      scope = scope.enclosingScope
    ) {
      final element = scope._element;
      if (!scope._active || element == null) {
        continue;
      }
      final open = scope._descendantsCanRequestFocus;
      if (open && !identical(scope, own) && scope.focusedChild != null) {
        scope.requestFocus();
        if (_primary != null) {
          return;
        }
      }
      if (open && place != null) {
        final order = _TreeOrder(element);
        if (order.beside(order.stopsOf(scope), place) case final next?) {
          _enter(next, order);
          if (_primary != null) {
            return;
          }
        }
      }
      if (scope.canRequestFocus) {
        _setPrimary(scope);
        return;
      }
    }
  }

  // the elements from that of the primary focus up to the top of the
  // tree, and their slots, as the last flush found them: where a node
  // removed with the focus was
  final _placePath = <Element>[];
  final _placeSlots = <Object?>[];

  void _recordPlace() {
    _placePath.clear();
    _placeSlots.clear();
    final primary = _primary;
    final element = primary?._element;
    if (element == null || !primary!._active) {
      return;
    }
    _placePath.add(element);
    _placeSlots.add(element.slot);
    element.visitAncestorElements((e) {
      _placePath.add(e);
      _placeSlots.add(e.slot);
      return true;
    });
  }

  /// Where [node] is, or was before it left the tree with the focus.
  _Place? _placeOf(FocusNode node) {
    final element = node._element;
    if (element == null) {
      return null;
    }
    if (node._active) {
      return _Place(element);
    }
    if (_placePath.isEmpty || !identical(_placePath.first, element)) {
      return null;
    }
    // the top of the subtree removed with it, whose parent is still there
    var top = element;
    element.visitAncestorElements((e) {
      top = e;
      return true;
    });
    for (var i = 0; i + 1 < _placePath.length; i++) {
      if (identical(_placePath[i], top)) {
        final slot = _placeSlots[i];
        return switch (slot) {
          IndexedSlot<Element?>(:final index, :final value) => _Place.gap(
            _placePath[i + 1],
            after: value,
            index: index,
          ),
          _ => _Place.gap(_placePath[i + 1]),
        };
      }
    }
    return null;
  }

  void _queueAutofocus(FocusNode node) {
    _autofocus.add(node);
    _scheduleFlush();
  }

  bool _traverse(FocusNode from, {required bool forward}) {
    final scope = from.nearestScope;
    final root = scope?._element;
    if (scope == null || root == null) {
      return false;
    }
    final order = _TreeOrder(root);
    final stops = order.stopsOf(scope);
    if (stops.isEmpty) {
      return false;
    }
    final i = stops.indexOf(from);
    final FocusNode next;
    if (i >= 0) {
      next = stops[(i + (forward ? 1 : -1)) % stops.length];
    } else if (forward) {
      next = stops.firstWhere(
        (s) => order.compare(from, s) < 0,
        orElse: () => stops.first,
      );
    } else {
      next = stops.lastWhere(
        (s) => order.compare(s, from) < 0,
        orElse: () => stops.last,
      );
    }
    _enter(next, order);
    return true;
  }

  /// Focuses [node]; a scope the node it focused last, else its first.
  void _enter(FocusNode node, _TreeOrder order) {
    if (node is FocusScopeNode && node.focusedChild == null) {
      final stops = order.stopsOf(node);
      if (stops.isNotEmpty) {
        _enter(stops.first, order);
        return;
      }
    }
    node.requestFocus();
  }
}

/// Where the primary focus is: [element], or, after the subtree it was
/// in left the tree, a gap among the children of [element] where the top
/// of that subtree was, right after [after] while that is still one of
/// them, else at [index].
final class _Place {
  _Place(this.element) : gap = false, after = null, index = null;

  _Place.gap(this.element, {this.after, this.index}) : gap = true;

  final Element element;
  final bool gap;
  final Element? after;
  final int? index;
}

/// The order of the tree below [root]: an element before the elements
/// below it and after those of the siblings before it.
final class _TreeOrder {
  _TreeOrder(this.root);

  final Element root;

  // the elements from below the root down to each element; null for one
  // not below it
  final _paths = Map<Element, List<Element>?>.identity();

  /// The stop of [stops], in order, right after [place], else the one
  /// right before it.
  FocusNode? beside(List<FocusNode> stops, _Place place) {
    final at = _path(place.element);
    if (at == null) {
      return null;
    }
    FocusNode? before;
    for (final stop in stops) {
      final path = _path(stop._element!);
      if (path == null) {
        continue;
      }
      final side = place.gap ? _sideOfGap(path, at, place) : _compare(path, at);
      if (side > 0) {
        return stop;
      }
      before = stop;
    }
    return before;
  }

  /// Whether the element at [path] is before (negative) or after
  /// (positive) the gap of [place], below the element at [at].
  int _sideOfGap(List<Element> path, List<Element> at, _Place place) {
    var i = 0;
    while (i < path.length && i < at.length && identical(path[i], at[i])) {
      i++;
    }
    if (i == path.length) {
      // the element is the gap's parent or above it
      return -1;
    }
    if (i < at.length) {
      return _siblings(i == 0 ? root : at[i - 1], path[i], at[i]);
    }
    final parent = place.element;
    final child = path[i];
    final after = place.after;
    if (after != null && identical(_parentOf(after), parent)) {
      return identical(child, after) || _siblings(parent, child, after) < 0
          ? -1
          : 1;
    }
    if ((place.index, child.slot) case (
      final index?,
      IndexedSlot<Element?>(index: final j),
    )) {
      return j < index ? -1 : 1;
    }
    return 1;
  }

  static Element? _parentOf(Element element) {
    Element? parent;
    element.visitAncestorElements((e) {
      parent = e;
      return false;
    });
    return parent;
  }

  /// The nodes of [scope] that Tab stops at, in order: those that can
  /// request focus and do not skip traversal, scopes inside it but not
  /// their nodes, nor the nodes below one whose descendants are not
  /// focusable.
  List<FocusNode> stopsOf(FocusScopeNode scope) {
    final stops = <FocusNode>[];
    // nothing above the scope keeps the focus from its nodes, as the focus
    // is in it or Tab enters it: their own flags tell
    void collect(FocusNode node) {
      if (!node._descendantsAreFocusable) {
        return;
      }
      for (final child in node._children) {
        if (!child._active || child._element == null) {
          continue;
        }
        if (child._canRequestFocus && !child.skipTraversal) {
          stops.add(child);
        }
        if (child is! FocusScopeNode) {
          collect(child);
        }
      }
    }

    collect(scope);
    return stops..sort(compare);
  }

  int compare(FocusNode a, FocusNode b) =>
      _compare(_path(a._element!) ?? const [], _path(b._element!) ?? const []);

  int _compare(List<Element> pa, List<Element> pb) {
    var i = 0;
    while (i < pa.length && i < pb.length && identical(pa[i], pb[i])) {
      i++;
    }
    if (i == pa.length) {
      return i == pb.length ? 0 : -1;
    }
    if (i == pb.length) {
      return 1;
    }
    return _siblings(i == 0 ? root : pa[i - 1], pa[i], pb[i]);
  }

  List<Element>? _path(Element element) {
    if (_paths.containsKey(element)) {
      return _paths[element];
    }
    if (identical(element, root)) {
      return _paths[element] = const <Element>[];
    }
    final path = [element];
    var below = false;
    element.visitAncestorElements((e) {
      if (identical(e, root)) {
        below = true;
        return false;
      }
      path.add(e);
      return true;
    });
    return _paths[element] = below ? path.reversed.toList() : null;
  }

  /// The order of [a] and [b], children of [parent].
  static int _siblings(Element parent, Element a, Element b) {
    if (a.slot case IndexedSlot<Element?>(index: final i)) {
      if (b.slot case IndexedSlot<Element?>(index: final j)) {
        return i - j;
      }
    }
    var order = 0;
    parent.visitChildren((child) {
      if (order == 0) {
        if (identical(child, a)) {
          order = -1;
        } else if (identical(child, b)) {
          order = 1;
        }
      }
    });
    return order;
  }
}

/// Puts a [FocusNode] in the focus tree for [child], under the node of the
/// nearest [Focus] or [FocusScope] above it: [focusNode], or one of its
/// own.
///
/// The widgets below find the node with [Focus.of].
///
/// With [autofocus], the node gets the focus once mounted when its scope
/// has none yet. [onKeyEvent], [canRequestFocus], [skipTraversal],
/// [descendantsAreFocusable] and [debugLabel] configure the node, its own
/// with each new widget; a given [focusNode] only those that are not null.
/// Another [focusNode] takes the place of the one before, with the focus.
///
/// A panel that Tab stops at, focused at the start, which takes `r` while
/// it has the focus:
///
/// ```dart
/// Focus(
///   autofocus: true,
///   debugLabel: 'log',
///   onKeyEvent: (node, event) {
///     if (event.char == 'r') {
///       print('reload');
///       return KeyEventResult.handled;
///     }
///     return KeyEventResult.ignored;
///   },
///   child: const Text('log'),
/// )
/// ```
///
/// See also:
///
///  * `KeyBindings`, keys bound by name rather than read one by one.
///  * [FocusScope], a node that keeps Tab among those below it.
///  * `FocusBuilder`, which shows whether the focus is in a part of the
///    app.
final class Focus extends StatefulWidget {
  /// Puts [focusNode], or a node of its own, in the focus tree for
  /// [child].
  const Focus({
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
    this.canRequestFocus,
    this.skipTraversal,
    this.descendantsAreFocusable,
    this.debugLabel,
    super.key,
  });

  /// What is below the node in the focus tree.
  final Widget child;

  /// The node of this widget; the widget makes one, and disposes it, when
  /// none is given.
  final FocusNode? focusNode;

  /// Whether the node gets the focus once mounted, when its scope has
  /// none yet; false by default.
  final bool autofocus;

  /// See [FocusNode.onKeyEvent].
  final FocusOnKeyEventCallback? onKeyEvent;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// See [FocusNode.skipTraversal].
  final bool? skipTraversal;

  /// See [FocusNode.descendantsAreFocusable].
  final bool? descendantsAreFocusable;

  /// See [FocusNode.debugLabel].
  final String? debugLabel;

  /// The node of the nearest [Focus] or [FocusScope] above [context]; the
  /// root scope's in an app, which puts one above it. The context depends
  /// on it: it is rebuilt when the node's [FocusNode.hasFocus] or
  /// [FocusNode.hasPrimaryFocus] changes. A [StateError] if there is none.
  static FocusNode of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError(
        'no Focus above ${context.widget.runtimeType}: an app puts one '
        'above it',
      ));

  /// The node [of] finds, if there is one; without [createDependency],
  /// [context] does not depend on it.
  static FocusNode? maybeOf(
    BuildContext context, {
    bool createDependency = true,
  }) =>
      (createDependency
              ? context.dependOnInheritedWidgetOfExactType<_FocusMarker>()
              : context.getInheritedWidgetOfExactType<_FocusMarker>())
          ?.node;

  @override
  State<Focus> createState() => _FocusState();
}

/// A [Focus] whose node is a [FocusScopeNode] ([node], or one of its
/// own): Tab and Shift+Tab stay among the nodes below it, and the one it
/// focused last gets the focus back.
///
/// A dialog's fields, which Tab goes round without leaving the dialog:
///
/// ```dart
/// const FocusScope(
///   autofocus: true,
///   child: Column(
///     children: [TextField(autofocus: true), TextField()],
///   ),
/// )
/// ```
final class FocusScope extends StatefulWidget {
  /// Puts [node], or a scope node of its own, in the focus tree for
  /// [child].
  const FocusScope({
    required this.child,
    this.node,
    this.autofocus = false,
    this.onKeyEvent,
    this.canRequestFocus,
    this.skipTraversal,
    this.descendantsAreFocusable,
    this.debugLabel,
    super.key,
  });

  /// What is below the scope in the focus tree.
  final Widget child;

  /// See [Focus.focusNode].
  final FocusScopeNode? node;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// See [FocusNode.onKeyEvent].
  final FocusOnKeyEventCallback? onKeyEvent;

  /// See [FocusNode.canRequestFocus].
  final bool? canRequestFocus;

  /// See [FocusNode.skipTraversal].
  final bool? skipTraversal;

  /// See [FocusNode.descendantsAreFocusable].
  final bool? descendantsAreFocusable;

  /// See [FocusNode.debugLabel].
  final String? debugLabel;

  /// The scope of the node [Focus.of] finds ([FocusNode.nearestScope]).
  static FocusScopeNode of(BuildContext context) =>
      Focus.of(context).nearestScope ??
      (throw StateError(
        'no FocusScope above ${context.widget.runtimeType}: an app puts '
        'one above it',
      ));

  @override
  State<FocusScope> createState() => _FocusScopeState();
}

/// What [Focus] and [FocusScope] share: the node, attached as the element
/// is mounted, moved and removed, and rebuilt with its focus.
abstract class _NodeState<W extends StatefulWidget, N extends FocusNode>
    extends State<W> {
  late N _node;
  N? _own;
  var _attachedOnce = false;

  N? get _given;
  N _create();
  bool get _autofocus;
  Widget get _child;
  FocusOnKeyEventCallback? get _onKeyEvent;
  bool? get _canRequestFocus;
  bool? get _skipTraversal;
  bool? get _descendantsAreFocusable;
  String? get _debugLabel;

  @override
  void initState() {
    super.initState();
    _node = _given ?? (_own = _create());
    _configure();
    _node.addListener(_changed);
  }

  void _configure() {
    final node = _node;
    if (identical(node, _own)) {
      node
        ..onKeyEvent = _onKeyEvent
        ..canRequestFocus = _canRequestFocus ?? true
        ..skipTraversal = _skipTraversal ?? false
        ..descendantsAreFocusable = _descendantsAreFocusable ?? true
        ..debugLabel = _debugLabel;
      return;
    }
    if (_onKeyEvent case final onKeyEvent?) {
      node.onKeyEvent = onKeyEvent;
    }
    if (_canRequestFocus case final canRequestFocus?) {
      node.canRequestFocus = canRequestFocus;
    }
    if (_skipTraversal case final skipTraversal?) {
      node.skipTraversal = skipTraversal;
    }
    if (_descendantsAreFocusable case final descendantsAreFocusable?) {
      node.descendantsAreFocusable = descendantsAreFocusable;
    }
    if (_debugLabel case final debugLabel?) {
      node.debugLabel = debugLabel;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _node._attach(
      context as Element,
      context.dependOnInheritedWidgetOfExactType<_FocusMarker>()?.node,
    );
    if (!_attachedOnce) {
      _attachedOnce = true;
      if (_autofocus) {
        _node._manager?._queueAutofocus(_node);
      }
    }
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    final given = _given;
    final old = _node;
    if (!identical(given ?? _own, old)) {
      final next = given ?? (_own = _create());
      old.removeListener(_changed);
      next._replace(old);
      _node = next..addListener(_changed);
      if (identical(old, _own)) {
        _own = null;
        old.dispose();
      }
    }
    _configure();
  }

  @override
  void deactivate() {
    _node._deactivate();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _node._activate();
  }

  @override
  void dispose() {
    _node
      ..removeListener(_changed)
      .._detach();
    _own?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) => _FocusMarker(
    node: _node,
    hasFocus: _node.hasFocus,
    hasPrimaryFocus: _node.hasPrimaryFocus,
    child: _child,
  );
}

final class _FocusState extends _NodeState<Focus, FocusNode> {
  @override
  FocusNode? get _given => widget.focusNode;

  @override
  FocusNode _create() => FocusNode();

  @override
  bool get _autofocus => widget.autofocus;

  @override
  Widget get _child => widget.child;

  @override
  FocusOnKeyEventCallback? get _onKeyEvent => widget.onKeyEvent;

  @override
  bool? get _canRequestFocus => widget.canRequestFocus;

  @override
  bool? get _skipTraversal => widget.skipTraversal;

  @override
  bool? get _descendantsAreFocusable => widget.descendantsAreFocusable;

  @override
  String? get _debugLabel => widget.debugLabel;
}

final class _FocusScopeState extends _NodeState<FocusScope, FocusScopeNode> {
  @override
  FocusScopeNode? get _given => widget.node;

  @override
  FocusScopeNode _create() => FocusScopeNode();

  @override
  bool get _autofocus => widget.autofocus;

  @override
  Widget get _child => widget.child;

  @override
  FocusOnKeyEventCallback? get _onKeyEvent => widget.onKeyEvent;

  @override
  bool? get _canRequestFocus => widget.canRequestFocus;

  @override
  bool? get _skipTraversal => widget.skipTraversal;

  @override
  bool? get _descendantsAreFocusable => widget.descendantsAreFocusable;

  @override
  String? get _debugLabel => widget.debugLabel;
}

/// What finds the node of a [Focus] from below, and rebuilds those that
/// depend on it when its focus changes.
final class _FocusMarker extends InheritedWidget {
  const _FocusMarker({
    required this.node,
    required this.hasFocus,
    required this.hasPrimaryFocus,
    required super.child,
  });

  final FocusNode node;
  final bool hasFocus;
  final bool hasPrimaryFocus;

  @override
  bool updateShouldNotify(_FocusMarker oldWidget) =>
      !identical(node, oldWidget.node) ||
      hasFocus != oldWidget.hasFocus ||
      hasPrimaryFocus != oldWidget.hasPrimaryFocus;
}

/// What [FocusManager.keysChanged] is.
final class _Notifier with ChangeNotifier {
  void _notify() => notifyListeners();
}
