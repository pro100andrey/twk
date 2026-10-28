/// Sections that fold: [ExpansionTile], a header that shows or hides what
/// is below it, the [ExpansionController] that holds whether it does, and
/// [Accordion], tiles one below another of which one is open at a time.
library;

import 'package:twk_core/twk_core.dart'
    show
        BoxConstraints,
        DiagnosticPropertiesBuilder,
        EdgeInsets,
        PaintContext,
        RenderObject,
        RenderObjectWithChildMixin,
        TextWrap;

import '../animation/animation_controller.dart';
import '../animation/curves.dart';
import '../animation/ticker.dart';
import '../binding/app_binding.dart';
import '../controls/pressable.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'basic.dart';
import 'box.dart';
import 'flex.dart';
import 'one_child.dart';

/// Whether an [ExpansionTile] shows what is below its header: [expanded],
/// which [expand], [collapse] and [toggle] change, telling the listeners
/// each time it does.
///
/// The app keeps one to open or close a section from elsewhere, and to
/// know whether it is open; a tile given none keeps one of its own.
///
/// A section opened from a key of the app's own:
///
/// ```dart
/// final details = ExpansionController();
/// final tile = ExpansionTile(
///   controller: details,
///   title: const Text('Details'),
///   child: const Text('Size: 4 KiB'),
/// );
/// // on `d`:
/// details.toggle();
/// ```
final class ExpansionController extends ChangeNotifier {
  /// A controller that is [expanded] from the start, or not.
  ExpansionController({this._expanded = false});

  bool _expanded;

  /// Whether the tile shows what is below its header. Set to another
  /// value, it tells the listeners.
  bool get expanded => _expanded;

  set expanded(bool value) {
    if (value != _expanded) {
      _expanded = value;
      notifyListeners();
    }
  }

  /// Shows what is below the header.
  void expand() => expanded = true;

  /// Hides what is below the header.
  void collapse() => expanded = false;

  /// Shows what is below the header if it is hidden, hides it if it is
  /// shown.
  void toggle() => expanded = !_expanded;
}

/// A header of [title] that shows [child] below it, [indent] cells in,
/// while it is expanded, and hides it while it is collapsed.
///
/// ```text
/// ▶ Advanced Network Options
/// ▼ Security Settings
///   ┌──────────────────────────────┐
///   │ TLS Version: 1.3  Verify: [x]│
///   └──────────────────────────────┘
/// ```
///
/// The header is a row: `▶` while collapsed, `▼` while expanded, then
/// [title] with [subtitle] below it in [ThemeData.muted], and [trailing]
/// (a count, a badge) at its right end. It is one stop of the focus:
/// Enter or Space toggles it (Enter hinted), Right expands it and Left
/// collapses it; Right on one expanded and Left on one collapsed pass on.
/// A click on it toggles it, and focuses it. In an [Accordion] Up and Down
/// go to the header above and below.
///
/// [child] is built only while it is expanded and while it folds: it
/// unfolds from the header down in [duration], a row at a time, and folds
/// back up the same way; a [duration] of zero, or outside an app, it is
/// shown or hidden at once. A focus in [child] as it collapses goes to the
/// header, and Tab passes what is folding by.
///
/// Whether it is expanded is its [controller]'s, or one of its own that
/// starts as [initiallyExpanded] says; [onExpansionChanged] is told each
/// time it changes, by a key, a click or the controller.
///
/// A section of settings, open at the start:
///
/// ```dart
/// ExpansionTile(
///   initiallyExpanded: true,
///   title: const Text('Security Settings'),
///   trailing: const Text('2'),
///   child: Checkbox(value: true, onChanged: (_) {}, label: 'Verify'),
/// )
/// ```
///
/// The styles of the header, each merged over those before it: the
/// theme's text and [headerStyle]; [expandedHeaderStyle] while it is
/// expanded, nothing when null; [hoverStyle] while the mouse is over it
/// and it has not the focus, [ThemeData.surface]'s background when null;
/// the theme's [ThemeData.selection] while it has the focus. The marker is
/// in [ThemeData.muted] while collapsed, [ThemeData.primary] while
/// expanded.
///
/// A screen reader reads the header as a [SemanticsRole.button] of what it
/// shows but the marker, `expanded` or `collapsed`.
///
/// See also:
///
///  * [Accordion], tiles of which one is open at a time.
///  * `TreeView`, a tree of nodes that open and close.
final class ExpansionTile extends StatefulWidget {
  /// A header of [title] that shows [child] while it is expanded.
  const ExpansionTile({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.trailing,
    this.initiallyExpanded = false,
    this.controller,
    this.onExpansionChanged,
    this.duration = const Duration(milliseconds: 150),
    this.indent = 2,
    this.focusNode,
    this.headerStyle,
    this.expandedHeaderStyle,
    this.hoverStyle,
  }) : assert(indent >= 0, 'an indent of 0 or more');

  /// What the header says, after its marker.
  final Widget title;

  /// What is shown below the header while it is expanded; built only then
  /// and while it folds.
  final Widget child;

  /// Below [title], in [ThemeData.muted]; null for none.
  final Widget? subtitle;

  /// At the right end of the header, a cell after the title: a count, a
  /// badge; null for none.
  final Widget? trailing;

  /// Whether a tile with no [controller] is expanded at the start; in an
  /// [Accordion], the accordion reads it.
  final bool initiallyExpanded;

  /// Holds whether it is expanded; null for one of its own.
  final ExpansionController? controller;

  /// Called with whether it is expanded each time that changes; null for
  /// nothing.
  final void Function(bool expanded)? onExpansionChanged;

  /// How long it takes to unfold or fold; zero for at once.
  final Duration duration;

  /// How many cells [child] is in from the left edge of the header: 2 by
  /// default, under the title.
  final int indent;

  /// The header's node of the focus tree; null for one of its own.
  final FocusNode? focusNode;

  /// The header, over the theme's text.
  final Style? headerStyle;

  /// The header while it is expanded, over [headerStyle]; null for
  /// nothing.
  final Style? expandedHeaderStyle;

  /// The header while the mouse is over it and it has not the focus;
  /// [ThemeData.surface]'s background when null. `const Style()` for no
  /// hover, and then it asks the terminal for no motion of the mouse.
  final Style? hoverStyle;

  @override
  State<ExpansionTile> createState() => _ExpansionTileState();
}

final class _ExpansionTileState extends State<ExpansionTile>
    with TickerProviderStateMixin {
  ExpansionController? _ownController;
  FocusNode? _ownNode;
  late ExpansionController _controller;
  late final AnimationController _fold;

  // the node above what is below the header, which takes no focus itself
  final _body = FocusNode(debugLabel: 'expansion body');

  // what the controller said when it last told this tile
  late bool _expanded;
  var _hovered = false;

  /// The [Accordion]'s slot this tile is the child of, if it is one's: a
  /// tile in a section of one of its tiles is no tile of it.
  _AccordionSlot? get _slot {
    _AccordionSlot? slot;
    context.visitAncestorElements((element) {
      final w = element.widget;
      if (w is _AccordionSlot) {
        slot = w;
      }
      return false;
    });
    return slot;
  }

  FocusNode get _header =>
      widget.focusNode ?? _slot?.focusNode ?? (_ownNode ??= FocusNode());

  ExpansionController _given() =>
      widget.controller ??
      _slot?.controller ??
      (_ownController ??= ExpansionController(
        expanded: widget.initiallyExpanded,
      ));

  @override
  void initState() {
    super.initState();
    _controller = _given()..addListener(_changed);
    _expanded = _controller.expanded;
    _fold = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: _expanded ? 1 : 0,
    )..addListener(_folded);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // rebuilt with the slot, whose controller and node may change
    if (_slot != null) {
      context.dependOnInheritedWidgetOfExactType<_AccordionSlot>();
    }
    _attach();
  }

  @override
  void didUpdateWidget(ExpansionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fold.duration = widget.duration;
    _attach();
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _ownController?.dispose();
    _ownNode?.dispose();
    _body.dispose();
    _fold.dispose();
    super.dispose();
  }

  /// Listens to the controller it now has, if that is another: shown as
  /// that one says at once, nobody told.
  void _attach() {
    final given = _given();
    if (identical(given, _controller)) {
      return;
    }
    _controller.removeListener(_changed);
    _controller = given..addListener(_changed);
    if (given.expanded != _expanded) {
      _expanded = given.expanded;
      _fold.value = _expanded ? 1 : 0;
    }
  }

  void _changed() {
    final expanded = _controller.expanded;
    if (expanded == _expanded) {
      return;
    }
    if (!expanded && _body.hasFocus) {
      _header.requestFocus();
    }
    setState(() => _expanded = expanded);
    final to = expanded ? 1.0 : 0.0;
    if (widget.duration <= Duration.zero ||
        AppBinding.maybeOf(context) == null) {
      _fold.value = to;
    } else if (expanded) {
      _fold.forward();
    } else {
      _fold.reverse();
    }
    widget.onExpansionChanged?.call(expanded);
  }

  void _folded() => setState(() {});

  void _hover(bool hovered) {
    if (hovered != _hovered) {
      setState(() => _hovered = hovered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _expanded;
    final controller = _controller;
    final slot = _slot;
    final header = Pressable(
      focusNode: _header,
      bindings: {
        'enter': controller.toggle,
        'space': controller.toggle,
        'right': expanded ? null : controller.expand,
        'left': expanded ? controller.collapse : null,
        'up': slot?.up,
        'down': slot?.down,
      },
      hints: {'enter': expanded ? 'collapse' : 'expand'},
      onTap: (_) => controller.toggle(),
      builder: _buildHeader,
    );
    final shown = _fold.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          role: SemanticsRole.button,
          state: SemanticsState(expanded: expanded),
          child: header,
        ),
        if (expanded || shown > 0)
          _Fold(
            shown: Curves.easeOut.transform(shown),
            child: Padding(
              padding: EdgeInsets.only(left: widget.indent),
              child: Focus(
                focusNode: _body,
                canRequestFocus: false,
                skipTraversal: true,
                descendantsAreFocusable: expanded,
                child: widget.child,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool focused) {
    final theme = Theme.of(context);
    final expanded = _expanded;
    var style = theme.text.merge(widget.headerStyle ?? const Style());
    if (expanded) {
      style = style.merge(widget.expandedHeaderStyle ?? const Style());
    }
    final hover = widget.hoverStyle ?? theme.hover;
    final hovers = hover != const Style();
    if (focused) {
      style = style.merge(focusedRow(theme));
    } else if (hovers && _hovered) {
      style = style.merge(hover);
    }
    final subtitle = widget.subtitle;
    final trailing = widget.trailing;
    Widget row = Box(
      style: style,
      child: DefaultTextStyle(
        style: style,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Text(
                expanded ? '▼ ' : '▶ ',
                style: expanded ? theme.primary : theme.muted,
                wrap: TextWrap.none,
                maxLines: 1,
              ),
            ),
            Expanded(
              child: subtitle == null
                  ? widget.title
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.title,
                        DefaultTextStyle(style: theme.muted, child: subtitle),
                      ],
                    ),
            ),
            if (trailing != null)
              Padding(padding: const EdgeInsets.only(left: 1), child: trailing),
          ],
        ),
      ),
    );
    if (hovers) {
      row = MouseRegion(
        onEnter: (_) => _hover(true),
        onExit: (_) => _hover(false),
        child: row,
      );
    }
    return row;
  }
}

/// [child] laid out as tall as it is, showing [shown] of its rows from the
/// top, 0 to 1, the rest cut off; as wide as it is.
final class _Fold extends SingleChildRenderObjectWidget {
  const _Fold({required this.shown, super.child});

  final double shown;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderFold createRenderObject(BuildContext context) => _RenderFold(shown);

  @override
  void updateRenderObject(BuildContext context, _RenderFold renderObject) =>
      renderObject.shown = shown;
}

/// What a [_Fold] lays out and paints.
final class _RenderFold extends RenderObject with RenderObjectWithChildMixin {
  _RenderFold(this._shown);

  double _shown;
  double get shown => _shown;
  set shown(double s) {
    if (s != _shown) {
      _shown = s;
      markNeedsLayout();
    }
  }

  int _rows(int h) => (h * _shown).round().clamp(0, h);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('shown', _shown, defaultValue: 1.0);
  }

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(
      BoxConstraints(c.minW, c.maxW, 0, c.maxH),
      parentUsesSize: true,
    );
    width = c.constrainW(child.width);
    height = c.constrainH(_rows(child.height));
    child.parentData
      ..dx = 0
      ..dy = 0;
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      _rows(child?.getMinIntrinsicHeight(width) ?? 0);

  @override
  int computeMaxIntrinsicHeight(int width) =>
      _rows(child?.getMaxIntrinsicHeight(width) ?? 0);

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}

/// [children], [ExpansionTile]s, one below another, of which one is
/// expanded at a time unless [allowMultiple]: expanding one collapses
/// the one that was.
///
/// Up and Down on a header go to the header above and below. A tile with
/// no controller of its own has one of the accordion's, expanded at the
/// start where it is the [initiallyExpanded]th, or where none is given
/// and it is the first that says [ExpansionTile.initiallyExpanded]; with
/// [allowMultiple], every tile that says it. A tile with a controller
/// keeps it, the accordion collapsing it as any other.
///
/// Three sections of settings, the second open:
///
/// ```dart
/// Accordion(
///   initiallyExpanded: 1,
///   children: const [
///     ExpansionTile(title: Text('General'), child: Text('…')),
///     ExpansionTile(title: Text('Network'), child: Text('…')),
///     ExpansionTile(title: Text('Security'), child: Text('…')),
///   ],
/// )
/// ```
final class Accordion extends StatefulWidget {
  /// The tiles of [children], one expanded at a time unless
  /// [allowMultiple].
  const Accordion({
    required this.children,
    super.key,
    this.allowMultiple = false,
    this.initiallyExpanded,
  });

  /// The tiles, from the top.
  final List<ExpansionTile> children;

  /// Whether several tiles can be expanded at once; false: expanding one
  /// collapses the others.
  final bool allowMultiple;

  /// The index of the tile expanded at the start; null for those that
  /// say so ([ExpansionTile.initiallyExpanded]).
  final int? initiallyExpanded;

  @override
  State<Accordion> createState() => _AccordionState();
}

final class _AccordionState extends State<Accordion> {
  // the accordion's own, by index, for the tiles with none; kept until it
  // goes, the tiles that had them disposing of their elements first
  final _ownControllers = <ExpansionController?>[];
  final _ownNodes = <FocusNode?>[];

  // the controllers listened to, by index, and their listeners
  final _listened = <ExpansionController>[];
  final _listeners = <VoidCallback>[];

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Accordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _unlisten();
    for (final c in _ownControllers) {
      c?.dispose();
    }
    for (final n in _ownNodes) {
      n?.dispose();
    }
    super.dispose();
  }

  void _unlisten() {
    for (var i = 0; i < _listened.length; i++) {
      _listened[i].removeListener(_listeners[i]);
    }
    _listened.clear();
    _listeners.clear();
  }

  ExpansionController _controllerOf(int i) =>
      widget.children[i].controller ?? _ownControllers[i]!;

  FocusNode _nodeOf(int i) =>
      widget.children[i].focusNode ??
      (_ownNodes[i] ??= FocusNode(debugLabel: 'accordion header $i'));

  /// Gives each tile with no controller one of the accordion's, and
  /// listens to the controller of each.
  void _sync() {
    final tiles = widget.children;
    while (_ownControllers.length < tiles.length) {
      _ownControllers.add(null);
      _ownNodes.add(null);
    }
    var open = false;
    for (var i = 0; i < tiles.length; i++) {
      final given = tiles[i].controller;
      if (given != null) {
        open |= given.expanded;
        continue;
      }
      final own = _ownControllers[i];
      if (own != null) {
        open |= own.expanded;
        continue;
      }
      final first = widget.initiallyExpanded;
      final expanded =
          (first != null ? i == first : tiles[i].initiallyExpanded) &&
          (widget.allowMultiple || !open);
      open |= expanded;
      _ownControllers[i] = ExpansionController(expanded: expanded);
    }
    _unlisten();
    for (var i = 0; i < tiles.length; i++) {
      final c = _controllerOf(i);
      void listener() => _changed(c);
      _listened.add(c..addListener(listener));
      _listeners.add(listener);
    }
  }

  /// [c] changed: expanded, the others collapse unless
  /// [Accordion.allowMultiple].
  void _changed(ExpansionController c) {
    if (widget.allowMultiple || !c.expanded) {
      return;
    }
    for (final other in List.of(_listened)) {
      if (!identical(other, c)) {
        other.collapse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tiles = widget.children;
    final last = tiles.length - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i <= last; i++)
          _AccordionSlot(
            tile: tiles[i],
            controller: _controllerOf(i),
            focusNode: _nodeOf(i),
            up: i > 0 ? _nodeOf(i - 1).requestFocus : null,
            down: i < last ? _nodeOf(i + 1).requestFocus : null,
          ),
      ],
    );
  }
}

/// What an [Accordion] gives [tile], its child: the controller and the
/// header's node it has unless it has its own, and the moves to the
/// headers above and below.
final class _AccordionSlot extends InheritedWidget {
  const _AccordionSlot({
    required this.tile,
    required this.controller,
    required this.focusNode,
    required this.up,
    required this.down,
  }) : super(child: tile);

  final ExpansionTile tile;
  final ExpansionController controller;
  final FocusNode focusNode;
  final VoidCallback? up;
  final VoidCallback? down;

  @override
  bool updateShouldNotify(_AccordionSlot oldWidget) =>
      !identical(controller, oldWidget.controller) ||
      !identical(focusNode, oldWidget.focusNode) ||
      up != oldWidget.up ||
      down != oldWidget.down;
}
