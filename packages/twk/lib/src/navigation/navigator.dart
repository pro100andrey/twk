/// The stack of screens: a [Navigator] shows the [Route]s pushed on it,
/// the last in front, and pops them off again; its [NavigatorObserver]s
/// are told of each change, and a [PopScope] refuses or intercepts a pop
/// of its route.
///
/// @docImport '../controls/button.dart';
/// @docImport '../layout/basic.dart';
/// @docImport '../layout/box.dart';
/// @docImport '../overlay/dialog.dart';
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        DiagnosticPropertiesBuilder,
        HitTestResult,
        PaintContext,
        ParentData,
        RenderObject;

import '../animation/animation_controller.dart';
import '../animation/curves.dart';
import '../animation/switcher.dart' show FractionalTranslation;
import '../animation/ticker.dart';
import '../focus/focus_tree.dart';
import '../focus/shortcuts.dart';
import '../foundation/controller_host.dart';
import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import '../gestures/ignore_pointer.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/child_list.dart';
import '../layout/stack.dart';
import '../overlay/barrier.dart';
import '../overlay/layer.dart';
import '../style/style.dart';

// Examples can assume:
// late BuildContext context;
// late bool edited;
// late Widget form;
// void askToDiscard(BuildContext context) {}
// late int id;

/// Makes the route [settings] name, or null when it names none.
typedef RouteFactory = Route<Object?>? Function(RouteSettings settings);

/// Tells whether [route] is the one looked for.
typedef RoutePredicate = bool Function(Route<Object?> route);

/// What a [PopScope] is told of a pop of its route: whether it was popped
/// ([didPop]), and the [result] it was popped with or asked to be.
typedef PopInvokedWithResultCallback<T> = void Function(bool didPop, T? result);

/// What the back key does with the route in front of a [Navigator]
/// ([Route.popDisposition], [NavigatorState.maybePop]).
enum RoutePopDisposition {
  /// Pops it.
  pop,

  /// Leaves it, which is told it was not popped
  /// ([Route.onPopInvokedWithResult]): the key goes no further.
  doNotPop,

  /// Leaves it to what is past the navigator: the key goes on, as to a
  /// binding that quits.
  bubble,
}

/// What a [Route] is known by: the [name] it was pushed by
/// ([NavigatorState.pushNamed]) and the [arguments] it was pushed with.
@immutable
final class RouteSettings {
  /// Settings of a route named [name] with [arguments]; with neither, those
  /// of a route pushed by itself.
  const RouteSettings({this.name, this.arguments});

  /// The route's name, such as `/settings`; null for one pushed by itself.
  final String? name;

  /// What the route was pushed with, for its widgets to read
  /// (`Route.of(context).settings.arguments`).
  final Object? arguments;

  @override
  String toString() => 'RouteSettings($name, $arguments)';
}

/// A screen of a [Navigator], or a layer over one: what [build] builds, as
/// big as the navigator, over the routes pushed before it. A route is
/// pushed once; the future [popped] completes with the result it is
/// popped with, a [T] or null.
///
/// An [opaque] route hides the routes under it: they keep their state but
/// are not laid out, painted or hit by the mouse until it is popped. A
/// route takes the focus as it is pushed; those under the one in front
/// ([isCurrent]) cannot take it. Popped, a route gives the focus back to
/// what had it when it was pushed.
///
/// [PageRoute] is the route of a screen, and `showDialog` pushes one of a
/// dialog; a route of one's own extends this with a [build], and with
/// [opaque] false to show the routes under it. A route that shows a
/// message over the screen it is pushed on, and returns nothing:
///
/// ```dart
/// final class NoticeRoute extends Route<void> {
///   NoticeRoute(this.message);
///
///   final String message;
///
///   @override
///   bool get opaque => false;
///
///   @override
///   Widget build(BuildContext context) => Center(
///     child: Box(border: const Border.all(), child: Text(message)),
///   );
/// }
/// ```
abstract class Route<T> {
  /// A route known by [settings], none by default.
  Route({this.settings = const RouteSettings()});

  /// What the route is known by: its name and the arguments it was pushed
  /// with.
  final RouteSettings settings;

  /// Whether the route covers all of the routes under it: true for a
  /// screen, false for a dialog, which shows them around it.
  bool get opaque => true;

  /// Whether the navigator's back key pops it while it is in front; when
  /// not, the key goes on past the navigator.
  bool get popsOnBack => true;

  /// How long the route takes to come in as it is pushed: it slides in
  /// from the right over the routes under it, which stay painted and dim
  /// in the theme's shade (`ThemeData.shade`) as it covers them. Zero, the
  /// default, shows it at once.
  Duration get transitionDuration => Duration.zero;

  /// How long the route takes to go out as it is popped: it slides out to
  /// the right, the shade going from what it uncovers. Zero takes it off
  /// at once; [transitionDuration] by default.
  Duration get reverseTransitionDuration => transitionDuration;

  /// What the back key does with the route while it is in front:
  /// [RoutePopDisposition.doNotPop] while a [PopScope] in it cannot pop;
  /// else [RoutePopDisposition.bubble] for the first route, or one that
  /// does not pop on back ([popsOnBack]), and [RoutePopDisposition.pop]
  /// for the others.
  RoutePopDisposition get popDisposition {
    for (final scope in _popScopes) {
      if (!scope.widget.canPop) {
        return RoutePopDisposition.doNotPop;
      }
    }
    return isFirst || !popsOnBack
        ? RoutePopDisposition.bubble
        : RoutePopDisposition.pop;
  }

  /// Tells the [PopScope]s in the route of a pop: popped ([didPop]) with
  /// [result], as [NavigatorState.pop] and [NavigatorState.popUntil] pop
  /// it, or not, asked to be by [NavigatorState.maybePop] while it was
  /// [RoutePopDisposition.doNotPop]. A route removed or replaced is not
  /// told.
  @mustCallSuper
  void onPopInvokedWithResult(bool didPop, T? result) {
    for (final scope in [..._popScopes]) {
      scope._invoked(didPop, result);
    }
  }

  // the PopScopes in the route, those mounted first first
  final _popScopes = <_PopScopeState<Object?>>[];

  /// A [PopScope] in the route came, went or changed: the back key may do
  /// otherwise now, which what lists the keys is told.
  void _popScopesChanged() {
    if (isActive) {
      _guard.markKeysChanged();
    }
  }

  /// What the route shows, over all of its navigator.
  @protected
  Widget build(BuildContext context);

  NavigatorState? _navigator;
  final _popped = Completer<T?>();
  var _pushed = false;

  // takes the focus once its widgets are mounted: pushed, not the first
  var _takesFocus = false;

  // what had the focus when the route was pushed, which gets it back when
  // it is popped
  FocusNode? _returnFocus;

  // what builds it while it is in the tree
  _RoutePageState? _page;

  // what shows it, and runs its transition, while it is in the tree
  _RouteHostState? _host;

  // sliding in as it was pushed; sliding out as it was popped, off the
  // navigator already; replaced by the route above it, which is sliding
  // in over it
  var _entering = false;
  var _leaving = false;
  var _replaced = false;

  /// Whether it covers what is under it now: opaque, and not sliding.
  bool get _covers => opaque && !_entering && !_leaving;

  // above the route's scope: keeps the focus from it while it is covered
  late final _guard = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
    debugLabel: 'route guard',
  );

  late final _scope = FocusScopeNode(debugLabel: settings.name ?? 'route');

  /// The navigator the route is on, from its push until it is popped.
  NavigatorState? get navigator => _navigator;

  /// Whether the route is on a navigator.
  bool get isActive => _navigator != null;

  /// Whether the route is the one in front of its navigator.
  bool get isCurrent {
    final navigator = _navigator;
    return navigator != null && identical(navigator._history.last, this);
  }

  /// Whether the route is the first of its navigator, the one it keeps.
  bool get isFirst {
    final navigator = _navigator;
    return navigator != null && identical(navigator._history.first, this);
  }

  /// Completes with the result the route is popped with; with null when
  /// it is popped without one or its navigator leaves the tree.
  Future<T?> get popped => _popped.future;

  /// Completes [popped] with [result], which has to be a [T] (a
  /// [TypeError] if not).
  void _complete(Object? result) => _popped.complete(result as T?);

  /// The route [context] is in, on a [Navigator]; the context depends on
  /// it, rebuilt when the route comes in front or is covered. A
  /// [StateError] if there is none.
  static Route<Object?> of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError(
        'no Route above ${context.widget.runtimeType}: a Navigator shows '
        'its routes',
      ));

  /// The route [of] finds, if there is one.
  static Route<Object?>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RouteScope>()?.route;

  /// Tells the route named [name] ([RouteSettings.name]), as for
  /// [NavigatorState.popUntil].
  static RoutePredicate withName(String name) =>
      (route) => route.settings.name == name;

  @override
  String toString() {
    final hash = identityHashCode(this).toUnsigned(20).toRadixString(16);
    final name = settings.name;
    return '$runtimeType#${hash.padLeft(5, '0')}'
        '${name == null ? '' : '($name)'}';
  }
}

/// A screen: what [builder] builds, covering the routes under it. It is
/// there at once by default; given a [transitionDuration], it slides in
/// from the right as it is pushed, over the route under it, which dims,
/// and out again as it is popped, over [reverseTransitionDuration].
///
/// A screen pushed for an item, whose result is what it is popped with:
///
/// ```dart
/// final saved = await Navigator.push<bool>(
///   context,
///   PageRoute(builder: (context) => Text('item $id')),
/// );
/// ```
///
/// One that slides in over 220 ms and out over 180:
///
/// ```dart
/// await Navigator.push<void>(
///   context,
///   PageRoute(
///     transitionDuration: const Duration(milliseconds: 220),
///     reverseTransitionDuration: const Duration(milliseconds: 180),
///     builder: (context) => Text('item $id'),
///   ),
/// );
/// ```
final class PageRoute<T> extends Route<T> {
  /// A screen of what [builder] builds, known by [settings], coming in
  /// over [transitionDuration] and going out over
  /// [reverseTransitionDuration] (the same where null).
  PageRoute({
    required this.builder,
    super.settings,
    this.transitionDuration = Duration.zero,
    Duration? reverseTransitionDuration,
  }) : reverseTransitionDuration =
           reverseTransitionDuration ?? transitionDuration;

  /// Builds what the screen shows, again when the route's widgets ask for
  /// it.
  final Widget Function(BuildContext context) builder;

  @override
  final Duration transitionDuration;

  @override
  final Duration reverseTransitionDuration;

  @override
  Widget build(BuildContext context) => builder(context);
}

/// Shows a stack of [Route]s, the last pushed in front: its first, which
/// [initialRoute] names ([defaultRouteName] by default), and those pushed
/// on it ([NavigatorState.push], [NavigatorState.pushNamed]) until they
/// are popped ([NavigatorState.pop]). The widgets below find it with
/// [Navigator.of], or call its methods through the static ones here:
/// `Navigator.pushNamed(context, '/item', arguments: id)`.
///
/// A name is made a route by [home] for [defaultRouteName], by [routes],
/// a [PageRoute] of the builder there, by [onGenerateRoute], then by
/// [onUnknownRoute]; a [StateError] when none makes it. The navigator
/// built again builds each of its routes again, that of [home] with the
/// new one.
///
/// The routes are as big as the navigator, which fills the room it gets
/// (along an axis with no bound, as long as the first route it shows).
/// Those under an [Route.opaque] one keep their state, but are not laid
/// out, painted or hit by the mouse. A route pushed takes the focus; popped,
/// it gives it back to what had it when it was pushed, as a dialog does.
/// None under the one in front can take it.
///
/// A route with a transition ([Route.transitionDuration]) slides in from
/// the right over those under it, which are painted, dimmed in the
/// theme's shade, until it is in; popped, it slides out to the right
/// ([Route.reverseTransitionDuration]), the one under it in front and
/// with the focus at once, the mouse going past the route as it goes. A
/// route that replaces another ([NavigatorState.pushReplacement]) slides
/// in over it. Its own background is the theme's while it moves.
///
/// [backKey], Escape by default and none when null, pops the route in
/// front ([NavigatorState.maybePop]) when it is not the first and pops on
/// back ([Route.popsOnBack]). It is bound in a layer above the routes
/// (see `Shortcuts`): a route's own bindings take the key first; and
/// with no route to pop, it goes on past the navigator, as to a binding
/// that quits. A [PopScope] in the route in front that cannot pop keeps
/// the key, on the first route too, and is told it did not pop.
///
/// The [observers] are told of each route pushed, popped, replaced and
/// removed.
///
/// The navigator holds an [Overlay] over its routes, which the widgets in
/// them find with [Overlay.of]: their toasts and tooltips show over the
/// routes. A dialog (`showDialog`) is a route of the navigator above.
///
/// An app of a list and a screen for each of its items, the item's id in
/// the route's arguments:
///
/// ```dart
/// Navigator(
///   home: Builder(
///     builder: (context) => Button(
///       'Open item 7',
///       onPressed: () =>
///           Navigator.pushNamed<void>(context, '/item', arguments: 7),
///     ),
///   ),
///   routes: {
///     '/item': (context) =>
///         Text('item ${Route.of(context).settings.arguments}'),
///   },
/// )
/// ```
///
/// See also:
///
///  * [PopScope], which keeps a route from being popped.
///  * [NavigatorObserver], which is told of each change.
final class Navigator extends StatefulWidget {
  /// A navigator whose first route is [initialRoute], [home] by default.
  const Navigator({
    super.key,
    this.home,
    this.routes = const {},
    this.initialRoute,
    this.onGenerateRoute,
    this.onUnknownRoute,
    this.backKey = 'escape',
    this.observers = const [],
  });

  /// The name of the first route when [initialRoute] gives none: `/`.
  static const defaultRouteName = '/';

  /// What the route named [defaultRouteName] shows.
  final Widget? home;

  /// What the route of each name shows.
  final Map<String, Widget Function(BuildContext context)> routes;

  /// The name of the first route.
  final String? initialRoute;

  /// Makes the routes of the names that [home] and [routes] do not show.
  final RouteFactory? onGenerateRoute;

  /// Makes the routes of the names that nothing else makes.
  final RouteFactory? onUnknownRoute;

  /// The key that pops the route in front, as `KeyBindings` names one:
  /// `escape` by default; null for none.
  final String? backKey;

  /// What is told of each route pushed, popped, replaced or removed, the
  /// first route too, as each change is made. An observer is on one
  /// navigator at a time ([NavigatorObserver.navigator]).
  final List<NavigatorObserver> observers;

  /// The nearest navigator above [context], or with [rootNavigator] the
  /// furthest; a [StateError] if there is none.
  static NavigatorState of(
    BuildContext context, {
    bool rootNavigator = false,
  }) =>
      maybeOf(context, rootNavigator: rootNavigator) ??
      (throw StateError(
        'no Navigator above ${context.widget.runtimeType}: place a '
        'Navigator above it',
      ));

  /// The navigator [of] finds, if there is one.
  static NavigatorState? maybeOf(
    BuildContext context, {
    bool rootNavigator = false,
  }) {
    var element = context
        .getElementForInheritedWidgetOfExactType<_NavigatorScope>();
    while (rootNavigator && element != null) {
      final above = _above(element);
      if (above == null) {
        break;
      }
      element = above;
    }
    return (element?.widget as _NavigatorScope?)?.navigator;
  }

  static InheritedElement? _above(Element element) {
    InheritedElement? found;
    element.visitAncestorElements((parent) {
      found = parent.getElementForInheritedWidgetOfExactType<_NavigatorScope>();
      return false;
    });
    return found;
  }

  /// [NavigatorState.push] on the navigator above [context].
  static Future<T?> push<T>(BuildContext context, Route<T> route) =>
      of(context).push(route);

  /// [NavigatorState.pushNamed] on the navigator above [context].
  static Future<T?> pushNamed<T>(
    BuildContext context,
    String name, {
    Object? arguments,
  }) => of(context).pushNamed<T>(name, arguments: arguments);

  /// [NavigatorState.pushReplacement] on the navigator above [context].
  static Future<T?> pushReplacement<T>(
    BuildContext context,
    Route<T> route, {
    Object? result,
  }) => of(context).pushReplacement(route, result: result);

  /// [NavigatorState.pushReplacementNamed] on the navigator above
  /// [context].
  static Future<T?> pushReplacementNamed<T>(
    BuildContext context,
    String name, {
    Object? arguments,
    Object? result,
  }) => of(
    context,
  ).pushReplacementNamed<T>(name, arguments: arguments, result: result);

  /// [NavigatorState.pop] on the navigator above [context].
  static void pop(BuildContext context, [Object? result]) =>
      of(context).pop(result);

  /// [NavigatorState.popUntil] on the navigator above [context].
  static void popUntil(BuildContext context, RoutePredicate predicate) =>
      of(context).popUntil(predicate);

  /// [NavigatorState.maybePop] on the navigator above [context].
  static bool maybePop(BuildContext context, [Object? result]) =>
      of(context).maybePop(result);

  /// [NavigatorState.canPop] on the navigator above [context]; false when
  /// there is none.
  static bool canPop(BuildContext context) =>
      maybeOf(context)?.canPop() ?? false;

  @override
  State<Navigator> createState() => NavigatorState();
}

/// The routes of a [Navigator], the first at the bottom, and what pushes
/// and pops them. Each change shows from the next build of the app on;
/// the focus moves at once.
///
/// The widgets below the navigator reach it with [Navigator.of], or call
/// the statics of [Navigator] that do the same:
///
/// ```dart
/// final navigator = Navigator.of(context);
/// if (navigator.canPop()) {
///   navigator.pop();
/// } else {
///   navigator.pushReplacementNamed<void>('/');
/// }
/// ```
final class NavigatorState extends State<Navigator> {
  final _history = <Route<Object?>>[];

  // what the theater shows, in order: the routes of the history, and
  // those still sliding out of it or under one that slides in over them
  final _stage = <Route<Object?>>[];

  // what the back key asks for, the same map at each build
  late final _actions = <Type, Action<Intent>>{
    _BackIntent: _BackAction(this),
  };

  @override
  void initState() {
    super.initState();
    _observe(widget.observers);
    final route = _named<Object?>(
      widget.initialRoute ?? Navigator.defaultRouteName,
      null,
    );
    _adopt(route);
    _history.add(route);
    _stage.add(route);
    for (final observer in widget.observers) {
      observer.didPush(route, null);
    }
  }

  @override
  void didUpdateWidget(Navigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.observers, widget.observers)) {
      _unobserve(oldWidget.observers);
      _observe(widget.observers);
    }
    for (final route in _stage) {
      route._page?._changed();
    }
  }

  @override
  void dispose() {
    _unobserve(widget.observers);
    for (final route in _history.reversed) {
      route._navigator = null;
      route._popped.complete();
    }
    _history.clear();
    _stage.clear();
    super.dispose();
  }

  /// Puts [observers] on this navigator, those on one it was built in
  /// place of too.
  void _observe(List<NavigatorObserver> observers) {
    for (final observer in observers) {
      observer._hosts.attach(this);
    }
  }

  /// Takes [observers] off this navigator, those it is still on.
  void _unobserve(List<NavigatorObserver> observers) {
    for (final observer in observers) {
      observer._hosts.detach(this);
    }
  }

  /// The route of [name], with [arguments] in its settings, a
  /// [PageRoute<T>] when [Navigator.home] or [Navigator.routes] shows it.
  Route<Object?> _named<T>(String name, Object? arguments) {
    final settings = RouteSettings(name: name, arguments: arguments);
    final home = widget.home;
    if (home != null && name == Navigator.defaultRouteName) {
      return PageRoute<T>(
        builder: (_) => widget.home ?? home,
        settings: settings,
      );
    }
    final builder = widget.routes[name];
    if (builder != null) {
      return PageRoute<T>(builder: builder, settings: settings);
    }
    return widget.onGenerateRoute?.call(settings) ??
        widget.onUnknownRoute?.call(settings) ??
        (throw StateError(
          'Navigator: no route named "$name": '
          '${name == Navigator.defaultRouteName ? 'give a home, or ' : ''}'
          'give it in routes, or make it in onGenerateRoute or '
          'onUnknownRoute',
        ));
  }

  void _adopt(Route<Object?> route) {
    assert(!route._pushed, '$route was pushed before: a route is pushed once');
    route
      .._pushed = true
      .._navigator = this;
  }

  /// The node with the primary focus.
  FocusNode? get _primaryFocus => Focus.maybeOf(
    context,
    createDependency: false,
  )?.manager?.primaryFocus;

  /// Whether there is a route under the one in front to pop to.
  bool canPop() => _history.length > 1;

  /// Shows [route] in front of the others, which keep their state, and
  /// gives it the focus; returns its [Route.popped].
  Future<T?> push<T>(Route<T> route) {
    _adopt(route);
    final covered = _history.last;
    setState(() {
      route
        .._takesFocus = true
        .._returnFocus = _primaryFocus;
      covered._guard.descendantsAreFocusable = false;
      _history.add(route);
      _enter(route);
    });
    for (final observer in widget.observers) {
      observer.didPush(route, covered);
    }
    return route.popped;
  }

  /// [push]es the route of [name] ([Navigator]), [arguments] in its
  /// settings.
  Future<T?> pushNamed<T>(String name, {Object? arguments}) =>
      _typed<T>(push<Object?>(_named<T>(name, arguments)));

  /// Pops the route in front with [result] and pushes [route] in its place,
  /// which gives the focus back, once popped, to what the route it
  /// replaced would have.
  Future<T?> pushReplacement<T>(Route<T> route, {Object? result}) {
    final old = _history.last.._complete(result);
    _adopt(route);
    setState(() {
      _history.removeLast();
      old
        .._navigator = null
        .._guard.descendantsAreFocusable = false;
      route
        .._takesFocus = true
        .._returnFocus = old._returnFocus;
      _history.add(route);
      // it shows over the route it replaced until it is in
      old._replaced = _enter(route);
      _tidy();
    });
    for (final observer in widget.observers) {
      observer.didReplace(newRoute: route, oldRoute: old);
    }
    return route.popped;
  }

  /// [pushReplacement] with the route of [name], [arguments] in its
  /// settings.
  Future<T?> pushReplacementNamed<T>(
    String name, {
    Object? arguments,
    Object? result,
  }) => _typed<T>(
    pushReplacement<Object?>(_named<T>(name, arguments), result: result),
  );

  static Future<T?> _typed<T>(Future<Object?> result) =>
      result.then((value) => value as T?);

  /// Takes the route in front off, its [Route.popped] completing with
  /// [result], which has to be of its type (a [TypeError] if not). The
  /// route under it comes in front, and when the focus was in the route
  /// popped, it goes back to what had it when that was pushed, or else to
  /// the route in front. The first route stays: a [StateError] when it is
  /// the only one ([canPop]). A [PopScope] in it is told it was popped,
  /// whether it can pop or not, and so are the [Navigator.observers].
  void pop([Object? result]) {
    if (!canPop()) {
      throw StateError(
        'pop: the navigator keeps its first route; canPop tells whether '
        'there is one to pop',
      );
    }
    final route = _history.last;
    setState(() => _remove(route, result, slide: true));
    _popped(route, result);
  }

  /// Tells [route]'s [PopScope]s and the observers that it was popped with
  /// [result].
  void _popped(Route<Object?> route, Object? result) {
    route.onPopInvokedWithResult(true, result);
    final under = _history.last;
    for (final observer in widget.observers) {
      observer.didPop(route, under);
    }
  }

  /// Does what the back key does, by the route in front's
  /// [Route.popDisposition]: [pop]s it with [result]; or leaves it while a
  /// [PopScope] in it cannot pop, which is told so with [result]; or, for
  /// the first route or one that does not pop on back
  /// ([Route.popsOnBack]), leaves it to what is past the navigator.
  /// Returns false then, and true when it popped or a [PopScope] kept the
  /// route.
  bool maybePop([Object? result]) {
    final route = _history.last;
    switch (route.popDisposition) {
      case RoutePopDisposition.bubble:
        return false;
      case RoutePopDisposition.doNotPop:
        route.onPopInvokedWithResult(false, result);
        return true;
      case RoutePopDisposition.pop:
        pop(result);
        return true;
    }
  }

  /// Pops the routes in front, each with null, until [predicate] holds for
  /// the one in front ([Route.withName] tells one by its name); the first
  /// route stays. Each is told it was popped, as by [pop].
  void popUntil(RoutePredicate predicate) {
    if (!canPop() || predicate(_history.last)) {
      return;
    }
    final popped = <Route<Object?>>[];
    setState(() {
      while (_history.length > 1 && !predicate(_history.last)) {
        final route = _history.last;
        _remove(route, null, slide: popped.isEmpty);
        popped.add(route);
      }
    });
    for (var i = 0; i < popped.length; i++) {
      final route = popped[i]..onPopInvokedWithResult(true, null);
      final under = i + 1 < popped.length ? popped[i + 1] : _history.last;
      for (final observer in widget.observers) {
        observer.didPop(route, under);
      }
    }
  }

  /// Takes [route], one of this navigator's but not its only one, off
  /// wherever it is, its [Route.popped] completing with [result]: as [pop]
  /// does for the route in front; a route above it goes back, once popped,
  /// to what [route] would have. Its [PopScope]s are not told; the
  /// observers are ([NavigatorObserver.didRemove]).
  ///
  /// An [ArgumentError] when [route] is not on this navigator, a
  /// [StateError] when it is the only route.
  void removeRoute(Route<Object?> route, [Object? result]) {
    if (!identical(route._navigator, this)) {
      throw ArgumentError.value(route, 'route', 'is not on this navigator');
    }
    if (!canPop()) {
      throw StateError('removeRoute: the navigator keeps its only route');
    }
    final i = _history.indexOf(route);
    final under = i > 0 ? _history[i - 1] : null;
    setState(
      () => _remove(route, result, slide: identical(route, _history.last)),
    );
    for (final observer in widget.observers) {
      observer.didRemove(route, under);
    }
  }

  /// Takes [route] off the stack; with [slide], it slides out where it
  /// has a time for that ([Route.reverseTransitionDuration]).
  void _remove(Route<Object?> route, Object? result, {bool slide = false}) {
    route._complete(result);
    final hadFocus = route._guard.hasFocus;
    final i = _history.indexOf(route);
    _history.removeAt(i);
    route
      .._navigator = null
      .._guard.descendantsAreFocusable = false
      .._entering = false;
    if (slide) {
      route._leaving = route._host?._leave() ?? false;
    }
    _tidy();
    if (i < _history.length) {
      // the route above now covers the one under it: the focus it took
      // from the route removed goes back where that one's would have
      final above = _history[i];
      if (_isBelow(above._returnFocus, route._guard)) {
        above._returnFocus = route._returnFocus;
      }
      // the back key may do otherwise for the route in front, the first
      // one now
      _history.last._guard.markKeysChanged();
      return;
    }
    final top = _history.last
      .._guard.descendantsAreFocusable = true
      // the back key may do otherwise for it, as the first route now
      .._guard.markKeysChanged();
    if (hadFocus) {
      final back = route._returnFocus;
      back?.requestFocus();
      if (back == null || !back.hasFocus) {
        top._scope.requestFocus();
      }
    }
  }

  /// Has [route], just pushed, slide in where it has a time for that
  /// ([Route.transitionDuration]); returns whether it does.
  bool _enter(Route<Object?> route) {
    _stage.add(route);
    return route._entering = route.transitionDuration > Duration.zero;
  }

  /// [route] is in, or out: what it slid in over or out of is shown as
  /// ever.
  void _settled(Route<Object?> route) {
    if (!mounted || !(route._entering || route._leaving)) {
      return;
    }
    setState(() {
      route
        .._entering = false
        .._leaving = false;
      _tidy();
    });
  }

  /// Takes off the stage the routes off the navigator that are not
  /// sliding out, nor under a route that slides in over them.
  void _tidy() {
    for (var i = _stage.length - 1; i >= 0; i--) {
      final route = _stage[i];
      if (route.isActive || route._leaving) {
        continue;
      }
      if (route._replaced && i + 1 < _stage.length && _stage[i + 1]._entering) {
        continue;
      }
      _stage.removeAt(i);
    }
  }

  static bool _isBelow(FocusNode? node, FocusNode above) {
    for (var n = node?.parent; n != null; n = n.parent) {
      if (identical(n, above)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = _history.last;
    var onstage = _stage.length - 1;
    while (onstage > 0 && !_stage[onstage]._covers) {
      onstage--;
    }
    final back = widget.backKey;
    // the action, enabled as the route in front pops on back when the key
    // comes, tells whether the key goes on past the navigator: a PopScope
    // that changes it needs no build of the navigator
    return _NavigatorScope(
      this,
      child: Actions(
        _actions,
        child: Shortcuts(
          {?back: _back},
          hints: {?back: 'back'},
          debugLabel: 'navigator',
          child: Overlay(
            child: _Theater(
              onstage: onstage,
              children: [
                for (final route in _stage)
                  _RouteHost(
                    this,
                    route,
                    current: identical(route, top),
                    key: ObjectKey(route),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a [Navigator]'s back key asks for.
final class _BackIntent extends Intent {
  const _BackIntent();
}

const _back = _BackIntent();

/// [NavigatorState.maybePop], enabled while the route in front does not
/// leave the key to what is past the navigator.
final class _BackAction extends Action<_BackIntent> {
  _BackAction(this.navigator);

  final NavigatorState navigator;

  @override
  bool isEnabled(_BackIntent intent) {
    final history = navigator._history;
    return history.isNotEmpty &&
        history.last.popDisposition != RoutePopDisposition.bubble;
  }

  @override
  void invoke(_BackIntent intent) => navigator.maybePop();
}

/// Told by the [Navigator]s it is given to ([Navigator.observers]) of
/// each route pushed, popped, replaced and removed, after the change and
/// before the next build shows it. Each method does nothing here: a
/// subclass overrides those it needs.
///
/// It is on one navigator at a time: given to one built in place of
/// another, it goes over to the new one.
///
/// An observer that keeps the names of the routes shown, the one in front
/// last:
///
/// ```dart
/// final class RouteNames extends NavigatorObserver {
///   final names = <String?>[];
///
///   @override
///   void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
///       names.add(route.settings.name);
///
///   @override
///   void didPop(Route<Object?> route, Route<Object?>? previousRoute) =>
///       names.removeLast();
/// }
/// ```
class NavigatorObserver {
  /// The navigator the observer is on; null while it is on none.
  NavigatorState? get navigator => _hosts.host;
  final _hosts = ControllerHost<NavigatorState>();

  /// [route] was pushed, over [previousRoute]; the first route is told
  /// with none.
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {}

  /// [route] was popped, [previousRoute] in front now.
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {}

  /// [route] was taken off ([NavigatorState.removeRoute]) from over
  /// [previousRoute], none when it was the first.
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {}

  /// [newRoute] took the place of [oldRoute]
  /// ([NavigatorState.pushReplacement]).
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {}
}

/// Refuses or intercepts a pop of the route it is in: while [canPop] is
/// false, the back key and [NavigatorState.maybePop] leave the route,
/// even the first one, whose back key otherwise goes on past the
/// navigator; they take the key, and [onPopInvokedWithResult] is told
/// that it did not pop, with the result asked for. A pop that goes ahead
/// ([NavigatorState.pop], which [canPop] does not stop, or the back key
/// while it is true) tells it that it did, with the result.
/// [onPopInvoked] is told the same, without the result.
///
/// ```dart
/// PopScope<Object?>(
///   canPop: !edited,
///   onPopInvokedWithResult: (didPop, _) {
///     if (!didPop) askToDiscard(context);
///   },
///   child: form,
/// )
/// ```
///
/// The route's scopes are asked in turn ([Route.popDisposition]): one
/// that cannot pop is enough. Outside a route it does nothing.
final class PopScope<T> extends StatefulWidget {
  /// Keeps the route [child] is in from being popped while [canPop] is
  /// false, telling [onPopInvokedWithResult] and [onPopInvoked] of each
  /// pop.
  const PopScope({
    required this.child,
    this.canPop = true,
    this.onPopInvokedWithResult,
    this.onPopInvoked,
    super.key,
  });

  /// What is in the route, below the scope.
  final Widget child;

  /// Whether the back key pops the route, false to keep it.
  final bool canPop;

  /// Told of a pop of the route, whether it was popped or kept, and the
  /// result; a [TypeError] if that is not a [T].
  // called with the results of its own T, cast as they come
  // ignore: unsafe_variance
  final PopInvokedWithResultCallback<T>? onPopInvokedWithResult;

  /// Told of a pop of the route, whether it was popped or kept.
  final void Function(bool didPop)? onPopInvoked;

  @override
  State<PopScope<T>> createState() => _PopScopeState<T>();
}

final class _PopScopeState<T> extends State<PopScope<T>> {
  // the route it is in, and is listed by
  Route<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = Route.maybeOf(context);
    if (!identical(route, _route)) {
      _leave();
      _route = route?.._popScopes.add(this);
      route?._popScopesChanged();
    }
  }

  @override
  void didUpdateWidget(PopScope<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.canPop != widget.canPop) {
      _route?._popScopesChanged();
    }
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  void _leave() {
    final route = _route;
    if (route != null) {
      route._popScopes.remove(this);
      route._popScopesChanged();
      _route = null;
    }
  }

  void _invoked(bool didPop, Object? result) {
    final value = result as T?;
    widget.onPopInvokedWithResult?.call(didPop, value);
    widget.onPopInvoked?.call(didPop);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// What finds the [NavigatorState] from below.
final class _NavigatorScope extends InheritedWidget {
  const _NavigatorScope(this.navigator, {required super.child});

  final NavigatorState navigator;

  @override
  bool updateShouldNotify(_NavigatorScope oldWidget) =>
      !identical(navigator, oldWidget.navigator);
}

/// Shows a [Route]: its build in its focus scope, under the node that
/// keeps the focus from it while it is covered; and, for a route with a
/// transition, slides it in and out over the routes under it, which it
/// dims.
final class _RouteHost extends StatefulWidget {
  const _RouteHost(
    this.navigator,
    this.route, {
    required this.current,
    super.key,
  });

  final NavigatorState navigator;
  final Route<Object?> route;
  final bool current;

  @override
  State<_RouteHost> createState() => _RouteHostState();
}

final class _RouteHostState extends State<_RouteHost>
    with TickerProviderStateMixin<_RouteHost> {
  // how far the route is in, from 0 to 1, for one with a transition
  AnimationController? _run;

  // how the run is eased: out as it comes in, and as it goes out from
  // all the way in; as it came when it goes back out from part of the way
  Curve _curve = Curves.easeOut;

  @override
  void initState() {
    super.initState();
    final route = widget.route.._host = this;
    final push = route.transitionDuration;
    final pop = route.reverseTransitionDuration;
    if (push > Duration.zero || pop > Duration.zero) {
      final run = _run = AnimationController(
        vsync: this,
        duration: push,
        reverseDuration: pop,
        value: route._entering ? 0 : 1,
      )..addStatusListener(_ran);
      if (route._entering) {
        run.forward();
      }
    }
  }

  void _ran(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      widget.navigator._settled(widget.route);
    }
  }

  /// Slides the route out from where it is, when it has a time for that
  /// and is in some of the way; returns whether it does.
  bool _leave() {
    final run = _run;
    final pop = widget.route.reverseTransitionDuration;
    if (run == null ||
        pop <= Duration.zero ||
        run.value * pop.inMicroseconds < 1) {
      return false;
    }
    if (run.value >= 1) {
      _curve = Curves.easeOut.flipped;
    }
    run.reverse();
    return true;
  }

  // the same widget at each build: the route is built again only as its
  // own widgets ask
  late final Widget _child = Focus(
    focusNode: widget.route._guard,
    child: FocusScope(
      node: widget.route._scope,
      // the first route takes the focus when nothing has it
      autofocus: !widget.route._takesFocus,
      child: _RoutePage(widget.route),
    ),
  );

  @override
  void dispose() {
    final route = widget.route;
    if (identical(route._host, this)) {
      route._host = null;
    }
    _run?.dispose();
    route._guard.dispose();
    route._scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return _RouteScope(
      widget.route,
      current: widget.current,
      child: run == null ? _child : _sliding(context, run),
    );
  }

  /// The route moved [run]'s way in from the right, on the theme's
  /// background while it moves, over a shade of what is under it; out of
  /// the mouse's way while it goes. The same widgets at each build, so
  /// that the route's own are kept.
  Widget _sliding(BuildContext context, AnimationController run) {
    final route = widget.route;
    final moving = route._entering || route._leaving;
    final curve = _curve;
    return IgnorePointer(
      ignoring: route._leaving,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: moving
                ? AnimatedModalBarrier(animation: run, curve: curve)
                : const SizedBox.shrink(),
          ),
          ListenableBuilder(
            listenable: run,
            builder: (context, child) => FractionalTranslation(
              x: moving ? 1 - curve.transform(run.value) : 0,
              child: child,
            ),
            child: Box(
              style: moving ? Theme.of(context).background : null,
              child: _child,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a [Route] builds; a route pushed takes the focus as it is mounted.
final class _RoutePage extends StatefulWidget {
  const _RoutePage(this.route);

  final Route<Object?> route;

  @override
  State<_RoutePage> createState() => _RoutePageState();
}

final class _RoutePageState extends State<_RoutePage> {
  @override
  void initState() {
    super.initState();
    widget.route._page = this;
  }

  @override
  void dispose() {
    widget.route._page = null;
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = widget.route;
    if (route._takesFocus) {
      route._takesFocus = false;
      route._scope.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => widget.route.build(context);
}

/// What finds the [Route] from below.
final class _RouteScope extends InheritedWidget {
  const _RouteScope(this.route, {required this.current, required super.child});

  final Route<Object?> route;
  final bool current;

  @override
  bool updateShouldNotify(_RouteScope oldWidget) =>
      !identical(route, oldWidget.route) || current != oldWidget.current;
}

/// The routes of a [Navigator], those from [onstage] on shown.
final class _Theater extends MultiChildRenderObjectWidget {
  const _Theater({required this.onstage, super.children});

  final int onstage;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderTheater createRenderObject(BuildContext context) =>
      _RenderTheater(onstage);

  @override
  void updateRenderObject(BuildContext context, _RenderTheater renderObject) =>
      renderObject.onstage = onstage;
}

final class _TheaterData extends ParentData with ContainerParentDataMixin {}

/// What a [Navigator] lays out and paints: the children from the one at
/// [onstage] on, each as big as it, over those before. The children
/// before are detached from the pipeline, so that what changes in them is
/// not laid out or painted, nor marks this object; laid out last within
/// tight constraints, each is a relayout boundary, where a mark inside it
/// stops.
///
/// A repaint boundary in a child shown that repaints on its own has the
/// children after it painted again over it, as a dialog's barrier dims it.
final class _RenderTheater extends RenderObject
    with ContainerRenderObjectMixin<_TheaterData> {
  _RenderTheater(this._onstage);

  int _onstage;

  int get onstage => _onstage;

  /// Attaches the children shown from now on at once, so that what was
  /// marked in them while they were not is laid out in the next layout,
  /// and detaches the others.
  set onstage(int index) {
    if (index == _onstage) {
      return;
    }
    _onstage = index;
    final o = owner;
    if (o != null) {
      var i = 0;
      for (var child = firstChild; child != null; child = childAfter(child)) {
        final shown = i++ >= index;
        if (shown && child.owner == null) {
          child.attach(o);
        } else if (!shown && child.owner != null) {
          child.detach();
        }
      }
    }
    markNeedsLayout();
  }

  /// The first child shown.
  RenderObject? get _first {
    var child = firstChild;
    for (var i = 0; i < _onstage && child != null; i++) {
      child = childAfter(child);
    }
    return child;
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _TheaterData) {
      child.parentData = _TheaterData();
    }
  }

  /// The children shown alone: the others are not in the pipeline, nor
  /// painted, described or outlined.
  @override
  void visitChildren(void Function(RenderObject child) visit) {
    for (var child = _first; child != null; child = childAfter(child)) {
      visit(child);
    }
  }

  @override
  void detach() {
    super.detach();
    // a child adopted since the last layout may be attached too
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child.owner != null) {
        child.detach();
      }
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('onstage', _onstage, defaultValue: 0);
  }

  int _most(int Function(RenderObject child) size) {
    var most = 0;
    for (var child = _first; child != null; child = childAfter(child)) {
      final s = size(child);
      most = s > most ? s : most;
    }
    return most;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      _most((child) => child.getMinIntrinsicWidth(height));

  @override
  int computeMaxIntrinsicWidth(int height) =>
      _most((child) => child.getMaxIntrinsicWidth(height));

  @override
  int computeMinIntrinsicHeight(int width) =>
      _most((child) => child.getMinIntrinsicHeight(width));

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _most((child) => child.getMaxIntrinsicHeight(width));

  @override
  void performLayout(BoxConstraints c) {
    final o = owner;
    RenderObject? first;
    var i = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (i++ < _onstage) {
        if (child.owner != null) {
          child.detach();
        }
      } else {
        first ??= child;
        if (o != null && child.owner == null) {
          child.attach(o);
        }
      }
    }
    const unbounded = BoxConstraints.unbounded;
    final wide = c.maxW < unbounded;
    final tall = c.maxH < unbounded;
    if (first == null) {
      width = wide ? c.maxW : c.minW;
      height = tall ? c.maxH : c.minH;
      return;
    }
    var rest = first;
    if (wide && tall) {
      width = c.maxW;
      height = c.maxH;
    } else {
      first.layout(
        BoxConstraints(
          wide ? c.maxW : c.minW,
          c.maxW,
          tall ? c.maxH : c.minH,
          c.maxH,
        ),
        parentUsesSize: true,
      );
      first.parentData
        ..dx = 0
        ..dy = 0;
      width = first.width;
      height = first.height;
      final next = childAfter(first);
      if (next == null) {
        return;
      }
      rest = next;
    }
    final tight = BoxConstraints.tight(width, height);
    for (RenderObject? child = rest; child != null; child = childAfter(child)) {
      child.layout(tight);
      child.parentData
        ..dx = 0
        ..dy = 0;
    }
  }

  @override
  void paint(PaintContext ctx) {
    for (var child = _first; child != null; child = childAfter(child)) {
      paintChild(ctx, child);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) {
    final first = _first;
    for (var child = lastChild; child != null; child = childBefore(child)) {
      if (child.hitTest(result, x, y)) {
        return true;
      }
      if (identical(child, first)) {
        break;
      }
    }
    return false;
  }

  /// Whether a child after [child] is shown: it covers all of [child].
  @override
  bool paintsOver(RenderObject child, int x, int y, int w, int h) =>
      childAfter(child) != null;

  /// Paints the children after [child], in order; whatever they keep of
  /// what they painted is forgotten.
  @override
  void paintOver(
    PaintContext ctx,
    RenderObject child,
    int x,
    int y,
    int w,
    int h,
  ) {
    for (var c = childAfter(child); c != null; c = childAfter(c)) {
      paintChild(ctx, c);
      _forgetPaint(c);
    }
  }

  static void _forgetPaint(RenderObject o) => o
    ..invalidatePaintCache()
    ..visitChildren(_forgetPaint);
}
