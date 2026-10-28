/// Menus: a [MenuBar] of [Menu]s over an app, and context menus at the
/// mouse or at the focused widget ([ContextMenu], [showContextMenu]); each
/// a list of [MenuEntry]s shown in the [Overlay] above, whose items do what
/// the keys bound to the same callbacks and intents do, and show those
/// keys; a [MenuController] opens and closes them from the app.
///
/// @docImport '../framework/builder.dart';
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        Attr,
        BorderType,
        BoxConstraints,
        Canvas,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        CrossAxisAlignment,
        HitTestBehavior,
        HitTestResult,
        KeyCode,
        KeyEvent,
        KeyKind,
        Mod,
        PaintContext,
        ParentData,
        RenderObject,
        StyleTable,
        TextMode,
        TextSegmenter;

import '../focus/focus.dart';
import '../foundation/change_notifier.dart' show ChangeNotifier, VoidCallback;
import '../foundation/controller_host.dart';
import '../foundation/helpers.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/child_list.dart';
import '../layout/flex.dart';
import '../layout/shadow.dart';
import '../semantics/semantics.dart';
import '../style/color_mix.dart';
import '../style/style.dart';
import 'anchor.dart';
import 'key_path.dart';
import 'layer.dart';
import 'panel.dart';

// Examples can assume:
// late BuildContext context;
// var lineNumbers = false;
// void setState(void Function() change) {}
// final class SaveIntent extends Intent {
//   const SaveIntent();
// }
// final class SaveAsIntent extends Intent {
//   const SaveAsIntent();
// }
// final class QuitIntent extends Intent {
//   const QuitIntent();
// }
// final class ZoomIntent extends Intent {
//   const ZoomIntent(this.step);
//   final int step;
// }
// final class ThemeIntent extends Intent {
//   const ThemeIntent(this.name);
//   final String name;
// }
// late Menu file;
// late Menu edit;
// late Widget body;
// late Widget editor;
// late Widget fileList;
// late List<MenuEntry> rowItems;
// void open() {}
// void save() {}
// void undo() {}
// void rename() {}
// void delete() {}

/// What a menu lists: a [MenuItem] to choose, a [Menu] of entries of its
/// own, or a [MenuDivider] between them.
///
/// A label marks its mnemonic with `&` before it: `&File`, `Save &as`;
/// `&&` is an `&`. The mnemonic is drawn underlined. Pressed while its menu
/// is open, in either case, it chooses the entry, or highlights the next
/// one that has it when more than one does; Alt and the mnemonic of a
/// [MenuBar]'s menu opens that menu.
///
/// A File menu of three items in two groups, `S` the mnemonic of Save,
/// `a` that of Save as:
///
/// ```dart
/// const fileMenu = Menu('&File', items: [
///   MenuItem('&Save', intent: SaveIntent()),
///   MenuItem('Save &as…', intent: SaveAsIntent()),
///   MenuDivider(),
///   MenuItem('&Quit', intent: QuitIntent()),
/// ]);
/// ```
@immutable
sealed class MenuEntry {
  /// An entry; one of the three kinds.
  const MenuEntry();
}

/// An entry that does something when chosen, once its menus are closed:
/// calls [onSelected], or does [intent] as a key that `Shortcuts` binds
/// to it would, from the node the keys went to first when the menu opened
/// (the focused one, [FocusManager.keyPath]): the enabled [Action] for it
/// of the nearest [Actions] above that node.
///
/// On its right it shows the key that does the same from there, if one
/// does: of those [FocusManagerKeys.activeKeys] lists for that node, the
/// first bound to [onSelected] (the same function, a tear-off such as
/// `save`, not a closure made for the binding) or to an intent equal to
/// [intent] ([ActiveKey.binding]); a sequence whole, `ctrl+x ctrl+s`
/// ([ActiveKey.label]). A key the node takes in its own `onKeyEvent` is
/// not among them.
///
/// With [checked] not null, a check mark shows before its label while it
/// is true: the app keeps the value, and flips it in [onSelected].
///
/// It cannot be chosen, and shows muted, when not [enabled], with neither
/// [onSelected] nor [intent], or when no enabled action does [intent].
///
/// An item that turns line numbers on and off, a check mark showing while
/// they are on:
///
/// ```dart
/// MenuItem(
///   '&Line numbers',
///   checked: lineNumbers,
///   onSelected: () => setState(() => lineNumbers = !lineNumbers),
/// )
/// ```
final class MenuItem extends MenuEntry {
  /// An item of [label] that calls [onSelected] or does [intent], not
  /// both: it asserts so.
  const MenuItem(
    this.label, {
    this.onSelected,
    this.intent,
    this.checked,
    this.enabled = true,
  }) : assert(
         onSelected == null || intent == null,
         'onSelected or intent, not both',
       );

  /// What it says, its mnemonic marked (see [MenuEntry]).
  final String label;

  /// Called when it is chosen.
  final VoidCallback? onSelected;

  /// Done when it is chosen.
  final Intent? intent;

  /// Whether a check mark shows before the label; null for an item that
  /// has none.
  final bool? checked;

  /// Whether it can be chosen, as far as what it does can be done: true by
  /// default.
  final bool enabled;
}

/// An entry that opens a menu of [items] beside the menu it is in, its
/// first entry level with this one: on its right, or, where it does not
/// fit there, on the side with more room, and higher where it does not fit
/// below, its last entry level with this one. One of a [MenuBar]'s opens
/// under its title, ending at its right edge where it does not fit on the
/// right.
///
/// It cannot be opened, and shows muted, when not [enabled] or with no
/// items.
///
/// A View menu with a menu of its own beside it:
///
/// ```dart
/// const view = Menu('&View', items: [
///   MenuItem('&Zoom in', intent: ZoomIntent(1)),
///   Menu('&Theme', items: [
///     MenuItem('&Dark', intent: ThemeIntent('dark')),
///     MenuItem('&Light', intent: ThemeIntent('light')),
///   ]),
/// ]);
/// ```
final class Menu extends MenuEntry {
  /// A menu of [label] that opens [items].
  const Menu(this.label, {required this.items, this.enabled = true});

  /// What it says, its mnemonic marked (see [MenuEntry]).
  final String label;

  /// The entries of the menu it opens, in order.
  final List<MenuEntry> items;

  /// Whether it can be opened, as far as it has items: true by default.
  final bool enabled;
}

/// A line between two groups of entries.
final class MenuDivider extends MenuEntry {
  /// A divider, which cannot be chosen.
  const MenuDivider();
}

/// What opens and closes the menus of the [MenuBar] or the [ContextMenu]
/// it is given to as `controller`, and says which are open, however they
/// opened: by it, the keys or the mouse.
///
/// The menus open are a [path] down from the bar or the context menu: for
/// a [MenuBar], the index of its menu open in [MenuBar.menus], then for
/// each menu open beside another the row of the entry it opened from in
/// the one before, from 0, dividers counted; for a [ContextMenu], those
/// rows alone, from [ContextMenu.items]. The listeners are told when the
/// menus open or close and when the path changes, not when the highlight
/// moves within a menu. The entries are the app's values: rebuilt with
/// other [MenuItem.enabled], [MenuItem.checked] or items, the widget shows
/// them in the menus open.
///
/// It is given to one widget at a time, and goes over to one built in that
/// one's place (a key changed), the menus open opening there again after
/// the build; while it is given to none, [open] throws a [StateError] and
/// [close] does nothing.
///
/// A bar whose Edit menu, the second, the app opens itself:
///
/// ```dart
/// final menus = MenuController();
/// final bar = MenuBar(controller: menus, menus: [file, edit], child: body);
/// // later, from a key of the app's or a timer:
/// menus.open([1]);
/// ```
final class MenuController extends ChangeNotifier {
  final _hosts = ControllerHost<_MenuHost>();
  var _isOpen = false;
  List<int> _path = const [];

  /// Whether any menu is open.
  bool get isOpen => _isOpen;

  /// The menus open (see [MenuController]); empty while none is.
  List<int> get path => _path;

  /// Opens the menus along [path], as far as they can open, in place of
  /// those open before, the first entry of the innermost highlighted as
  /// when the keys open it: the keys go to the menus, and the focus back
  /// to the node focused before as they close.
  ///
  /// For a [MenuBar], [path] starts with the bar's menu; null or empty,
  /// the first that can open, as F10 opens it. A bar's menu that cannot
  /// open opens nothing and leaves the menus as they were. For a
  /// [ContextMenu], the menu has its top left at the cell [at] of the
  /// ContextMenu's child, as a right click there opens it; with [at] null,
  /// it opens under the widget focused in the child, as Shift+F10 does, or
  /// under the child's first row when the focus is not in it; with no
  /// items, not at all. [at] is for a ContextMenu alone.
  ///
  /// A [RangeError] for an index in [path] past the entries of the menu it
  /// is in, an [ArgumentError] for one of an entry that is no [Menu] or for
  /// [at] given to a MenuBar's controller, a [StateError] while the
  /// controller is given to no widget; nothing opens before the widget is
  /// laid out.
  void open([List<int>? path, (int, int)? at]) {
    final host = _hosts.host;
    if (host == null) {
      throw StateError(
        'MenuController.open: the controller is given to no widget: give '
        'it as controller: to a MenuBar or a ContextMenu',
      );
    }
    host._openPath(path, at);
  }

  /// Closes the menus open, if any: the focus goes back to the node
  /// focused before they opened.
  void close() => _hosts.host?._closeAll();

  /// [host] serves the controller, in place of the widget that did: the
  /// menus open then open again in it, after the build.
  void _attach(_MenuHost host) {
    _hosts.attach(host);
    _resumeIn(host);
  }

  /// Opens the menus the controller says are open in [host], its host,
  /// after the build.
  void _resumeIn(_MenuHost host) {
    if (!_isOpen) {
      return;
    }
    final path = _path;
    _hosts.afterBuild(() {
      if (_hosts.isHost(host)) {
        host._resume(path);
      }
    });
  }

  /// [host] lets go of the controller: where no widget takes it over, it
  /// reads closed after the build.
  void _detach(_MenuHost host) => _hosts.detach(host, () => _set(null));

  /// The menus open are [path]; null for none.
  void _set(List<int>? path) {
    if (_hosts.isDisposed) {
      return;
    }
    final open = path != null;
    final to = path ?? const <int>[];
    if (open == _isOpen && sameList(to, _path)) {
      return;
    }
    _isOpen = open;
    _path = List.unmodifiable(to);
    notifyListeners();
  }

  @override
  void dispose() {
    _hosts.dispose();
    super.dispose();
  }
}

/// A widget whose menus a [MenuController] opens and follows.
abstract interface class _MenuHost {
  /// Opens the menus along [path], the first by [at]; see
  /// [MenuController.open].
  void _openPath(List<int>? path, (int, int)? at);

  /// Closes the menus open.
  void _closeAll();

  /// [session]'s menus changed.
  void _sessionChanged(_MenuSession session);

  /// [session] closed on its own.
  void _sessionClosed(_MenuSession session);

  /// Opens the menus along [path] again, as a [MenuController] says they
  /// are open, where none is and they can: built in place of the widget
  /// that had them open, or put back in the tree. Tells the controller
  /// what opened.
  void _resume(List<int> path);
}

/// Whether the indexes of [path] from [from] on are those of [Menu]s down
/// from [entries].
bool _isPath(List<MenuEntry> entries, List<int> path, int from) {
  var items = entries;
  for (var i = from; i < path.length; i++) {
    if (path[i] < 0 || path[i] >= items.length) {
      return false;
    }
    if (items[path[i]] case final Menu menu) {
      items = menu.items;
    } else {
      return false;
    }
  }
  return true;
}

/// Throws as [MenuController.open] does for a [path] whose indexes from
/// [from] on are not those of [Menu]s down from [entries].
void _checkPath(List<MenuEntry> entries, List<int> path, int from) {
  var items = entries;
  for (var i = from; i < path.length; i++) {
    RangeError.checkValidIndex(path[i], items, 'path[$i]');
    final entry = items[path[i]];
    if (entry is! Menu) {
      throw ArgumentError.value(path, 'path', 'path[$i] is no Menu');
    }
    items = entry.items;
  }
}

/// Where a context menu goes in the widget of [context]: its top left at
/// [at], or with [at] null under the first row of the widget focused, if
/// one is and [within] is false or it is in the widget of [context], and
/// of the widget of [context] if not.
_Anchor _contextAnchor(
  BuildContext context,
  (int, int)? at, {
  required bool within,
}) {
  if (at case (final x, final y)) {
    return _Anchor(context.findRenderObject(), x, y, 1, 1, below: false);
  }
  final manager = Focus.maybeOf(context, createDependency: false)?.manager;
  var focused = manager?.primaryFocus?.context;
  if (focused != null &&
      (!focused.mounted || within && !_isIn(focused, context))) {
    focused = null;
  }
  final widget = (focused ?? context).findRenderObject();
  return _Anchor(widget, 0, 0, widget?.width ?? 0, 1, below: true);
}

/// Whether [context] is [ancestor] or below it.
bool _isIn(BuildContext context, BuildContext ancestor) {
  if (identical(context, ancestor)) {
    return true;
  }
  var found = false;
  context.visitAncestorElements((element) {
    found = identical(element, ancestor);
    return !found;
  });
  return found;
}

/// Shows a menu of [items] in an entry of the [Overlay] above [context] (a
/// [StateError] that says where to place one if there is none): its top
/// left at the cell [at] of the widget of [context] (where a
/// `PointerEvent` of a `Listener` there says the mouse is), or, with [at]
/// null, under the first row of the widget whose node has the primary
/// focus (of the widget of [context] when none has). It is kept on the
/// overlay: where it does not fit on the right of [at], it goes on the
/// side with more room, ending at [at] on the left; so too above [at] where
/// it does not fit below; and it is moved in as far as it has to. Opened
/// without [at], its first entry is highlighted.
///
/// The menu takes the keys and the mouse as a [MenuBar]'s menus do. Its
/// items do what they do from the node the keys went to first as it
/// opened, and show the keys that do the same there, each named by
/// [keyLabel] (`ctrl+s` by default, [KeyCombo.toString]).
///
/// A menu at the mouse where the right button is pressed on a row, the
/// cell the event gives being one of the row's, whose context the
/// [Builder] gives:
///
/// ```dart
/// Builder(
///   builder: (context) => Listener(
///     onDown: (event) {
///       if (event.button == 2) {
///         showContextMenu(context, rowItems, at: (event.x, event.y));
///       }
///     },
///     child: Text('notes.md'),
///   ),
/// )
/// ```
void showContextMenu(
  BuildContext context,
  List<MenuEntry> items, {
  (int, int)? at,
  String Function(KeyCombo combo)? keyLabel,
  PanelLook look = PanelLook.raised,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    throw StateError(
      'showContextMenu: no Overlay above ${context.widget.runtimeType}: '
      'place an Overlay above it, as around the whole app: Overlay(child: …)',
    );
  }
  if (items.isEmpty) {
    return;
  }
  _MenuSession(
    overlay,
    items,
    anchor: _contextAnchor(context, at, within: false),
    target: keyTarget(context),
    keyLabel: keyLabel,
    byKey: at == null,
    look: look,
  );
}

/// [child], with a menu of [items] that a right click on it opens at the
/// mouse, and Shift+F10 under the focused widget while the focus is in it
/// ([showContextMenu]); in a layer of the focus tree around it, whose
/// Shift+F10 a `KeyHintsBar` lists, `shift+f10 menu`.
///
/// The Menu key of a keyboard is no key the app gets: terminals send
/// nothing for it, or a sequence the app does not read; Shift+F10 reaches
/// the app wherever F10 does (see [MenuBar]). Without an [Overlay] above it
/// the build fails with a [StateError] that says where to place one.
///
/// A [controller] opens and closes the menu too, and says which menus are
/// open. Built with other [items] while its menu is open, the menu shows
/// them; it closes as the ContextMenu leaves the tree, or is built with
/// none.
///
/// A list whose rows a right click, or Shift+F10, offers to rename or
/// delete:
///
/// ```dart
/// ContextMenu(
///   items: [
///     MenuItem('&Rename', onSelected: rename),
///     MenuItem('&Delete', onSelected: delete),
///   ],
///   child: fileList,
/// )
/// ```
final class ContextMenu extends StatefulWidget {
  /// [child], with a menu of [items] that a right click or Shift+F10
  /// opens.
  const ContextMenu({
    required this.items,
    required this.child,
    super.key,
    this.keyLabel,
    this.look = PanelLook.raised,
    this.controller,
  });

  /// The entries of the menu, in order; none for a menu that does not
  /// open.
  final List<MenuEntry> items;

  /// What the menu is of: a right click on it opens the menu.
  final Widget child;

  /// How a key is named, those of a sequence one by one; null for
  /// [KeyCombo.toString].
  final String Function(KeyCombo combo)? keyLabel;

  /// How the menus look; see [MenuBar.look].
  final PanelLook look;

  /// What opens and closes the menu from the app, and follows it; null
  /// for none.
  final MenuController? controller;

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

final class _ContextMenuState extends State<ContextMenu> implements _MenuHost {
  _MenuSession? _session;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(ContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
      // the new one told what is open, not in the build
      widget.controller?._hosts.afterBuild(_report);
    }
    final session = _session;
    if (session != null && !identical(widget.items, oldWidget.items)) {
      if (widget.items.isEmpty) {
        _closeMenus();
      } else {
        // the menu's entry may have been built in this build already
        session._update(widget.items);
        scheduleMicrotask(session._changed);
      }
    }
  }

  // out of the tree, the menus close; the controller still says they are
  // open, for the widget built in this one's place to open them, or this
  // one put back
  @override
  void deactivate() {
    _closeMenus(report: false);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.controller?._resumeIn(this);
  }

  @override
  void dispose() {
    _closeMenus(report: false);
    widget.controller?._detach(this);
    super.dispose();
  }

  void _report() {
    if (widget.controller case final controller?
        when controller._hosts.isHost(this)) {
      controller._set(_session?._rows);
    }
  }

  void _closeMenus({bool report = true}) {
    final session = _session;
    _session = null;
    session?._close();
    if (report) {
      _report();
    }
  }

  @override
  void _resume(List<int> path) {
    if (mounted && _session == null && _isPath(widget.items, path, 0)) {
      _show(null, byKey: true, rows: path);
    }
    _report();
  }

  /// Opens the menu by [at] (see [_contextAnchor]) and those of the
  /// entries at [rows] (see [_MenuSession._openFrom]), in place of those
  /// open.
  void _show((int, int)? at, {required bool byKey, List<int> rows = const []}) {
    final items = widget.items;
    if (items.isEmpty || !mounted) {
      return;
    }
    final anchor = _contextAnchor(context, at, within: true);
    final session = _session;
    if (session == null) {
      _session = _MenuSession(
        Overlay.of(context),
        items,
        anchor: anchor,
        target: keyTarget(context),
        keyLabel: widget.keyLabel,
        byKey: byKey,
        rows: rows,
        look: widget.look,
        host: this,
      );
    } else {
      session._reset(items, anchor, byKey: byKey, rows: rows);
    }
    _report();
  }

  @override
  void _openPath(List<int>? path, (int, int)? at) {
    final rows = path ?? const [];
    _checkPath(widget.items, rows, 0);
    _show(at, byKey: true, rows: rows);
  }

  @override
  void _closeAll() => _closeMenus();

  @override
  void _sessionChanged(_MenuSession session) {
    if (identical(_session, session)) {
      _report();
    }
  }

  @override
  void _sessionClosed(_MenuSession session) {
    if (identical(_session, session)) {
      _session = null;
      _report();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) {
      throw StateError(
        'ContextMenu: no Overlay above it: place an Overlay above it, as '
        'around the whole app: Overlay(child: …)',
      );
    }
    return KeyBindings.combos(
      {_shiftF10: () => _show(null, byKey: true)},
      hints: {_shiftF10: 'menu'},
      debugLabel: 'context menu',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onDown: (event) {
          if (event.button == 2) {
            _show((event.x, event.y), byKey: false);
          }
        },
        child: widget.child,
      ),
    );
  }

  static const _shiftF10 = KeyCombo(KeyCode.f10, modifiers: Mod.shift);
}

/// A row of the titles of [menus] over [child], which fills the rest of
/// the room it gets (along an axis with no bound, it is as long as it
/// likes): the menu bar of an app. A title clicked opens its menu under it,
/// in an entry of the [Overlay] above; while one is open, the mouse moved
/// over another title opens that one, and a click on the open one closes
/// it. A press on a title held down to an item and released there chooses
/// the item.
///
/// It is a layer of the focus tree around [child], as `KeyBindings` is:
/// wherever the focus is in [child], F10 opens the first menu (`f10 menu`
/// in a `KeyHintsBar`), or closes the menus open, and Alt with the mnemonic
/// of a menu opens that one, its first entry highlighted. F10 reaches the
/// app on the terminals that send it, which are most (some take it for a
/// menu bar of their own, as GNOME Terminal does until told not to); Alt
/// and a letter where the terminal sends Alt as Escape before the key, as
/// most do (macOS Terminal and iTerm2 once Option is set to). Alt alone is
/// no key the app gets: terminals send nothing for it, and the kitty
/// keyboard protocol only with all keys sent as escape codes, which the app
/// does not ask for.
///
/// Open, the menus take the keys: Up and Down highlight the entry before
/// and after, of those that can be chosen, from the last to the first and
/// back, Home and End the first and the last; Enter or Space chooses the
/// highlighted one, or opens its menu with its first entry highlighted, as
/// Right does; Left closes a menu opened beside another; at the bar's menu,
/// Right and Left open the next and the previous menu of the bar. Escape
/// closes the innermost menu, F10 them all, and a mnemonic chooses an
/// entry of the menu with the highlighted entry (see [MenuEntry]). Other
/// letters are taken too, the other keys left to the nodes above the
/// overlay. The mouse moved over an entry highlights it and opens its
/// menu, a click chooses it, and a click outside the menus and the bar
/// closes them all, reaching nothing under them.
///
/// The items do what they do from the node the keys went to first as the
/// menus opened, and show the keys that do the same there, each named by
/// [keyLabel] (`ctrl+s` by default, [KeyCombo.toString]); see [MenuItem].
/// The focus goes back to that node as the menus close.
/// In the inline mode the menus have the rows of the app alone, as all of
/// an overlay's entries do, cut off where they go past them, and the mouse
/// is the terminal's.
///
/// The styles, each merged over those before it: [style] for the bar,
/// over the theme's surface and text; [openStyle] for the title of the menu
/// open, the theme's selection when null; a menu that cannot open in the
/// theme's muted text. The menus are raised panels ([look]): the theme's
/// surface and text, a cell of room around the rows and no outline, the
/// theme's panel shadow ([Panel.shadowOf]), a divider a line in the
/// surface's color most of the way to the border's; the entry highlighted
/// in the theme's selection with a primary `▎` at its left, in the
/// unfocused selection (`selectionIdle`) with the `▎` muted while a menu
/// opened from it has an entry highlighted, the keys and what cannot be
/// chosen in the muted text. The first menu fades in over 90 ms as the
/// menus open. With [look] [PanelLook.bordered]: a border in the theme's
/// border color, dividers joining it, the entry highlighted in the
/// selection alone, no shadow and no fade.
/// Without an [Overlay] above it the build fails with a [StateError] that
/// says where to place one.
///
/// A screen reader reads the bar as a [SemanticsRole.menuBar] of a
/// [SemanticsRole.menuItem] for each menu, `expanded` while it is open,
/// and the menus open, these and those of [showContextMenu], each as a
/// [SemanticsRole.menu] titled by the entry it opened from, of a
/// [SemanticsRole.menuItem] for each item and menu in it: its label, the
/// key that does the same as its value, `checked` or `not checked` for an
/// item with a check mark, `expanded` or `collapsed` for a menu, and
/// `disabled` for an entry that cannot be chosen. The entry highlighted in
/// the menu the keys move in is the focused node.
///
/// A [controller] opens and closes the menus too, and says which are open.
/// Built with other [menus] while one is open, the menus open show them,
/// as far as their entries still open them; they close as the bar leaves
/// the tree, or is built with the one open unable to open.
///
/// An editor with a File and an Edit menu over it:
///
/// ```dart
/// MenuBar(
///   menus: [
///     Menu('&File', items: [
///       MenuItem('&Open…', onSelected: open),
///       MenuItem('&Save', onSelected: save),
///     ]),
///     Menu('&Edit', items: [
///       MenuItem('&Undo', onSelected: undo),
///     ]),
///   ],
///   child: editor,
/// )
/// ```
final class MenuBar extends StatefulWidget {
  /// A bar of the titles of [menus] over [child].
  const MenuBar({
    required this.menus,
    required this.child,
    super.key,
    this.keyLabel,
    this.style,
    this.openStyle,
    this.look = PanelLook.raised,
    this.controller,
  });

  /// The menus of the bar, from the left.
  final List<Menu> menus;

  /// What is under the bar.
  final Widget child;

  /// How a key is named, those of a sequence one by one; null for
  /// [KeyCombo.toString].
  final String Function(KeyCombo combo)? keyLabel;

  /// The bar, the theme's surface and text under it.
  final Style? style;

  /// The title of the menu open; the theme's selection when null.
  final Style? openStyle;

  /// How the menus look: raised panels (the default) or bordered boxes.
  final PanelLook look;

  /// What opens and closes the menus from the app, and follows them; null
  /// for none.
  final MenuController? controller;

  @override
  State<MenuBar> createState() => _MenuBarState();
}

final class _MenuBarState extends State<MenuBar> implements _MenuHost {
  final GlobalKey _row = GlobalKey();
  _MenuSession? _session;

  // the menu open; -1 for none
  var _open = -1;

  _RenderBarRow? get _bar =>
      _row.currentContext?.findRenderObject() as _RenderBarRow?;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(MenuBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
      // the new one told what is open, not in the build
      widget.controller?._hosts.afterBuild(_report);
    }
    final session = _session;
    if (session != null && !identical(widget.menus, oldWidget.menus)) {
      if (_canOpen(_open)) {
        // the menus' entry may have been built in this build already
        session._update(widget.menus[_open].items);
        scheduleMicrotask(session._changed);
      } else {
        _closeMenus();
      }
    }
  }

  // out of the tree, the menus close; the controller still says they are
  // open, for the widget built in this one's place to open them, or this
  // one put back
  @override
  void deactivate() {
    _closeMenus(report: false);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.controller?._resumeIn(this);
  }

  @override
  void dispose() {
    _closeMenus(report: false);
    widget.controller?._detach(this);
    super.dispose();
  }

  void _report() {
    final session = _session;
    if (widget.controller case final controller?
        when controller._hosts.isHost(this)) {
      controller._set(session == null ? null : [_open, ...session._rows]);
    }
  }

  void _closeMenus({bool report = true}) {
    final session = _session;
    _session = null;
    _open = -1;
    session?._close();
    if (report) {
      _report();
    }
  }

  @override
  void _resume(List<int> path) {
    final menus = widget.menus;
    if (mounted &&
        _session == null &&
        path.isNotEmpty &&
        path.first >= 0 &&
        path.first < menus.length &&
        _isPath(menus[path.first].items, path, 1)) {
      _openPath(path, null);
    }
    _report();
  }

  @override
  void _openPath(List<int>? path, (int, int)? at) {
    if (at != null) {
      throw ArgumentError.value(at, 'at', 'for a ContextMenu, not a MenuBar');
    }
    if (path == null || path.isEmpty) {
      for (var i = 0; i < widget.menus.length; i++) {
        if (_canOpen(i)) {
          _openMenu(i, byKey: true);
          return;
        }
      }
      return;
    }
    final menus = widget.menus;
    RangeError.checkValidIndex(path[0], menus, 'path[0]');
    _checkPath(menus[path[0]].items, path, 1);
    _openMenu(path[0], byKey: true, rows: path.sublist(1));
  }

  @override
  void _closeAll() {
    if (_session != null) {
      _closeMenus();
      setState(() {});
    }
  }

  @override
  void _sessionChanged(_MenuSession session) {
    if (identical(_session, session)) {
      _report();
    }
  }

  bool _canOpen(int index) {
    final menus = widget.menus;
    return index >= 0 &&
        index < menus.length &&
        menus[index].enabled &&
        menus[index].items.isNotEmpty;
  }

  /// Opens menu [index] under its title, and the menus of its entries at
  /// [rows] (see [_MenuSession._openFrom]); the menu open before closes.
  void _openMenu(int index, {required bool byKey, List<int> rows = const []}) {
    final bar = _bar;
    if (!_canOpen(index) || bar == null || bar.owner == null) {
      return;
    }
    final (x, width) = bar.spanOf(index);
    final anchor = _Anchor(bar, x, 0, width, 1, below: true);
    final items = widget.menus[index].items;
    final session = _session;
    _open = index;
    if (session == null) {
      _session = _MenuSession(
        Overlay.of(context),
        items,
        anchor: anchor,
        target: keyTarget(context),
        keyLabel: widget.keyLabel,
        byKey: byKey,
        rows: rows,
        host: this,
        look: widget.look,
      );
    } else {
      session._reset(items, anchor, byKey: byKey, rows: rows);
    }
    setState(() {});
    _report();
  }

  /// Opens the menu [step] after the open one that can open, from the last
  /// to the first and back.
  void _step(int step) {
    final n = widget.menus.length;
    for (var i = 1; i < n; i++) {
      final index = (_open + step * i) % n;
      if (_canOpen(index)) {
        _openMenu(index, byKey: true);
        return;
      }
    }
  }

  /// Opens the first menu that can open, or closes the menus open.
  void _toggle() {
    if (_session != null) {
      _closeMenus();
      setState(() {});
      return;
    }
    for (var i = 0; i < widget.menus.length; i++) {
      if (_canOpen(i)) {
        _openMenu(i, byKey: true);
        return;
      }
    }
  }

  /// Opens the menu whose mnemonic is [key]; returns whether one is.
  bool _openByKey(String key) {
    final menus = widget.menus;
    for (var i = 0; i < menus.length; i++) {
      if (_Label.parse(menus[i].label).key == key && _canOpen(i)) {
        _openMenu(i, byKey: true);
        return true;
      }
    }
    return false;
  }

  @override
  void _sessionClosed(_MenuSession session) {
    if (identical(_session, session)) {
      _session = null;
      _open = -1;
      if (mounted) {
        setState(() {});
      }
      _report();
    }
  }

  void _down(PointerEvent event) {
    if (_session != null || event.button != 0) {
      return;
    }
    if (_bar?.titleAt(event.x) case final title?) {
      _openMenu(title, byKey: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) {
      throw StateError(
        'MenuBar: no Overlay above it: place an Overlay above it, as '
        'around the whole app: Overlay(child: …)',
      );
    }
    final theme = Theme.of(context);
    final menus = widget.menus;
    final titles = [for (final menu in menus) _Label.parse(menu.label)];
    final keys = <KeyCombo, VoidCallback>{_f10: _toggle};
    for (var i = 0; i < titles.length; i++) {
      if (titles[i].key case final key?) {
        keys.putIfAbsent(
          KeyCombo.char(key, modifiers: Mod.alt),
          () =>
              () => _openMenu(i, byKey: true),
        );
      }
    }
    final style = theme.surface
        .merge(theme.text)
        .merge(widget.style ?? const Style());
    return KeyBindings.combos(
      keys,
      hints: _hints,
      debugLabel: 'menu bar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Listener(
            onDown: _down,
            onDrag: (event) => _session?._fromBar(event, release: false),
            onUp: (event) => _session?._fromBar(event, release: true),
            child: Semantics(
              role: SemanticsRole.menuBar,
              nodes: [
                for (var i = 0; i < menus.length; i++)
                  SemanticsNode(
                    role: SemanticsRole.menuItem,
                    label: titles[i].text,
                    state: SemanticsState(
                      expanded: i == _open ? true : null,
                      disabled: !_canOpen(i),
                    ),
                  ),
              ],
              child: _BarRow(
                key: _row,
                titles: titles,
                enabled: [for (var i = 0; i < menus.length; i++) _canOpen(i)],
                open: _open,
                style: style,
                openStyle: style.merge(widget.openStyle ?? theme.selection),
                mutedStyle: style.merge(theme.muted),
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  static const _f10 = KeyCombo(KeyCode.f10);
  static final Map<KeyCombo, String> _hints = {_f10: 'menu'};
}

/// A label as a menu shows it: [text], and its mnemonic, the [length] code
/// units at [at] in it, marked with `&`; [at] is -1 for none.
@immutable
final class _Label {
  const _Label(this.text, this.at, this.length);

  factory _Label.parse(String label) {
    if (!label.contains('&')) {
      return _Label(label, -1, 0);
    }
    final text = StringBuffer();
    var at = -1;
    var length = 0;
    final runes = label.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      var rune = runes[i];
      if (rune == 0x26 && i + 1 < runes.length) {
        rune = runes[++i];
        if (rune != 0x26 && at < 0) {
          at = text.length;
          length = rune > 0xFFFF ? 2 : 1;
        }
      }
      text.writeCharCode(rune);
    }
    return _Label(text.toString(), at, length);
  }

  final String text;
  final int at;
  final int length;

  /// The mnemonic in lower case; null for none.
  String? get key =>
      at < 0 ? null : text.substring(at, at + length).toLowerCase();

  @override
  bool operator ==(Object other) =>
      other is _Label &&
      other.text == text &&
      other.at == at &&
      other.length == length;

  @override
  int get hashCode => Object.hash(text, at, length);

  /// Draws the label at [x], [y] in [style], the mnemonic underlined.
  void paint(Canvas canvas, StyleTable styles, int x, int y, Style style) {
    final pen = style.penIn(styles);
    if (at < 0) {
      canvas.text(x, y, text, pen);
      return;
    }
    final marked = style.merge(const Style(attrs: Attr.underline));
    var to = x + canvas.text(x, y, text.substring(0, at), pen);
    to += canvas.text(
      to,
      y,
      text.substring(at, at + length),
      marked.penIn(styles),
    );
    canvas.text(to, y, text.substring(at + length), pen);
  }
}

/// Where the first menu of a [_MenuSession] goes: by the rectangle of
/// [width] × [height] at [x], [y] of [target], a render object in the tree
/// of the menus; under the rectangle, or over it when [below] is false, its
/// top left at the rectangle's (see [_RenderMenuPlace]).
@immutable
final class _Anchor {
  const _Anchor(
    this.target,
    this.x,
    this.y,
    this.width,
    this.height, {
    required this.below,
  });

  final RenderObject? target;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool below;

  @override
  bool operator ==(Object other) =>
      other is _Anchor &&
      identical(other.target, target) &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.below == below;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(target), x, y, width, height, below);
}

/// A menu open: its entries, and the one highlighted; -1 for none.
final class _Level {
  _Level(this.items);

  List<MenuEntry> items;
  var highlighted = -1;
}

/// The menus open from a [MenuBar] or [showContextMenu], in an entry of
/// [overlay] from when they open until [_close]: the first, by [anchor],
/// and each opened from an entry of the one before it.
final class _MenuSession {
  _MenuSession(
    this.overlay,
    List<MenuEntry> items, {
    required this.anchor,
    required this.target,
    required this.keyLabel,
    required bool byKey,
    required this.look,
    List<int> rows = const [],
    this.host,
  }) : keys = firstKeys(activeKeysAt(target)) {
    _levels.add(_Level(items));
    _openFrom(rows, byKey: byKey);
    overlay.insert(_entry);
  }

  final OverlayState overlay;

  /// Where the items do their intents from.
  final BuildContext target;

  /// The first key listed for each callback and intent as the menus opened
  /// ([firstKeys]).
  final Map<Object, ActiveKey> keys;

  final String Function(KeyCombo combo)? keyLabel;

  /// The widget the menus are of, told of their changes; null for those
  /// of [showContextMenu].
  final _MenuHost? host;

  /// The bar whose menu the first one is; null for a context menu.
  _MenuBarState? get bar => switch (host) {
    final _MenuBarState bar => bar,
    _ => null,
  };

  final PanelLook look;

  bool get _raised => look == PanelLook.raised;

  _Anchor anchor;

  final _levels = <_Level>[];
  late final _entry = OverlayEntry(
    builder: (_) => _MenuLayer(this),
    fadeIn: _raised ? const Duration(milliseconds: 90) : Duration.zero,
    fadeOut: Duration.zero,
  );
  final GlobalKey _place = GlobalKey();
  var _closed = false;

  _RenderMenuPlace? get _placed =>
      _place.currentContext?.findRenderObject() as _RenderMenuPlace?;

  void _changed() {
    if (!_closed) {
      _entry.markNeedsBuild();
      host?._sessionChanged(this);
    }
  }

  /// For each menu but the first, the row of the entry it opened from.
  List<int> get _rows => [
    for (var i = 1; i < _levels.length; i++) _levels[i - 1].highlighted,
  ];

  /// Closes the menus: they are gone from the next frame on.
  void _close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _entry.remove();
    host?._sessionClosed(this);
  }

  /// The menus left the tree, as with their overlay.
  void _gone() {
    if (!_closed) {
      _closed = true;
      host?._sessionClosed(this);
    }
  }

  /// Shows [items] by [anchor], and the menus of the entries at [rows]
  /// (see [_openFrom]).
  void _reset(
    List<MenuEntry> items,
    _Anchor anchor, {
    required bool byKey,
    List<int> rows = const [],
  }) {
    this.anchor = anchor;
    _levels
      ..clear()
      ..add(_Level(items));
    _openFrom(rows, byKey: byKey);
    _changed();
  }

  /// Opens beside the first menu the menu of its entry at the first of
  /// [rows], beside that the menu of its entry at the next, and so on, as
  /// far as they are menus that can open, and highlights the first entry
  /// of the innermost when [byKey]; with the menus after the first closed.
  void _openFrom(List<int> rows, {required bool byKey}) {
    _levels.removeRange(1, _levels.length);
    for (final row in rows) {
      final level = _levels.last;
      final entry = row >= 0 && row < level.items.length
          ? level.items[row]
          : null;
      if (entry is! Menu || !_enabled(entry)) {
        break;
      }
      level.highlighted = row;
      _levels.add(_Level(entry.items));
    }
    if (byKey) {
      _levels.last.highlighted = _next(_levels.length - 1, -1, 1);
    }
  }

  /// The first menu shows [items], and those opened from it what their
  /// entries open now, as far as those still do; from the next build of
  /// the menus on.
  void _update(List<MenuEntry> items) {
    _levels.first.items = items;
    for (var i = 1; i < _levels.length; i++) {
      final before = _levels[i - 1];
      final row = before.highlighted;
      final opener = row >= 0 && row < before.items.length
          ? before.items[row]
          : null;
      if (opener is! Menu || !_enabled(opener)) {
        _levels.removeRange(i, _levels.length);
        break;
      }
      _levels[i].items = opener.items;
    }
    for (final level in _levels) {
      if (level.highlighted >= level.items.length) {
        level.highlighted = -1;
      }
    }
  }

  bool _enabled(MenuEntry entry) => switch (entry) {
    MenuItem(:final enabled, :final onSelected, :final intent) =>
      enabled &&
          (onSelected != null ||
              intent != null &&
                  target.mounted &&
                  Actions.maybeFind(target, intent) != null),
    Menu(:final enabled, :final items) => enabled && items.isNotEmpty,
    MenuDivider() => false,
  };

  /// The menu the keys move in: the innermost with an entry highlighted,
  /// the first when none has.
  int get _active {
    for (var i = _levels.length - 1; i > 0; i--) {
      if (_levels[i].highlighted >= 0) {
        return i;
      }
    }
    return 0;
  }

  /// The entry of menu [level] after [from] in [direction] (1 or -1) that
  /// can be chosen, from the last to the first and back; from the first
  /// (or the last) when [from] is -1; -1 when none can.
  int _next(int level, int from, int direction) {
    final items = _levels[level].items;
    final n = items.length;
    final start = from >= 0 ? from : (direction > 0 ? n - 1 : 0);
    for (var i = 1; i <= n; i++) {
      final at = (start + direction * i) % n;
      if (_enabled(items[at])) {
        return at;
      }
    }
    return -1;
  }

  /// Highlights entry [row] of menu [level], closing the menus after it.
  void _highlight(int level, int row) {
    _levels.removeRange(level + 1, _levels.length);
    _levels[level].highlighted = row;
    _changed();
  }

  /// Opens the menu of entry [row] of menu [level] beside it, its first
  /// entry highlighted when [byKey].
  void _openAt(int level, int row, {required bool byKey}) {
    final entry = _levels[level].items[row];
    if (entry is! Menu || !_enabled(entry)) {
      return;
    }
    if (_levels[level].highlighted != row || _levels.length == level + 1) {
      _levels
        ..removeRange(level + 1, _levels.length)
        ..add(_Level(entry.items));
      _levels[level].highlighted = row;
    }
    if (byKey) {
      _levels.removeRange(level + 2, _levels.length);
      _levels[level + 1].highlighted = _next(level + 1, -1, 1);
    }
    _changed();
  }

  /// Chooses entry [row] of menu [level]: an item's menus close and it
  /// does what it does; a menu opens.
  void _choose(int level, int row, {required bool byKey}) {
    final entry = _levels[level].items[row];
    if (!_enabled(entry)) {
      return;
    }
    switch (entry) {
      case Menu():
        _openAt(level, row, byKey: byKey);
      case MenuItem(:final onSelected, :final intent):
        _close();
        if (onSelected != null) {
          onSelected();
        } else if (intent != null && target.mounted) {
          Actions.maybeInvoke(target, intent);
        }
      case MenuDivider():
        break;
    }
  }

  void _up() {
    final level = _active;
    _highlight(level, _next(level, _levels[level].highlighted, -1));
  }

  void _down() {
    final level = _active;
    _highlight(level, _next(level, _levels[level].highlighted, 1));
  }

  void _home() {
    final level = _active;
    _highlight(level, _next(level, -1, 1));
  }

  void _end() {
    final level = _active;
    _highlight(level, _next(level, -1, -1));
  }

  void _right() {
    final level = _active;
    final row = _levels[level].highlighted;
    if (row >= 0 && _levels[level].items[row] is Menu) {
      _openAt(level, row, byKey: true);
    } else {
      bar?._step(1);
    }
  }

  void _left() {
    final level = _active;
    if (level > 0) {
      _levels.removeRange(level, _levels.length);
      _changed();
    } else {
      bar?._step(-1);
    }
  }

  void _enter() {
    final level = _active;
    final row = _levels[level].highlighted;
    if (row >= 0) {
      _choose(level, row, byKey: true);
    }
  }

  void _escape() {
    if (_levels.length > 1) {
      _levels.removeLast();
      _changed();
    } else {
      _close();
    }
  }

  void _closeAll() {
    if (bar case final bar?) {
      bar._toggle();
    } else {
      _close();
    }
  }

  /// A letter: a mnemonic of the menu the keys move in, or with Alt one of
  /// the bar's menus.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.kind == KeyKind.release ||
        event.code != KeyCode.char ||
        event.ctrl ||
        event.char == ' ') {
      return KeyEventResult.ignored;
    }
    final key = event.char.toLowerCase();
    if (event.alt) {
      return bar?._openByKey(key) ?? false
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    final level = _active;
    final items = _levels[level].items;
    final rows = [
      for (var i = 0; i < items.length; i++)
        if (_keyOf(items[i]) == key && _enabled(items[i])) i,
    ];
    if (rows.length == 1) {
      _choose(level, rows.single, byKey: true);
    } else if (rows.isNotEmpty) {
      final from = _levels[level].highlighted;
      _highlight(
        level,
        rows.firstWhere((r) => r > from, orElse: () => rows[0]),
      );
    }
    return KeyEventResult.handled;
  }

  static String? _keyOf(MenuEntry entry) => switch (entry) {
    MenuItem(:final label) || Menu(:final label) => _Label.parse(label).key,
    MenuDivider() => null,
  };

  /// The menu and its entry at the cell [x], [y] of the overlay, as
  /// [_RenderMenuPlace.entryAt] says: the row -1 for one no longer shown.
  (int, int)? _entryAt(int x, int y) {
    final at = _placed?.entryAt(x, y);
    if (at == null) {
      return null;
    }
    final (level, row) = at;
    return level < _levels.length && row < _levels[level].items.length
        ? at
        : (level, -1);
  }

  /// The bar's title at [x], [y] of the overlay; null for none.
  int? _titleAt(int x, int y) => bar == null ? null : _placed?.titleAt(x, y);

  void _pressed(PointerEvent event) {
    final x = event.x;
    final y = event.y;
    if (_entryAt(x, y) != null) {
      return;
    }
    final bar = this.bar;
    final title = _titleAt(x, y);
    if (bar == null || title == null) {
      _closeAll();
    } else if (title == bar._open) {
      bar._toggle();
    } else {
      bar._openMenu(title, byKey: false);
    }
  }

  /// The mouse at [x], [y] of the overlay: the entry under it highlighted,
  /// its menu opened, or the bar's menu under it opened.
  void _hover(int x, int y) {
    final at = _entryAt(x, y);
    if (at == null) {
      final bar = this.bar;
      final title = _titleAt(x, y);
      if (bar != null && title != null && title != bar._open) {
        bar._openMenu(title, byKey: false);
      }
      return;
    }
    final (level, row) = at;
    if (row < 0) {
      return;
    }
    final menu = _levels[level];
    final entry = menu.items[row];
    if (!_enabled(entry)) {
      if (menu.highlighted != -1 || _levels.length > level + 1) {
        _highlight(level, -1);
      }
    } else if (entry is Menu) {
      _openAt(level, row, byKey: false);
    } else if (menu.highlighted != row || _levels.length > level + 1) {
      _highlight(level, row);
    }
  }

  /// A button released at [x], [y] of the overlay: the entry there chosen.
  void _release(int x, int y) {
    if (_entryAt(x, y) case (final level, final row) when row >= 0) {
      _choose(level, row, byKey: false);
    }
  }

  /// A drag or a release that follows a press on the bar's titles, in the
  /// bar's coordinates.
  void _fromBar(PointerEvent event, {required bool release}) {
    final at = _placed?.anchorAt;
    if (at == null) {
      return;
    }
    final (x, y) = at;
    if (release) {
      _release(x + event.x, y + event.y);
    } else {
      _hover(x + event.x, y + event.y);
    }
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final box = theme.surface.merge(theme.text);
    final raised = _raised;
    final styles = _BoxStyles(
      box: box,
      border: raised
          ? box.merge(
              Style(
                fg:
                    mixRgb(theme.surface.bg, theme.border.fg, 0.8) ??
                    theme.border.fg,
                attrs: theme.border.attrs,
              ),
            )
          : box.merge(theme.border),
      highlight: theme.selection,
      muted: theme.muted,
      bar: theme.primary,
      idle: theme.selectionIdle,
      raised: raised,
    );
    final shadow = raised ? Panel.shadowOf(theme) : null;
    final active = _active;
    return FocusScope(
      debugLabel: 'menu',
      onKeyEvent: _onKey,
      child: KeyBindings(
        {
          'up': _up,
          'down': _down,
          'home': _home,
          'end': _end,
          'left': _left,
          'right': _right,
          'enter': _enter,
          'space': _enter,
          'escape': _escape,
          'f10': _closeAll,
        },
        hints: const {'enter': 'select', 'escape': 'close'},
        debugLabel: 'menu keys',
        child: Semantics(
          nodes: _semantics(),
          child: Focus(
            autofocus: true,
            debugLabel: 'menu',
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onDown: _pressed,
              onUp: (event) => _release(event.x, event.y),
              onMove: (event) => _hover(event.x, event.y),
              onDrag: (event) => _hover(event.x, event.y),
              onScroll: (_) {},
              child: _MenuPlace(
                key: _place,
                anchor: anchor,
                rows: [
                  for (var i = 1; i < _levels.length; i++)
                    _levels[i - 1].highlighted,
                ],
                shadow: shadow,
                children: [
                  for (final (l, level) in _levels.indexed)
                    _shadowed(
                      shadow,
                      _MenuBox(
                        rows: [for (final entry in level.items) _rowOf(entry)],
                        highlighted: level.highlighted,
                        active: l == active,
                        styles: styles,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _shadowed(BoxShadow? shadow, Widget box) =>
      shadow == null ? box : Shadow(shadow: shadow, child: box);

  /// What menu [level] opened from says: the entry highlighted in the menu
  /// before, or the bar's menu open; null for none.
  String? _titleOf(int level) {
    if (level > 0) {
      final before = _levels[level - 1];
      final at = before.highlighted;
      return at < 0 ? null : _rowOf(before.items[at]).label?.text;
    }
    final bar = this.bar;
    final open = bar?._open ?? -1;
    return open < 0 ? null : _Label.parse(bar!.widget.menus[open].label).text;
  }

  /// The menus open as a screen reader reads them (see [MenuBar]).
  List<SemanticsNode> _semantics() {
    final active = _active;
    return [
      for (var l = 0; l < _levels.length; l++)
        SemanticsNode(
          role: SemanticsRole.menu,
          label: _titleOf(l),
          children: [
            for (final (i, entry) in _levels[l].items.indexed)
              if (_rowOf(entry) case _Row(:final label?) && final row)
                SemanticsNode(
                  role: SemanticsRole.menuItem,
                  label: label.text,
                  value: row.key,
                  state: SemanticsState(
                    checked: row.checked,
                    expanded: row.submenu
                        ? l + 1 < _levels.length && _levels[l].highlighted == i
                        : null,
                    disabled: !row.enabled,
                  ),
                  focused: l == active && _levels[l].highlighted == i,
                ),
          ],
        ),
    ];
  }

  _Row _rowOf(MenuEntry entry) => switch (entry) {
    MenuItem(:final label, :final checked) => _Row(
      _Label.parse(label),
      key: _keyLabelOf(entry),
      enabled: _enabled(entry),
      checked: checked,
    ),
    Menu(:final label) => _Row(
      _Label.parse(label),
      enabled: _enabled(entry),
      submenu: true,
    ),
    MenuDivider() => const _Row.divider(),
  };

  /// The name of the key that does what [item] does; null for none.
  String? _keyLabelOf(MenuItem item) {
    final bound = item.onSelected ?? item.intent;
    return (bound == null ? null : keys[bound])?.label(keyLabel);
  }
}

/// The menus of a [_MenuSession], in the entry of its overlay; it tells
/// the session when it leaves the tree.
final class _MenuLayer extends StatefulWidget {
  const _MenuLayer(this.session);

  final _MenuSession session;

  @override
  State<_MenuLayer> createState() => _MenuLayerState();
}

final class _MenuLayerState extends State<_MenuLayer> {
  @override
  void dispose() {
    widget.session._gone();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.session._build(context);
}

/// The styles a menu is drawn in, each over [box].
@immutable
final class _BoxStyles {
  const _BoxStyles({
    required this.box,
    required this.border,
    required this.highlight,
    required this.muted,
    required this.bar,
    required this.idle,
    required this.raised,
  });

  final Style box;

  /// The border, or on a raised menu its dividers.
  final Style border;
  final Style highlight;
  final Style muted;

  /// The `▎` of the highlighted entry, on a raised menu.
  final Style bar;

  /// The highlighted entry of a menu the keys do not move in, on a raised
  /// menu.
  final Style idle;

  /// Whether the menu is a raised panel, or a bordered box.
  final bool raised;

  @override
  bool operator ==(Object other) =>
      other is _BoxStyles &&
      other.box == box &&
      other.border == border &&
      other.highlight == highlight &&
      other.muted == muted &&
      other.bar == bar &&
      other.idle == idle &&
      other.raised == raised;

  @override
  int get hashCode =>
      Object.hash(box, border, highlight, muted, bar, idle, raised);
}

/// A row of a menu: an entry's [label], the [key] that does the same,
/// whether it can be chosen, its check mark and whether it opens a menu;
/// a line for a divider ([label] null).
@immutable
final class _Row {
  const _Row(
    _Label this.label, {
    required this.enabled,
    this.key,
    this.checked,
    this.submenu = false,
  });

  const _Row.divider()
    : label = null,
      key = null,
      enabled = false,
      checked = null,
      submenu = false;

  final _Label? label;
  final String? key;
  final bool enabled;
  final bool? checked;
  final bool submenu;

  @override
  bool operator ==(Object other) =>
      other is _Row &&
      other.label == label &&
      other.key == key &&
      other.enabled == enabled &&
      other.checked == checked &&
      other.submenu == submenu;

  @override
  int get hashCode => Object.hash(label, key, enabled, checked, submenu);
}

/// The menus open, placed over the overlay; see [_RenderMenuPlace].
final class _MenuPlace extends MultiChildRenderObjectWidget {
  const _MenuPlace({
    required this.anchor,
    required this.rows,
    required this.shadow,
    super.key,
    super.children,
  });

  final _Anchor anchor;

  /// For each menu but the first, the row of the entry it opens from.
  final List<int> rows;

  /// The shadow each menu casts, in cells of its own; null for none.
  final BoxShadow? shadow;

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  _RenderMenuPlace createRenderObject(BuildContext context) =>
      _RenderMenuPlace(anchor, rows, shadow);

  @override
  void updateRenderObject(BuildContext context, _RenderMenuPlace renderObject) {
    renderObject
      ..anchor = anchor
      ..rows = rows
      ..shadow = shadow;
  }
}

final class _PlaceData extends ParentData with ContainerParentDataMixin {}

/// As big as it may be, over an overlay: lays its children, the menus
/// open, out as small as they like, and places them on itself. The first
/// goes by the anchor's rectangle on its target, as the last layout of
/// both left them: from the rectangle's left edge, under it (from its top
/// left when not [_Anchor.below]); else, where it does not fit, on the side
/// with more room, ending at the rectangle's right edge, over it (at its
/// bottom right). Each other goes beside the one before it, its first entry
/// level with the entry it opens from: on its right; else on the side with
/// more room, and with its last entry level with that one. Each is moved in
/// as far as it has to. Shows nothing while the target is in no tree with
/// it. A menu's shadow, in cells of its own to its right and below it, is
/// left out of where it goes and of what is in it.
final class _RenderMenuPlace extends RenderObject
    with ContainerRenderObjectMixin<_PlaceData> {
  _RenderMenuPlace(this._anchor, this._rows, this._shadow);

  BoxShadow? _shadow;
  BoxShadow? get shadow => _shadow;
  set shadow(BoxShadow? s) {
    if (s != _shadow) {
      _shadow = s;
      markNeedsLayout();
    }
  }

  // the cells of a menu's shadow to its right and below it
  int get _dw => _shadow?.insets.right ?? 0;
  int get _dh => _shadow?.insets.bottom ?? 0;

  _Anchor _anchor;
  _Anchor get anchor => _anchor;
  set anchor(_Anchor a) {
    if (a != _anchor) {
      _anchor = a;
      markNeedsLayout();
    }
  }

  List<int> _rows;
  List<int> get rows => _rows;
  set rows(List<int> r) {
    if (!sameList(r, _rows)) {
      _rows = r;
      markNeedsLayout();
    }
  }

  /// Where the anchor's target is from this object, as laid out last;
  /// null while they are in no tree together.
  (int, int)? get anchorAt => _at;
  (int, int)? _at;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _PlaceData) {
      child.parentData = _PlaceData();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.minW;
    height = c.maxH < BoxConstraints.unbounded ? c.maxH : c.minH;
    final target = _anchor.target;
    final at = _at = target == null ? null : offsetIn(this, target);
    var level = 0;
    RenderObject? before;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(BoxConstraints(0, width, 0, height), parentUsesSize: true);
      final w = child.width - _dw;
      final h = child.height - _dh;
      final int x;
      final int y;
      if (before == null) {
        final (tx, ty) = at ?? (0, 0);
        final a = _anchor;
        final left = tx + a.x;
        final top = ty + a.y;
        x = placeAlong(left, left + a.width, w, width);
        y = a.below
            ? placeAlong(top + a.height, top, h, height)
            : placeAlong(top, top + a.height, h, height);
      } else {
        final p = before.parentData;
        final row = p.dy + 1 + (level <= _rows.length ? _rows[level - 1] : 0);
        x = placeAlong(p.dx + before.width - _dw, p.dx, w, width);
        y = placeAlong(row - 1, row + 2, h, height);
      }
      child.parentData
        ..dx = x
        ..dy = y;
      before = child;
      level++;
    }
  }

  /// The menu at [x], [y] and its entry there, from 0 each: the row -1 on
  /// its border; null outside the menus.
  (int, int)? entryAt(int x, int y) {
    if (_at == null) {
      return null;
    }
    var level = childCount - 1;
    for (var c = lastChild; c != null; c = childBefore(c), level--) {
      final p = c.parentData;
      final cx = x - p.dx;
      final cy = y - p.dy;
      final w = c.width - _dw;
      final h = c.height - _dh;
      if (cx >= 0 && cy >= 0 && cx < w && cy < h) {
        final inside = cx >= 1 && cy >= 1 && cx < w - 1 && cy < h - 1;
        return (level, inside ? cy - 1 : -1);
      }
    }
    return null;
  }

  /// The title of the bar that the anchor's target is at [x], [y]; null
  /// for none.
  int? titleAt(int x, int y) {
    final at = _at;
    final target = _anchor.target;
    if (at == null || target is! _RenderBarRow) {
      return null;
    }
    final (ax, ay) = at;
    return y == ay && x >= ax && x < ax + target.width
        ? target.titleAt(x - ax)
        : null;
  }

  @override
  bool hitTestChildren(HitTestResult result, int x, int y) =>
      _at != null && super.hitTestChildren(result, x, y);

  @override
  void paint(PaintContext ctx) {
    if (_at == null) {
      return;
    }
    for (var child = firstChild; child != null; child = childAfter(child)) {
      paintChild(ctx, child);
    }
  }
}

/// A menu: its [rows] in a raised panel or a box with a border.
final class _MenuBox extends LeafRenderObjectWidget {
  const _MenuBox({
    required this.rows,
    required this.highlighted,
    required this.active,
    required this.styles,
  });

  final List<_Row> rows;
  final int highlighted;

  /// Whether the keys move in this menu.
  final bool active;
  final _BoxStyles styles;

  @override
  _RenderMenuBox createRenderObject(BuildContext context) =>
      _RenderMenuBox(rows, highlighted, styles, active: active);

  @override
  void updateRenderObject(BuildContext context, _RenderMenuBox renderObject) {
    renderObject
      ..rows = rows
      ..highlighted = highlighted
      ..active = active
      ..styles = styles;
  }
}

/// What a [_MenuBox] lays out and paints: a row for each entry inside a
/// border, or the cell of room a raised menu has in its place, a line
/// across it for a divider. A row is a blank, the check mark column when
/// an entry has one, the label, two blanks and the keys' column, or `▸`
/// there for a menu, and a blank. As wide and as tall as that within its
/// constraints; what does not fit is cut off. On a raised menu the
/// highlighted row is lit across the whole menu, a `▎` at its left, idle
/// unless the menu is [active].
final class _RenderMenuBox extends RenderObject {
  _RenderMenuBox(
    this._rows,
    this._highlighted,
    this._styles, {
    required this._active,
  });

  bool _active;
  bool get active => _active;
  set active(bool a) {
    if (a != _active) {
      _active = a;
      markNeedsPaint();
    }
  }

  List<_Row> _rows;
  List<_Row> get rows => _rows;
  set rows(List<_Row> rows) {
    if (!sameList(rows, _rows)) {
      _rows = rows;
      markNeedsLayout();
    }
  }

  int _highlighted;
  int get highlighted => _highlighted;
  set highlighted(int row) {
    if (row != _highlighted) {
      _highlighted = row;
      markNeedsPaint();
    }
  }

  _BoxStyles _styles;
  _BoxStyles get styles => _styles;
  set styles(_BoxStyles styles) {
    if (styles != _styles) {
      _styles = styles;
      markNeedsPaint();
    }
  }

  // the columns of the check marks, the labels and the keys
  var _check = 0;
  var _label = 0;
  var _keys = 0;

  int _measure() {
    final segmenter = owner?.segmenter ?? TextSegmenter();
    _check = 0;
    _label = 0;
    _keys = 0;
    for (final row in _rows) {
      final label = row.label;
      if (label == null) {
        continue;
      }
      if (row.checked != null) {
        _check = 2;
      }
      final w = segmenter.width(label.text);
      if (w > _label) {
        _label = w;
      }
      final k = row.submenu ? 1 : segmenter.width(row.key ?? '');
      if (k > _keys) {
        _keys = k;
      }
    }
    return _check + _label + (_keys > 0 ? 2 + _keys : 0) + 4;
  }

  @override
  int computeMinIntrinsicWidth(int height) => _measure();

  @override
  int computeMaxIntrinsicWidth(int height) => _measure();

  @override
  int computeMinIntrinsicHeight(int width) => _rows.length + 2;

  @override
  int computeMaxIntrinsicHeight(int width) => _rows.length + 2;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_measure());
    height = c.constrainH(_rows.length + 2);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    final w = width;
    final h = height;
    final s = _styles;
    canvas.fill(0, 0, w, h, s.box.penIn(styles));
    if (w < 2 || h < 2) {
      return;
    }
    final border = s.border.penIn(styles);
    final ambiguous = owner?.segmenter.ambiguousWidth ?? 1;
    final lines = ambiguous == 1 ? BorderType.single : BorderType.ascii;
    final across = lines.glyph(left: true, right: true);
    final down = lines.glyph(up: true, down: true);
    if (s.raised) {
      _paintRaised(canvas, styles, border, across);
      return;
    }
    canvas
      ..fill(0, 0, 1, 1, border, lines.glyph(right: true, down: true))
      ..fill(1, 0, w - 2, 1, border, across)
      ..fill(w - 1, 0, 1, 1, border, lines.glyph(left: true, down: true))
      ..fill(0, 1, 1, h - 2, border, down)
      ..fill(w - 1, 1, 1, h - 2, border, down)
      ..fill(0, h - 1, 1, 1, border, lines.glyph(up: true, right: true))
      ..fill(1, h - 1, w - 2, 1, border, across)
      ..fill(w - 1, h - 1, 1, 1, border, lines.glyph(up: true, left: true));
    final segmenter = owner?.segmenter ?? TextSegmenter();
    for (var i = 0; i < _rows.length && i < h - 2; i++) {
      final y = i + 1;
      final row = _rows[i];
      final label = row.label;
      if (label == null) {
        canvas
          ..fill(
            0,
            y,
            1,
            1,
            border,
            lines.glyph(up: true, right: true, down: true),
          )
          ..fill(1, y, w - 2, 1, border, across)
          ..fill(
            w - 1,
            y,
            1,
            1,
            border,
            lines.glyph(up: true, down: true, left: true),
          );
        continue;
      }
      var style = row.enabled ? s.box : s.box.merge(s.muted);
      if (i == _highlighted) {
        style = style.merge(s.highlight);
      }
      final pen = style.penIn(styles);
      canvas
        ..save()
        ..clipRect(1, y, w - 2, 1)
        ..fill(1, y, w - 2, 1, pen);
      if (row.checked ?? false) {
        canvas.text(2, y, '✓', pen);
      }
      label.paint(canvas, styles, 2 + _check, y, style);
      final key = row.key;
      if (row.submenu) {
        canvas.text(w - 3, y, '▸', pen);
      } else if (key != null) {
        canvas.text(
          w - 2 - segmenter.width(key),
          y,
          key,
          style.merge(s.muted).penIn(styles),
        );
      }
      canvas.restore();
    }
  }
}

extension on _RenderMenuBox {
  /// Paints the rows of a raised menu, its room around them.
  void _paintRaised(Canvas canvas, StyleTable styles, int rule, int across) {
    final w = width;
    final h = height;
    final s = _styles;
    final segmenter = owner?.segmenter ?? TextSegmenter();
    for (var i = 0; i < _rows.length && i < h - 2; i++) {
      final y = i + 1;
      final row = _rows[i];
      final label = row.label;
      if (label == null) {
        canvas.fill(1, y, w - 2, 1, rule, across);
        continue;
      }
      var style = row.enabled ? s.box : s.box.merge(s.muted);
      if (i == _highlighted) {
        style = style.merge(_active ? s.highlight : s.idle);
        canvas
          ..fill(0, y, w, 1, style.penIn(styles))
          ..text(
            0,
            y,
            '▎',
            style.merge(_active ? s.bar : s.muted).penIn(styles),
          );
      }
      final pen = style.penIn(styles);
      canvas
        ..save()
        ..clipRect(1, y, w - 2, 1);
      if (row.checked ?? false) {
        canvas.text(2, y, '✓', pen);
      }
      label.paint(canvas, styles, 2 + _check, y, style);
      final key = row.key;
      if (row.submenu) {
        canvas.text(w - 3, y, '▸', pen);
      } else if (key != null) {
        canvas.text(
          w - 2 - segmenter.width(key),
          y,
          key,
          style.merge(s.muted).penIn(styles),
        );
      }
      canvas.restore();
    }
  }
}

/// The titles of a [MenuBar]'s menus in a row.
final class _BarRow extends LeafRenderObjectWidget {
  const _BarRow({
    required this.titles,
    required this.enabled,
    required this.open,
    required this.style,
    required this.openStyle,
    required this.mutedStyle,
    super.key,
  });

  final List<_Label> titles;
  final List<bool> enabled;
  final int open;
  final Style style;
  final Style openStyle;
  final Style mutedStyle;

  @override
  _RenderBarRow createRenderObject(BuildContext context) =>
      _RenderBarRow(titles).._configure(this);

  @override
  void updateRenderObject(BuildContext context, _RenderBarRow renderObject) =>
      renderObject
        ..titles = titles
        .._configure(this);
}

/// What a [_BarRow] lays out and paints: each title with a blank on either
/// side, one after another from the left, in a row as wide as it may be.
final class _RenderBarRow extends RenderObject {
  _RenderBarRow(this._titles);

  List<_Label> _titles;
  List<_Label> get titles => _titles;
  set titles(List<_Label> titles) {
    if (!sameList(titles, _titles)) {
      _titles = titles;
      _measuredIn = null;
      markNeedsLayout();
    }
  }

  var _enabled = const <bool>[];
  var _open = -1;
  var _style = const Style();
  var _openStyle = const Style();
  var _mutedStyle = const Style();

  // the first column of each title and the end of the last, measured for
  // the text mode and ambiguous width of _measuredIn
  var _starts = const <int>[0];
  (TextMode, int)? _measuredIn;

  void _configure(_BarRow row) {
    if (row.open != _open ||
        row.style != _style ||
        row.openStyle != _openStyle ||
        row.mutedStyle != _mutedStyle ||
        !sameList(row.enabled, _enabled)) {
      _enabled = row.enabled;
      _open = row.open;
      _style = row.style;
      _openStyle = row.openStyle;
      _mutedStyle = row.mutedStyle;
      markNeedsPaint();
    }
  }

  List<int> _measure() {
    final segmenter = owner?.segmenter ?? TextSegmenter();
    final measure = (segmenter.mode, segmenter.ambiguousWidth);
    if (_measuredIn != measure) {
      final starts = <int>[];
      var x = 0;
      for (final title in _titles) {
        starts.add(x);
        x += segmenter.width(title.text) + 2;
      }
      _starts = starts..add(x);
      _measuredIn = measure;
    }
    return _starts;
  }

  /// The first column of title [i] and its width.
  (int, int) spanOf(int i) {
    final starts = _measure();
    return (starts[i], starts[i + 1] - starts[i]);
  }

  /// The title at column [x]; null where there is none.
  int? titleAt(int x) {
    final starts = _measure();
    for (var i = 0; i + 1 < starts.length; i++) {
      if (starts[i] <= x && x < starts[i + 1]) {
        return i;
      }
    }
    return null;
  }

  @override
  int computeMinIntrinsicWidth(int height) => 0;

  @override
  int computeMaxIntrinsicWidth(int height) => _measure().last;

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    final total = _measure().last;
    width = c.maxW < BoxConstraints.unbounded ? c.maxW : c.constrainW(total);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final styles = canvas.styles;
    canvas.fill(0, 0, width, height, _style.penIn(styles));
    final starts = _measure();
    for (var i = 0; i < _titles.length; i++) {
      final style = i == _open
          ? _openStyle
          : (i < _enabled.length && !_enabled[i] ? _mutedStyle : _style);
      final x = starts[i];
      canvas.fill(x, 0, starts[i + 1] - x, 1, style.penIn(styles));
      _titles[i].paint(canvas, styles, x + 1, 0, style);
    }
  }
}
