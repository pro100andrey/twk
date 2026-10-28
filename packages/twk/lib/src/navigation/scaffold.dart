/// An app's frame: a [Scaffold] of a header, a sidebar beside the body, a
/// status bar and the key hints, each part a zone of the focus, and the
/// [ScaffoldController] that shows, hides and sizes its sidebar.
library;

import 'package:twk_core/twk_core.dart'
    show BoxConstraints, CrossAxisAlignment, EdgeInsets, HitTestBehavior;

import '../binding/app_binding.dart';
import '../controls/key_hints.dart';
import '../controls/status_bar.dart' show StatusBar;
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../style/style.dart';
import '../text/widgets.dart';

/// The side of the body a [Scaffold]'s sidebar is on.
enum SidebarSide {
  /// Before the body, at the left edge.
  left,

  /// After the body, at the right edge.
  right,
}

/// A zone of the focus of a [Scaffold]: one of its parts.
enum ScaffoldZone {
  /// The header rows.
  header,

  /// The sidebar.
  sidebar,

  /// The body.
  body,

  /// The status bar.
  statusBar,
}

/// Whether the sidebar of a [Scaffold] is shown and how wide it is: what
/// an app sets to show, hide or size it, and saves to show it as it was.
/// The header's toggle, Ctrl+B and a resize by the mouse or the keys set
/// it too. It notifies its listeners of each change; one the screen's
/// width crossing the scaffold's `collapsedBelow` makes is told at the
/// start of the next frame. It is given to one scaffold at a time.
///
/// A sidebar that the app shows from the start, and hides from a button
/// of its own:
///
/// ```dart
/// final controller = ScaffoldController(sidebarOpen: true);
/// final scaffold = Scaffold(
///   controller: controller,
///   sidebar: Text('Files'),
///   body: Button('Hide the files', onPressed: controller.toggleSidebar),
/// );
/// ```
final class ScaffoldController extends ChangeNotifier {
  /// A sidebar [sidebarWidth] columns wide, shown or hidden as
  /// [sidebarOpen] says, as the screen's width has it when null.
  ScaffoldController({bool? sidebarOpen, int sidebarWidth = 24})
    : assert(sidebarWidth >= 0, 'a sidebarWidth of 0 or more'),
      _choice = sidebarOpen,
      _width = sidebarWidth;

  // shown or hidden by the app or the user, null as the width has it
  bool? _choice;

  // whether the screen was narrower than collapsedBelow at the last
  // layout; null before the first
  bool? _narrow;

  int _width;

  _ScaffoldState? _state;

  /// Whether the sidebar is shown: as the app or the user set it last,
  /// else as the screen's width has it, hidden below the scaffold's
  /// `collapsedBelow`. The width crossing it puts it back as the width has
  /// it. Set, it shows or hides the sidebar at any width; hidden while it
  /// has the focus, the focus goes back to the zone it came from.
  bool get sidebarOpen => _choice ?? !(_narrow ?? false);

  set sidebarOpen(bool value) {
    if (value != _choice) {
      _choose(value);
    }
  }

  /// Hides a shown sidebar and shows a hidden one, as the header's `≡`
  /// does.
  void toggleSidebar() => sidebarOpen = !sidebarOpen;

  /// The sidebar's columns, cut to the screen's width where it is wider.
  /// A drag of its divider and the keys that resize it set it; set, a
  /// [RangeError] for one below 0.
  int get sidebarWidth => _width;

  set sidebarWidth(int value) {
    RangeError.checkNotNegative(value, 'sidebarWidth');
    if (value != _width) {
      _width = value;
      notifyListeners();
    }
  }

  /// The zone that has the focus; null when none has it, or before the
  /// controller is given to a scaffold.
  ScaffoldZone? get focusedZone => _state?._focusedZone;

  /// Moves the focus to [zone], where it was in it last, else to its first
  /// node, as F6 does; the sidebar shown when it is hidden, as Ctrl+B does,
  /// whose way back hides it again. Whether the scaffold has the zone and
  /// moved the focus to it; false before the controller is given to one.
  bool focusZone(ScaffoldZone zone) => _state?._focusZone(zone) ?? false;

  /// Tells the listeners of a change the screen's width made.
  void _tell() => notifyListeners();

  /// Sets the choice to [choice], telling the listeners when that shows or
  /// hides the sidebar.
  void _choose(bool? choice) {
    final was = sidebarOpen;
    _choice = choice;
    if (sidebarOpen != was) {
      notifyListeners();
    }
  }
}

/// The frame most full-screen apps are built in: [header] rows on top,
/// [sidebar] beside [body] under them, the [statusBar] row and the key
/// hints (a [KeyHintsBar], with [keyHints]) at the bottom. Each part is
/// optional but the body, which takes the rows and columns the others
/// leave.
///
/// The header, the sidebar and the hints are drawn on the theme's chrome
/// ([ThemeData.chrome]), the header and the hints two columns in from the
/// sides; the body on its background, and the whole in its text color
/// ([DefaultTextStyle]). The status bar draws itself, as a [StatusBar]
/// does on the surface.
///
/// The sidebar is [sidebarWidth] columns wide, on the [sidebarSide] of the
/// body; with a [controller], as wide as it says
/// ([ScaffoldController.sidebarWidth]), which also shows and hides it.
/// Below [collapsedBelow] columns it is collapsed: it gets no columns, is
/// not painted, hit by the mouse or focusable, and keeps its
/// state for when it is shown again. Ctrl+B or a press of the `≡` the
/// header shows at the sidebar's side shows a collapsed sidebar and hides
/// a shown one, at any width; the screen's width crossing [collapsedBelow]
/// puts it back as the width has it. With [resizableSidebar] a divider is
/// between the sidebar and the body, and the left button dragging it
/// makes the sidebar wider or narrower, between 4 columns and all but 10
/// of the screen's ([onSidebarResized] is told the width a drag leaves);
/// the pointer over it has the shape of a resize, and while the mouse is
/// over it or drags it, it is drawn in the theme's primary color. While
/// the sidebar has the focus, Alt+, and Alt+. move the divider too.
///
/// Each part but the hints is a zone of the focus, a [FocusScope]: Tab and
/// Shift+Tab move the focus among the nodes of the zone it is in, and a
/// zone left gets the focus back where it had it. The keys of the frame,
/// in a [KeyBindings] layer around it, which the hints show:
///
/// * F6 moves the focus to the next zone that has a node to focus, in the
///   order they are on the screen (the header, the sidebar and the body as
///   they are from left to right, the status bar), Shift+F6 to the one
///   before; from the last to the first and round.
/// * Ctrl+B goes to the sidebar, showing it when it is collapsed, and from
///   the sidebar back to the zone the focus came from, collapsing it again
///   if Ctrl+B showed it.
/// * Alt+, and Alt+. move the divider of a [resizableSidebar] a column to
///   the left and to the right while the sidebar has the focus: narrower
///   and wider on the left, wider and narrower on the right, between the
///   bounds of a drag; [onSidebarResized] is told each width. Not the
///   arrows with Ctrl or Alt, which move the caret by words in a text
///   field, nor `Alt+[` and `Alt+]`, whose bytes start a CSI and an OSC on a
///   terminal that does not report keys unambiguously; Alt with a letter
///   is a `MenuBar`'s. The divider takes no focus, which would make it a
///   stop of Tab's in the sidebar's zone.
///
/// Keys a node of the parts binds come first; the frame's are left to the
/// layers around it where it has no sidebar (Ctrl+B) or one zone (F6).
/// With nothing focused after the first frame, the frame focuses the
/// first node of the body, else of the sidebar, the header or the status
/// bar; a node that asked for the focus (autofocus), in it or anywhere
/// else in the app, gets it instead.
///
/// A mail client's frame: a title on top, the folders beside the list of
/// messages, which hide on a screen narrower than 60 columns, and a status
/// row:
///
/// ```dart
/// Scaffold(
///   header: Text('Mail'),
///   sidebar: Column(children: [Text('Inbox'), Text('Sent')]),
///   collapsedBelow: 60,
///   resizableSidebar: true,
///   body: Text('No messages'),
///   statusBar: StatusBar(left: Text('connected'), right: Text('0 unread')),
/// )
/// ```
final class Scaffold extends StatefulWidget {
  /// The frame of [body] and of the parts given around it.
  const Scaffold({
    required this.body,
    super.key,
    this.header,
    this.sidebar,
    this.statusBar,
    this.keyHints = true,
    this.sidebarWidth = 24,
    this.sidebarSide = SidebarSide.left,
    this.resizableSidebar = false,
    this.collapsedBelow,
    this.onSidebarResized,
    this.controller,
  }) : assert(sidebarWidth >= 0, 'a sidebarWidth of 0 or more');

  /// What the app is about, under the header and beside the sidebar.
  final Widget body;

  /// The rows on top: as many as it is tall.
  final Widget? header;

  /// Beside the body, as tall as it.
  final Widget? sidebar;

  /// The row under the body, a [StatusBar] most often: as many as it is
  /// tall.
  final Widget? statusBar;

  /// Whether a [KeyHintsBar] is the bottom row.
  final bool keyHints;

  /// The sidebar's columns, until a drag or a key changes them; a new
  /// width resets them. Cut to the screen's width. Unused with a
  /// [controller], whose width is the sidebar's.
  final int sidebarWidth;

  /// The side of the body the sidebar is on.
  final SidebarSide sidebarSide;

  /// Whether the left button dragging the divider between the sidebar and
  /// the body resizes the sidebar.
  final bool resizableSidebar;

  /// The fewest columns of the screen that show the sidebar without Ctrl+B
  /// or the header's toggle; null shows it at any width.
  final int? collapsedBelow;

  /// Told the sidebar's columns at the end of a drag that changed them,
  /// and at each key that did.
  final void Function(int width)? onSidebarResized;

  /// Shows, hides and sizes the sidebar, and moves the focus between the
  /// zones; null, the scaffold makes its own, of [sidebarWidth].
  final ScaffoldController? controller;

  /// The fewest columns a drag leaves the sidebar.
  static const minSidebarWidth = 4;

  /// The fewest columns a drag leaves the body.
  static const minBodyWidth = 10;

  @override
  State<Scaffold> createState() => _ScaffoldState();
}

final class _ScaffoldState extends State<Scaffold> {
  final FocusScopeNode _header = _zone('header');
  final FocusScopeNode _sidebar = _zone('sidebar');
  final FocusScopeNode _body = _zone('body');
  final FocusScopeNode _status = _zone('status bar');

  /// A zone: Tab does not stop at the scope itself, which F6 enters.
  static FocusScopeNode _zone(String part) =>
      FocusScopeNode(debugLabel: 'scaffold $part', skipTraversal: true);

  // the zone other than the sidebar that had the focus last, where Ctrl+B
  // goes back to
  FocusScopeNode? _last;
  var _inSidebar = false;

  // the scaffold's own controller, without the widget's
  ScaffoldController? _own;
  late ScaffoldController _controller;

  // whether the controller had the sidebar open when it last told it,
  // which a change of only its width leaves
  var _seenOpen = false;

  // whether Ctrl+B showed the sidebar, which its way back hides again,
  // putting back the choice it was hidden by
  var _revealed = false;
  bool? _revealedFrom;

  // whether the sidebar was shown at the last layout, and the screen's
  // columns then
  var _open = false;
  var _screen = 80;

  // the screen's column and the sidebar's width at a press of the divider
  (int, int)? _grip;
  var _hovered = false;

  var _focusAsked = false;

  @override
  void initState() {
    super.initState();
    for (final zone in _zones) {
      zone.addListener(_focusChanged);
    }
    _attach(
      widget.controller ??
          (_own = ScaffoldController(sidebarWidth: widget.sidebarWidth)),
    );
  }

  @override
  void didUpdateWidget(Scaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    final given = widget.controller;
    if (!identical(given, oldWidget.controller)) {
      _detach();
      _revealed = false;
      if (given == null) {
        _attach(_own = ScaffoldController(sidebarWidth: widget.sidebarWidth));
      } else {
        _own?.dispose();
        _own = null;
        _attach(given);
      }
    } else if (widget.sidebarWidth != oldWidget.sidebarWidth) {
      // the build that follows lays it out: no listener to tell
      _own?._width = widget.sidebarWidth;
    }
    if (widget.sidebar == null && _revealed) {
      _revealed = false;
      _controller._choice = _revealedFrom;
      _seenOpen = _controller.sidebarOpen;
    }
  }

  @override
  void dispose() {
    for (final zone in _zones) {
      zone
        ..removeListener(_focusChanged)
        ..dispose();
    }
    _detach();
    _own?.dispose();
    super.dispose();
  }

  void _attach(ScaffoldController c) {
    _controller = c
      .._state = this
      ..addListener(_controllerChanged);
    _seenOpen = c.sidebarOpen;
  }

  void _detach() {
    final c = _controller..removeListener(_controllerChanged);
    if (identical(c._state, this)) {
      c._state = null;
    }
  }

  /// The controller changed: the sidebar shown or hidden, its width.
  void _controllerChanged() {
    final open = _controller.sidebarOpen;
    if (open != _seenOpen) {
      _seenOpen = open;
      _revealed = false;
      if (!open && _sidebar.hasFocus) {
        _leaveSidebar();
      }
    }
    setState(() {});
  }

  List<FocusScopeNode> get _zones => [_header, _sidebar, _body, _status];

  void _focusChanged() {
    for (final zone in [_header, _body, _status]) {
      if (zone.hasFocus) {
        _last = zone;
      }
    }
    if (_sidebar.hasFocus != _inSidebar) {
      setState(() => _inSidebar = _sidebar.hasFocus);
    }
  }

  /// The zones there are, in the order they are on the screen.
  List<FocusScopeNode> get _shownZones => [
    if (widget.header != null) _header,
    if (widget.sidebarSide == SidebarSide.right) _body,
    if (widget.sidebar != null && _open) _sidebar,
    if (widget.sidebarSide == SidebarSide.left) _body,
    if (widget.statusBar != null) _status,
  ];

  ScaffoldZone? get _focusedZone => _header.hasFocus
      ? ScaffoldZone.header
      : _sidebar.hasFocus
      ? ScaffoldZone.sidebar
      : _body.hasFocus
      ? ScaffoldZone.body
      : _status.hasFocus
      ? ScaffoldZone.statusBar
      : null;

  /// [ScaffoldController.focusZone].
  bool _focusZone(ScaffoldZone zone) {
    if (!mounted) {
      return false;
    }
    switch (zone) {
      case ScaffoldZone.sidebar:
        if (widget.sidebar == null) {
          return false;
        }
        _toSidebar();
        return true;
      case ScaffoldZone.header:
        return widget.header != null && _enter(_header, itself: true);
      case ScaffoldZone.body:
        return _enter(_body, itself: true);
      case ScaffoldZone.statusBar:
        return widget.statusBar != null && _enter(_status, itself: true);
    }
  }

  /// Focuses the node [zone] focused last, else its first; the zone itself
  /// when it has none and [itself]. Whether it focused one.
  static bool _enter(FocusScopeNode zone, {bool itself = false}) {
    final child = zone.focusedChild;
    if (child != null && !identical(child, zone)) {
      child.requestFocus();
      return true;
    }
    if (zone.nextFocus()) {
      return true;
    }
    if (itself) {
      zone.requestFocus();
    }
    return itself;
  }

  /// Moves the focus to the next zone with a node to focus, [step] 1, or
  /// the one before, -1.
  void _cycle(int step) {
    final zones = _shownZones;
    final n = zones.length;
    final at = zones.indexWhere((z) => z.hasFocus);
    for (var i = 1; i < n + (at < 0 ? 1 : 0); i++) {
      final k = at < 0 ? (step > 0 ? i - 1 : n - i) : (at + step * i) % n;
      if (_enter(zones[k])) {
        return;
      }
    }
  }

  void _nextZone() => _cycle(1);
  void _previousZone() => _cycle(-1);

  /// Ctrl+B: to the sidebar, shown if it was not, and from it back.
  void _sidebarKey() {
    if (!_sidebar.hasFocus) {
      _toSidebar();
      return;
    }
    _leaveSidebar();
    if (_revealed) {
      // hidden again as it was: the listener finds the focus gone
      _controller._choose(_revealedFrom);
      _revealed = false;
    }
  }

  /// To the sidebar, shown if it was not: hidden again on Ctrl+B's way
  /// back.
  void _toSidebar() {
    if (!_open) {
      final from = _controller._choice;
      _controller._choose(true);
      _revealed = true;
      _revealedFrom = from;
      // focusable at once, as the next layout makes it
      _sidebar
        ..descendantsAreFocusable = true
        ..canRequestFocus = true;
    }
    _enter(_sidebar, itself: true);
  }

  /// Moves the focus from the sidebar to the zone it came from.
  void _leaveSidebar() {
    final to = _last;
    if (to == null || !_enter(to, itself: true)) {
      _enter(_body, itself: true);
    }
  }

  /// After the first frame: the first node of the body, else of the other
  /// zones, when nothing has the focus. A node built in the layout, as a
  /// lazy list's items are, asks for the focus (autofocus) after the
  /// frame's build has settled it; the flush waiting for the next build
  /// is run first, so the node gets it rather than the body.
  void _focusFirst(Duration _) {
    if (!mounted) {
      return;
    }
    final manager = _body.manager;
    if (manager != null && manager.needsFlush) {
      manager.flush();
    }
    if (manager?.primaryFocus != null) {
      return;
    }
    for (final zone in [_body, _sidebar, _header, _status]) {
      if ((!identical(zone, _sidebar) || _open) && _enter(zone)) {
        return;
      }
    }
  }

  /// [w] clamped as a drag or a key leaves the sidebar: 4 columns at
  /// least, and all of the screen's but the divider and 10 at most.
  int _clamped(int w) {
    final most = _screen - 1 - Scaffold.minBodyWidth;
    final v = w > most ? most : w;
    return v < Scaffold.minSidebarWidth ? Scaffold.minSidebarWidth : v;
  }

  void _down(PointerEvent e) {
    if (e.button == 0) {
      setState(() => _grip = (e.screenX, _controller.sidebarWidth));
    }
  }

  void _drag(PointerEvent e) {
    final grip = _grip;
    if (grip == null) {
      return;
    }
    final (x, from) = grip;
    final delta = e.screenX - x;
    _controller.sidebarWidth = _clamped(
      widget.sidebarSide == SidebarSide.left ? from + delta : from - delta,
    );
  }

  void _up() {
    final grip = _grip;
    if (grip == null) {
      return;
    }
    setState(() => _grip = null);
    final w = _controller.sidebarWidth;
    if (w != grip.$2) {
      widget.onSidebarResized?.call(w);
    }
  }

  /// Alt+, and Alt+.: the divider a column to the left, [step] -1, or to
  /// the right, 1.
  void _resizeKey(int step) {
    final from = _controller.sidebarWidth;
    final w = _clamped(
      widget.sidebarSide == SidebarSide.left ? from + step : from - step,
    );
    if (w != from) {
      _controller.sidebarWidth = w;
      widget.onSidebarResized?.call(w);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_focusAsked) {
      _focusAsked = true;
      AppBinding.maybeOf(context)?.scheduleFrameCallback(_focusFirst);
    }
    final hasSidebar = widget.sidebar != null;
    final zones =
        (widget.header != null ? 1 : 0) +
        (hasSidebar ? 1 : 0) +
        1 +
        (widget.statusBar != null ? 1 : 0);
    final resizing = hasSidebar && widget.resizableSidebar && _inSidebar;
    final left = widget.sidebarSide == SidebarSide.left;
    return KeyBindings(
      {
        if (zones > 1) 'f6': _nextZone,
        if (zones > 1) 'shift+f6': _previousZone,
        if (hasSidebar) 'ctrl+b': _sidebarKey,
        if (resizing) 'alt+,': () => _resizeKey(-1),
        if (resizing) 'alt+.': () => _resizeKey(1),
      },
      hints: {
        if (zones > 1) 'f6': 'next pane',
        if (hasSidebar) 'ctrl+b': _inSidebar ? 'back' : 'sidebar',
        if (resizing) 'alt+,': left ? 'narrower' : 'wider',
        if (resizing) 'alt+.': left ? 'wider' : 'narrower',
      },
      debugLabel: 'scaffold keys',
      child: LayoutBuilder(builder: _frame),
    );
  }

  Widget _frame(BuildContext context, BoxConstraints c) {
    final theme = Theme.of(context);
    final screen = c.maxW < BoxConstraints.unbounded ? c.maxW : 80;
    _screen = screen;
    final below = widget.collapsedBelow;
    final narrow = below != null && screen < below;
    final controller = _controller;
    final was = controller._narrow;
    if (narrow != was) {
      controller._narrow = narrow;
      // the first layout keeps the choice the controller was made with;
      // the width crossing the threshold puts it back as the width has it
      if (was != null) {
        controller._choice = null;
        _revealed = false;
      }
      // what the app read before the first layout is no change to tell
      final shown = controller.sidebarOpen;
      if (shown != _seenOpen && was != null) {
        AppBinding.maybeOf(
          context,
        )?.scheduleFrameCallback((_) => controller._tell());
      }
      _seenOpen = shown;
    }
    final open = widget.sidebar != null && controller.sidebarOpen;
    _open = open;
    final text = theme.text;
    final chrome = theme.chrome.merge(text);
    final left = widget.sidebarSide == SidebarSide.left;
    final edge = open && widget.resizableSidebar ? 1 : 0;
    var sw = controller.sidebarWidth;
    if (sw > screen - edge) {
      sw = screen - edge < 0 ? 0 : screen - edge;
    }

    final sidebar = SizedBox(
      key: const ValueKey('sidebar'),
      width: open ? sw : 0,
      child: FocusScope(
        node: _sidebar,
        canRequestFocus: open,
        descendantsAreFocusable: open,
        skipTraversal: true,
        child: Box(
          style: chrome,
          child: DefaultTextStyle(
            style: chrome,
            child: widget.sidebar ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
    final active = _hovered || _grip != null;
    final divider = SizedBox(
      key: const ValueKey('divider'),
      width: edge,
      // mounted only when resizable: a Listener has the terminal report
      // the mouse
      child: !widget.resizableSidebar
          ? null
          : MouseRegion(
              cursor: PointerShape.ewResize,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onDown: _down,
                onDrag: _drag,
                onUp: (_) => _up(),
                child: VerticalDivider(
                  style: active ? theme.primary : theme.faint,
                ),
              ),
            ),
    );
    final body = Expanded(
      key: const ValueKey('body'),
      child: FocusScope(node: _body, skipTraversal: true, child: widget.body),
    );

    final header = widget.header;
    final status = widget.statusBar;
    return Box(
      style: theme.background.merge(text),
      child: DefaultTextStyle(
        style: theme.background.merge(text),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) _headerRow(header, chrome, left),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: left
                    ? [sidebar, divider, body]
                    : [body, divider, sidebar],
              ),
            ),
            if (status != null)
              FocusScope(node: _status, skipTraversal: true, child: status),
            if (widget.keyHints)
              Box(
                style: chrome,
                padding: const EdgeInsets.x(2),
                child: KeyHintsBar(style: theme.chrome),
              ),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(Widget header, Style chrome, bool left) {
    final toggle = widget.sidebar == null
        ? null
        : Listener(
            behavior: HitTestBehavior.opaque,
            onDown: (e) {
              if (e.button == 0) {
                _controller.toggleSidebar();
              }
            },
            child: const Text('≡'),
          );
    return Box(
      style: chrome,
      padding: const EdgeInsets.x(2),
      child: DefaultTextStyle(
        style: chrome,
        child: Row(
          children: [
            if (toggle != null && left) ...[toggle, const SizedBox(width: 2)],
            Expanded(
              child: FocusScope(
                node: _header,
                skipTraversal: true,
                child: header,
              ),
            ),
            if (toggle != null && !left) ...[const SizedBox(width: 2), toggle],
          ],
        ),
      ),
    );
  }
}
