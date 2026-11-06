// The gallery around the pages, as it draws and behaves
// (doc/design.md): a header; a sidebar of the groups and their pages with a
// filter; the page (its title, what it is about, the Preview and Code
// tabs, the stage, the inspector of its options); the key hints of what
// has the focus; a palette over everything, toasts, a theme that fades,
// a new page that dissolves in.
import 'dart:convert';

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show clipboardSequence;
import 'package:twk_rich/twk_rich.dart';

import '../input/keys.dart';
import '../input/line_edit.dart';
import '../model/catalog_pages.dart';
import '../model/code_record.dart';
import '../model/code_text.dart';
import '../model/gallery_tab.dart';
import '../model/page_store.dart';
import '../model/palette.dart';
import '../model/toasts.dart';
import '../motion.dart';
import '../page.dart';
import '../paint.dart';
import '../route.dart';
import 'code_select.dart';
import 'controls.dart';
import 'dissolve.dart';
import 'metrics.dart';
import 'split.dart';
import 'stage.dart';
import 'tokens.dart';

part 'shell_code.dart';
part 'shell_header.dart';
part 'shell_hints.dart';
part 'shell_inspector.dart';
part 'shell_keys.dart';
part 'shell_page.dart';
part 'shell_palette.dart';
part 'shell_sidebar.dart';
part 'shell_toasts.dart';

/// Where the focus is, as the design names it.
enum Zone { list, filter, page }

/// The whole gallery: its pages [pages], opened at [route], on [clock].
final class GalleryShell extends StatefulWidget {
  const GalleryShell({
    required this.pages,
    super.key,
    this.route,
    this.clock = const Clock.app(),
  });

  final List<GalleryPage> pages;
  final GalleryRoute? route;
  final Clock clock;

  @override
  State<GalleryShell> createState() => GalleryShellState();
}

/// What a test or a tool reads of a [GalleryShell] that shows
/// (`package:gallery/testing.dart`, `shellOf`): where it is, and what the
/// page shown's Code and stage are.
abstract interface class ShellProbe {
  /// The page shown.
  ShellPage get page;

  /// Where the focus is: the list, the filter or the page.
  Zone get zone;

  /// The route of where the gallery is now.
  GalleryRoute get route;

  /// The room the stage gave the page shown at its last layout; null
  /// before it was laid out.
  StageRoom? get room;

  /// The Dart of the page shown's Code tab, its options as they are, in
  /// [room]; null where it has no Code tab.
  String? get code;
}

/// The state of a [GalleryShell]: where it is, what is chosen, open and
/// moving.
final class GalleryShellState extends State<GalleryShell>
    implements ShellProbe {
  late final List<ShellGroup> groups = joinCatalog(widget.pages);
  late final List<ShellPage> pages = [for (final g in groups) ...g.pages];
  late final Map<String, ShellPage> _byKey = {for (final p in pages) p.key: p};

  @override
  late ShellPage page = pages.first;

  /// The page the gallery opened at.
  late final ShellPage _firstPage;
  GalleryTab tab = GalleryTab.preview;
  var filter = '';
  var themeName = 'dark';
  var _asciiGlyphs = false;
  Zone _zone = Zone.list;

  /// Whether the stage had the focus when the focus was last in the
  /// shell's own zones: it keeps it while a dialog or menu of the page, in
  /// the app's Overlay, or the palette has the focus, as the design's
  /// `S.pageFocus` stays on the page.
  var _stageHadFocus = false;

  /// Each page's options and its own state, by page key.
  late final _store = PageStore(update: setState, toast: toast);

  /// The titles of what the palette ran, the last first.
  final _recent = <String>[];
  PaletteState? _palette;
  final _toasts = Toasts();

  var _codeScroll = 0;
  var _codeX = 0;
  final _codes = <String, CodeRecord>{};

  /// How far the Code tab scrolls, as it was last painted.
  var _codeMaxScroll = 0;

  /// What the mouse selected in the Code tab (its SelectionArea): the
  /// shell builds again when something comes to be selected and when
  /// nothing is any more, for the hint of Escape.
  late final _selection = SelectionAreaController()..addListener(_rebuild);

  /// The room the stage last gave each page's widget, by page key, for
  /// its Code ([GalleryPage.codeIn]).
  final _rooms = <String, StageRoom>{};

  // the page's dissolve, and the body's on a change of tab
  var _pageSerial = 0;
  var _bodySerial = 0;

  // the list's scroll, kept between frames
  var _listTarget = 0;
  int? _lastSel;
  String? _lastFilter;
  int? _lastLh;

  // the scroll of the options under a narrow stage, by page key
  final _optionScroll = <String, int>{};

  // where the mouse is on the screen, and whether a button is held
  (int, int)? _mouse;
  var _pressed = false;

  // the slider an option press grabbed: where, and the thumb's start
  ({int at, int start})? _grab;

  late final _motion = Motion(_rebuild);

  late final _list = FocusNode(
    debugLabel: 'gallery list',
    onKeyEvent: (_, e) => _handled(_toPalette(e) || _listKey(e)),
  );
  late final _filter = FocusNode(
    debugLabel: 'gallery filter',
    skipTraversal: true,
    onKeyEvent: (_, e) => _handled(_toPalette(e) || _filterKey(e)),
  );
  late final _code = FocusNode(
    debugLabel: 'gallery code',
    onKeyEvent: (_, e) => _handled(_toPalette(e) || _codeKey(e)),
  );
  late final _paletteNode = FocusNode(
    debugLabel: 'gallery palette',
    onKeyEvent: (_, e) {
      if (keyName(e) == 'ctrl+c') {
        return KeyEventResult.ignored;
      }
      _paletteKey(e);
      return KeyEventResult.handled;
    },
  );
  final _pageNode = FocusNode(
    debugLabel: 'gallery page',
    canRequestFocus: false,
  );
  final _stageNode = FocusNode(
    debugLabel: 'gallery stage',
    canRequestFocus: false,
  );
  final _optionNodes = <String, FocusNode>{};

  // the node the palette took the focus from
  FocusNode? _beforePalette;
  FocusManager? _manager;
  var _routeApplied = false;

  Clock get _clock => widget.clock;

  /// [setState], for the parts of the shell in the files of its own.
  void _update(void Function() change) => setState(change);

  @override
  void initState() {
    super.initState();
    for (final n in [_list, _filter, _pageNode, _stageNode, _code]) {
      n.addListener(_focusChanged);
    }
    _openRoute(widget.route);
    _firstPage = page;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = Focus.maybeOf(context, createDependency: false)?.manager;
    if (!identical(manager, _manager)) {
      _manager?.keysChanged.removeListener(_focusChanged);
      _manager = manager?..keysChanged.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    _manager?.keysChanged.removeListener(_focusChanged);
    _motion.dispose();
    _selection.dispose();
    for (final n in [
      _list,
      _filter,
      _code,
      _paletteNode,
      _pageNode,
      _stageNode,
      ..._optionNodes.values,
    ]) {
      n.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  void _focusChanged() {
    final zone = _filter.hasFocus
        ? Zone.filter
        : _list.hasFocus
        ? Zone.list
        : _pageNode.hasFocus
        ? Zone.page
        : null;
    if (zone != null) {
      _zone = zone;
      _stageHadFocus = _stageNode.hasFocus;
    } else if (_zone == Zone.page &&
        _palette == null &&
        _manager != null &&
        _manager!.primaryFocus == null) {
      // the page's focused stop went with no stop after it (the last
      // window of WindowLayer closed): twk leaves the focus on no node,
      // the design's shell takes it back to the list
      _zone = Zone.list;
      _stageHadFocus = false;
      _list.requestFocus();
    }
    _rebuild();
  }

  @override
  Zone get zone => _zone;

  /// The palette's query while it is open.
  String? get paletteQuery => _palette?.query;

  // ------------------------------------------------------------ route

  void _openRoute(GalleryRoute? route) {
    if (route == null) {
      return;
    }
    final group = groups.where((g) => g.slug == route.group).firstOrNull;
    page =
        _byKey['${route.group}/${route.page}'] ??
        group?.pages.first ??
        pages.first;
    if (galleryThemes.containsKey(route.theme)) {
      themeName = route.theme!;
    }
    _asciiGlyphs = route.glyphs == 'ascii';
    final def = page.def;
    if (def != null && route.options.isNotEmpty) {
      final raw = _store.rawOf(page.key);
      for (final opt in def.options) {
        final v = route.options[opt.key];
        if (v == null) {
          continue;
        }
        if (opt.rawNamed(v) case final value?) {
          raw[opt.key] = value;
        }
      }
    }
    if (route.tab == GalleryTab.code.name && (def?.hasCode ?? false)) {
      tab = GalleryTab.code;
    }
    filter = route.filter ?? '';
    final palette = route.palette;
    if (palette != null) {
      _palette = PaletteState(palette, Duration.zero);
    }
    final toast = route.toast;
    if (toast != null) {
      final kind = ToastKind.values.asNameMap()[route.kind] ?? ToastKind.info;
      _toasts.add(Toast(toast, kind, Duration.zero), capped: false);
    }
  }

  /// What the route focuses as the gallery opens: `list`, `filter`,
  /// `code`, `o:<key>`, or `page` for the first stop of the page.
  late final String _firstFocus = () {
    final focus = widget.route?.focus;
    final def = page.def;
    return switch (focus) {
      null || 'list' => 'list',
      'filter' => 'filter',
      'code' => tab == GalleryTab.code ? 'code' : 'list',
      final f when f.startsWith('o:') =>
        def != null && def.options.any((o) => 'o:${o.key}' == f) ? f : 'list',
      _ => 'page',
    };
  }();

  /// Focuses what the route asks for first; returns the node.
  FocusNode _focusFirst() {
    final page0 = _firstPage;
    final node = switch (_firstFocus) {
      'filter' => _filter,
      'code' => _code,
      final f when f.startsWith('o:') => _optionNode(page0, f.substring(2)),
      _ => _list,
    };
    if (_firstFocus == 'page') {
      _focusPage();
      return _manager?.primaryFocus ?? _list;
    }
    node.requestFocus();
    return node;
  }

  /// Moves the focus to the page's first stop, as the route asks.
  void _focusPage() {
    _list
      ..requestFocus()
      ..nextFocus();
  }

  @override
  GalleryRoute get route {
    final def = page.def;
    final o = def == null ? '' : _store.optionsOf(page.key, def).route;
    return GalleryRoute(
      group: page.group.slug,
      page: page.slug,
      theme: themeName == 'dark' ? null : themeName,
      glyphs: _asciiGlyphs ? 'ascii' : null,
      tab: tab == GalleryTab.code ? GalleryTab.code.name : null,
      options: {
        for (final part in o.split(';'))
          if (part.contains(':'))
            part.substring(0, part.indexOf(':')): part.substring(
              part.indexOf(':') + 1,
            ),
      },
      t: _clock.frozenAt,
    );
  }

  // ------------------------------------------------------------ options

  Options? _optionsOf(ShellPage p) {
    final def = p.def;
    return def == null ? null : _store.optionsOf(p.key, def);
  }

  FocusNode _optionNode(ShellPage p, String key) =>
      _optionNodes['${p.key}:$key'] ??= FocusNode(
        debugLabel: 'option $key',
        onKeyEvent: (_, e) {
          final opt = p.def?.options.where((o) => o.key == key).firstOrNull;
          return _handled(
            _toPalette(e) || opt != null && _optionKey(p, opt, e),
          );
        },
      );

  // ------------------------------------------------------------ actions

  /// Shows [p], dissolving the page before into it.
  void show(ShellPage p, {bool keepZone = false}) {
    if (identical(p, page)) {
      return;
    }
    _clearSelection();
    setState(() {
      page = p;
      _pageSerial++;
      _codeScroll = 0;
      _codeX = 0;
      _grab = null;
      if (tab == GalleryTab.code && !(p.def?.hasCode ?? false)) {
        tab = GalleryTab.preview;
      }
    });
    if (!keepZone && _zone == Zone.page) {
      _list.requestFocus();
    }
  }

  void _setTab(GalleryTab t) {
    if (t == tab) {
      return;
    }
    if (t == GalleryTab.code && !(page.def?.hasCode ?? false)) {
      toast('This page is not drawn yet: no code to show');
      return;
    }
    _clearSelection();
    setState(() {
      tab = t;
      _bodySerial++;
    });
  }

  void _setTheme(String name, {bool quiet = false}) {
    setState(() => themeName = name);
    if (!quiet) {
      toast('Theme: ${galleryThemes[name]!.$1}');
    }
  }

  void _nextTheme([int step = 1]) {
    final names = galleryThemes.keys.toList();
    final i = names.indexOf(themeName);
    _setTheme(names[(i + step + names.length) % names.length]);
  }

  /// Shows [message] in a toast of [kind] for a while.
  void toast(String message, [ToastKind kind = ToastKind.info]) {
    setState(() => _toasts.add(Toast(message, kind, _motion.now)));
  }

  @override
  StageRoom? get room => _rooms[page.key];

  @override
  String? get code {
    final def = page.def;
    final o = _optionsOf(page);
    return def == null || o == null
        ? null
        : def.codeOf(o, room ?? StageRoom.unbounded);
  }

  void _copyCode() {
    final src = code;
    if (src == null) {
      return;
    }
    if (_toClipboard(src)) {
      toast(
        'Copied ${src.split('\n').length} lines of Dart',
        ToastKind.success,
      );
    }
  }

  /// What the mouse selected of the code, copied.
  void _copySelected(String text) {
    if (_toClipboard(text)) {
      toast('Copied ${copiedWhat(text)}', ToastKind.success);
    }
  }

  /// Clears what is selected of the code; whether anything was.
  bool _clearSelection() {
    if (!_selection.hasSelection) {
      return false;
    }
    _selection.clear();
    return true;
  }

  /// `y` and ⧉ copy: what is selected of the code, else the whole code.
  void _copy() {
    final selected = _selection.text;
    if (selected.isNotEmpty) {
      _copySelected(selected);
    } else {
      _copyCode();
    }
  }

  /// Writes [text] to the system clipboard (OSC 52, wrapped for a
  /// multiplexer); whether there was a terminal to write it to.
  bool _toClipboard(String text) {
    final terminal = AppBinding.maybeOf(context)?.twkApp.terminal;
    if (terminal == null) {
      toast('The clipboard is not available here', ToastKind.warning);
      return false;
    }
    terminal.write(
      ascii.encode(
        clipboardSequence(text, multiplexer: terminal.info.multiplexer),
      ),
    );
    return true;
  }

  void _listUp() => _listStep(-1);
  void _listDown() => _listStep(1);
  void _intoPage() => _list.nextFocus();
  void _toFilter() => _filter.requestFocus();
  void _search() => _openPalette('');
  void _toggleCode() => _setTab(tab.other);
  void _themeKey() => _nextTheme();
  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (!_routeApplied) {
      _routeApplied = true;
      if (_firstFocus == 'page') {
        AppBinding.maybeOf(context)?.scheduleFrameCallback((_) => _focusPage());
      }
    }
    final base = galleryTheme(themeName, context);
    final theme = _asciiGlyphs ? base.copyWith(glyphs: Glyphs.ascii) : base;
    return ClockScope(
      clock: _clock,
      child: AnimatedTheme(
        data: theme,
        duration: _clock.frozen
            ? Duration.zero
            : const Duration(milliseconds: themeFadeMs),
        curve: const ThemeCurve(),
        child: Overlay(
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: _onKey,
            debugLabel: 'gallery',
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onMove: (e) => _hover(e.screenX, e.screenY),
              onPointerDown: (e) => _pressed = true,
              onPointerUp: (e) => _pressed = false,
              child: LayoutBuilder(builder: _screen),
            ),
          ),
        ),
      ),
    );
  }

  void _hover(int x, int y) {
    if (_mouse != (x, y)) {
      setState(() => _mouse = (x, y));
    }
  }

  /// Whether the mouse is over [w] × [h] cells at [x], [y] of the screen,
  /// no button held.
  bool _hovering(int x, int y, int w, int h) {
    final m = _mouse;
    return m != null &&
        !_pressed &&
        m.$1 >= x &&
        m.$1 < x + w &&
        m.$2 >= y &&
        m.$2 < y + h;
  }

  Widget _screen(BuildContext context, BoxConstraints c) {
    _motion.begin(context);
    final t = Tokens(Theme.of(context));
    final w = c.maxWidth < BoxConstraints.unbounded ? c.maxWidth : 120;
    final h = c.maxHeight < BoxConstraints.unbounded ? c.maxHeight : 36;
    final sw = sidebarWidth(w);
    final children = <Widget>[
      Positioned(
        left: 0,
        top: 1,
        width: sw,
        height: h - 2 < 0 ? 0 : h - 2,
        child: _sidebar(t, sw, h - 2),
      ),
      Positioned(
        left: sw,
        top: 1,
        width: w - sw,
        height: h - 2 < 0 ? 0 : h - 2,
        child: _pageArea(context, t, w, h, w - sw, h - 2),
      ),
      Positioned(left: 0, top: 0, width: w, height: 1, child: _header(t, w)),
      Positioned(
        left: 0,
        top: h - 1,
        width: w,
        height: 1,
        child: _hints(t, w),
      ),
      ..._paletteLayer(t, w, h),
      ?_toastLayer(t, w, h),
    ];
    _motion.end();
    return Box(
      style: Style(bg: t.background, fg: t.text),
      child: Stack(children: children),
    );
  }
}
