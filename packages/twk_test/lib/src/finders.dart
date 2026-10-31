/// Finders of the widgets of the app a test runs: [find] makes them, the
/// matchers [findsNothing], [findsOneWidget], [findsWidgets] and
/// [findsNWidgets] count what they find, and a [TwkTester] reads what one
/// finds — its widget, state, render object and cells — and clicks it
/// ([FinderTester]).
library;

import 'dart:math';

import 'package:meta/meta.dart' show internal;
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'tester.dart';

// Examples can assume:
// import 'package:test/test.dart';
// import 'package:twk/twk.dart';

/// Makes the finders: `find.byType(Text)`, `find.text('Save')`.
///
/// ```dart
/// testTwk('the title is shown once', (t) async {
///   await t.pumpWidget(const Column(children: [Text('Title'), Text('Body')]));
///   expect(find.text('Title'), findsOneWidget);
///   expect(find.byType(Text), findsNWidgets(2));
///   expect(find.text('Footer'), findsNothing);
/// });
/// ```
const find = Finders._();

/// What [find] is.
final class Finders {
  const Finders._();

  /// The widgets of exactly the type [type], not of its subtypes.
  Finder byType(Type type) =>
      _WidgetFinder('type $type', (w) => w.runtimeType == type);

  /// The widgets whose key is [key].
  Finder byKey(Key key) => _WidgetFinder('key $key', (w) => w.key == key);

  /// The [Text]s that show [text]: their string, or their spans joined
  /// ([Text.rich]).
  Finder text(String text) => _WidgetFinder(
    'text "$text"',
    (w) =>
        w is Text &&
        (w.data ?? [for (final s in w.spans!) s.text].join()) == text,
  );

  /// The widgets [predicate] is true of, named [description] in messages.
  Finder byWidgetPredicate(
    bool Function(Widget widget) predicate, {
    String description = 'widgets a predicate takes',
  }) => _WidgetFinder(description, predicate);

  /// The widgets [matching] finds below those [of] finds, in the order of
  /// the tree.
  Finder descendant({required Finder of, required Finder matching}) =>
      _DescendantFinder(of, matching);

  /// The widgets [matching] finds above those [of] finds: above the first
  /// from the nearest up, then above the next.
  Finder ancestor({required Finder of, required Finder matching}) =>
      _AncestorFinder(of, matching);
}

/// What picks elements out of the app's tree: out of the candidates it is
/// given ([apply]), all of the app's when it is evaluated in a test
/// ([evaluate]). Its [description] names it in messages: `type Text`.
abstract class Finder {
  /// Lets a subclass be constant.
  const Finder();

  /// What it finds, for messages: `type Text`, `text "Save"`.
  String get description;

  /// The elements this finds among [candidates], in their order.
  Iterable<Element> apply(Iterable<Element> candidates);

  /// The elements this finds in the app of the test running ([testTwk]):
  /// among those of the widget [TwkTester.pumpWidget] showed and the
  /// widgets below it, in the order of the tree. None before the app's
  /// first frame or after it ended; a [StateError] outside [testTwk] or
  /// before [TwkTester.pumpWidget].
  List<Element> evaluate() {
    final t =
        runningTester ??
        (throw StateError(
          'a finder finds the widgets of the app of a testTwk',
        ));
    return apply(_appElements(t)).toList();
  }

  /// The first of what this finds.
  Finder get first => _IndexFinder(this, 0, 'the first of $description');

  /// The last of what this finds.
  Finder get last => _IndexFinder(this, -1, 'the last of $description');

  /// What this finds at [index], from 0.
  Finder at(int index) => _IndexFinder(this, index, '$description at $index');

  @override
  String toString() => description;
}

/// Matches a [Finder] that finds no widget.
const Matcher findsNothing = _Finds(0, 0);

/// Matches a [Finder] that finds exactly one widget.
const Matcher findsOneWidget = _Finds(1, 1);

/// Matches a [Finder] that finds one widget or more.
const Matcher findsWidgets = _Finds(1, null);

/// Matches a [Finder] that finds exactly [n] widgets.
Matcher findsNWidgets(int n) => _Finds(n, n);

/// Matches a [Finder] that finds from [_least] to [_most] widgets.
final class _Finds extends Matcher {
  const _Finds(this._least, this._most);

  final int _least;
  final int? _most;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is! Finder) {
      return false;
    }
    final found = matchState[_Finds] = item.evaluate();
    final most = _most;
    return found.length >= _least && (most == null || found.length <= most);
  }

  @override
  Description describe(Description description) => description.add(
    switch ((_least, _most)) {
      (0, 0) => 'finds no widget',
      (1, 1) => 'finds one widget',
      (1, null) => 'finds a widget or more',
      (final n, _) => 'finds $n widgets',
    },
  );

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (item is! Finder) {
      return mismatchDescription.add('is not a Finder');
    }
    final found = matchState[_Finds] as List<Element>;
    final root = appRoot(runningTester!);
    return mismatchDescription
        .add(found.isEmpty ? 'finds none' : 'finds ${found.length}:')
        .add([for (final e in found) '\n  ${_describe(e)}'].join())
        .add('\n\nwidget tree:\n')
        .add(root?.describe().toStringDeep() ?? 'none');
  }
}

/// What a [TwkTester] reads of the widget a [Finder] finds, and how it
/// clicks one. Each finds in the tester's app, as [Finder.evaluate] does,
/// and takes one widget: a [StateError] names what it found when it found
/// none or more.
///
/// A button clicked where it is laid out:
///
/// ```dart
/// testTwk('a click on Save saves', (t) async {
///   var saved = 0;
///   await t.pumpWidget(
///     Center(child: Button('Save', onPressed: () => saved++)),
///     size: (20, 3),
///   );
///   expect(t.rect(find.byType(Button)), (x: 7, y: 1, width: 6, height: 1));
///   await t.clickOn(find.byType(Button));
///   expect(saved, 1);
/// });
/// ```
extension FinderTester on TwkTester {
  /// The element of the widget [finder] finds.
  Element element(Finder finder) {
    final found = finder.apply(_appElements(this)).toList();
    return switch (found) {
      [final one] => one,
      [] => throw StateError('$finder finds no widget'),
      _ => throw StateError(
        '$finder finds ${found.length} widgets, not one: '
        '${found.map(_describe).join('; ')}',
      ),
    };
  }

  /// The widget [finder] finds; a [StateError] if it is not a [T].
  T widget<T extends Widget>(Finder finder) {
    final widget = element(finder).widget;
    return widget is T
        ? widget
        : throw StateError(
            '$finder finds a ${widget.runtimeType}, not a $T',
          );
  }

  /// The state of the stateful widget [finder] finds; a [StateError] if it
  /// has none, or one that is not a [T].
  T state<T extends State<StatefulWidget>>(Finder finder) {
    final e = element(finder);
    final type = e.widget.runtimeType;
    if (e is! StatefulElement) {
      throw StateError('$finder finds a $type, which has no state');
    }
    final state = e.state;
    return state is T
        ? state
        : throw StateError(
            '$finder finds a $type, whose state is a ${state.runtimeType}',
          );
  }

  /// The render object of the widget [finder] finds, or of the nearest
  /// widget below it that has one; a [StateError] if there is none, or one
  /// that is not a [T].
  T renderObject<T extends RenderObject>(Finder finder) {
    final e = element(finder);
    final type = e.widget.runtimeType;
    return switch (e.renderObject) {
      final T o => o,
      null => throw StateError(
        '$finder finds a $type, which has no render object',
      ),
      final o => throw StateError(
        '$finder finds a $type, whose render object is a ${o.runtimeType}',
      ),
    };
  }

  /// The cells of the widget [finder] finds, as its render object was laid
  /// out last: full screen, those of the screen; in the inline mode, those
  /// of the region, row 0 its first. Partly or wholly off the screen when
  /// the widget is. A [StateError] before it was laid out.
  ({int x, int y, int width, int height}) rect(Finder finder) {
    final e = element(finder);
    return _rectOf(e) ??
        (throw StateError('$finder finds $e, which is not laid out'));
  }

  /// The rows of the cells of the widget [finder] finds ([rect]), as
  /// [TwkTester.linesIn] gives them.
  List<String> linesOf(Finder finder) => linesIn(rect(finder));

  /// Clicks [button] on the widget [finder] finds ([TwkTester.click]): on
  /// the cell in the middle of those it shows, its own cut off where they
  /// are outside one of the render objects above it, as a hit test cuts
  /// them. A [StateError] when it shows none.
  Future<void> clickOn(Finder finder, {int button = 0}) {
    final e = element(finder);
    final o = e.renderObject;
    if (o == null || o.constraints == null) {
      throw StateError('$finder finds $e, which is not laid out');
    }
    var (left, top) = o.globalOffset;
    var right = left + o.width;
    var bottom = top + o.height;
    for (var a = o.parent; a != null; a = a.parent) {
      final (x, y) = a.globalOffset;
      left = max(left, x);
      top = max(top, y);
      right = min(right, x + a.width);
      bottom = min(bottom, y + a.height);
    }
    if (left >= right || top >= bottom) {
      throw StateError('$finder finds ${_describe(e)}, which shows no cell');
    }
    return click(
      left + (right - left - 1) ~/ 2,
      top + (bottom - top - 1) ~/ 2,
      button: button,
    );
  }
}

/// The widgets [_test] takes.
final class _WidgetFinder extends Finder {
  const _WidgetFinder(this.description, this._test);

  @override
  final String description;

  final bool Function(Widget widget) _test;

  @override
  Iterable<Element> apply(Iterable<Element> candidates) =>
      candidates.where((e) => _test(e.widget));
}

/// What [_matching] finds below what [_of] finds.
final class _DescendantFinder extends Finder {
  const _DescendantFinder(this._of, this._matching);

  final Finder _of;
  final Finder _matching;

  @override
  String get description => '$_matching below $_of';

  @override
  Iterable<Element> apply(Iterable<Element> candidates) {
    final all = candidates.toList();
    final above = _of.apply(all).toSet();
    bool below(Element e) {
      var found = false;
      e.visitAncestorElements((a) {
        found = above.contains(a);
        return !found;
      });
      return found;
    }

    return _matching.apply(all.where(below));
  }
}

/// What [_matching] finds above what [_of] finds, from the nearest up.
final class _AncestorFinder extends Finder {
  const _AncestorFinder(this._of, this._matching);

  final Finder _of;
  final Finder _matching;

  @override
  String get description => '$_matching above $_of';

  @override
  Iterable<Element> apply(Iterable<Element> candidates) {
    final all = candidates.toSet();
    final above = <Element>{};
    for (final e in _of.apply(all)) {
      // up to the app's widget
      e.visitAncestorElements((a) {
        if (!all.contains(a)) {
          return false;
        }
        above.add(a);
        return true;
      });
    }
    return _matching.apply(above);
  }
}

/// What [_finder] finds at [_index], from the last back when negative.
final class _IndexFinder extends Finder {
  const _IndexFinder(this._finder, this._index, this.description);

  final Finder _finder;
  final int _index;

  @override
  final String description;

  @override
  Iterable<Element> apply(Iterable<Element> candidates) {
    final found = _finder.apply(candidates).toList();
    final i = _index < 0 ? found.length + _index : _index;
    return [if (i >= 0 && i < found.length) found[i]];
  }
}

/// The elements of [t]'s app in the order of the tree: that of the widget
/// [TwkTester.pumpWidget] showed, and those below it.
List<Element> _appElements(TwkTester t) {
  final out = <Element>[];
  void visit(Element e) {
    out.add(e);
    e.visitChildren(visit);
  }

  final root = appRoot(t);
  if (root != null) {
    visit(root);
  }
  return out;
}

/// The element of [t]'s app's widget: the child of the binding's scope,
/// the first element from the root focus scope's down that finds the
/// binding ([AppBinding.maybeOf]). None before the first frame or once the
/// app ended.
@internal
Element? appRoot(TwkTester t) {
  final binding = t.binding;
  Element? scope;
  void visit(Element e) {
    if (scope != null) {
      return;
    }
    if (identical(AppBinding.maybeOf(e), binding)) {
      scope = e;
    } else {
      e.visitChildren(visit);
    }
  }

  if (binding.focusManager.rootScope.context case final Element top) {
    visit(top);
  }
  Element? root;
  scope?.visitChildren((e) => root = e);
  return root;
}

/// [e] as messages name it: its widget's type and key, and its cells
/// ([FinderTester.rect]) once laid out — `Tile at (2, 3), 6×1`.
String _describe(Element e) => switch (_rectOf(e)) {
  null => '$e',
  (:final x, :final y, :final width, :final height) =>
    '$e at ($x, $y), $width×$height',
};

/// The cells of [e]'s render object; null before it was laid out.
({int x, int y, int width, int height})? _rectOf(Element e) {
  final o = e.renderObject;
  if (o == null || o.constraints == null) {
    return null;
  }
  final (x, y) = o.globalOffset;
  return (x: x, y: y, width: o.width, height: o.height);
}
