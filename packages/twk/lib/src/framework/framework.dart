/// Widgets, elements and state: the tree the framework builds and rebuilds.
///
/// As in Flutter, a [Widget] is an immutable description that the framework
/// inflates into an [Element]; the element stays in the tree while widgets
/// of the same type replace one another on rebuilds. A [StatefulWidget]
/// keeps its [State] on its element, a [RenderObjectWidget] a render object
/// of the core, placed under the render object of the nearest ancestor that
/// has one; a [ParentDataWidget] in between puts on it what that ancestor's
/// layout needs. An [InheritedWidget] is found from below by its type in
/// constant time, and rebuilds the elements that depend on it when it
/// changes. A [Notification] goes the other way, up from a context to the
/// [NotificationListener]s above it. A [BuildOwner] holds what a tree needs
/// between frames: the elements to rebuild, the removed ones waiting to be
/// unmounted and those of the [GlobalKey]s, which move with their widgets
/// from one place in the tree to another within a frame, state and render
/// object kept. A [Builder] builds its child with a function of its own
/// context, a [LayoutBuilder] in the layout instead, with the constraints
/// it is laid out within. An element describes itself and the elements
/// below it when asked ([Element.describe]), with what its widget, its
/// state and its render object say of themselves, for dumps and messages.
///
/// @docImport 'package:twk_core/twk_core.dart';
/// @docImport '../layout/child_list.dart';
/// @docImport '../layout/one_child.dart';
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        DiagnosticsFlag,
        DiagnosticsNode,
        PaintContext,
        ParentData,
        RenderObject,
        RenderObjectWithChildMixin;

import 'builder.dart' show Builder;

export 'package:twk_core/twk_core.dart'
    show
        DiagnosticPropertiesBuilder,
        DiagnosticsFlag,
        DiagnosticsNode,
        DiagnosticsProperty,
        describeAlignment,
        describeColor,
        describeConstraints,
        describeInsets,
        describePen,
        describeText,
        describeValue;

export 'builder.dart';
export 'slots.dart';

/// What [Element.visitChildren] and its kin call for each element.
typedef ElementVisitor = void Function(Element element);

/// What [BuildContext.visitAncestorElements] calls for each ancestor; false
/// stops the walk.
typedef ConditionalElementVisitor = bool Function(Element element);

/// What tells a widget apart from its siblings: an element goes on to a new
/// widget only if their keys are equal, and among siblings the old child
/// with a key goes on to the new widget with that key wherever it moved.
@immutable
abstract class Key {
  /// A [ValueKey] of [value].
  const factory Key(String value) = ValueKey<String>;

  /// For subclasses.
  const Key.empty();
}

/// A key that tells a widget apart from its siblings only.
abstract class LocalKey extends Key {
  /// For subclasses.
  const LocalKey() : super.empty();
}

/// A key equal to the keys of the same type whose [value]s are equal.
///
/// A key of another type (a `ValueKey<num>` and a `ValueKey<int>`) is
/// unequal whatever its value.
///
/// ```dart
/// Column(
///   children: [
///     for (final name in ['ann', 'bob']) Text(name, key: ValueKey(name)),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [ObjectKey], equal only for the identical object.
///  * [UniqueKey], equal only to itself.
final class ValueKey<T> extends LocalKey {
  /// A key of [value].
  const ValueKey(this.value);

  /// What tells this key apart: keys of the same type are equal when their
  /// values are.
  final T value;

  // the type arguments last, as Types: the same one is the identical Type
  // on the VM and dart2js, which the language does not promise, so Type ==
  // tells apart the rest, the type arguments of a related type
  // (ValueKey<num>(1) and ValueKey<int>(1)) after `is` and equal values:
  // exact (dynamic is not Object?) and some 8 ns AOT, where comparing the
  // two runtimeTypes makes Types for about 140; identical keys first,
  // which also makes a key of a value unequal to itself (NaN) equal to
  // itself
  @override
  bool operator ==(Object other) =>
      identical(other, this) ||
      other is ValueKey<T> &&
          other.value == value &&
          (identical(other._type, T) || other._type == T);

  Type get _type => T;

  // keys of other types with an equal value hash alike and are unequal
  @override
  int get hashCode => Object.hash(ValueKey, value);

  @override
  String toString() => T == String ? "[<'$value'>]" : '[<$value>]';
}

/// A key equal to the keys whose [value] is the identical object.
final class ObjectKey extends LocalKey {
  /// A key of [value], by its identity.
  const ObjectKey(this.value);

  /// The object that tells this key apart, compared by identity.
  final Object? value;

  @override
  bool operator ==(Object other) =>
      other is ObjectKey && identical(other.value, value);

  @override
  int get hashCode => identityHashCode(value);

  @override
  String toString() => '[${value.runtimeType}#${_shortHash(value)}]';
}

/// A key equal only to itself.
final class UniqueKey extends LocalKey {
  /// A key unequal to every other.
  // a const one would be one key wherever it is written
  // ignore: prefer_const_constructors_in_immutables
  UniqueKey();

  @override
  String toString() => '[#${_shortHash(this)}]';
}

/// A key equal only to itself, and unique in the whole tree: while the
/// element of the widget that has it is mounted, the key finds it. It is
/// in one tree at a time, on one widget at a time.
///
/// A widget with it that leaves one place in the tree and appears in
/// another in the same frame keeps its element there, with the subtree,
/// the state and the render objects; the element is deactivated and
/// activated on the way. Two widgets of a tree with the same key at once
/// fail an assert at the end of the frame ([BuildOwner.finalizeTree]).
///
/// A field that keeps its text and its focus as the layout around it
/// changes:
///
/// ```dart
/// final field = GlobalKey(debugLabel: 'name');
///
/// Widget form({required bool wide}) {
///   final input = TextField(key: field);
///   return wide
///       ? Row(children: [const Text('Name '), Expanded(child: input)])
///       : Column(children: [const Text('Name'), input]);
/// }
/// ```
///
/// See also:
///
///  * [ValueKey], which tells a widget apart from its siblings only.
final class GlobalKey<T extends State<StatefulWidget>> extends Key {
  /// A key unequal to every other, named [debugLabel] in [toString].
  // a const one would be one key wherever it is written
  // ignore: prefer_const_constructors_in_immutables
  GlobalKey({this.debugLabel}) : super.empty();

  // the owner of the tree an element with the key is mounted in, by key
  static final _owners = Expando<BuildOwner>();

  /// Names the key in [toString].
  final String? debugLabel;

  Element? get _currentElement => _owners[this]?._globalKeys[this];

  /// The element of the widget that has this key, while it is mounted.
  BuildContext? get currentContext => _currentElement;

  /// The widget that has this key, while its element is mounted.
  Widget? get currentWidget => _currentElement?.widget;

  /// The state of the element of the widget that has this key, while it is
  /// mounted, if it is a [T].
  T? get currentState => switch (_currentElement) {
    StatefulElement(:final T state) => state,
    _ => null,
  };

  @override
  String toString() {
    final label = debugLabel == null ? '' : ' $debugLabel';
    return '[GlobalKey#${_shortHash(this)}$label]';
  }
}

/// The widgets from the root down to [element]'s, a key after its widget's
/// type, to name the element in messages.
String _pathOf(Element element) => [
  for (Element? e = element; e != null; e = e._parent) _nameOf(e),
].reversed.join(' > ');

/// The type of [element]'s widget, its key after it.
String _nameOf(Element element) => switch (element.widget) {
  Widget(key: null, :final runtimeType) => '$runtimeType',
  Widget(:final key, :final runtimeType) => '$runtimeType-$key',
};

/// Five hex digits of [object]'s identity hash, to tell objects apart in
/// descriptions.
String _shortHash(Object? object) =>
    identityHashCode(object).toUnsigned(20).toRadixString(16).padLeft(5, '0');

/// An immutable description of part of the interface. The framework
/// inflates it into an [Element], which later widgets of the same type
/// update in place.
///
/// An app writes its widgets as a [StatelessWidget] or a
/// [StatefulWidget], and those that lay out and paint as a
/// [RenderObjectWidget].
@immutable
abstract class Widget {
  /// For subclasses: [key] tells the widget apart from its siblings.
  const Widget({this.key});

  /// Tells this widget apart from its siblings; see [Key].
  final Key? key;

  /// Inflates this widget into a new element for the tree.
  @protected
  Element createElement();

  /// Whether the element showing [oldWidget] can show [newWidget] instead of
  /// being replaced: widgets match by their type and [key].
  static bool canUpdate(Widget oldWidget, Widget newWidget) =>
      oldWidget.runtimeType == newWidget.runtimeType &&
      oldWidget.key == newWidget.key;

  /// Adds what describes this widget in its element's description
  /// ([Element.describe]) to [properties], those not worth showing (a
  /// default) left out; an override calls this first. A render object
  /// widget adds only what its render object does not show. Only
  /// [Element.describe] calls it: a frame never does.
  @protected
  @mustCallSuper
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {}
}

/// A widget that is a function of its configuration: [build] returns the
/// widgets it is made of, from its fields and what it reads through its
/// context.
///
/// It is built again when its parent rebuilds with a new widget, and when
/// an [InheritedWidget] it depends on changes.
///
/// ```dart
/// final class Greeting extends StatelessWidget {
///   const Greeting(this.name, {super.key});
///
///   final String name;
///
///   @override
///   Widget build(BuildContext context) => Text('Hello, $name!');
/// }
/// ```
///
/// See also:
///
///  * [StatefulWidget], for a widget that keeps something between builds.
///  * [Builder], a stateless widget built by a function, without a class.
abstract class StatelessWidget extends Widget {
  /// For subclasses.
  const StatelessWidget({super.key});

  @override
  StatelessElement createElement() => StatelessElement(this);

  /// Describes this part of the interface; called when the widget is placed
  /// in the tree, whenever its parent gives it a new widget, and when its
  /// element is marked dirty.
  @protected
  Widget build(BuildContext context);
}

/// A widget whose element keeps a [State] that outlives rebuilds.
///
/// The widget holds the configuration its parent gives it; [createState]
/// makes the state once, when the widget is placed in the tree, and the
/// state builds the widgets it is made of, again after each
/// [State.setState]. A new widget of the same type and key from the parent
/// keeps the state ([State.didUpdateWidget]).
///
/// A counter that Up increments:
///
/// ```dart
/// final class Counter extends StatefulWidget {
///   const Counter({super.key});
///
///   @override
///   State<Counter> createState() => _CounterState();
/// }
///
/// final class _CounterState extends State<Counter> {
///   var _count = 0;
///
///   @override
///   Widget build(BuildContext context) => KeyBindings(
///     {'up': () => setState(() => _count++)},
///     child: Text('Count: $_count'),
///   );
/// }
/// ```
///
/// See also:
///
///  * [StatelessWidget], for a widget that keeps nothing.
///  * `ListenableBuilder`, which rebuilds what it builds when a model
///    notifies, the model kept outside.
abstract class StatefulWidget extends Widget {
  /// For subclasses.
  const StatefulWidget({super.key});

  @override
  StatefulElement createElement() => StatefulElement(this);

  /// Creates the state of a new element; it lives as long as the element.
  @protected
  State<StatefulWidget> createState();
}

/// What a [StatefulWidget] keeps between builds while its element is in
/// the tree.
///
/// The framework calls [initState] and [didChangeDependencies], then
/// [build]; [didUpdateWidget] when the parent rebuilds with a new widget and
/// [didChangeDependencies] when something the state depends on changed,
/// each followed by [build]; [deactivate] when the element is removed from
/// the tree and [dispose] when it is unmounted at the end of that frame,
/// unless a [GlobalKey] put it back elsewhere in the frame, which calls
/// [activate] and [build] (after [didChangeDependencies] if the state
/// depended on inherited widgets).
abstract class State<T extends StatefulWidget> {
  late T _widget;
  StatefulElement? _element;

  /// The current configuration; already the new one in [didUpdateWidget].
  T get widget => _widget;

  /// The element of this state, from its creation until [dispose] returns.
  BuildContext get context {
    assert(_element != null, 'the context of $this used after dispose()');
    return _element!;
  }

  /// Whether this state has an element: false once [dispose] has run.
  bool get mounted => _element != null;

  /// Called once, when the element is placed in the tree, before the first
  /// [build]. Not the place to depend on inherited widgets: that is
  /// [didChangeDependencies]. When it throws, the element leaves the tree
  /// again, and the state is neither deactivated nor disposed.
  @protected
  @mustCallSuper
  void initState() {}

  /// Called when the parent rebuilt with a new widget of the same type;
  /// [widget] is already the new one.
  @protected
  @mustCallSuper
  void didUpdateWidget(covariant T oldWidget) {}

  /// Called after [initState], and before the next [build] whenever
  /// something this state depends on changed. An inherited widget depended
  /// on here stays depended on through the builds until a later call does
  /// not ask for it again.
  @protected
  @mustCallSuper
  void didChangeDependencies() {}

  /// Called when the element is removed from the tree; [activate] follows
  /// if a [GlobalKey] puts it back elsewhere in the same frame, [dispose]
  /// if not.
  @protected
  @mustCallSuper
  void deactivate() {}

  /// Called when a [GlobalKey] put the element, removed from the tree
  /// earlier in the frame, back in it elsewhere, before it is built there:
  /// take up again what [deactivate] let go.
  @protected
  @mustCallSuper
  void activate() {}

  /// Called when the element is unmounted for good, at the end of the frame
  /// that removed it: release what the state holds.
  @protected
  @mustCallSuper
  void dispose() {}

  /// Describes this part of the interface; see [StatelessWidget.build].
  @protected
  Widget build(BuildContext context);

  /// Adds what describes this state to its element's description, after
  /// its widget's; see [Widget.debugFillProperties].
  @protected
  @mustCallSuper
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {}

  /// Runs [fn], which changes this state, and rebuilds the element in the
  /// owner's next build scope: any number of calls before then make one
  /// rebuild.
  @protected
  void setState(void Function() fn) {
    assert(_element != null, 'setState() called after dispose(): $this');
    fn();
    _element!.markNeedsBuild();
  }
}

/// Where a widget sits in the tree, as its build and its state see it.
abstract interface class BuildContext {
  /// The widget the element currently shows.
  Widget get widget;

  /// Whether the element is still mounted: false once it was unmounted.
  bool get mounted;

  /// The owner that builds the tree.
  BuildOwner? get owner;

  /// The render object of the element, or of the nearest element below it
  /// that has one.
  RenderObject? findRenderObject();

  /// The widget of the nearest ancestor whose widget is exactly a [T].
  T? findAncestorWidgetOfExactType<T extends Widget>();

  /// The state of the nearest stateful ancestor whose state is a [T].
  T? findAncestorStateOfType<T extends State<StatefulWidget>>();

  /// Calls [visitor] for each ancestor, nearest first, until it returns
  /// false.
  void visitAncestorElements(ConditionalElementVisitor visitor);

  /// The nearest [InheritedWidget] of exactly the type [T] above this
  /// context (or the context's own widget), found in constant time; null if
  /// there is none.
  ///
  /// The context depends on it from then on: when it is replaced by one
  /// whose [InheritedWidget.updateShouldNotify] is true, the element is
  /// told in [Element.didChangeDependencies] and rebuilt. The dependency
  /// lasts until a later build of the element (its updateRenderObject, for
  /// a [RenderObjectWidget]) does not ask for it again, or one asked for in
  /// [State.didChangeDependencies] until a later call of it does not, or
  /// until the element leaves the tree. Not to be called in
  /// [State.initState].
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>();

  /// Depends on [ancestor], the element of an inherited widget above this
  /// context, as [dependOnInheritedWidgetOfExactType] does, and returns its
  /// widget.
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor);

  /// The widget [dependOnInheritedWidgetOfExactType] finds, without
  /// depending on it.
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>();

  /// The element of the widget [dependOnInheritedWidgetOfExactType] finds,
  /// without depending on it.
  InheritedElement?
  getElementForInheritedWidgetOfExactType<T extends InheritedWidget>();
}

enum _Lifecycle { initial, active, inactive, defunct }

/// A widget's place in the tree: it is created by the widget, mounted
/// under its parent, updated with each new widget of the same type, and
/// deactivated, then unmounted when it leaves the tree.
abstract class Element implements BuildContext {
  /// An element of [widget], not in the tree until [mount]ed.
  Element(Widget widget) : _widget = widget;

  Widget? _widget;
  Element? _parent;
  Object? _slot;
  var _depth = 0;
  BuildOwner? _owner;
  _Lifecycle _lifecycle = _Lifecycle.initial;
  var _dirty = true;
  var _inDirtyList = false;

  // the elements of the inherited widgets at and above this element, by
  // their widgets' types; shared with the parent unless this element's
  // widget is one
  Map<Type, InheritedElement>? _inheritedElements;

  // the inherited elements this element depends on, registered since its
  // last build began (or its last updateRenderObject)
  Set<InheritedElement>? _dependencies;

  // it depended on inherited elements when it was deactivated
  var _hadDependencies = false;

  @override
  Widget get widget => _widget!;

  @override
  bool get mounted => _widget != null;

  @override
  BuildOwner? get owner => _owner;

  /// Where the parent placed this element among its children.
  Object? get slot => _slot;

  /// The number of elements from the root to this one, the root's being 1.
  int get depth => _depth;

  /// Whether this element is to be rebuilt in the next build scope.
  bool get dirty => _dirty;

  /// Adds what describes this element, besides its widget's type and key
  /// and its size, to [properties]: its widget's properties
  /// ([Widget.debugFillProperties]); an override calls this first.
  @protected
  @mustCallSuper
  void debugFillProperties(DiagnosticPropertiesBuilder properties) =>
      widget.debugFillProperties(properties);

  /// This element and those below it as a tree of descriptions, built when
  /// called: its widget's type and key; the properties
  /// [debugFillProperties] adds; the size of its render object, or of the
  /// nearest below it, once laid out; whether it is to be rebuilt
  /// ([DiagnosticsFlag.needsBuild]); and the descriptions of its children.
  /// `debugDumpTree` prints it.
  DiagnosticsNode describe() {
    final properties = DiagnosticPropertiesBuilder();
    debugFillProperties(properties);
    if (_dirty && _lifecycle == _Lifecycle.active) {
      properties.flag(DiagnosticsFlag.needsBuild);
    }
    final children = <DiagnosticsNode>[];
    visitChildren((child) => children.add(child.describe()));
    final o = renderObject;
    return properties.toNode(
      '${widget.runtimeType}',
      key: widget.key?.toString(),
      size: o == null || o.constraints == null ? null : (o.width, o.height),
      children: children,
    );
  }

  /// The type of its widget, the key after a dash: what messages name it
  /// by.
  @override
  String toString() =>
      _widget == null ? '$runtimeType, unmounted' : _nameOf(this);

  /// The child whose render object stands for this element's in the render
  /// tree, for an element that has none of its own.
  Element? get _renderObjectAttachingChild => null;

  /// The render object of this element, or of the nearest element below it
  /// that has one.
  RenderObject? get renderObject {
    for (Element? e = this; e != null; e = e._renderObjectAttachingChild) {
      if (e is RenderObjectElement) {
        return e._renderObject;
      }
    }
    return null;
  }

  @override
  RenderObject? findRenderObject() => renderObject;

  /// Calls [visitor] for each child.
  void visitChildren(ElementVisitor visitor) {}

  @override
  void visitAncestorElements(ConditionalElementVisitor visitor) {
    var ancestor = _parent;
    while (ancestor != null && visitor(ancestor)) {
      ancestor = ancestor._parent;
    }
  }

  @override
  T? findAncestorWidgetOfExactType<T extends Widget>() {
    for (var a = _parent; a != null; a = a._parent) {
      final widget = a.widget;
      if (widget.runtimeType == T) {
        return widget as T;
      }
    }
    return null;
  }

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>() {
    final ancestor = _inheritedElements?[T];
    return ancestor == null ? null : dependOnInheritedElement(ancestor) as T;
  }

  @override
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor) {
    (_dependencies ??= {}).add(ancestor);
    ancestor._dependents.add(this);
    return ancestor.widget;
  }

  /// Whether [ancestor] is above this element in the tree.
  bool _isBelow(Element ancestor) {
    for (
      var e = _parent;
      e != null && e._depth >= ancestor._depth;
      e = e._parent
    ) {
      if (identical(e, ancestor)) {
        return true;
      }
    }
    return false;
  }

  /// Whether this element depends on [ancestor].
  bool _dependsOn(InheritedElement ancestor) =>
      _dependencies?.contains(ancestor) ?? false;

  /// Whether this element depends on any inherited element.
  bool get _hasDependencies => _dependencies?.isNotEmpty ?? false;

  /// Takes the dependencies this element has, for a build in which it
  /// registers them anew; those it does not register again are dropped
  /// after it ([_dropDependencies] of what this returns). Taken and
  /// dropped around the build, not given the build to run, which would
  /// make a closure at every build.
  Set<InheritedElement>? _takeDependencies() {
    final previous = _dependencies;
    _dependencies = null;
    return previous;
  }

  /// Takes this element off the dependents of those of [ancestors] it no
  /// longer depends on.
  void _dropDependencies(Set<InheritedElement>? ancestors) {
    if (ancestors == null) {
      return;
    }
    for (final ancestor in ancestors) {
      if (!_dependsOn(ancestor)) {
        ancestor._dependents.remove(this);
      }
    }
  }

  /// Takes this element off the dependents of all it depends on.
  void _dropAllDependencies() {
    final previous = _dependencies;
    _dependencies = null;
    _dropDependencies(previous);
  }

  @override
  T? getInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      _inheritedElements?[T]?.widget as T?;

  @override
  InheritedElement?
  getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      _inheritedElements?[T];

  @override
  T? findAncestorStateOfType<T extends State<StatefulWidget>>() {
    for (var a = _parent; a != null; a = a._parent) {
      if (a is StatefulElement && a.state is T) {
        return a.state as T;
      }
    }
    return null;
  }

  /// Places this element in the tree under [parent] (null for a root, whose
  /// [owner] is assigned before) at [newSlot].
  @mustCallSuper
  void mount(Element? parent, Object? newSlot) {
    assert(_lifecycle == _Lifecycle.initial, '$this mounted twice');
    _parent = parent;
    _slot = newSlot;
    _lifecycle = _Lifecycle.active;
    if (parent != null) {
      _depth = parent._depth + 1;
      _owner = parent._owner;
    } else {
      _depth = 1;
    }
    assert(_owner != null, 'a root element needs an owner: $this');
    _updateInheritance();
    final key = widget.key;
    if (key is GlobalKey) {
      _owner!._registerGlobalKey(key, this);
    }
  }

  /// Takes the inherited elements of the parent; an inherited element adds
  /// its own.
  void _updateInheritance() {
    _inheritedElements = _parent?._inheritedElements;
  }

  /// Shows [newWidget], which [Widget.canUpdate] matched with [widget].
  @mustCallSuper
  void update(covariant Widget newWidget) {
    assert(
      Widget.canUpdate(widget, newWidget),
      '$newWidget cannot update $this',
    );
    _widget = newWidget;
  }

  /// Moves this element to [newSlot] among its parent's children.
  @protected
  @mustCallSuper
  void updateSlot(Object? newSlot) {
    _slot = newSlot;
  }

  /// Moves [child] to [newSlot], along with the elements below it down to
  /// the one whose render object stands for it.
  @protected
  void updateSlotForChild(Element child, Object? newSlot) {
    for (Element? e = child; e != null; e = e._renderObjectAttachingChild) {
      e.updateSlot(newSlot);
    }
  }

  /// Makes [child] show [newWidget] at [newSlot] and returns the element
  /// that does: [child] itself when the widget is the same or matches it,
  /// else a new element in its place. A null [newWidget] removes [child].
  @protected
  Element? updateChild(Element? child, Widget? newWidget, Object? newSlot) {
    if (newWidget == null) {
      if (child != null) {
        deactivateChild(child);
      }
      return null;
    }
    if (child == null) {
      return inflateWidget(newWidget, newSlot);
    }
    if (Widget.canUpdate(child.widget, newWidget)) {
      if (child.slot != newSlot) {
        updateSlotForChild(child, newSlot);
      }
      if (!identical(child.widget, newWidget)) {
        child.update(newWidget);
      }
      return child;
    }
    deactivateChild(child);
    return inflateWidget(newWidget, newSlot);
  }

  /// Makes [oldChildren] show [newWidgets] and returns the elements that do,
  /// in order; each child's slot is an [IndexedSlot]. As in Flutter, the
  /// matching heads of both lists are updated in place, then the middles,
  /// where an old child with a key goes on to the new widget with that key
  /// and the other old children are removed, then the matching tails. So a
  /// child inserted or removed leaves its siblings their elements, and
  /// children with keys keep theirs, render objects moved, when reordered.
  /// The [forgottenChildren] among [oldChildren], which [forgetChild] let
  /// go, are no longer there: they are neither updated nor removed.
  @protected
  List<Element> updateChildren(
    List<Element> oldChildren,
    List<Widget> newWidgets, {
    Set<Element>? forgottenChildren,
  }) {
    var oldTop = 0;
    var newTop = 0;
    var oldBottom = oldChildren.length - 1;
    var newBottom = newWidgets.length - 1;
    final newChildren = <Element>[];
    Element? previous;
    while (oldTop <= oldBottom &&
        newTop <= newBottom &&
        !_forgotten(forgottenChildren, oldChildren[oldTop]) &&
        Widget.canUpdate(oldChildren[oldTop].widget, newWidgets[newTop])) {
      final slot = IndexedSlot(newTop, previous);
      previous = updateChild(oldChildren[oldTop], newWidgets[newTop], slot)!;
      newChildren.add(previous);
      oldTop++;
      newTop++;
    }
    // the tails are updated last, when the siblings before them are known
    while (oldTop <= oldBottom &&
        newTop <= newBottom &&
        Widget.canUpdate(
          oldChildren[oldBottom].widget,
          newWidgets[newBottom],
        )) {
      oldBottom--;
      newBottom--;
    }
    // made only for a middle of old children left
    Map<Key, Element>? keyed;
    for (var i = oldTop; i <= oldBottom; i++) {
      final child = oldChildren[i];
      final key = child.widget.key;
      if (key != null) {
        (keyed ??= {})[key] = child;
      } else {
        deactivateChild(child);
      }
    }
    for (; newTop <= newBottom; newTop++) {
      final widget = newWidgets[newTop];
      var child = keyed?[widget.key];
      if (child != null &&
          !_forgotten(forgottenChildren, child) &&
          Widget.canUpdate(child.widget, widget)) {
        keyed!.remove(widget.key);
      } else {
        // one with the key but of another type is removed with those left,
        // and one forgotten is taken back from where it went
        child = null;
      }
      previous = updateChild(child, widget, IndexedSlot(newTop, previous))!;
      newChildren.add(previous);
    }
    for (var i = oldBottom + 1; i < oldChildren.length; i++, newTop++) {
      final child = oldChildren[i];
      final slot = IndexedSlot(newTop, previous);
      previous = updateChild(
        _forgotten(forgottenChildren, child) ? null : child,
        newWidgets[newTop],
        slot,
      )!;
      newChildren.add(previous);
    }
    if (keyed != null) {
      for (final child in keyed.values) {
        if (!_forgotten(forgottenChildren, child)) {
          deactivateChild(child);
        }
      }
    }
    return newChildren;
  }

  // asked anew at each step of updateChildren: a GlobalKey takes a child
  // away meanwhile
  static bool _forgotten(Set<Element>? forgottenChildren, Element child) =>
      forgottenChildren != null &&
      // an empty set's lookup still hashes the element
      forgottenChildren.isNotEmpty &&
      forgottenChildren.contains(child);

  /// Creates the element of [newWidget] and mounts it as a child of this
  /// one at [newSlot]. For a widget with a [GlobalKey], the element of the
  /// key moves here instead if the widget can update it, wherever it is in
  /// the tree or among the elements removed in the frame: with its subtree,
  /// state and render objects, the old parent letting go of it. When that
  /// throws, what was mounted or moved here leaves the tree again.
  @protected
  Element inflateWidget(Widget newWidget, Object? newSlot) {
    final key = newWidget.key;
    Element? element;
    try {
      if (key is GlobalKey) {
        element = _retake(key, newWidget);
        if (element != null) {
          element._activateWithParent(this, newSlot);
          return updateChild(element, newWidget, newSlot)!;
        }
      }
      return (element = newWidget.createElement())..mount(this, newSlot);
    } on Object {
      if (element != null && identical(element._parent, this)) {
        deactivateChild(element);
      }
      rethrow;
    }
  }

  /// The element of [key] in this tree if [newWidget] can update it, taken
  /// from its parent if it has one, and off the inactive elements; null if
  /// there is none, or if it is this element or above it, which fails an
  /// assert.
  Element? _retake(GlobalKey key, Widget newWidget) {
    final owner = this.owner!;
    final element = owner._globalKeys[key];
    if (element == null || !Widget.canUpdate(element.widget, newWidget)) {
      return null;
    }
    var above = false;
    for (Element? e = this; e != null && !above; e = e._parent) {
      above = identical(e, element);
    }
    assert(!above, owner._onTwo(key, 'under ${_pathOf(this)}'));
    if (above) {
      return null;
    }
    final parent = element._parent;
    if (parent != null) {
      (owner._keysTakenFrom[parent] ??= {}).add(key);
      parent
        ..forgetChild(element)
        ..deactivateChild(element);
    }
    owner._inactive.remove(element);
    return element;
  }

  /// Puts this element, inactive, back in the tree under [parent] at
  /// [newSlot]: the elements of the subtree are activated, parents first,
  /// and its render objects go back into the render tree.
  void _activateWithParent(Element parent, Object? newSlot) {
    _parent = parent;
    _updateDepth(parent._depth);
    BuildOwner._activateAll(this);
    attachRenderObject(newSlot);
  }

  /// Gives this element and those below it their depths under a parent at
  /// [parentDepth].
  void _updateDepth(int parentDepth) {
    final depth = parentDepth + 1;
    if (_depth != depth) {
      _depth = depth;
      visitChildren((child) => child._updateDepth(depth));
    }
  }

  /// Removes [child] from the tree: its render objects leave the render
  /// tree now, and the owner unmounts it at the end of the frame unless a
  /// [GlobalKey] puts it back before.
  @protected
  void deactivateChild(Element child) {
    child
      .._parent = null
      ..detachRenderObject();
    owner!._deactivate(child);
  }

  /// Lets go of [child], which a [GlobalKey] is moving under another
  /// element: this element no longer visits it, and leaves it out when it
  /// next updates its children.
  @protected
  void forgetChild(Element child) {}

  /// Records that this element updated its children: those a [GlobalKey]
  /// took from it before are no longer on its widgets.
  void _childrenUpdated() => owner!._keysTakenFrom.remove(this);

  /// Takes the render objects of this subtree out of the render tree.
  void detachRenderObject() {
    visitChildren(_detachRenderObject);
    _slot = null;
  }

  static void _detachRenderObject(Element e) => e.detachRenderObject();

  /// Puts the render objects of this subtree, which [detachRenderObject]
  /// took out, back into the render tree at [newSlot].
  void attachRenderObject(Object? newSlot) {
    // the slot handed down in a static, not in a closure, which makes a
    // closure and a context at each element
    final outer = _attachingAt;
    _attachingAt = newSlot;
    try {
      visitChildren(_attachRenderObject);
    } finally {
      _attachingAt = outer;
    }
    _slot = newSlot;
  }

  /// The slot [attachRenderObject] puts the children it visits at.
  static Object? _attachingAt;

  static void _attachRenderObject(Element e) =>
      e.attachRenderObject(_attachingAt);

  /// Called when this element leaves the tree: it no longer finds
  /// inherited widgets, nor depends on any, unless [activate] puts it back.
  @mustCallSuper
  void deactivate() {
    _hadDependencies = _hasDependencies;
    _dropAllDependencies();
    _inheritedElements = null;
    _lifecycle = _Lifecycle.inactive;
  }

  /// Called when this element, deactivated earlier in the frame, is back
  /// in the tree, where a [GlobalKey] moved it or an element above it: it
  /// finds the inherited widgets of its new place, and is rebuilt if it
  /// depended on any, or if it was dirty.
  @mustCallSuper
  void activate() {
    assert(
      _lifecycle == _Lifecycle.inactive,
      '$this activated while ${_lifecycle.name}',
    );
    _lifecycle = _Lifecycle.active;
    _updateInheritance();
    // a place in the running build scope's dirty list was for where it was
    _inDirtyList = false;
    if (_dirty) {
      owner!.scheduleBuildFor(this);
    }
    if (_hadDependencies) {
      _hadDependencies = false;
      didChangeDependencies();
    }
  }

  /// Called when this element is unmounted for good, after [deactivate].
  @mustCallSuper
  void unmount() {
    final key = widget.key;
    if (key is GlobalKey) {
      owner!._unregisterGlobalKey(key, this);
    }
    _widget = null;
    _lifecycle = _Lifecycle.defunct;
  }

  /// Called when something this element depends on changed: it rebuilds.
  @mustCallSuper
  void didChangeDependencies() => markNeedsBuild();

  /// Rebuilds this element in its owner's next build scope.
  void markNeedsBuild() {
    if (_lifecycle != _Lifecycle.active || _dirty) {
      return;
    }
    _dirty = true;
    owner!.scheduleBuildFor(this);
  }

  /// Rebuilds this element if it is dirty, or [force]d, and in the tree.
  void rebuild({bool force = false}) {
    if (_lifecycle != _Lifecycle.active || (!_dirty && !force)) {
      return;
    }
    owner!._rebuilds++;
    performRebuild();
  }

  /// Does the rebuild and clears [dirty].
  @protected
  @mustCallSuper
  void performRebuild() {
    _dirty = false;
  }
}

/// What an element that builds its one child keeps: the child, and whether
/// it shows what the owner gave it in place of a build that threw.
mixin _BuildsChild on Element {
  Element? _child;

  // its last build threw
  var _failed = false;

  // the error the last report was of (its type and text), and what the
  // owner gave for it
  String? _failure;
  Widget? _failureShown;

  /// What to show for [error], which [element] threw (this element or one
  /// below it): what the owner returns ([BuildOwner.onBuildError]), or,
  /// while the last build failed with an error of the same type and text,
  /// what it returned then, reported no more: an element that throws the
  /// same on every rebuild is reported once.
  Widget _failedWith(Element element, Object error, StackTrace stack) {
    final String text;
    try {
      text = '${error.runtimeType}: $error';
    } on Object {
      return owner!._buildFailed(element, error, stack);
    }
    final shown = _failureShown;
    if (_failed && shown != null && text == _failure) {
      return shown;
    }
    final widget = owner!._buildFailed(element, error, stack);
    _failure = text;
    _failureShown = widget;
    return widget;
  }

  /// A build succeeded: the next failure is reported.
  void _built() {
    _failed = false;
    _failure = null;
    _failureShown = null;
  }

  /// The slot of the child.
  Object? get _childSlot;

  /// Raises [DiagnosticsFlag.error] while it shows what the owner gave it in
  /// place of a build that threw.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    if (_failed) {
      properties.flag(DiagnosticsFlag.error);
    }
  }

  /// Shows what the owner returns for [error], which [element] threw (this
  /// element or one below it), in place of the child.
  void _showError(Element element, Object error, StackTrace stack) {
    final shown = _failedWith(element, error, stack);
    _failed = true;
    // a child an update left half done goes; one it removed is gone
    final child = _child;
    _child = updateChild(
      child != null && identical(child._parent, this) ? child : null,
      shown,
      _childSlot,
    );
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null) {
      visitor(_child!);
    }
  }

  @override
  void forgetChild(Element child) {
    assert(identical(child, _child), '$child is not the child of $this');
    _child = null;
  }
}

/// An element that builds one child widget.
abstract class ComponentElement extends Element with _BuildsChild {
  /// An element of [widget], which builds its child when mounted.
  ComponentElement(super.widget);

  @override
  Object? get _childSlot => slot;

  @override
  Element? get _renderObjectAttachingChild => _child;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _firstBuild();
  }

  void _firstBuild() => rebuild();

  /// The child widget this element shows now.
  @protected
  Widget build();

  /// Builds the child widget and makes the child show it. A build that
  /// throws is reported to the owner, and the child shows what the owner
  /// returns instead; so is what is thrown below as the child is made to
  /// show it, other than by the builds there (a createRenderObject,
  /// updateRenderObject, initState or didUpdateWidget), which goes on up
  /// when the owner has no [BuildOwner.onBuildError].
  @override
  void performRebuild() {
    Widget built;
    try {
      final previous = _takeDependencies();
      try {
        built = build();
      } finally {
        _dropDependencies(previous);
      }
      _built();
    } on Object catch (error, stack) {
      built = _failedWith(this, error, stack);
      _failed = true;
    } finally {
      super.performRebuild();
    }
    try {
      _child = updateChild(_child, built, slot);
    } on Object catch (error, stack) {
      if (owner!.onBuildError == null) {
        rethrow;
      }
      _showError(this, error, stack);
    }
    _childrenUpdated();
  }
}

/// The element of a [StatelessWidget].
class StatelessElement extends ComponentElement {
  /// An element of [widget], which builds what [StatelessWidget.build]
  /// returns.
  StatelessElement(StatelessWidget super.widget);

  @override
  StatelessWidget get widget => super.widget as StatelessWidget;

  @override
  Widget build() => widget.build(this);

  @override
  void update(StatelessWidget newWidget) {
    super.update(newWidget);
    rebuild(force: true);
  }
}

/// The element of a [StatefulWidget]; it keeps the [state].
class StatefulElement extends ComponentElement {
  /// An element of [widget], with the state [StatefulWidget.createState]
  /// makes, whose [State.initState] runs when the element is mounted.
  StatefulElement(StatefulWidget widget)
    : _state = widget.createState(),
      super(widget) {
    state
      .._element = this
      .._widget = widget;
  }

  State<StatefulWidget>? _state;

  // didChangeDependencies is due before the next build
  var _didChangeDependencies = false;

  // initState runs, or threw: then the state is neither deactivated nor
  // disposed
  var _initializing = false;

  // the inherited elements the state depends on, registered since its last
  // didChangeDependencies began
  Set<InheritedElement>? _stateDependencies;

  @override
  StatefulWidget get widget => super.widget as StatefulWidget;

  /// The state, until the element is unmounted.
  State<StatefulWidget> get state => _state!;

  @override
  Widget build() => state.build(this);

  /// Adds the state's properties after the widget's.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    state.debugFillProperties(properties);
  }

  @override
  void _firstBuild() {
    _initializing = true;
    state.initState();
    _initializing = false;
    _changeDependencies();
    super._firstBuild();
  }

  @override
  void performRebuild() {
    if (_didChangeDependencies) {
      _didChangeDependencies = false;
      _changeDependencies();
    }
    super.performRebuild();
  }

  /// Calls the state's didChangeDependencies, in which it registers its
  /// dependencies anew: those it had and does not register again are
  /// dropped, unless the last build registered them.
  void _changeDependencies() {
    final built = _dependencies;
    final previous = _stateDependencies;
    _dependencies = null;
    try {
      state.didChangeDependencies();
    } finally {
      _stateDependencies = _dependencies;
      _dependencies = built;
      _dropDependencies(previous);
    }
  }

  @override
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor) {
    assert(
      !_initializing,
      '$state depends on ${ancestor.widget.runtimeType} in initState(), '
      'which is not called again when it changes: depend on it in '
      'didChangeDependencies() or build()',
    );
    return super.dependOnInheritedElement(ancestor);
  }

  @override
  bool _dependsOn(InheritedElement ancestor) =>
      super._dependsOn(ancestor) ||
      (_stateDependencies?.contains(ancestor) ?? false);

  @override
  bool get _hasDependencies =>
      super._hasDependencies || (_stateDependencies?.isNotEmpty ?? false);

  @override
  void _dropAllDependencies() {
    final previous = _stateDependencies;
    _stateDependencies = null;
    super._dropAllDependencies();
    _dropDependencies(previous);
  }

  @override
  void update(StatefulWidget newWidget) {
    super.update(newWidget);
    final oldWidget = state.widget;
    state
      .._widget = newWidget
      ..didUpdateWidget(oldWidget);
    rebuild(force: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _didChangeDependencies = true;
  }

  @override
  void deactivate() {
    if (!_initializing) {
      state.deactivate();
    }
    super.deactivate();
  }

  /// Activates the state too, and rebuilds: it may have let go in
  /// [State.deactivate] of what its build set up.
  @override
  void activate() {
    super.activate();
    state.activate();
    markNeedsBuild();
  }

  /// Disposes the state too: let go of by its element also when its
  /// [State.dispose] throws, which goes on up.
  @override
  void unmount() {
    super.unmount();
    try {
      if (!_initializing) {
        state.dispose();
      }
    } finally {
      state._element = null;
      _state = null;
    }
  }
}

/// A widget that shows its [child] and does something else for the
/// subtree; its element is told when it is replaced.
abstract class ProxyWidget extends Widget {
  /// For subclasses: shows [child].
  const ProxyWidget({required this.child, super.key});

  /// The widget below this one, which it shows as it is.
  final Widget child;
}

/// The element of a [ProxyWidget]: it builds the widget's child, and when
/// the widget is replaced, calls [updated] before it updates the child.
abstract class ProxyElement extends ComponentElement {
  /// An element of [widget], which builds the widget's child.
  ProxyElement(ProxyWidget super.widget);

  @override
  ProxyWidget get widget => super.widget as ProxyWidget;

  @override
  Widget build() => widget.child;

  @override
  void update(ProxyWidget newWidget) {
    final oldWidget = widget;
    super.update(newWidget);
    updated(oldWidget);
    rebuild(force: true);
  }

  /// Called when [widget] replaced [oldWidget]: it notifies the clients.
  @protected
  void updated(covariant ProxyWidget oldWidget) => notifyClients(oldWidget);

  /// Tells those that use the widget that it replaced [oldWidget].
  @protected
  void notifyClients(covariant ProxyWidget oldWidget);
}

/// A widget that the elements below it find by its type in constant time
/// ([BuildContext.dependOnInheritedWidgetOfExactType]), the nearest one of
/// a type hiding those above it. Those that depend on it are rebuilt when
/// it is replaced by one that [updateShouldNotify]s; the others are not.
///
/// A value for a subtree, read with a static `of` as the framework's own
/// inherited widgets (`Theme`, `DefaultTextStyle`) are:
///
/// ```dart
/// final class Account extends InheritedWidget {
///   const Account({required this.user, required super.child, super.key});
///
///   final String user;
///
///   static String of(BuildContext context) =>
///       context.dependOnInheritedWidgetOfExactType<Account>()!.user;
///
///   @override
///   bool updateShouldNotify(Account oldWidget) => user != oldWidget.user;
/// }
/// ```
///
/// See also:
///
///  * `ListenableBuilder`, for a value that changes without its parent
///    rebuilding.
abstract class InheritedWidget extends ProxyWidget {
  /// For subclasses: shows [child], whose subtree finds this widget.
  const InheritedWidget({required super.child, super.key});

  @override
  InheritedElement createElement() => InheritedElement(this);

  /// Whether the elements that depend on this widget are to be rebuilt now
  /// that it replaced [oldWidget].
  @protected
  bool updateShouldNotify(covariant InheritedWidget oldWidget);
}

/// The element of an [InheritedWidget]: it keeps the elements that depend
/// on it, and tells each of them when a new widget
/// [InheritedWidget.updateShouldNotify]s.
class InheritedElement extends ProxyElement {
  /// An element of [widget], which the elements below it find.
  InheritedElement(InheritedWidget super.widget);

  // the elements that depend on this one, in the order they started to
  final _dependents = <Element>{};

  @override
  InheritedWidget get widget => super.widget as InheritedWidget;

  @override
  void _updateInheritance() {
    _inheritedElements = {
      ...?_parent?._inheritedElements,
      widget.runtimeType: this,
    };
  }

  @override
  void updated(InheritedWidget oldWidget) {
    if (widget.updateShouldNotify(oldWidget)) {
      super.updated(oldWidget);
    }
  }

  /// Calls [notifyDependent] for each element that depends on this one.
  @override
  void notifyClients(InheritedWidget oldWidget) {
    for (final dependent in _dependents) {
      notifyDependent(oldWidget, dependent);
    }
  }

  /// Tells [dependent] that the widget replaced [oldWidget]: calls its
  /// [Element.didChangeDependencies].
  @protected
  void notifyDependent(
    covariant InheritedWidget oldWidget,
    Element dependent,
  ) => dependent.didChangeDependencies();
}

/// A widget that puts data on the render object below it, the [T] its
/// parent keeps on it for its layout (a flex factor, a position). That
/// render object is the one of the nearest element below this one that has
/// one, through widgets without one; its parent is the render object of
/// the nearest render object element above this one, which has to keep a
/// [T] on its children. One widget at most puts data of a type on a render
/// object.
///
/// A tag a parent of an app's own lays its children out by:
///
/// ```dart
/// final class TagData extends ParentData {
///   String? tag;
/// }
///
/// final class Tag extends ParentDataWidget<TagData> {
///   const Tag(this.tag, {required super.child, super.key});
///
///   final String tag;
///
///   @override
///   void applyParentData(RenderObject renderObject) {
///     final data = renderObject.parentData as TagData;
///     if (data.tag != tag) {
///       data.tag = tag;
///       renderObject.parent?.markNeedsLayout();
///     }
///   }
///
///   @override
///   Type get debugTypicalAncestorWidgetClass => Column;
/// }
/// ```
abstract class ParentDataWidget<T extends ParentData> extends ProxyWidget {
  /// For subclasses: puts its data on the render object of [child].
  const ParentDataWidget({required super.child, super.key});

  @override
  ParentDataElement<T> createElement() => ParentDataElement<T>(this);

  /// Puts this widget's data on the parent data of [renderObject], a [T],
  /// and lays the parent out again when that changed it. Called when the
  /// render object is placed in the render tree, and when this widget
  /// replaced another.
  @protected
  void applyParentData(RenderObject renderObject);

  /// The widget this one usually goes inside, for the message when it is
  /// used elsewhere.
  Type get debugTypicalAncestorWidgetClass;

  /// The type of the data this widget puts on a render object.
  Type get _dataType => T;

  /// Whether the parent of [renderObject] keeps a [T] on it.
  bool _fits(RenderObject renderObject) => renderObject.parentData is T;
}

/// The element of a [ParentDataWidget]: it puts the data of each new
/// widget on the render object below it.
class ParentDataElement<T extends ParentData> extends ProxyElement {
  /// An element of [widget].
  ParentDataElement(ParentDataWidget<T> super.widget);

  @override
  ParentDataWidget<T> get widget => super.widget as ParentDataWidget<T>;

  @override
  void notifyClients(ParentDataWidget<T> oldWidget) {
    for (var e = _child; e != null; e = e._renderObjectAttachingChild) {
      if (e is RenderObjectElement) {
        e._applyParentData(widget);
        return;
      }
    }
  }
}

/// What a [NotificationListener] calls with each notification of type [T]
/// that reaches it; true stops the notification there.
typedef NotificationListenerCallback<T extends Notification> = bool Function(
  T notification,
);

/// Something that happened in a subtree, told to the [NotificationListener]s
/// above it: [dispatch] bubbles it up from a context, the nearest listener
/// first, until one of them stops it.
///
/// ```dart
/// final class Saved extends Notification {
///   const Saved(this.path);
///
///   final String path;
/// }
///
/// void save(BuildContext context) =>
///     const Saved('notes.txt').dispatch(context);
/// ```
abstract class Notification {
  /// For subclasses.
  const Notification();

  /// Tells the listeners above [target] about this notification, the
  /// nearest first, until one of them returns true; a walk up the tree that
  /// stops there.
  void dispatch(BuildContext target) =>
      target.visitAncestorElements(visitAncestor);

  /// Called by [dispatch] for each ancestor of the target, the nearest
  /// first: tells [element] about this notification if it is a listener's,
  /// and returns whether the notification goes on up.
  @protected
  @mustCallSuper
  bool visitAncestor(Element element) =>
      element is! _NotificationElement<Notification> || !element._notify(this);

  @override
  String toString() => '$runtimeType';
}

/// A widget that hears the [Notification]s of type [T] dispatched from the
/// contexts below it: [onNotification] returns true to stop one there, or
/// false to let it bubble on up. Notifications of other types go past it.
///
/// A list that hears its rows scroll, and lets the notifications go on up:
///
/// ```dart
/// NotificationListener<ScrollNotification>(
///   onNotification: (n) {
///     log('scrolled to ${n.metrics.offset}');
///     return false;
///   },
///   child: ListView(children: const [Text('one'), Text('two')]),
/// )
/// ```
final class NotificationListener<T extends Notification> extends ProxyWidget {
  /// Hears the notifications of type [T] from [child]'s subtree with
  /// [onNotification].
  const NotificationListener({
    required super.child,
    super.key,
    this.onNotification,
  });

  /// Called with each notification of type [T] that reaches this widget;
  /// without it, they all go past.
  // called by the element, whose T is the widget's own
  // ignore: unsafe_variance
  final NotificationListenerCallback<T>? onNotification;

  @override
  ProxyElement createElement() => _NotificationElement<T>(this);
}

/// The element of a [NotificationListener]: it hands the notifications of
/// type [T] that reach it to the widget's callback.
final class _NotificationElement<T extends Notification> extends ProxyElement {
  _NotificationElement(NotificationListener<T> super.widget);

  @override
  NotificationListener<T> get widget => super.widget as NotificationListener<T>;

  /// Whether the widget's callback heard [notification] and stopped it.
  bool _notify(Notification notification) =>
      notification is T && (widget.onNotification?.call(notification) ?? false);

  // the subtree takes nothing from the widget
  @override
  void notifyClients(NotificationListener<T> oldWidget) {}
}

/// A widget with a render object of the core: its element creates the
/// render object, updates it with each new widget and places it in the
/// render tree under the render object of the nearest ancestor that has
/// one.
///
/// A widget of an app's own that lays out and paints writes its render
/// object, and creates it here; this one paints three dots:
///
/// ```dart
/// final class Dots extends LeafRenderObjectWidget {
///   const Dots({super.key});
///
///   @override
///   RenderObject createRenderObject(BuildContext context) => _RenderDots();
/// }
///
/// final class _RenderDots extends RenderObject {
///   @override
///   void performLayout(BoxConstraints c) {
///     width = c.constrainW(3);
///     height = c.constrainH(1);
///   }
///
///   @override
///   void paint(PaintContext ctx) {
///     final canvas = ctx.canvas;
///     canvas.text(0, 0, '...', canvas.styles.pen(const Pen()));
///   }
/// }
/// ```
///
/// A widget with fields updates the render object from them in
/// [updateRenderObject] too, as [RenderObject]'s own example shows.
abstract class RenderObjectWidget extends Widget {
  /// For subclasses.
  const RenderObjectWidget({super.key});

  @override
  RenderObjectElement createElement();

  /// Creates the render object, configured from this widget.
  @protected
  RenderObject createRenderObject(BuildContext context);

  /// Configures [renderObject] from this widget: called when it replaced
  /// the widget that created or last configured the render object, and
  /// when the element is rebuilt.
  @protected
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {}

  /// Called when the element of [renderObject] was unmounted: release what
  /// the render object holds.
  @protected
  void didUnmountRenderObject(covariant RenderObject renderObject) {}
}

/// A render object widget without children.
abstract class LeafRenderObjectWidget extends RenderObjectWidget {
  /// For subclasses.
  const LeafRenderObjectWidget({super.key});

  @override
  LeafRenderObjectElement createElement() => LeafRenderObjectElement(this);
}

/// A render object widget with at most one child. The render object's
/// child is set by the element, which each widget provides
/// ([RenderObjectElement.insertRenderObjectChild] and the rest): a
/// [OneChildElement] where the render object has a
/// [RenderObjectWithChildMixin].
abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  /// For subclasses: the render object's child is [child]'s.
  const SingleChildRenderObjectWidget({super.key, this.child});

  /// The widget below this one, whose render object is the child of this
  /// one's; null for none.
  final Widget? child;

  @override
  SingleChildRenderObjectElement createElement();
}

/// A render object widget with a list of children. The render object's
/// children are kept in order by the element, which each widget provides
/// ([RenderObjectElement.insertRenderObjectChild] and the rest): a
/// [ChildListElement] where the render object has a
/// [ContainerRenderObjectMixin].
abstract class MultiChildRenderObjectWidget extends RenderObjectWidget {
  /// For subclasses: the render object's children are those of
  /// [children], in order. Two of them with equal keys fail an assert.
  const MultiChildRenderObjectWidget({
    super.key,
    this.children = const <Widget>[],
  });

  /// The widgets below this one, whose render objects are the children of
  /// this one's, in order; none by default.
  final List<Widget> children;

  @override
  MultiChildRenderObjectElement createElement();
}

/// The element of a [RenderObjectWidget]. The render objects of the
/// elements below it, down to the next render object elements, are its
/// render object's children: it puts them into it, moves them and takes
/// them out, through that render object's own API.
abstract class RenderObjectElement extends Element {
  /// An element of [widget], which creates its render object when mounted.
  RenderObjectElement(RenderObjectWidget super.widget);

  RenderObject? _renderObject;
  RenderObjectElement? _ancestorRenderObjectElement;

  @override
  RenderObjectWidget get widget => super.widget as RenderObjectWidget;

  @override
  RenderObject get renderObject => _renderObject!;

  /// Adds after the widget's properties those its render object describes
  /// ([RenderObject.debugFillProperties]) and those its parent keeps on it
  /// ([ParentData.debugFillProperties]), and its flags: a repaint boundary,
  /// to be laid out, to be repainted, showing an error its layout or paint
  /// threw.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final o = renderObject..debugFillProperties(properties);
    o.parentData.debugFillProperties(properties);
    if (o.isRepaintBoundary) {
      properties.flag(DiagnosticsFlag.repaintBoundary);
    }
    if (o.debugNeedsLayout) {
      properties.flag(DiagnosticsFlag.needsLayout);
    }
    if (o.debugNeedsPaint) {
      properties.flag(DiagnosticsFlag.needsPaint);
    }
    if (o.debugError != null) {
      properties.flag(DiagnosticsFlag.error);
    }
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _renderObject = widget.createRenderObject(this);
    attachRenderObject(newSlot);
    _dirty = false;
  }

  @override
  void update(covariant RenderObjectWidget newWidget) {
    super.update(newWidget);
    _updateRenderObject();
    _dirty = false;
  }

  @override
  void performRebuild() {
    _updateRenderObject();
    super.performRebuild();
  }

  void _updateRenderObject() {
    final previous = _takeDependencies();
    try {
      widget.updateRenderObject(this, renderObject);
    } finally {
      _dropDependencies(previous);
    }
  }

  /// Puts the render object into the render tree at [newSlot], as a child
  /// of the nearest ancestor render object element's (a root has none),
  /// with the data of the [ParentDataWidget]s in between.
  @override
  void attachRenderObject(Object? newSlot) {
    _slot = newSlot;
    var ancestor = _parent;
    while (ancestor != null && ancestor is! RenderObjectElement) {
      ancestor = ancestor._parent;
    }
    final host = ancestor as RenderObjectElement?;
    _ancestorRenderObjectElement = host;
    host?.insertRenderObjectChild(renderObject, newSlot);
    for (var e = _parent; e != null && e != host; e = e._parent) {
      if (e is ParentDataElement<ParentData>) {
        assert(
          _sameKindBelow(e) == null,
          '${_nameOf(e)} and ${_nameOf(_sameKindBelow(e)!)} below it both '
          'put ${e.widget._dataType} on the render object of '
          '${_pathOf(this)}: one widget at most puts data of a type on it',
        );
        _applyParentData(e.widget);
      }
    }
  }

  /// The parent data element between this element and [outer] whose
  /// widget puts the same type of data as [outer]'s.
  ParentDataElement<ParentData>? _sameKindBelow(
    ParentDataElement<ParentData> outer,
  ) {
    for (var e = _parent; e != null && e != outer; e = e._parent) {
      if (e is ParentDataElement<ParentData> &&
          e.widget._dataType == outer.widget._dataType) {
        return e;
      }
    }
    return null;
  }

  /// Puts the data of [parentDataWidget] on the render object if its
  /// parent keeps that type of data on it, as it has to.
  void _applyParentData(ParentDataWidget<ParentData> parentDataWidget) {
    final fits = parentDataWidget._fits(renderObject);
    assert(fits, _misplaced(parentDataWidget));
    if (fits) {
      parentDataWidget.applyParentData(renderObject);
    }
  }

  /// Says that the parent does not keep the type of data
  /// [parentDataWidget] puts on the render object, and where it goes.
  String _misplaced(ParentDataWidget<ParentData> parentDataWidget) {
    final kind = parentDataWidget.runtimeType;
    final host = _ancestorRenderObjectElement;
    final keeps = host == null
        ? 'which has no parent'
        : 'on which ${_nameOf(host)} keeps '
              '${renderObject.parentData.runtimeType}';
    return '$kind puts ${parentDataWidget._dataType} on the render object '
        'of ${_pathOf(this)}, $keeps: $kind widgets go inside '
        '${parentDataWidget.debugTypicalAncestorWidgetClass} widgets, with '
        'no render object widget in between';
  }

  @override
  void detachRenderObject() {
    _ancestorRenderObjectElement?.removeRenderObjectChild(renderObject, slot);
    _ancestorRenderObjectElement = null;
    _slot = null;
  }

  @override
  void updateSlot(Object? newSlot) {
    final oldSlot = slot;
    super.updateSlot(newSlot);
    _ancestorRenderObjectElement?.moveRenderObjectChild(
      renderObject,
      oldSlot,
      newSlot,
    );
  }

  @override
  void unmount() {
    final oldWidget = widget;
    super.unmount();
    // there is none when createRenderObject threw
    final o = _renderObject;
    if (o != null) {
      oldWidget.didUnmountRenderObject(o);
    }
    _renderObject = null;
  }

  /// Makes [child] a child of [renderObject] at [slot].
  @protected
  void insertRenderObjectChild(
    covariant RenderObject child,
    covariant Object? slot,
  );

  /// Moves [child], a child of [renderObject], from [oldSlot] to [newSlot].
  @protected
  void moveRenderObjectChild(
    covariant RenderObject child,
    covariant Object? oldSlot,
    covariant Object? newSlot,
  );

  /// Takes [child], at [slot], out of [renderObject]'s children.
  @protected
  void removeRenderObjectChild(
    covariant RenderObject child,
    covariant Object? slot,
  );
}

/// The element of a [LeafRenderObjectWidget]: its render object has no
/// children, and putting one in it throws an [UnsupportedError].
class LeafRenderObjectElement extends RenderObjectElement {
  /// An element of [widget].
  LeafRenderObjectElement(LeafRenderObjectWidget super.widget);

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) =>
      throw UnsupportedError('a leaf has no children: $this');

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) => throw UnsupportedError('a leaf has no children: $this');

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) =>
      throw UnsupportedError('a leaf has no children: $this');
}

/// The element of a [SingleChildRenderObjectWidget]; its child's slot is
/// null.
abstract class SingleChildRenderObjectElement extends RenderObjectElement {
  /// An element of [widget], which mounts the widget's child below it.
  SingleChildRenderObjectElement(SingleChildRenderObjectWidget super.widget);

  Element? _child;

  @override
  SingleChildRenderObjectWidget get widget =>
      super.widget as SingleChildRenderObjectWidget;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _child = updateChild(_child, widget.child, null);
  }

  @override
  void update(SingleChildRenderObjectWidget newWidget) {
    super.update(newWidget);
    _child = updateChild(_child, widget.child, null);
    _childrenUpdated();
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    if (_child != null) {
      visitor(_child!);
    }
  }

  @override
  void forgetChild(Element child) {
    assert(identical(child, _child), '$child is not the child of $this');
    _child = null;
  }
}

/// The element of a [MultiChildRenderObjectWidget]. Each child's slot is
/// an [IndexedSlot]: a render object goes after the render object of the
/// sibling before it.
abstract class MultiChildRenderObjectElement extends RenderObjectElement {
  /// An element of [widget], which mounts the widget's children below it.
  MultiChildRenderObjectElement(MultiChildRenderObjectWidget super.widget);

  var _children = const <Element>[];

  // the children in _children that a GlobalKey took elsewhere
  final _forgottenChildren = <Element>{};

  @override
  MultiChildRenderObjectWidget get widget =>
      super.widget as MultiChildRenderObjectWidget;

  /// The child elements, in order.
  @protected
  @visibleForTesting
  Iterable<Element> get children =>
      _children.where((c) => !_forgottenChildren.contains(c));

  @override
  void mount(Element? parent, Object? newSlot) {
    assert(
      _duplicateKey(widget) == null,
      '$widget has children with equal keys: ${_duplicateKey(widget)}',
    );
    super.mount(parent, newSlot);
    // the children mounted so far are its own, should the next one throw
    final children = _children = <Element>[];
    Element? previous;
    for (final w in widget.children) {
      previous = inflateWidget(w, IndexedSlot(children.length, previous));
      children.add(previous);
    }
    _childrenUpdated();
  }

  @override
  void update(MultiChildRenderObjectWidget newWidget) {
    assert(
      _duplicateKey(newWidget) == null,
      '$newWidget has children with equal keys: ${_duplicateKey(newWidget)}',
    );
    super.update(newWidget);
    _children = updateChildren(
      _children,
      widget.children,
      forgottenChildren: _forgottenChildren,
    );
    _childrenUpdated();
  }

  /// Keeps forgotten only the children a [GlobalKey] took after they were
  /// placed among the new ones, whose keys are on two widgets at once; one
  /// the update took back is a child again.
  @override
  void _childrenUpdated() {
    // retainAll copies the set, even an empty one
    if (_forgottenChildren.isNotEmpty) {
      _keepForgotten();
    }
    if (_forgottenChildren.isEmpty) {
      super._childrenUpdated();
    }
  }

  /// Apart from [_childrenUpdated], which then makes no context for this
  /// closure when nothing is forgotten.
  void _keepForgotten() => _forgottenChildren
    ..retainAll(_children)
    ..removeWhere((c) => identical(c._parent, this));

  @override
  void visitChildren(ElementVisitor visitor) {
    for (final child in _children) {
      if (!_forgottenChildren.contains(child)) {
        visitor(child);
      }
    }
  }

  @override
  void forgetChild(Element child) {
    _forgottenChildren.add(child);
  }

  /// The first key among [widget]'s children equal to an earlier one's.
  static Key? _duplicateKey(MultiChildRenderObjectWidget widget) {
    final keys = <Key>{};
    for (final child in widget.children) {
      final key = child.key;
      if (key != null && !keys.add(key)) {
        return key;
      }
    }
    return null;
  }
}

/// The slot of a child among several: its [index], and the sibling before
/// it ([value], null for the first), whose render object the child's
/// render object follows.
@immutable
final class IndexedSlot<T extends Element?> {
  /// The slot at [index], after [value].
  const IndexedSlot(this.index, this.value);

  /// Where the child is among its siblings, the first at 0.
  final int index;

  /// The sibling before the child; null for the first.
  final T value;

  @override
  bool operator ==(Object other) =>
      other is IndexedSlot<Element?> &&
      other.index == index &&
      identical(other.value, value);

  @override
  int get hashCode => Object.hash(index, value);
}

/// What a [LayoutBuilder] builds its child with: its context and the
/// constraints it is laid out within.
typedef LayoutWidgetBuilder = Widget Function(
  BuildContext context,
  BoxConstraints constraints,
);

/// Builds its child with the constraints it is laid out within, so that
/// what it shows depends on the room it gets: one layout for a wide
/// terminal and another for a narrow one, a pane that collapses.
///
/// [builder] runs in the layout of a frame, not in its build: at the first
/// layout, when the constraints differ from those of the last build, when
/// the widget is replaced, and when an inherited widget the builder depends
/// on changes; at no other layout. What it builds is laid out in the same
/// frame, and the elements below it marked dirty meanwhile are rebuilt
/// with it; those elsewhere wait for the next build scope. A build that
/// throws is reported as any build is ([BuildOwner.onBuildError]), and what
/// the owner returns shown in place of the child.
///
/// It is as big as its child. Its intrinsic sizes are those of the child
/// it built last, none before its first layout: the builder does not run
/// for them, and a parent laid out by sizes that the next build changed is
/// laid out again on the next frame.
///
/// Two panes side by side in a terminal 80 columns wide or more, one
/// above the other in a narrower one:
///
/// ```dart
/// LayoutBuilder(
///   builder: (context, constraints) => constraints.maxW >= 80
///       ? Row(children: const [Text('list'), Text('details')])
///       : Column(children: const [Text('list'), Text('details')]),
/// )
/// ```
///
/// See also:
///
///  * [Builder], which builds with its context in the build, not the
///    layout.
final class LayoutBuilder extends RenderObjectWidget {
  /// Builds its child with [builder] at its layout.
  const LayoutBuilder({required this.builder, super.key});

  /// Builds the child for the constraints.
  final LayoutWidgetBuilder builder;

  @override
  RenderObjectElement createElement() => _LayoutBuilderElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutBuilder();
}

/// The element of a [LayoutBuilder]: it builds its child when its render
/// object is laid out, in a build of its own ([BuildOwner._buildInLayout]).
final class _LayoutBuilderElement extends RenderObjectElement
    with _BuildsChild {
  _LayoutBuilderElement(LayoutBuilder super.widget);

  @override
  LayoutBuilder get widget => super.widget as LayoutBuilder;

  @override
  _RenderLayoutBuilder get renderObject =>
      super.renderObject as _RenderLayoutBuilder;

  @override
  Object? get _childSlot => null;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject._build = _build;
  }

  // a new widget, or a dependency that changed: the builder runs at the
  // next layout, where it registers its dependencies anew
  @override
  void _updateRenderObject() => renderObject._markNeedsBuild();

  @override
  void unmount() {
    // there is none when mounting it threw
    final o = _renderObject;
    if (o is _RenderLayoutBuilder) {
      o._build = null;
    }
    super.unmount();
  }

  /// Builds the child for [constraints], as the render object is laid out.
  void _build(BoxConstraints constraints) => owner!._buildInLayout(this, () {
    Widget built;
    try {
      final previous = _takeDependencies();
      try {
        built = widget.builder(this, constraints);
      } finally {
        _dropDependencies(previous);
      }
      _built();
    } on Object catch (error, stack) {
      built = _failedWith(this, error, stack);
      _failed = true;
    }
    try {
      _child = updateChild(_child, built, null);
    } on Object catch (error, stack) {
      if (owner!.onBuildError == null) {
        rethrow;
      }
      _showError(this, error, stack);
    }
    _childrenUpdated();
  });

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.child = child;

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) => throw UnsupportedError('one child does not move: $this');

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    assert(identical(renderObject.child, child), '$child is not the child');
    renderObject.child = null;
  }
}

/// The render object of a [LayoutBuilder]: at its layout, it has the
/// element build its child for its constraints when they differ from those
/// of the last build or a build was asked for, then lays the child out
/// within them. As big as its child; without one, as small as the
/// constraints allow. Its intrinsic sizes are the child's.
final class _RenderLayoutBuilder extends RenderObject
    with RenderObjectWithChildMixin {
  void Function(BoxConstraints constraints)? _build;
  BoxConstraints? _built;
  var _needsBuild = true;

  /// Has the child built again at the next layout.
  void _markNeedsBuild() {
    _needsBuild = true;
    markNeedsLayout();
  }

  @override
  void performLayout(BoxConstraints c) {
    final build = _build;
    if (build != null && (_needsBuild || c != _built)) {
      _needsBuild = false;
      _built = c;
      invokeLayoutCallback(() => build(c));
    }
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(c, parentUsesSize: true);
    width = c.constrainW(child.width);
    height = c.constrainH(child.height);
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}

/// The widget at the top of a tree; [attach] mounts it with a
/// [BuildOwner].
///
/// `runApp` puts the app's widget under one; a tree of widgets run
/// without an app (a test of a layout, a tool that renders to a string)
/// is mounted with one, and its render object, the root's below it, laid
/// out by the core's pipeline:
///
/// ```dart
/// final owner = BuildOwner();
/// final root = const RootWidget(child: Text('hi')).attach(owner);
/// final renderObject = root.renderObject;
/// ```
final class RootWidget extends Widget {
  /// A root that shows [child].
  const RootWidget({required this.child});

  /// The widget at the top of the tree below the root: an app's.
  final Widget child;

  @override
  RootElement createElement() => RootElement(this);

  /// Mounts this widget as the root of a tree that [owner] builds. Given
  /// the [element] an earlier call returned, that root shows this widget
  /// from [owner]'s next build scope on instead.
  RootElement attach(BuildOwner owner, [RootElement? element]) {
    if (element == null) {
      final root = createElement().._owner = owner;
      owner.buildScope(() => root.mount(null, null));
      return root;
    }
    element
      .._newWidget = this
      ..markNeedsBuild();
    return element;
  }
}

/// The element of a [RootWidget]: the root of an element tree.
final class RootElement extends ComponentElement {
  /// An element of [widget], which [RootWidget.attach] mounts.
  RootElement(RootWidget super.widget);

  RootWidget? _newWidget;

  @override
  RootWidget get widget => super.widget as RootWidget;

  @override
  Widget build() => widget.child;

  @override
  void performRebuild() {
    final next = _newWidget;
    if (next != null) {
      _newWidget = null;
      _widget = next;
    }
    super.performRebuild();
  }
}

/// Builds a tree of elements: the dirty ones are rebuilt in a build scope,
/// and the removed ones are unmounted when the tree is finalized. A frame
/// calls [buildScope] first and [finalizeTree] last.
final class BuildOwner {
  /// An owner that calls [onBuildScheduled] when an element becomes dirty
  /// and reports a build that throws to [onBuildError].
  BuildOwner({this.onBuildScheduled, this.onBuildError});

  /// Called when an element becomes dirty while no build scope is pending:
  /// the frame loop schedules one.
  final void Function()? onBuildScheduled;

  /// Reports an exception thrown by an element's build, and returns the
  /// widget that element shows instead. So is one a component element's
  /// child threw while it was updated (see [ComponentElement.performRebuild])
  /// and one a rebuild threw past that (a state's didChangeDependencies, an
  /// updateRenderObject when a dependency changed): reported for the
  /// element that threw it, the nearest component element or
  /// [LayoutBuilder] at or above it shows the widget in place of its child.
  /// An element whose builds go on throwing an error of the same type and
  /// text is reported once: it shows the widget again until it builds, or
  /// throws another. Unset, a build's exception
  /// goes to the current [Zone]'s error handler and the element shows an
  /// empty render object; the others go out of [buildScope].
  final Widget Function(Element element, Object error, StackTrace stack)?
  onBuildError;

  final _dirty = <Element>[];
  final _inactive = <Element>{};
  final _globalKeys = <GlobalKey, Element>{};
  // since the last finalizeTree: the elements a GlobalKey took a child
  // from, with those keys, until they update their children; the elements
  // whose GlobalKey a newer element took over, with the keys
  final _keysTakenFrom = <Element, Set<GlobalKey>>{};
  final _keysTakenOver = <Element, GlobalKey>{};
  // onBuildScheduled was called, or a build scope runs
  var _scheduled = false;
  var _needsSorting = false;

  /// How many times elements of this owner's tree have built
  /// ([Element.rebuild]): when mounted, when dirty and when updated with a
  /// new widget. A frame's are the difference.
  int get rebuilds => _rebuilds;
  var _rebuilds = 0;

  /// Adds [element], just marked dirty, to the next build scope. One
  /// rebuilt earlier in the running scope fails an assert naming its path,
  /// as builds that mark one another dirty so can loop; without asserts it
  /// is rebuilt once more, and again each time a build marks it so, which
  /// a build that always does keeps doing (as in Flutter: a programming
  /// error the assert is there to catch).
  void scheduleBuildFor(Element element) {
    if (element._inDirtyList) {
      // its turn comes again, also when the assert is caught as an error of
      // the build that marked it
      _needsSorting = true;
      assert(
        false,
        '${_pathOf(element)} was marked dirty again after it was rebuilt in '
        'the same build scope',
      );
      return;
    }
    if (!_scheduled) {
      _scheduled = true;
      onBuildScheduled?.call();
    }
    _dirty.add(element);
    element._inDirtyList = true;
  }

  /// Runs [callback], then rebuilds the dirty elements, parents before
  /// their children, including those marked dirty for the first time
  /// meanwhile; see [scheduleBuildFor] for those marked again. A child its
  /// parent's rebuild updated is clean by its turn and is not rebuilt
  /// again. A rebuild that throws is reported ([onBuildError]); an
  /// exception that goes out of the scope leaves the elements it did not
  /// rebuild to the next one, which it asks for ([onBuildScheduled]).
  void buildScope([void Function()? callback]) {
    if (callback == null && _dirty.isEmpty) {
      // nothing to rebuild, as when what was marked dirty was removed since
      _scheduled = false;
      return;
    }
    _scheduled = true;
    try {
      callback?.call();
      _rebuildDirty(null);
    } finally {
      _endScope();
    }
  }

  /// Runs [callback], in which [context] builds its child as its render
  /// object is laid out ([LayoutBuilder]), then rebuilds the dirty elements
  /// below [context] as [buildScope] does, a scope of its own; those
  /// elsewhere wait for the next build scope, which it asks for
  /// ([onBuildScheduled]). The elements it removes wait for the
  /// [finalizeTree] after the layout.
  void _buildInLayout(Element context, void Function() callback) {
    _scheduled = true;
    try {
      callback();
      _rebuildDirty(context);
    } finally {
      _endScope();
    }
  }

  /// Rebuilds the dirty elements, parents before their children, those
  /// below [within] only when it is given; see [buildScope].
  void _rebuildDirty(Element? within) {
    _dirty.sort(_byDepth);
    _needsSorting = false;
    var count = _dirty.length;
    var i = 0;
    while (i < count) {
      final element = _dirty[i++];
      if (within == null || element._isBelow(within)) {
        try {
          element.rebuild();
        } on Object catch (error, stack) {
          _rebuildFailed(element, error, stack);
        }
      }
      if (count < _dirty.length || _needsSorting) {
        _dirty.sort(_byDepth);
        _needsSorting = false;
        count = _dirty.length;
        // an element marked meanwhile may sort before those rebuilt: go on
        // from the first dirty one
        i = 0;
        while (i < count && !_dirty[i]._dirty) {
          i++;
        }
      }
    }
  }

  /// Ends a build scope: the elements left dirty (by an exception out of
  /// it, or outside a build during layout) stay for the next one, which is
  /// asked for when there are any.
  void _endScope() {
    var kept = 0;
    for (final e in _dirty) {
      if (e._dirty && e._lifecycle == _Lifecycle.active) {
        _dirty[kept++] = e;
      } else {
        e._inDirtyList = false;
      }
    }
    _dirty.length = kept;
    _scheduled = false;
    _needsSorting = false;
    if (kept > 0) {
      _scheduled = true;
      onBuildScheduled?.call();
    }
  }

  /// [element]'s rebuild threw [error] past its own catches: the nearest
  /// component element or layout builder at or above it shows what
  /// [onBuildError] returns in place of its child. Unset, [error] goes on.
  void _rebuildFailed(Element element, Object error, StackTrace stack) {
    element._dirty = false;
    if (onBuildError != null) {
      for (Element? e = element; e != null; e = e._parent) {
        if (e is _BuildsChild) {
          e._showError(element, error, stack);
          return;
        }
      }
    }
    Error.throwWithStackTrace(error, stack);
  }

  /// Unmounts the elements removed from the tree since the last call that
  /// a [GlobalKey] did not put back, each subtree's children before their
  /// parent. A GlobalKey left on two widgets of the tree at once fails an
  /// assert naming both places.
  ///
  /// Every one of them is unmounted, also when an element's unmount (a
  /// [State.dispose]) throws: the first error is thrown once all are, with
  /// its stack, and each later one goes to the current [Zone]'s error
  /// handler after it, in a microtask, as a build's does when there is no
  /// [onBuildError].
  void finalizeTree() {
    // a dispose may finalize another tree: its errors are its own
    final outerError = _unmountError;
    final outerStack = _unmountStack;
    _unmountError = null;
    _unmountStack = null;
    Object? error;
    StackTrace? stack;
    try {
      while (_inactive.isNotEmpty) {
        final subtree = _inactive.first;
        _inactive.remove(subtree);
        _unmount(subtree);
      }
    } finally {
      error = _unmountError;
      stack = _unmountStack;
      _unmountError = outerError;
      _unmountStack = outerStack;
    }
    final clashes = _globalKeyClashes();
    if (error != null) {
      Error.throwWithStackTrace(error, stack!);
    }
    assert(clashes.isEmpty, clashes.join('\n'));
  }

  static int _byDepth(Element a, Element b) => a._depth - b._depth;

  void _registerGlobalKey(GlobalKey key, Element element) {
    final owner = GlobalKey._owners[key];
    assert(owner == null || identical(owner, this), '$key is in another tree');
    final holder = _globalKeys[key];
    if (holder != null) {
      _keysTakenOver[holder] = key;
    }
    GlobalKey._owners[key] = this;
    _globalKeys[key] = element;
  }

  /// The GlobalKeys on two widgets at once, each said in a line: a key
  /// taken from an element that has not updated its children since, or one
  /// whose element a newer one took over, while that element is still
  /// mounted.
  List<String> _globalKeyClashes() {
    // most frames take no key: nothing allocated for them
    if (_keysTakenFrom.isEmpty && _keysTakenOver.isEmpty) {
      return const [];
    }
    final clashes = [
      for (final MapEntry(key: parent, value: keys) in _keysTakenFrom.entries)
        if (parent._lifecycle != _Lifecycle.defunct)
          for (final key in keys) _onTwo(key, 'under ${_pathOf(parent)}'),
      for (final MapEntry(key: holder, value: key) in _keysTakenOver.entries)
        if (holder._lifecycle != _Lifecycle.defunct)
          _onTwo(key, 'at ${_pathOf(holder)}'),
    ];
    _keysTakenFrom.clear();
    _keysTakenOver.clear();
    return clashes;
  }

  /// Says that [key] is on a widget [place] and on the widget of its
  /// element.
  String _onTwo(GlobalKey key, String place) {
    final element = _globalKeys[key];
    final other = element == null
        ? 'on one removed since'
        : 'at ${_pathOf(element)}';
    return '$key is on two widgets at once, $place and $other: a GlobalKey '
        'is on one widget of a tree at a time';
  }

  // an element mounted later with the same key keeps it
  void _unregisterGlobalKey(GlobalKey key, Element element) {
    if (identical(_globalKeys[key], element)) {
      _globalKeys.remove(key);
      GlobalKey._owners[key] = null;
    }
  }

  void _deactivate(Element subtree) {
    // one a GlobalKey takes out of a subtree removed before is inactive
    if (subtree._lifecycle == _Lifecycle.active) {
      _deactivateAll(subtree);
    }
    _inactive.add(subtree);
  }

  // a child is visited while it is still the element's own: an update that
  // threw may have left the element holding one it removed

  // the element whose children are visited is in a static, not in a
  // closure, which makes a closure and a context at each element

  /// The element whose children [_deactivateAll] or [_unmount] visits.
  static Element? _visiting;

  static void _deactivateAll(Element e) {
    e.deactivate();
    final outer = _visiting;
    _visiting = e;
    try {
      e.visitChildren(_deactivateChild);
    } finally {
      _visiting = outer;
    }
  }

  static void _deactivateChild(Element child) {
    if (identical(child._parent, _visiting)) {
      _deactivateAll(child);
    }
  }

  static void _activateAll(Element e) {
    e
      ..activate()
      ..visitChildren(_activateAll);
  }

  static void _unmount(Element e) {
    final outer = _visiting;
    _visiting = e;
    try {
      e.visitChildren(_unmountChild);
    } finally {
      _visiting = outer;
    }
    try {
      e.unmount();
    } on Object catch (error, stack) {
      _unmountFailed(error, stack);
    }
  }

  /// The first error an element's unmount threw in the running
  /// [finalizeTree], and its stack: thrown once every element is unmounted.
  static Object? _unmountError;
  static StackTrace? _unmountStack;

  /// An element's unmount threw [error]: the first is kept for
  /// [finalizeTree] to throw, a later one goes to the zone once it is.
  static void _unmountFailed(Object error, StackTrace stack) {
    if (_unmountError == null) {
      _unmountError = error;
      _unmountStack = stack;
      return;
    }
    final zone = Zone.current;
    zone.scheduleMicrotask(() => zone.handleUncaughtError(error, stack));
  }

  static void _unmountChild(Element child) {
    if (identical(child._parent, _visiting)) {
      _unmount(child);
    }
  }

  Widget _buildFailed(Element element, Object error, StackTrace stack) {
    final report = onBuildError;
    if (report != null) {
      return report(element, error, stack);
    }
    Zone.current.handleUncaughtError(error, stack);
    return const _Nothing();
  }
}

/// What an element whose build threw shows when nothing else is given: a
/// render object, so that every component element has one below it and
/// its siblings' render objects keep their order.
final class _Nothing extends LeafRenderObjectWidget {
  const _Nothing();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderNothing();
}

/// As small as the constraints allow, paints nothing, and is never hit.
final class _RenderNothing extends RenderObject {
  @override
  bool hitTestSelf(int x, int y) => false;

  @override
  void performLayout(BoxConstraints c) {
    width = c.minW;
    height = c.minH;
  }

  @override
  void paint(PaintContext ctx) {}
}
