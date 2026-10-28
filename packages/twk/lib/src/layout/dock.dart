/// Docking: a [DockArea] shows [DockPanel]s in a tree of splits and tab
/// groups, and in windows over them; a tab or a window's title bar dragged
/// onto a group docks the panel beside it or among its tabs. The tree is a
/// [DockLayout] of [DockSplit]s, [DockTabs] and [DockWindow]s, which a
/// [DockController] keeps and which saves to JSON and back.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show Attr, Axis, BorderType, CrossAxisAlignment, RenderObject;

import '../controls/tabs.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart' show takeDrag;
import '../gestures/mouse.dart';
import '../overlay/window.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'basic.dart';
import 'box.dart';
import 'flex.dart';
import 'split.dart';
import 'stack.dart';

// Examples can assume:
// import 'dart:convert';
// late DockController dock;
// late Widget fileTree;
// late Widget editor;
// late Widget terminal;

/// Where a panel docks against a group of a [DockArea]: on a side of it,
/// the group and the panel sharing its room, or among its tabs.
enum DockSide {
  /// On the group's left, the two side by side.
  left,

  /// On the group's right, the two side by side.
  right,

  /// Above the group, the two one below the other.
  top,

  /// Below the group, the two one below the other.
  bottom,

  /// Among the group's tabs, as the last of them.
  center,
}

/// A node of a [DockLayout]'s tree: a [DockTabs] group or a [DockSplit].
///
/// Two nodes are equal when their trees are: the same panels in the same
/// groups, the same tabs selected, and the same splits with the same
/// shares.
sealed class DockNode {
  const DockNode._();

  /// The node [json] describes, as [toJson] gives it; a [FormatException]
  /// for anything else.
  factory DockNode.fromJson(Object? json) => switch (json) {
    {'tabs': final List<Object?> tabs, 'selected': final int selected}
        when tabs.isNotEmpty && selected >= 0 && selected < tabs.length =>
      DockTabs([
        for (final t in tabs)
          if (t is String) t else throw _bad(json),
      ], selected: selected),
    {
      'split': final String split,
      'fractions': final List<Object?> fractions,
      'children': final List<Object?> children,
    } =>
      _splitOf(split, fractions, children, json),
    _ => throw _bad(json),
  };

  /// The panels of the node, in the order of its tree.
  Iterable<String> get panels;

  /// The node as a value of JSON.
  Map<String, Object?> toJson();
}

/// A group of panels, a tab for each; the one at [selected] shown.
///
/// A group of two files, the second shown:
///
/// ```dart
/// DockTabs(['main.dart', 'pubspec.yaml'], selected: 1)
/// ```
final class DockTabs extends DockNode {
  /// An [ArgumentError] for no [panels], and a [RangeError] for a
  /// [selected] of none.
  DockTabs(List<String> panels, {this.selected = 0})
    : panels = List.unmodifiable(panels),
      super._() {
    if (panels.isEmpty) {
      throw ArgumentError.value(panels, 'panels', 'no panel');
    }
    RangeError.checkValidIndex(selected, panels, 'selected');
  }

  /// The panels, a tab each, in the order of their tabs.
  @override
  final List<String> panels;

  /// The index in [panels] of the panel shown, its tab selected: the
  /// first by default.
  final int selected;

  @override
  Map<String, Object?> toJson() => {'tabs': panels, 'selected': selected};

  @override
  bool operator ==(Object other) =>
      other is DockTabs &&
      other.selected == selected &&
      _same(other.panels, panels);

  @override
  int get hashCode => Object.hash(Object.hashAll(panels), selected);

  @override
  String toString() => 'DockTabs($panels, selected: $selected)';
}

/// [children] side by side ([Axis.horizontal]) or one below another, each
/// with its share of the room, a divider between each two that resizes
/// them as a [SplitView]'s does.
///
/// A file tree on the left, a quarter of the room, and an editor above a
/// terminal on the right:
///
/// ```dart
/// DockSplit(Axis.horizontal, [
///   DockTabs(['files']),
///   DockSplit(Axis.vertical, [
///     DockTabs(['editor']),
///     DockTabs(['terminal']),
///   ], fractions: [3, 1]),
/// ], fractions: [1, 3])
/// ```
final class DockSplit extends DockNode {
  /// Equal shares when [fractions] is null; [fractions] are scaled to make
  /// 1 together. An [ArgumentError] for fewer than two [children], and for
  /// another number of [fractions], one negative or not finite, or none
  /// above 0.
  DockSplit(this.direction, List<DockNode> children, {List<double>? fractions})
    : children = List.unmodifiable(children),
      fractions = _shares(fractions, children.length),
      super._() {
    if (children.length < 2) {
      throw ArgumentError.value(children, 'children', 'fewer than two');
    }
  }

  /// The axis the children are laid out along: side by side for
  /// [Axis.horizontal].
  final Axis direction;

  /// The groups and splits it shares its room among, from the left or the
  /// top: two or more.
  final List<DockNode> children;

  /// Each child's share of the room the dividers leave: 0 to 1, 1
  /// together.
  final List<double> fractions;

  @override
  Iterable<String> get panels => children.expand((c) => c.panels);

  @override
  Map<String, Object?> toJson() => {
    'split': direction.name,
    'fractions': fractions,
    'children': [for (final c in children) c.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is DockSplit &&
      other.direction == direction &&
      _same(other.children, children) &&
      _same(other.fractions, fractions);

  @override
  int get hashCode => Object.hash(
    direction,
    Object.hashAll(children),
    Object.hashAll(fractions),
  );

  @override
  String toString() => 'DockSplit(${direction.name}, $children, $fractions)';
}

/// A panel floating in a window over the docked ones: the cells its
/// window asks for, as a [WindowController]'s.
///
/// Two windows are equal when their panels and cells are.
///
/// A terminal floating ten columns and five rows in from the top left of
/// the area:
///
/// ```dart
/// const DockWindow('terminal', left: 10, top: 5, width: 60, height: 15)
/// ```
@immutable
final class DockWindow {
  /// A window of [panel] at [left] and [top], [width] by [height] cells:
  /// 40 by 12 at the top left by default.
  const DockWindow(
    this.panel, {
    this.left = 0,
    this.top = 0,
    this.width = 40,
    this.height = 12,
  });

  /// The window [json] describes, as [toJson] gives it; a
  /// [FormatException] for anything else.
  factory DockWindow.fromJson(Object? json) => switch (json) {
    {
      'panel': final String panel,
      'left': final int left,
      'top': final int top,
      'width': final int width,
      'height': final int height,
    }
        when width >= 0 && height >= 0 =>
      DockWindow(panel, left: left, top: top, width: width, height: height),
    _ => throw _bad(json),
  };

  /// The id of the panel in the window ([DockPanel.id]).
  final String panel;

  /// The columns from the area's left edge to the window's.
  final int left;

  /// The rows from the area's top edge to the window's.
  final int top;

  /// The window's width, in cells.
  final int width;

  /// The window's height, in cells.
  final int height;

  /// The window as a value of JSON.
  Map<String, Object?> toJson() => {
    'panel': panel,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  @override
  bool operator ==(Object other) =>
      other is DockWindow &&
      other.panel == panel &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(panel, left, top, width, height);

  @override
  String toString() => 'DockWindow($panel, $left, $top, $width × $height)';
}

/// Where the panels of a [DockArea] are: docked in the tree under [root],
/// none when it is null, or floating in [windows], the one in front last.
/// What an app saves ([toJson]) to show them as they were, and restores
/// ([DockLayout.fromJson]).
///
/// Two layouts are equal when their trees and windows, in order, are.
///
/// A layout saved as text, and read back:
///
/// ```dart
/// final saved = jsonEncode(dock.layout.toJson());
/// dock.layout = DockLayout.fromJson(
///   jsonDecode(saved) as Map<String, Object?>,
/// );
/// ```
final class DockLayout {
  /// An [ArgumentError] for a panel in two places.
  DockLayout({this.root, List<DockWindow> windows = const []})
    : windows = List.unmodifiable(windows) {
    if (_twice(panels) case final panel?) {
      throw ArgumentError.value(panel, 'panels', 'in two places');
    }
  }

  /// The layout [json] describes, as [toJson] gives it; a
  /// [FormatException] for anything else.
  factory DockLayout.fromJson(Map<String, Object?> json) {
    if (json case {'windows': final List<Object?> windows}) {
      final root = json['root'] == null
          ? null
          : DockNode.fromJson(json['root']);
      final floating = [for (final w in windows) DockWindow.fromJson(w)];
      if (_twice([...?root?.panels, for (final w in floating) w.panel]) ==
          null) {
        return DockLayout(root: root, windows: floating);
      }
    }
    throw _bad(json);
  }

  /// The tree of the docked panels; null for none docked.
  final DockNode? root;

  /// The floating panels' windows, from the back to the front.
  final List<DockWindow> windows;

  /// The panels docked, in the order of the tree, then those floating.
  Iterable<String> get panels => [
    ...?root?.panels,
    for (final w in windows) w.panel,
  ];

  /// The layout as a value of JSON, which `jsonEncode` encodes.
  Map<String, Object?> toJson() => {
    'root': root?.toJson(),
    'windows': [for (final w in windows) w.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is DockLayout &&
      other.root == root &&
      _same(other.windows, windows);

  @override
  int get hashCode => Object.hash(root, Object.hashAll(windows));

  @override
  String toString() => 'DockLayout($root, $windows)';
}

FormatException _bad(Object? json) =>
    FormatException('not a dock layout: $json');

/// The split [json] describes, its parts given; a [FormatException] for
/// anything but one.
DockSplit _splitOf(
  String split,
  List<Object?> fractions,
  List<Object?> children,
  Object? json,
) {
  final direction = Axis.values.where((a) => a.name == split).firstOrNull;
  final shares = [
    for (final f in fractions)
      if (f is num) f.toDouble() else throw _bad(json),
  ];
  if (direction == null ||
      children.length < 2 ||
      _badShares(shares, children.length) != null) {
    throw _bad(json);
  }
  return DockSplit(direction, [
    for (final c in children) DockNode.fromJson(c),
  ], fractions: shares);
}

/// A panel of [panels] twice; null for none.
String? _twice(Iterable<String> panels) {
  final seen = <String>{};
  return panels.where((p) => !seen.add(p)).firstOrNull;
}

bool _same<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// [shares] for [n] children, scaled to make 1 together; equal ones when
/// null.
List<double> _shares(List<double>? shares, int n) {
  if (shares == null) {
    return List.unmodifiable(List.filled(n, 1 / n));
  }
  if (_badShares(shares, n) case final why?) {
    throw ArgumentError.value(shares, 'fractions', why);
  }
  final sum = shares.fold<double>(0, (a, b) => a + b);
  // shares that make 1 already are kept as they are, so that a layout
  // read back from its JSON is the one saved
  return List.unmodifiable(
    (sum - 1).abs() < 1e-9 ? shares : [for (final s in shares) s / sum],
  );
}

/// What makes [shares] no shares of [n] children; null for nothing.
String? _badShares(List<double> shares, int n) {
  if (shares.length != n) {
    return 'not $n shares';
  }
  for (final s in shares) {
    if (!s.isFinite || s < 0) {
      return 'a share of $s';
    }
  }
  return shares.any((s) => s > 0) ? null : 'no share above 0';
}

/// The [DockLayout] of a [DockArea], and what moves its panels: an app
/// sets [layout] to restore one, and docks, floats, selects and removes
/// panels by their ids; the area does as its tabs and windows are dragged.
/// It notifies its listeners of each change.
///
/// An editor with a file tree on its left and a terminal below it, then a
/// log floated in a window:
///
/// ```dart
/// final controller = DockController()
///   ..dock('editor')
///   ..dock('files', beside: 'editor', side: DockSide.left)
///   ..dock('terminal', beside: 'editor', side: DockSide.bottom)
///   ..float('log', left: 4, top: 2);
/// ```
///
/// A [DockArea] given one listens to it while the area is in the tree; the
/// app that made it disposes of it.
final class DockController extends ChangeNotifier {
  /// A layout of no panels when [layout] is null.
  DockController([DockLayout? layout]) : _layout = layout ?? DockLayout();

  DockLayout _layout;

  /// Where the panels are. Set to another layout, it notifies its
  /// listeners and the area shows the panels where the layout puts them.
  DockLayout get layout => _layout;

  set layout(DockLayout value) {
    if (value != _layout) {
      _layout = value;
      notifyListeners();
    }
  }

  /// Docks [panel], taken from where it is or added, on [side] of the group
  /// of the docked panel [beside]: in a group of its own sharing that
  /// group's room, the two side by side or one below the other, or, for
  /// [DockSide.center], as the last of its tabs, selected (a panel among
  /// them already is selected). Where the group is in a split along the
  /// same axis, the new group goes into that split, beside it, the two
  /// sharing its share. With [beside] null, on [side] of all of the panels
  /// docked; [DockSide.center] there makes it the first group's last tab,
  /// or the only group when none is docked. An [ArgumentError] for a
  /// [beside] that is [panel] or docks nowhere.
  void dock(String panel, {String? beside, DockSide side = DockSide.center}) {
    final layout = _layout;
    final root = layout.root;
    if (beside != null) {
      if (beside == panel) {
        throw ArgumentError.value(beside, 'beside', 'the panel docked');
      }
      final group = root == null ? null : _groupOf(root, beside);
      if (group == null) {
        throw ArgumentError.value(beside, 'beside', 'docks nowhere');
      }
      if (side == DockSide.center && group.panels.contains(panel)) {
        select(panel);
        return;
      }
    }
    final rest = root == null ? null : _without(root, panel);
    final alone = DockTabs([panel]);
    final DockNode next;
    if (rest == null) {
      next = alone;
    } else if (side == DockSide.center) {
      next = _into(rest, beside ?? rest.panels.first, panel);
    } else if (beside != null) {
      next = _beside(rest, beside, alone, side);
    } else {
      final axis = _axisOf(side);
      final n = rest is DockSplit && rest.direction == axis
          ? rest.children.length
          : 1;
      next = _split(
        axis,
        _isBefore(side) ? [alone, rest] : [rest, alone],
        _isBefore(side) ? [1, n.toDouble()] : [n.toDouble(), 1],
      )!;
    }
    this.layout = DockLayout(root: next, windows: _windowsWithout(panel));
  }

  /// Floats [panel], taken from where it is or added, in a window in front
  /// of the others, [left] columns and [top] rows from the top left of the
  /// area, [width] by [height] cells.
  void float(
    String panel, {
    int left = 0,
    int top = 0,
    int width = 40,
    int height = 12,
  }) {
    final root = _layout.root;
    layout = DockLayout(
      root: root == null ? null : _without(root, panel),
      windows: [
        ..._windowsWithout(panel),
        DockWindow(panel, left: left, top: top, width: width, height: height),
      ],
    );
  }

  /// Selects the tab of the docked [panel]; nothing for a panel that is
  /// not docked.
  void select(String panel) {
    final root = _layout.root;
    if (root != null) {
      layout = DockLayout(
        root: _selecting(root, panel),
        windows: _layout.windows,
      );
    }
  }

  /// Takes [panel] out of the layout, wherever it is.
  void remove(String panel) {
    final root = _layout.root;
    layout = DockLayout(
      root: root == null ? null : _without(root, panel),
      windows: _windowsWithout(panel),
    );
  }

  List<DockWindow> _windowsWithout(String panel) => [
    for (final w in _layout.windows)
      if (w.panel != panel) w,
  ];

  /// Takes out the panels not among [ids]; tells no listener, the area
  /// showing the layout at once.
  void _fit(Set<String> ids) {
    final layout = _layout;
    if (layout.panels.every(ids.contains)) {
      return;
    }
    var root = layout.root;
    for (final panel in layout.panels) {
      if (!ids.contains(panel) && root != null) {
        root = _without(root, panel);
      }
    }
    _layout = DockLayout(
      root: root,
      windows: [
        for (final w in layout.windows)
          if (ids.contains(w.panel)) w,
      ],
    );
  }

  /// Gives the split at [path] [fractions], as its divider moved them.
  void _resized(List<int> path, List<double> fractions) {
    final root = _layout.root;
    if (root != null) {
      layout = DockLayout(
        root: _resizing(root, path, 0, fractions),
        windows: _layout.windows,
      );
    }
  }

  /// Puts the window of [panel] where it was dragged to.
  void _moved(String panel, int left, int top, int width, int height) {
    layout = DockLayout(
      root: _layout.root,
      windows: [
        for (final w in _layout.windows)
          if (w.panel == panel)
            DockWindow(
              panel,
              left: left,
              top: top,
              width: width,
              height: height,
            )
          else
            w,
      ],
    );
  }
}

Axis _axisOf(DockSide side) => side == DockSide.left || side == DockSide.right
    ? Axis.horizontal
    : Axis.vertical;

bool _isBefore(DockSide side) => side == DockSide.left || side == DockSide.top;

/// The group of [node]'s tree that [panel] is in; null for none.
DockTabs? _groupOf(DockNode node, String panel) => switch (node) {
  DockTabs(:final panels) => panels.contains(panel) ? node : null,
  DockSplit(:final children) =>
    children.map((c) => _groupOf(c, panel)).nonNulls.firstOrNull,
};

/// [node] without [panel]: its group without it, the tab after it
/// selected in its place when it was (the one before it for the last); a
/// group left with none gone, and a split left with one child that child.
/// Null for none left.
DockNode? _without(DockNode node, String panel) {
  switch (node) {
    case DockTabs(:final panels, :final selected):
      final i = panels.indexOf(panel);
      if (i < 0) {
        return node;
      }
      if (panels.length == 1) {
        return null;
      }
      final rest = [...panels]..removeAt(i);
      return DockTabs(
        rest,
        selected: i < selected
            ? selected - 1
            : (selected < rest.length ? selected : rest.length - 1),
      );
    case DockSplit(:final direction, :final children, :final fractions):
      final kept = <DockNode>[];
      final shares = <double>[];
      var changed = false;
      for (var i = 0; i < children.length; i++) {
        final c = _without(children[i], panel);
        changed |= !identical(c, children[i]);
        if (c != null) {
          kept.add(c);
          shares.add(fractions[i]);
        }
      }
      return changed ? _split(direction, kept, shares) : node;
  }
}

/// A split of [children] along [direction] by [shares], those of a child
/// split along [direction] too among them by its own: null for no
/// children, the child for one.
DockNode? _split(Axis direction, List<DockNode> children, List<double> shares) {
  final flat = <DockNode>[];
  final f = <double>[];
  for (var i = 0; i < children.length; i++) {
    final c = children[i];
    if (c is DockSplit && c.direction == direction) {
      for (var j = 0; j < c.children.length; j++) {
        flat.add(c.children[j]);
        f.add(shares[i] * c.fractions[j]);
      }
    } else {
      flat.add(c);
      f.add(shares[i]);
    }
  }
  if (flat.length < 2) {
    return flat.firstOrNull;
  }
  final some = f.any((s) => s > 0);
  return DockSplit(direction, flat, fractions: some ? f : null);
}

/// [node] with [panel] the last tab of [anchor]'s group, selected.
DockNode _into(DockNode node, String anchor, String panel) => switch (node) {
  DockTabs(:final panels) when panels.contains(anchor) => DockTabs([
    ...panels,
    panel,
  ], selected: panels.length),
  DockTabs() => node,
  DockSplit(:final direction, :final children, :final fractions) => DockSplit(
    direction,
    [for (final c in children) _into(c, anchor, panel)],
    fractions: fractions,
  ),
};

/// [node] with [group] on [side] of [anchor]'s group: in the split that
/// group is in when it is along the same axis, the two sharing its share,
/// else in a split of the two in its place.
DockNode _beside(DockNode node, String anchor, DockTabs group, DockSide side) {
  final axis = _axisOf(side);
  final before = _isBefore(side);
  switch (node) {
    case DockTabs(:final panels) when panels.contains(anchor):
      return DockSplit(axis, before ? [group, node] : [node, group]);
    case DockTabs():
      return node;
    case DockSplit(:final direction, :final children, :final fractions):
      for (var i = 0; i < children.length; i++) {
        final c = children[i];
        if (!c.panels.contains(anchor)) {
          continue;
        }
        if (direction == axis && c is DockTabs) {
          final half = fractions[i] / 2;
          final at = before ? i : i + 1;
          return DockSplit(
            direction,
            [...children]..insert(at, group),
            fractions: [...fractions]
              ..[i] = half
              ..insert(at, half),
          );
        }
        return _split(direction, [
          ...children.take(i),
          _beside(c, anchor, group, side),
          ...children.skip(i + 1),
        ], fractions)!;
      }
      return node;
  }
}

/// [node] with the tab of [panel] selected.
DockNode _selecting(DockNode node, String panel) => switch (node) {
  DockTabs(:final panels) when panels.contains(panel) => DockTabs(
    panels,
    selected: panels.indexOf(panel),
  ),
  DockTabs() => node,
  DockSplit(:final direction, :final children, :final fractions) => DockSplit(
    direction,
    [for (final c in children) _selecting(c, panel)],
    fractions: fractions,
  ),
};

/// [node] with the split at [path], from its [depth]th index, of
/// [fractions]; as it is when there is no split of as many children there.
DockNode _resizing(
  DockNode node,
  List<int> path,
  int depth,
  List<double> fractions,
) {
  if (node is! DockSplit) {
    return node;
  }
  if (depth == path.length) {
    return fractions.length == node.children.length
        ? DockSplit(node.direction, node.children, fractions: fractions)
        : node;
  }
  final i = path[depth];
  if (i >= node.children.length) {
    return node;
  }
  return DockSplit(node.direction, [
    for (var j = 0; j < node.children.length; j++)
      if (j == i)
        _resizing(node.children[j], path, depth + 1, fractions)
      else
        node.children[j],
  ], fractions: node.fractions);
}

/// A panel of a [DockArea]: [child] under its [title], on its tab and on
/// its window's title bar; [id] is what a [DockLayout] names it by.
///
/// A panel the layout names `editor`:
///
/// ```dart
/// DockPanel(id: 'editor', title: 'main.dart', child: editor)
/// ```
@immutable
final class DockPanel {
  /// A panel of [child], named [id] in the layout and [title] on screen.
  const DockPanel({required this.id, required this.title, required this.child});

  /// What the layout names the panel by: one of its own among the area's
  /// panels.
  final String id;

  /// What its tab and its window's title bar show.
  final String title;

  /// What the panel shows. Its state is kept as the panel moves from one
  /// group to another and into a window and back, and while its tab is not
  /// selected.
  final Widget child;
}

/// Shows [panels] where the [controller]'s [DockLayout] puts them: docked
/// in a tree of splits, each a [SplitView] whose dividers resize its
/// children, and groups of tabs, each a [TabBar] over a [TabView] of its
/// panels; floating in windows of a [WindowLayer] over them. A panel the
/// layout names that [panels] has not is taken out of it; a panel it does
/// not name is not shown. It fills the room it gets.
///
/// The left button dragging a group's tab bar drags its selected panel,
/// the tab the press selected, a chip with its title following the mouse
/// below and right of it; dragging a window's title bar moves it as in any
/// [WindowLayer]. Over a group, the drag shows five targets in its middle,
/// `◀ ▶ ▲ ▼` for its sides and `■` for its tabs (over an area with no
/// group docked, `■` in its middle alone); over one of them, the cells the
/// panel would take outlined, its title on the top edge, in place of the
/// chip. Released over a target, the panel docks there
/// ([DockController.dock]); a tab released elsewhere floats its panel
/// ([DockController.float]) in a window half as wide and as tall as the
/// area, its title bar under the mouse. A lone panel's own group shows no
/// targets for its tab. A divider dragged sets the shares of its split in
/// the layout, and a window moved or resized sets its cells there.
///
/// Each panel's [DockPanel.child] is kept, with its state and render
/// objects, as it moves from one group to another, into a window and
/// back: under a [GlobalKey] of its own, which takes its element along
/// within the frame of the move.
///
/// A group's tabs are a [TabBar.strip] while [tabStrip], on a strip of the
/// theme's surface with the selected tab cut out of it; a plain [TabBar]
/// otherwise. The windows are drawn as [windowFrame] says (see
/// [WindowLayer.frame]), without a shadow.
///
/// Three panels where a controller the app keeps (`dock`, laid out as the
/// one of [DockController]'s example) puts them:
///
/// ```dart
/// DockArea(
///   controller: dock,
///   panels: [
///     DockPanel(id: 'files', title: 'Files', child: fileTree),
///     DockPanel(id: 'editor', title: 'main.dart', child: editor),
///     DockPanel(id: 'terminal', title: 'Terminal', child: terminal),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [SplitView], panes the user resizes but does not move.
///  * [TabView], one group of tabs.
final class DockArea extends StatefulWidget {
  /// Shows [panels] where [controller]'s layout puts them, the tabs of a
  /// group on a strip ([tabStrip]) by default.
  const DockArea({
    required this.controller,
    required this.panels,
    super.key,
    this.tabStrip = true,
    this.windowFrame,
  });

  /// The layout of the panels, which the area shows and the user's drags
  /// change.
  final DockController controller;

  /// The panels, each with a [DockPanel.id] of its own.
  final List<DockPanel> panels;

  /// Whether a group's tabs are on a strip ([TabBar.strip]) rather than a
  /// plain [TabBar].
  final bool tabStrip;

  /// How the windows are drawn; see [WindowLayer.frame].
  final WindowFrame? windowFrame;

  @override
  State<DockArea> createState() => _DockAreaState();
}

/// Cells of an area: the left and top ones, the width and the height.
typedef _Rect = ({int left, int top, int width, int height});

bool _contains(_Rect r, int x, int y) =>
    x >= r.left && x < r.left + r.width && y >= r.top && y < r.top + r.height;

/// What the mouse drags: [panel], by a tab or by its [window]'s title bar;
/// at [x], [y] of the area, over the group [over] in [rect] (no group over
/// an area with none docked, no [rect] over no group), whose target for
/// [side] is under it, if any.
final class _Drag {
  _Drag(this.panel, {required this.window});

  final String panel;
  final bool window;

  var x = 0;
  var y = 0;
  _GroupState? over;
  _Rect? rect;
  DockSide? side;
}

/// A tab bar pressed: its selected panel and the cell of the screen
/// pressed.
typedef _Press = ({String panel, int x, int y});

final class _DockAreaState extends State<DockArea> {
  final _keys = <String, GlobalKey>{};
  final _windows = <String, WindowController>{};
  final _groups = <_GroupState>{};
  var _panels = <String, DockPanel>{};

  // while the area sets its windows' controllers from the layout
  var _syncing = false;

  _Press? _press;

  // the windows' cells as a press in one of them found them
  Map<String, _Rect>? _pressedWindows;

  _Drag? _drag;

  DockController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _fit();
  }

  @override
  void didUpdateWidget(DockArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_changed);
      _controller.addListener(_changed);
    }
    _fit();
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    for (final c in _windows.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The panels by their ids, the controller's layout without the others.
  void _fit() {
    final panels = widget.panels;
    _panels = {for (final p in panels) p.id: p};
    assert(_panels.length == panels.length, 'two panels share an id');
    _keys.removeWhere((id, _) => !_panels.containsKey(id));
    _controller._fit(_panels.keys.toSet());
  }

  void _changed() {
    _controller._fit(_panels.keys.toSet());
    setState(() {});
  }

  /// What shows [id]'s panel, under its key wherever it is.
  Widget _host(String id) => _Host(
    key: _keys.putIfAbsent(id, () => GlobalKey(debugLabel: id)),
    child: _panels[id]!.child,
  );

  String _title(String id) => _panels[id]!.title;

  // the cells of render objects

  RenderObject? get _area => context.findRenderObject();

  /// The cell of the screen at the top left of [o].
  static (int, int) _origin(RenderObject o) {
    var x = 0;
    var y = 0;
    for (var r = o; r.parent != null; r = r.parent!) {
      x += r.parentData.dx;
      y += r.parentData.dy;
    }
    return (x, y);
  }

  /// The cells of [group] in the area; null before it is laid out.
  _Rect? _rectOf(_GroupState group) {
    final area = _area;
    final o = group.context.findRenderObject();
    if (area == null || o == null) {
      return null;
    }
    final (ax, ay) = _origin(area);
    final (x, y) = _origin(o);
    return (left: x - ax, top: y - ay, width: o.width, height: o.height);
  }

  _Rect get _whole {
    final area = _area;
    return (
      left: 0,
      top: 0,
      width: area?.width ?? 0,
      height: area?.height ?? 0,
    );
  }

  // the drags

  void _tabDown(_GroupState group, PointerEvent event) {
    if (event.button != 0 || _drag != null) {
      return;
    }
    _press = (
      panel: group.widget.node.panels[group.selected],
      x: event.screenX,
      y: event.screenY,
    );
    MouseTracker.of(context)?.whenReleased(_released);
  }

  void _tabDrag(PointerEvent event) {
    final press = _press;
    if (_drag == null) {
      final tracker = MouseTracker.of(context);
      if (press == null ||
          tracker == null ||
          event.screenX == press.x && event.screenY == press.y) {
        return;
      }
      _press = null;
      if (!takeDrag(tracker, 0)) {
        return;
      }
      _drag = _Drag(press.panel, window: false);
    }
    if (_drag?.window == false) {
      _over(event);
    }
  }

  void _tabUp(PointerEvent event) {
    if (event.button == 0 && _drag?.window == false) {
      _drop(event);
    }
  }

  void _windowDown(PointerEvent event) {
    if (event.button != 0 || _drag != null) {
      return;
    }
    _pressedWindows = {
      for (final MapEntry(:key, value: c) in _windows.entries)
        key: (left: c.left, top: c.top, width: c.width, height: c.height),
    };
    MouseTracker.of(context)?.whenReleased(_released);
  }

  /// A window moved since the press, its size kept, is dragged by its
  /// title bar.
  void _windowDrag(PointerEvent event) {
    final pressed = _pressedWindows;
    if (_drag == null && pressed != null) {
      for (final MapEntry(key: panel, value: r) in pressed.entries) {
        final c = _windows[panel];
        if (c != null &&
            c.width == r.width &&
            c.height == r.height &&
            (c.left != r.left || c.top != r.top)) {
          _pressedWindows = null;
          _drag = _Drag(panel, window: true);
          break;
        }
      }
    }
    if (_drag?.window ?? false) {
      _over(event);
    }
  }

  void _windowUp(PointerEvent event) {
    if (event.button == 0 && (_drag?.window ?? false)) {
      _drop(event);
    }
  }

  /// The press ended: a drag whose release was lost docks nowhere.
  void _released() {
    _press = null;
    _pressedWindows = null;
    if (_drag != null && mounted) {
      setState(() => _drag = null);
    }
  }

  /// Finds the group the drag is over at [event] and its target there.
  void _over(PointerEvent event) {
    final drag = _drag!;
    final area = _area;
    if (area == null) {
      return;
    }
    final (ax, ay) = _origin(area);
    final x = event.screenX - ax;
    final y = event.screenY - ay;
    _GroupState? over;
    _Rect? rect;
    for (final g in _groups) {
      final panels = g.widget.node.panels;
      final r = _rectOf(g);
      if (r != null &&
          _contains(r, x, y) &&
          (drag.window || panels.length > 1 || panels.single != drag.panel)) {
        over = g;
        rect = r;
        break;
      }
    }
    if (rect == null && _controller.layout.root == null) {
      rect = _whole;
    }
    DockSide? side;
    if (rect != null) {
      for (final (s, r) in _targets(rect, all: over != null)) {
        if (_contains(r, x, y)) {
          side = s;
        }
      }
    }
    setState(() {
      drag
        ..x = x
        ..y = y
        ..over = over
        ..rect = rect
        ..side = side;
    });
  }

  void _drop(PointerEvent event) {
    _over(event);
    final drag = _drag!;
    setState(() => _drag = null);
    final side = drag.side;
    if (side != null) {
      final anchor = drag.over?.widget.node.panels.firstWhere(
        (p) => p != drag.panel,
        orElse: () => drag.panel,
      );
      _controller.dock(
        drag.panel,
        beside: anchor == drag.panel ? null : anchor,
        side: side,
      );
    } else if (!drag.window) {
      final whole = _whole;
      _controller.float(
        drag.panel,
        left: drag.x - 1,
        top: drag.y,
        width: whole.width ~/ 2,
        height: whole.height ~/ 2,
      );
    }
  }

  /// The targets of a group in [rect], a cell tall and three wide in a
  /// cross in its middle; the middle one alone without [all].
  static List<(DockSide, _Rect)> _targets(_Rect rect, {required bool all}) {
    final x = rect.left + rect.width ~/ 2 - 1;
    final y = rect.top + rect.height ~/ 2;
    _Rect at(int dx, int dy) =>
        (left: x + dx, top: y + dy, width: 3, height: 1);
    return [
      if (all) ...[
        (DockSide.left, at(-3, 0)),
        (DockSide.right, at(3, 0)),
        (DockSide.top, at(0, -1)),
        (DockSide.bottom, at(0, 1)),
      ],
      (DockSide.center, at(0, 0)),
    ];
  }

  /// The cells of [r] that a panel docked on [side] of it takes.
  static _Rect _taken(_Rect r, DockSide side) {
    final w = r.width ~/ 2;
    final h = r.height ~/ 2;
    return switch (side) {
      DockSide.left => (left: r.left, top: r.top, width: w, height: r.height),
      DockSide.right => (
        left: r.left + r.width - w,
        top: r.top,
        width: w,
        height: r.height,
      ),
      DockSide.top => (left: r.left, top: r.top, width: r.width, height: h),
      DockSide.bottom => (
        left: r.left,
        top: r.top + r.height - h,
        width: r.width,
        height: h,
      ),
      DockSide.center => r,
    };
  }

  static const Map<DockSide, String> _glyphs = {
    DockSide.left: '◀',
    DockSide.right: '▶',
    DockSide.top: '▲',
    DockSide.bottom: '▼',
    DockSide.center: '■',
  };

  // the build

  @override
  Widget build(BuildContext context) {
    final layout = _controller.layout;
    final root = layout.root;
    final drag = _drag;
    return Stack(
      fit: StackFit.expand,
      children: [
        WindowLayer(
          frame: widget.windowFrame,
          windows: _floating(layout.windows),
          decorate: (context, window) => Listener(
            onDown: _windowDown,
            onDrag: _windowDrag,
            onUp: _windowUp,
            child: window,
          ),
          child: root == null ? const SizedBox.expand() : _node(root, const []),
        ),
        if (drag != null) ..._dragged(Theme.of(context), drag),
      ],
    );
  }

  /// The windows of [windows], their controllers set from them.
  List<Window> _floating(List<DockWindow> windows) {
    final shown = {for (final w in windows) w.panel};
    _windows.removeWhere((panel, c) {
      if (shown.contains(panel)) {
        return false;
      }
      // the layer lets it go in this frame's build, after this one
      c.dispose();
      return true;
    });
    _syncing = true;
    try {
      return [
        for (final w in windows)
          Window(
            key: ValueKey<String>(w.panel),
            title: _title(w.panel),
            controller: _windowOf(w),
            child: _host(w.panel),
          ),
      ];
    } finally {
      _syncing = false;
    }
  }

  WindowController _windowOf(DockWindow w) {
    final c = _windows[w.panel];
    if (c == null) {
      return _windows[w.panel] = WindowController(
        left: w.left,
        top: w.top,
        width: w.width,
        height: w.height,
      )..addListener(() => _windowMoved(w.panel));
    }
    c
      ..moveTo(w.left, w.top)
      ..resizeTo(w.width, w.height);
    return c;
  }

  void _windowMoved(String panel) {
    final c = _windows[panel];
    if (!_syncing && c != null) {
      _controller._moved(panel, c.left, c.top, c.width, c.height);
    }
  }

  Widget _node(DockNode node, List<int> path) => switch (node) {
    DockTabs() => _Group(this, node),
    DockSplit(:final children) => _Split(this, node, path, [
      for (var i = 0; i < children.length; i++)
        _node(children[i], [...path, i]),
    ]),
  };

  /// What a drag shows over the area: the cells the panel would take,
  /// outlined with its title on the top edge, and the targets; for a tab
  /// over no target, the chip with its title.
  List<Widget> _dragged(ThemeData theme, _Drag drag) {
    final rect = drag.rect;
    final side = drag.side;
    final target = theme.surface.merge(theme.primary);
    final hovered = theme
        .fill(theme.primary.fg)
        .merge(const Style(attrs: Attr.bold));
    Widget place(_Rect r, Widget child) => Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: child,
    );
    return [
      if (rect != null && side != null)
        place(
          _taken(rect, side),
          Box(
            border: Border.all(type: BorderType.double, style: theme.primary),
            titles: [
              BorderTitle(' ${_title(drag.panel)} ', style: theme.primary),
            ],
          ),
        ),
      if (rect != null)
        for (final (s, r) in _targets(rect, all: drag.over != null))
          place(
            r,
            Text(
              ' ${_glyphs[s]} ',
              style: s == side ? hovered : target,
              wrap: TextWrap.none,
            ),
          ),
      if (!drag.window && side == null)
        Positioned(
          left: drag.x + 1,
          top: drag.y + 1,
          child: Text(
            ' ${_title(drag.panel)} ',
            style: theme.selection.merge(theme.text),
            wrap: TextWrap.none,
          ),
        ),
    ];
  }
}

/// A panel's child under its key.
final class _Host extends StatelessWidget {
  const _Host({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A group of tabs: its tab bar over its panels.
final class _Group extends StatefulWidget {
  const _Group(this.area, this.node);

  final _DockAreaState area;
  final DockTabs node;

  @override
  State<_Group> createState() => _GroupState();
}

final class _GroupState extends State<_Group> {
  late TabController _tabs = _make();

  // while the group sets its tab from the layout
  var _syncing = false;

  int get selected => _tabs.index;

  TabController _make() => TabController(
    length: widget.node.panels.length,
    initialIndex: widget.node.selected,
  )..addListener(_selected);

  @override
  void initState() {
    super.initState();
    widget.area._groups.add(this);
  }

  @override
  void didUpdateWidget(_Group oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.area, oldWidget.area)) {
      oldWidget.area._groups.remove(this);
      widget.area._groups.add(this);
    }
    final node = widget.node;
    if (node.panels.length != _tabs.length) {
      // the tab bar and the view let it go in this frame's build
      _tabs.dispose();
      _tabs = _make();
    } else if (node.selected != _tabs.index) {
      _syncing = true;
      _tabs.index = node.selected;
      _syncing = false;
    }
  }

  @override
  void dispose() {
    widget.area._groups.remove(this);
    _tabs.dispose();
    super.dispose();
  }

  void _selected() {
    if (!_syncing) {
      widget.area._controller.select(widget.node.panels[_tabs.index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.area;
    final panels = widget.node.panels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Listener(
          onDown: (event) => area._tabDown(this, event),
          onDrag: area._tabDrag,
          onUp: area._tabUp,
          child: area.widget.tabStrip
              ? TabBar.strip(
                  controller: _tabs,
                  tabs: [for (final p in panels) area._title(p)],
                )
              : TabBar(
                  controller: _tabs,
                  tabs: [for (final p in panels) area._title(p)],
                ),
        ),
        Expanded(
          child: TabView(
            controller: _tabs,
            children: [for (final p in panels) area._host(p)],
          ),
        ),
      ],
    );
  }
}

/// A split of the layout: a [SplitView] of its children, whose dividers
/// set its shares in the layout.
final class _Split extends StatefulWidget {
  const _Split(this.area, this.node, this.path, this.children);

  final _DockAreaState area;
  final DockSplit node;

  /// The indices of the children down to it from the root.
  final List<int> path;

  final List<Widget> children;

  @override
  State<_Split> createState() => _SplitState();
}

final class _SplitState extends State<_Split> {
  late SplitController _split = _make();

  // while the split sets its shares from the layout
  var _syncing = false;

  SplitController _make() =>
      SplitController(fractions: widget.node.fractions)..addListener(_resized);

  @override
  void didUpdateWidget(_Split oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fractions = widget.node.fractions;
    if (fractions.length != oldWidget.node.fractions.length) {
      // the view lets it go in this frame's build
      _split.dispose();
      _split = _make();
    } else {
      _syncing = true;
      _split.fractions = fractions;
      _syncing = false;
    }
  }

  @override
  void dispose() {
    _split.dispose();
    super.dispose();
  }

  void _resized() {
    if (!_syncing) {
      widget.area._controller._resized(widget.path, _split.fractions);
    }
  }

  @override
  Widget build(BuildContext context) {
    final across = widget.node.direction == Axis.horizontal;
    return SplitView(
      direction: widget.node.direction,
      controller: _split,
      style: Theme.of(context).border,
      panes: [
        for (final child in widget.children)
          SplitPane(minSize: across ? 4 : 2, child: child),
      ],
    );
  }
}
