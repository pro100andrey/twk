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

import '../motion.dart';
import '../page.dart';
import '../paint.dart';
import '../route.dart';
import 'catalog_pages.dart';
import 'code_select.dart';
import 'controls.dart';
import 'dissolve.dart';
import 'split.dart';
import 'stage.dart';
import 'tokens.dart';

/// Where the focus is, as the design names it.
enum Zone { list, filter, page }

/// A toast: [message] of [kind] (`info`, `success`, `warning`, `error`),
/// shown at [at].
final class _Toast {
  _Toast(this.message, this.kind, this.at);

  final String message;
  final String kind;
  final Duration at;
}

/// The palette while it is open.
final class _PaletteState {
  _PaletteState(this.query, this.opened);

  String query;
  final Duration opened;
  var selected = 0;
  var scroll = 0;
}

/// What the palette lists: [title], [detail] at its right, and what it
/// runs.
final class _Item {
  const _Item(this.title, this.detail, this.run);

  final String title;
  final String detail;
  final void Function() run;
}

/// The Code tab of a page as last shown: its lines, and when each last
/// changed.
final class _CodeRecord {
  _CodeRecord(this.source, this.lines, this.changed, this.tokens)
    : text = CodeText(source);

  final String source;

  /// The code as the mouse selects in it.
  final CodeText text;
  final List<String> lines;
  final List<Duration?> changed;
  final List<List<Token>> tokens;
}

/// What a page's widget asks of the shell.
final class _Control implements PageControl {
  _Control(this.shell, this.page);

  final GalleryShellState shell;
  final ShellPage page;

  @override
  Map<String, Object?> get state => shell._states[page.key] ??= {};

  @override
  void setOption(String key, Object? value) {
    final opt = page.def?.options.where((o) => o.key == key).firstOrNull;
    final raw = switch (opt) {
      null => null,
      SwitchOption() || SliderOption() => value,
      final ChoiceOption o => o.values.indexOf(value),
      final ColorOption o => value is String ? o.values.indexOf(value) : -1,
    };
    if (opt == null || raw == null || raw == -1) {
      return;
    }
    if (shell._rawOf(page)[key] != raw) {
      shell._setOption(page, opt, raw);
    }
  }

  @override
  void toast(String message, [String kind = 'info']) =>
      shell.toast(message, kind);
}

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

/// The state of a [GalleryShell]: where it is, what is chosen, open and
/// moving.
final class GalleryShellState extends State<GalleryShell> {
  late final List<ShellGroup> groups = joinCatalog(widget.pages);
  late final List<ShellPage> pages = [for (final g in groups) ...g.pages];
  late final Map<String, ShellPage> _byKey = {for (final p in pages) p.key: p};

  late ShellPage page = pages.first;

  /// The page the gallery opened at.
  late final ShellPage _firstPage = page;
  var tab = 'preview';
  var filter = '';
  var themeName = 'dark';
  Zone _zone = Zone.list;

  /// Whether the stage had the focus when the focus was last in the
  /// shell's own zones: it keeps it while a dialog or menu of the page, in
  /// the app's Overlay, or the palette has the focus, as the design's
  /// `S.pageFocus` stays on the page.
  var _stageHadFocus = false;

  /// The raw values of each page's options, by page key.
  final _options = <String, Map<String, Object>>{};

  /// Each page's own state, by page key ([PageControl.state]).
  final _states = <String, Map<String, Object?>>{};
  final _controls = <String, _Control>{};

  _Control _controlOf(ShellPage p) => _controls[p.key] ??= _Control(this, p);

  /// The titles of what the palette ran, the last first.
  final _recent = <String>[];
  _PaletteState? _palette;
  final _toasts = <_Toast>[];

  var _codeScroll = 0;
  var _codeX = 0;
  final _codes = <String, _CodeRecord>{};

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

  @override
  void initState() {
    super.initState();
    for (final n in [_list, _filter, _pageNode, _stageNode, _code]) {
      n.addListener(_focusChanged);
    }
    _openRoute(widget.route);
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
    _keepOptionInView();
    _rebuild();
  }

  /// Where the focus is: the list, the filter or the page.
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
    final def = page.def;
    if (def != null && route.options.isNotEmpty) {
      final raw = _rawOf(page);
      for (final opt in def.options) {
        final v = route.options[opt.key];
        if (v == null) {
          continue;
        }
        final value = switch (opt) {
          SwitchOption() => v == 'true' || v == 'on' || v == '1',
          final SliderOption o =>
            num.tryParse(v) == null ? null : o.clampStep(num.parse(v)),
          final ChoiceOption o =>
            o.names.contains(v) ? o.names.indexOf(v) : null,
          final ColorOption o =>
            o.values.contains(v) ? o.values.indexOf(v) : null,
        };
        if (value != null) {
          raw[opt.key] = value;
        }
      }
    }
    if (route.tab == 'code' && (def?.hasCode ?? false)) {
      tab = 'code';
    }
    filter = route.filter ?? '';
    final palette = route.palette;
    if (palette != null) {
      _palette = _PaletteState(palette, Duration.zero);
    }
    final toast = route.toast;
    if (toast != null) {
      _toasts.add(_Toast(toast, route.kind ?? 'info', Duration.zero));
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
      'code' => tab == 'code' ? 'code' : 'list',
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

  /// The route of where the gallery is now.
  GalleryRoute get route {
    final def = page.def;
    final o = def == null ? '' : Options(def, _rawOf(page)).route;
    return GalleryRoute(
      group: page.group.slug,
      page: page.slug,
      theme: themeName == 'dark' ? null : themeName,
      tab: tab == 'code' ? 'code' : null,
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

  Map<String, Object> _rawOf(ShellPage p) => _options[p.key] ??= {};

  Options? _optionsOf(ShellPage p) {
    final def = p.def;
    return def == null ? null : Options(def, _rawOf(p));
  }

  void _setOption(ShellPage p, PageOption opt, Object raw) {
    setState(() => _rawOf(p)[opt.key] = raw);
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
      if (tab == 'code' && !(p.def?.hasCode ?? false)) {
        tab = 'preview';
      }
    });
    if (!keepZone && _zone == Zone.page) {
      _list.requestFocus();
    }
  }

  void _setTab(String t) {
    if (t == tab) {
      return;
    }
    if (t == 'code' && !(page.def?.hasCode ?? false)) {
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
  void toast(String message, [String kind = 'info']) {
    setState(() {
      _toasts.add(_Toast(message, kind, _motion.now));
      if (_toasts.length > 3) {
        _toasts.removeAt(0);
      }
    });
  }

  /// The room the stage gave the page shown at its last layout; null
  /// before it was laid out.
  StageRoom? get room => _rooms[page.key];

  /// The Dart of the page shown's Code tab, its options as they are, in
  /// [room]; null where it has no Code tab.
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
      toast('Copied ${src.split('\n').length} lines of Dart', 'success');
    }
  }

  /// What the mouse selected of the code, copied.
  void _copySelected(String text) {
    if (_toClipboard(text)) {
      toast('Copied ${copiedWhat(text)}', 'success');
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
      toast('The clipboard is not available here', 'warning');
      return false;
    }
    terminal.write(
      ascii.encode(
        clipboardSequence(text, multiplexer: terminal.info.multiplexer),
      ),
    );
    return true;
  }

  // ------------------------------------------------------------ keys

  static KeyEventResult _handled(bool taken) =>
      taken ? KeyEventResult.handled : KeyEventResult.ignored;

  /// [e] as the design names keys: `tab`, `shift+tab`, `ctrl+p`, `t`,
  /// `T`, `space`, `pageup`.
  static String keyName(KeyEvent e) {
    final m = e.modifiers;
    final String base;
    if (e.code == KeyCode.char) {
      base = e.char == ' ' ? 'space' : e.char;
    } else {
      base = switch (e.code) {
        KeyCode.pageUp => 'pageup',
        KeyCode.pageDown => 'pagedown',
        final c => c.name,
      };
    }
    final shift = (m & Mod.shift) != 0 && e.code != KeyCode.char;
    return [
      if ((m & Mod.ctrl) != 0) 'ctrl',
      if ((m & Mod.alt) != 0) 'alt',
      if (shift) 'shift',
      base,
    ].join('+');
  }

  /// The gallery's own keys, which reach it where nothing focused took
  /// them.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e.kind == KeyKind.release) {
      return KeyEventResult.ignored;
    }
    final manager = _manager;
    if (manager != null && manager.primaryFocus == null) {
      // a key before the first focus took its place (the frame after the
      // first): focus what the route asks for, and give the key to it
      final first = _focusFirst();
      if (first.onKeyEvent?.call(first, e) == KeyEventResult.handled) {
        return KeyEventResult.handled;
      }
      if (e.code == KeyCode.tab) {
        if ((e.modifiers & Mod.shift) != 0) {
          first.previousFocus();
        } else {
          first.nextFocus();
        }
        return KeyEventResult.handled;
      }
    }
    if (_toPalette(e)) {
      return KeyEventResult.handled;
    }
    final name = keyName(e);
    if (name == 'ctrl+p') {
      _openPalette('');
      return KeyEventResult.handled;
    }
    if (_zone == Zone.filter && _filter.hasFocus) {
      return KeyEventResult.handled;
    }
    switch (name) {
      case 'escape':
        // a selection of the code first
        if (tab == 'code' && _clearSelection()) {
          break;
        }
        if (_zone == Zone.page && _pageNode.hasFocus) {
          _list.requestFocus();
        } else if (filter.isNotEmpty) {
          setState(() => filter = '');
        } else {
          return KeyEventResult.ignored;
        }
      case 't':
        _nextTheme();
      case 'T':
        _nextTheme(-1);
      case 'c':
        _setTab(tab == 'code' ? 'preview' : 'code');
      case 'y':
        if (tab != 'code') {
          return KeyEventResult.ignored;
        }
        _copy();
      case '/':
        _filter.requestFocus();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The pages the list shows: all, or those the filter matches.
  List<ShellPage> get visiblePages => filter.isEmpty
      ? pages
      : [
          for (final p in pages)
            if (fuzzyMatch(filter, p.title) != null) p,
        ];

  /// Shows the page [step] rows from this one in the list.
  void _listStep(int step) {
    final visible = visiblePages;
    final i = visible.indexOf(page);
    if (visible.isNotEmpty) {
      show(visible[(i < 0 ? 0 : i + step).clamp(0, visible.length - 1)]);
    }
  }

  // ------------------------------------------------------------ layers

  // The keys of the list, bound in a hinted layer around it, so that
  // FocusManager.activeKeys lists them (a KeyHintsBar on the stage):
  // tear-offs, the same binding at each build. The page's Tab, Shift+Tab
  // and Escape are not bound: Tab goes to the page's InputListeners before
  // it moves the focus, and a page's own KeyHintsBar lists its keys alone

  void _listUp() => _listStep(-1);
  void _listDown() => _listStep(1);
  void _intoPage() => _list.nextFocus();
  void _toFilter() => _filter.requestFocus();
  void _search() => _openPalette('');
  void _toggleCode() => _setTab(tab == 'code' ? 'preview' : 'code');
  void _themeKey() => _nextTheme();

  /// The list's layer: what the hint bar shows while the list has the
  /// focus.
  Widget _listLayer(Widget child) => KeyBindings(
    {
      'up': _listUp,
      'down': _listDown,
      'tab': _intoPage,
      '/': _toFilter,
      'ctrl+p': _search,
      'c': _toggleCode,
      't': _themeKey,
    },
    hints: {
      'up': 'pages',
      'down': 'pages',
      'tab': 'into the page',
      '/': 'filter',
      'ctrl+p': 'search',
      'c': tab == 'code' ? 'preview' : 'code',
      't': 'theme',
    },
    debugLabel: 'gallery list keys',
    child: child,
  );

  bool _listKey(KeyEvent e) {
    if (e.kind == KeyKind.release) {
      return false;
    }
    final visible = visiblePages;
    final i = visible.indexOf(page);
    bool go(int k) {
      if (visible.isNotEmpty) {
        show(visible[k.clamp(0, visible.length - 1)]);
      }
      return true;
    }

    // up and down are the layer's too; the node takes them first, as
    // before the first focus
    switch (keyName(e)) {
      case 'up':
        _listStep(-1);
        return true;
      case 'down':
        _listStep(1);
        return true;
      case 'home':
        return go(0);
      case 'end':
        return go(visible.length - 1);
      case 'pageup':
        return go(i - 10);
      case 'pagedown':
        return go(i + 10);
      case 'enter' || 'right':
        _list.nextFocus();
        return true;
    }
    return false;
  }

  bool _filterKey(KeyEvent e) {
    if (e.kind == KeyKind.release) {
      return false;
    }
    final name = keyName(e);
    switch (name) {
      case 'escape':
        if (filter.isNotEmpty) {
          setState(() => filter = '');
        } else {
          _list.requestFocus();
        }
        return true;
      case 'enter' || 'down' || 'tab':
        final v = visiblePages;
        if (v.isNotEmpty && !v.contains(page)) {
          show(v.first);
        }
        _list.requestFocus();
        return true;
      case 'backspace':
        final runes = filter.runes.toList();
        if (runes.isNotEmpty) {
          setState(
            () => filter = String.fromCharCodes(runes..removeLast()),
          );
        }
        return true;
      case 'ctrl+u':
        setState(() => filter = '');
        return true;
    }
    if (e.code == KeyCode.char && (e.modifiers & ~Mod.shift) == 0) {
      setState(() => filter += e.char);
      final v = visiblePages;
      if (v.isNotEmpty && !v.contains(page)) {
        show(v.first, keepZone: true);
      }
      return true;
    }
    return false;
  }

  bool _codeKey(KeyEvent e) {
    if (e.kind == KeyKind.release) {
      return false;
    }
    final name = keyName(e);
    final step = const {
      'up': -1,
      'down': 1,
      'pageup': -10,
      'pagedown': 10,
      'home': -1000000,
      'end': 1000000,
    }[name];
    if (step != null) {
      setState(() => _codeScroll = (_codeScroll + step).clamp(0, 1000000));
      return true;
    }
    final side = const {'left': -4, 'right': 4}[name];
    if (side != null) {
      setState(() => _codeX = (_codeX + side).clamp(0, 80));
      return true;
    }
    return false;
  }

  bool _optionKey(ShellPage p, PageOption opt, KeyEvent e) {
    if (e.kind == KeyKind.release) {
      return false;
    }
    final options = _optionsOf(p);
    if (options == null || !options.applies(opt)) {
      return false;
    }
    final name = keyName(e);
    final r = options.raw(opt.key);
    var taken = true;
    switch (opt) {
      case SwitchOption():
        if (name == 'space' || name == 'enter') {
          _setOption(p, opt, !(r as bool));
        } else {
          taken = false;
        }
      case final SliderOption o:
        final step = o.step;
        final tenth = ((o.max - o.min) / 10 / step).round() * step;
        final big = tenth > step ? tenth : step;
        final v = r as num;
        final next = switch (name) {
          'left' || 'down' => v - step,
          'right' || 'up' => v + step,
          'pageup' => v + big,
          'pagedown' => v - big,
          'home' => o.min,
          'end' => o.max,
          _ => null,
        };
        if (next == null) {
          taken = false;
        } else {
          _setOption(p, opt, o.clampStep(next));
        }
      case ChoiceOption() || ColorOption():
        final n = opt is ChoiceOption
            ? opt.values.length
            : (opt as ColorOption).values.length;
        final i = r as int;
        final next = switch (name) {
          'left' => (i + n - 1) % n,
          'right' || 'space' => (i + 1) % n,
          'home' => 0,
          'end' => n - 1,
          _ => null,
        };
        if (next == null) {
          taken = false;
        } else {
          _setOption(p, opt, next);
        }
    }
    if (taken) {
      return true;
    }
    if (name == 'up' || name == 'down') {
      final ids = [
        for (final o in p.def!.options)
          if (options.applies(o)) o.key,
      ];
      final k = ids.indexOf(opt.key) + (name == 'up' ? -1 : 1);
      if (k >= 0 && k < ids.length) {
        _optionNode(p, ids[k]).requestFocus();
      }
      return true;
    }
    return false;
  }

  // ------------------------------------------------------------ palette

  List<_Item> get _paletteItems => [
    for (final p in pages) _Item(p.title, p.group.title, () => show(p)),
    for (final MapEntry(key: n, value: (label, _)) in galleryThemes.entries)
      _Item('Theme: $label', 'theme', () => _setTheme(n)),
    for (final s in const ['80x24', '100x30', '120x36', '160x48', 'fit'])
      _Item(
        'Grid: ${s == 'fit' ? 'fit the window' : s.replaceAll('x', ' × ')}',
        'size',
        () => toast('Grid: the terminal sets the size'),
      ),
    _Item('Show the code', 'action', () => _setTab('code')),
    _Item('Show the preview', 'action', () => _setTab('preview')),
    _Item('Copy the code', 'action', _copyCode),
    _Item('Reset the options', 'action', () {
      setState(() {
        _options.remove(page.key);
        _states.remove(page.key);
      });
      toast('Options reset');
    }),
    for (final g in groups)
      _Item(
        'Group: ${g.title}',
        '${g.pages.length} pages',
        () => show(g.pages.first),
      ),
  ];

  /// The items that match the palette's query, as twk's CommandPalette
  /// ranks them.
  List<(_Item, FuzzyMatch?)> _paletteMatches() {
    final q = _palette?.query ?? '';
    int lastRun(_Item it) {
      final i = _recent.indexOf(it.title);
      return i < 0 ? _recent.length : i;
    }

    final out = <(_Item, FuzzyMatch?, int, int)>[];
    for (final (i, it) in _paletteItems.indexed) {
      if (q.isEmpty) {
        out.add((it, null, lastRun(it), i));
      } else if (fuzzyMatch(q, it.title) case final m?) {
        out.add((it, m, lastRun(it), i));
      }
    }
    out.sort((a, b) {
      final s = (b.$2?.score ?? 0).compareTo(a.$2?.score ?? 0);
      if (s != 0) {
        return s;
      }
      final r = a.$3.compareTo(b.$3);
      return r != 0 ? r : a.$4.compareTo(b.$4);
    });
    return [for (final (it, m, _, _) in out) (it, m)];
  }

  void _openPalette(String query) {
    final primary = _manager?.primaryFocus;
    setState(() {
      _palette = _PaletteState(query, _motion.now);
    });
    if (!identical(primary, _paletteNode)) {
      _beforePalette = primary;
    }
    // the palette's Focus asks for the focus as it mounts; should the
    // scope's flush come a frame later, it is asked for again then
    AppBinding.maybeOf(context)?.scheduleFrameCallback((_) {
      if (_palette != null && _paletteNode.context != null) {
        _paletteNode.requestFocus();
      }
    });
  }

  /// Gives [e] to the palette while it is open and the focus not in it
  /// yet (the frame it opens in): whether it took it.
  bool _toPalette(KeyEvent e) {
    if (_palette == null) {
      return false;
    }
    if (keyName(e) == 'ctrl+c') {
      return false;
    }
    _paletteKey(e);
    return true;
  }

  void _closePalette() {
    setState(() => _palette = null);
    final before = _beforePalette;
    _beforePalette = null;
    if (before != null && before.context != null) {
      before.requestFocus();
    } else {
      _list.requestFocus();
    }
  }

  void _runItem(_Item it) {
    _closePalette();
    _recent
      ..remove(it.title)
      ..insert(0, it.title);
    it.run();
  }

  void _paletteKey(KeyEvent e) {
    final pal = _palette;
    if (pal == null || e.kind == KeyKind.release) {
      return;
    }
    final m = _paletteMatches();
    final n = m.length;
    final name = keyName(e);
    switch (name) {
      case 'escape' || 'ctrl+p':
        _closePalette();
        return;
      case 'up':
        if (n > 0) {
          setState(() => pal.selected = (pal.selected - 1 + n) % n);
        }
        return;
      case 'down':
        if (n > 0) {
          setState(() => pal.selected = (pal.selected + 1) % n);
        }
        return;
      case 'tab' || 'shift+tab':
        return;
      case 'enter':
        if (pal.selected < n) {
          _runItem(m[pal.selected].$1);
        }
        return;
      case 'backspace':
        final runes = pal.query.runes.toList();
        if (runes.isNotEmpty) {
          setState(() {
            pal
              ..query = String.fromCharCodes(runes..removeLast())
              ..selected = 0;
          });
        }
        return;
      case 'ctrl+u':
        setState(() {
          pal
            ..query = ''
            ..selected = 0;
        });
        return;
    }
    if (e.code == KeyCode.char && (e.modifiers & ~Mod.shift) == 0) {
      setState(() {
        pal
          ..query += e.char
          ..selected = 0;
      });
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (!_routeApplied) {
      _routeApplied = true;
      if (_firstFocus == 'page') {
        AppBinding.maybeOf(context)?.scheduleFrameCallback((_) => _focusPage());
      }
    }
    final theme = galleryTheme(themeName, context);
    return ClockScope(
      clock: _clock,
      child: AnimatedTheme(
        data: theme,
        duration: _clock.frozen
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: const ThemeCurve(),
        child: Overlay(
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: _onKey,
            debugLabel: 'gallery',
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onMove: (e) => _hover(e.screenX, e.screenY),
              onDown: (e) => _pressed = true,
              onUp: (e) => _pressed = false,
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
    final w = c.maxW < BoxConstraints.unbounded ? c.maxW : 120;
    final h = c.maxH < BoxConstraints.unbounded ? c.maxH : 36;
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

  // ------------------------------------------------------------ header

  Widget _header(Tokens t, int w) => Listener(
    behavior: HitTestBehavior.opaque,
    onDown: (e) {
      if (e.button != 0) {
        return;
      }
      final theme = '◐ ${galleryThemes[themeName]!.$1}';
      final tx = w - 2 - widthOf(theme);
      final sx = tx - 4 - 15;
      if (e.x >= tx - 1 && e.x < tx + widthOf(theme) + 1) {
        _nextTheme();
      } else if (e.x >= sx - 1 && e.x < sx + 16) {
        _openPalette('');
      }
    },
    child: CellPaint((p) {
      p.fill(0, 0, w, 1, Style(bg: t.chrome));
      var x = 2;
      x += p.text(x, 0, '◆', Style(fg: t.primary));
      x += 1;
      x += p.text(x, 0, 'twk', Style(fg: t.text, attrs: Attr.bold));
      x += p.text(x, 0, ' gallery', Style(fg: t.muted));
      if (w >= 96) {
        x += 3;
        x += p.text(x, 0, page.group.title, Style(fg: t.dim));
        x += p.text(x, 0, '  ›  ', Style(fg: t.faint));
        p.text(x, 0, page.title, Style(fg: t.muted));
      }
      final theme = '◐ ${galleryThemes[themeName]!.$1}';
      final tw = widthOf(theme);
      final tx = w - 2 - tw;
      final themeHover = _hovering(tx - 1, 0, tw + 2, 1);
      p.text(tx, 0, theme, Style(fg: themeHover ? t.text : t.muted));
      final sx = tx - 4 - 15;
      final searchHover = _hovering(sx - 1, 0, 17, 1);
      p
        ..text(
          sx,
          0,
          'ctrl+p',
          Style(fg: searchHover ? t.text : t.muted, attrs: Attr.bold),
        )
        ..text(sx + 7, 0, 'search', Style(fg: searchHover ? t.text : t.dim));
    }),
  );

  // ------------------------------------------------------------ sidebar

  /// The rows of the list: a group's title, its pages, a gap between
  /// groups.
  List<({String kind, ShellGroup? group, int count, ShellPage? page})>
  _listRows() {
    final rows =
        <({String kind, ShellGroup? group, int count, ShellPage? page})>[];
    for (final g in groups) {
      final shown = filter.isEmpty
          ? g.pages
          : [
              for (final p in g.pages)
                if (fuzzyMatch(filter, p.title) != null) p,
            ];
      if (shown.isEmpty) {
        continue;
      }
      if (rows.isNotEmpty) {
        rows.add((kind: 'gap', group: null, count: 0, page: null));
      }
      rows.add((kind: 'group', group: g, count: shown.length, page: null));
      for (final p in shown) {
        rows.add((kind: 'page', group: g, count: 0, page: p));
      }
    }
    return rows;
  }

  Widget _sidebar(Tokens t, int sw, int bodyH) {
    final rows = _listRows();
    const lt = 3;
    final lh = bodyH - lt - 1 < 0 ? 0 : bodyH - lt - 1;
    final sel = rows.indexWhere((r) => identical(r.page, page));
    var target = _listTarget;
    final moved = sel != _lastSel || filter != _lastFilter || lh != _lastLh;
    _lastSel = sel;
    _lastFilter = filter;
    _lastLh = lh;
    if (sel >= 0 && moved) {
      if (sel < target || sel >= target + lh) {
        target = sel - lh ~/ 3;
      } else if (sel - 2 < target) {
        target = sel - 2 < 0 ? 0 : sel - 2;
      } else if (sel + 3 > target + lh) {
        target = sel + 3 - lh;
      }
    }
    final most = rows.length - lh < 0 ? 0 : rows.length - lh;
    target = target.clamp(0, most);
    _listTarget = target;
    final scroll = _motion.glide('listScroll', target.toDouble(), 160).round();
    final prevSel = _motion.targetOf('listSel')?.round() ?? sel;
    final selY = sel < 0
        ? -1
        : _motion
              .glide(
                'listSel',
                sel.toDouble(),
                (70 + 18 * (sel - prevSel).abs()).clamp(0, 220),
              )
              .round();
    final focusedList = _zone == Zone.list && _palette == null;
    final filterActive = _zone == Zone.filter && _palette == null;
    const fx = 2;
    const fy = 1;
    final fw = sw - 4;
    final count = '${visiblePages.length}';
    final room = fw - 4 - widthOf(count) - 1;
    final shown = cut(filter, room, start: true);
    final list = CellPaint(
      (p) {
        p
          ..fill(0, 0, sw, bodyH, Style(bg: t.chrome))
          // the filter
          ..fill(fx, fy, fw, 1, Style(bg: t.well));
        if (filterActive) {
          p.text(fx - 1, fy, '▎', Style(fg: t.primary));
        }
        p.text(
          fx + 1,
          fy,
          '⌕',
          Style(fg: filterActive || filter.isNotEmpty ? t.primary : t.dim),
        );
        if (filter.isNotEmpty || filterActive) {
          p
            ..text(fx + 3, fy, shown, Style(fg: t.text))
            ..text(fx + fw - 1 - widthOf(count), fy, count, Style(fg: t.dim));
        } else {
          p
            ..text(fx + 3, fy, 'Filter', Style(fg: t.dim))
            ..text(fx + fw - 2, fy, '/', Style(fg: t.dim, attrs: Attr.bold));
        }
        // the selection, gliding from where it was
        if (sel >= 0) {
          final y = lt + selY - scroll;
          if (y >= lt && y < lt + lh) {
            p
              ..fill(
                1,
                y,
                sw - 2,
                1,
                Style(bg: focusedList ? t.selection : t.selectionIdle),
              )
              ..text(1, y, '▎', Style(fg: focusedList ? t.primary : t.muted));
          }
        }
        for (var i = 0; i < lh; i++) {
          if (i + scroll >= rows.length) {
            break;
          }
          final r = rows[i + scroll];
          final y = lt + i;
          if (r.kind == 'group') {
            final c = '${r.count}';
            final label = cut(
              r.group!.title.toUpperCase(),
              sw - 7 - widthOf(c),
            );
            p
              ..text(3, y, label, Style(fg: t.muted))
              ..text(sw - 3 - widthOf(c), y, c, Style(fg: t.dim));
          } else if (r.kind == 'page') {
            final pg = r.page!;
            final selected = identical(pg, page);
            if (!selected && _hovering(1, y + 1, sw - 2, 1)) {
              p.bg(1, y, sw - 2, 1, t.lit(t.chrome, t.selection, 0.35));
            }
            // every title in the text colour, as the design shows them
            // all drawn; a page not drawn yet says so on its stage
            final fg = t.text;
            final title = cut(pg.title, sw - 8);
            p.text(
              5,
              y,
              title,
              Style(fg: fg, attrs: selected ? Attr.bold : 0),
            );
            if (filter.isNotEmpty) {
              final m = fuzzyMatch(filter, pg.title);
              for (final at in m?.positions ?? const <int>[]) {
                final col = widthOf(pg.title.substring(0, at));
                if (col < widthOf(title)) {
                  p.color(5 + col, y, 1, 1, t.primary, Attr.bold);
                }
              }
            }
          }
        }
        if (rows.isEmpty) {
          p.text(3, lt, 'no page matches', Style(fg: t.muted));
        }
        p.thumb(sw - 1, lt, lh, rows.length, scroll, t.muted);
      },
      cursor: filterActive ? (fx + 3 + widthOf(shown), fy) : null,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: _listLayer(
            Focus(
              focusNode: _list,
              autofocus: _firstFocus == 'list',
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onDown: (e) {
                  if (e.button != 0) {
                    return;
                  }
                  if (e.y == fy && e.x >= fx && e.x < fx + fw) {
                    _filter.requestFocus();
                    return;
                  }
                  final i = e.y - lt;
                  if (i < 0 || i >= lh || i + scroll >= rows.length) {
                    return;
                  }
                  if (e.x < 1 || e.x >= sw - 1) {
                    return;
                  }
                  final r = rows[i + scroll];
                  if (r.kind == 'page') {
                    show(r.page!);
                    _list.requestFocus();
                  } else if (r.kind == 'group') {
                    final g = r.group!;
                    final first =
                        g.pages
                            .where(
                              (p) =>
                                  filter.isEmpty ||
                                  fuzzyMatch(filter, p.title) != null,
                            )
                            .firstOrNull ??
                        g.pages.first;
                    show(first);
                  }
                },
                onScroll: (e) => setState(() {
                  _listTarget = (_listTarget + _wheel(e) * 3).clamp(0, most);
                  _lastSel = sel;
                }),
                child: list,
              ),
            ),
          ),
        ),
        Positioned(
          left: fx,
          top: fy,
          width: fw,
          height: 1,
          child: Focus(
            focusNode: _filter,
            autofocus: _firstFocus == 'filter',
            child: const SizedBox(),
          ),
        ),
      ],
    );
  }

  /// The rows the wheel moved: down positive.
  static int _wheel(PointerEvent e) => e.scrollY;

  // ------------------------------------------------------------ page

  Widget _pageArea(
    BuildContext context,
    Tokens t,
    int screenW,
    int screenH,
    int pw,
    int ph,
  ) {
    final pad = pw >= 70 ? pagePad : 2;
    final iw = pw - pad - 2;
    final short = screenH < 30;
    final def = page.def;
    final options = _optionsOf(page);
    final where = '${page.index + 1} of ${page.group.pages.length}';
    const tabs = [('preview', 'Preview'), ('code', 'Code')];
    final tabsW = tabs.fold(-3, (n, tb) => n + widthOf(tb.$2) + 3);
    final opts = def?.options ?? const <PageOption>[];
    // the inspector beside the stage where the page is wide, and the stage
    // keeps the columns its widget needs (less the marks' three each side)
    final besideW = opts.isNotEmpty ? inspectorWidth(screenW) : 0;
    final needs = def?.minWidth;
    final wide = pw >= 76 && (needs == null || pw - besideW - 6 >= needs);
    final inspW = wide ? besideW : 0;

    // where each tab is on its row, and the underline gliding to it
    final tabX = <String, (int, int)>{};
    var tx = short ? pw - 2 - tabsW : pad;
    for (final (id, label) in tabs) {
      tabX[id] = (tx, widthOf(label));
      tx += widthOf(label) + 3;
    }
    final (ax, aw) = tabX[tab]!;
    final ux = _motion.glide('tabX', ax.toDouble(), 160).round();
    final uw = _motion.glide('tabW', aw.toDouble(), 160).round();

    void drawTabs(Painter p, int y, {required int screenY}) {
      for (final (id, label) in tabs) {
        final (x, lw) = tabX[id]!;
        final on = tab == id;
        final can = id != 'code' || (def?.hasCode ?? false);
        final hov = _hovering(screenW - pw + x - 1, screenY, lw + 2, 1);
        final fg = on
            ? (short ? t.primary : t.text)
            : !can
            ? t.faint
            : hov
            ? t.text
            : t.muted;
        p.text(x, y, label, Style(fg: fg, attrs: on ? Attr.bold : 0));
      }
    }

    void pressTabs(PointerEvent e) {
      if (e.button != 0) {
        return;
      }
      for (final (id, label) in tabs) {
        final (x, lw) = tabX[id]!;
        if (e.x >= x - 1 && e.x < x + widthOf(label) + 1) {
          _setTab(id);
        }
      }
    }

    final aboutW = iw < 84 ? iw : 84;
    final titleRow = Listener(
      behavior: HitTestBehavior.opaque,
      onDown: short ? pressTabs : null,
      child: CellPaint(height: 1, (p) {
        p.text(pad, 0, page.title, Style(fg: t.text, attrs: Attr.bold));
        if (!short) {
          p.text(pw - 2 - widthOf(where), 0, where, Style(fg: t.dim));
        } else {
          drawTabs(p, 0, screenY: 2);
        }
      }),
    );
    final tabRow = Listener(
      behavior: HitTestBehavior.opaque,
      onDown: (e) {
        pressTabs(e);
        if (tab == 'code' && (def?.hasCode ?? false) && e.button == 0) {
          final cx = pw - 2 - widthOf('⧉ copy');
          if (e.x >= cx - 1 && e.x < cx + 7) {
            _copy();
          }
        }
      },
      child: CellPaint(height: 1, (p) {
        drawTabs(p, 0, screenY: -1);
        if (tab == 'code' && (def?.hasCode ?? false)) {
          final cx = pw - 2 - widthOf('⧉ copy');
          p
            ..text(cx, 0, '⧉', Style(fg: t.muted))
            ..text(cx + 2, 0, 'copy', Style(fg: t.muted))
            ..text(cx - 3, 0, 'y', Style(fg: t.dim, attrs: Attr.bold));
        }
      }),
    );
    final rule = CellPaint(height: 1, (p) {
      p.hline(0, 0, pw, t.faint, '─');
      if (!short) {
        p.hline(ux, 0, uw, t.primary, '━');
      }
      if (inspW > 0) {
        p.text(pw - inspW, 0, '┬', Style(fg: t.faint));
      }
    });

    Widget body;
    final stageFocused = _zone == Zone.page && _stageHadFocus;
    final key = page.key;
    if (tab == 'code' && def != null && def.hasCode && options != null) {
      // the Code in the room the stage would give the widget here
      body = LayoutBuilder(
        builder: (context, c) {
          final room = StageRoom(
            c.maxW - 6 < 0 ? 0 : c.maxW - 6,
            c.maxH - 2 < 0 ? 0 : c.maxH - 2,
          );
          _rooms[key] = room;
          // built in layout, after the screen's build: its own frame time
          _motion.begin(context);
          final pane = _codePane(context, t, pad, def.codeOf(options, room)!);
          _motion.end();
          return pane;
        },
      );
    } else {
      body = Stage(
        tokens: t,
        pad: pad,
        focused: stageFocused,
        fill: def?.stage == StageSize.room,
        onRoom: (room) => _rooms[key] = room,
        child: def == null || options == null
            ? null
            : Focus(
                focusNode: _stageNode,
                child: PageControlScope(
                  control: _controlOf(page),
                  child: Builder(
                    key: ValueKey(page.key),
                    builder: (context) => def.build(context, options),
                  ),
                ),
              ),
      );
    }
    if (options != null && opts.isNotEmpty) {
      if (wide) {
        body = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: body),
            SizedBox(width: inspW, child: _inspector(t, options, inspW)),
          ],
        );
      } else {
        final cw = pw - pad - 2;
        final full = _compactHeight(opts, cw);
        final heightIn = def!.heightIn;
        body = StageOverOptions(
          full: full,
          // the rule and a row: the stage keeps the rest
          least: 2,
          heightIn: heightIn == null ? null : (room) => heightIn(options, room),
          children: [body, _compactInspector(t, options, pw, pad)],
        );
      }
    }
    if (!_clock.frozen) {
      body = Effect(effect: PageDissolve(_bodySerial), child: body);
    }
    Widget area = Focus(
      focusNode: _pageNode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 1),
          titleRow,
          Padding(
            padding: EdgeInsets.only(left: pad),
            child: SizedBox(
              width: aboutW < 0 ? 0 : aboutW,
              child: Text(
                page.about,
                style: Style(fg: t.muted),
                overflow: TextOverflow.ellipsis,
                maxLines: short ? 2 : 3,
              ),
            ),
          ),
          if (!short) ...[const SizedBox(height: 1), tabRow],
          rule,
          Expanded(child: body),
        ],
      ),
    );
    if (!_clock.frozen) {
      area = Effect(effect: PageDissolve(-_pageSerial), child: area);
    }
    return area;
  }

  // ------------------------------------------------------------ code

  /// The Code tab: [src] in the colours of the theme at [themed].
  Widget _codePane(BuildContext themed, Tokens t, int pad, String src) {
    final now = _motion.now;
    var rec = _codes[page.key];
    if (rec == null || rec.source != src) {
      if (rec != null) {
        // an option or the stage's room changed the code: nothing of it
        // is selected
        _selection.clear();
      }
      final lines = src.split('\n');
      final old = rec;
      final h = Highlighter(dartLanguage, src);
      rec = _codes[page.key] = _CodeRecord(
        src,
        lines,
        [
          for (var i = 0; i < lines.length; i++)
            if (old == null)
              null
            else if (i >= old.lines.length || old.lines[i] != lines[i])
              now
            else if (i < old.changed.length)
              old.changed[i]
            else
              null,
        ],
        [for (var i = 0; i < h.lineCount; i++) h.tokens(i)],
      );
    }
    final record = rec;
    final syntax = SyntaxTheme.from(Theme.of(themed));
    final bg = t.dark ? t.well : t.chrome;
    const gut = 4;
    final focused = _code.hasFocus;
    final lit = [
      for (final c in record.changed)
        if (c == null) 0.0 else 1 - _motion.progress(c, 900),
    ];
    final x0 = pad + gut + 1;
    return Focus(
      focusNode: _code,
      autofocus: _firstFocus == 'code',
      // the mouse selects in its lines, as in a Text
      child: SelectionArea(
        controller: _selection,
        // the shell's Escape clears it, wherever the focus is
        clearKey: null,
        // copied as the design copies it, the blanks ending what is
        // selected dropped too
        copyTransform: trimLineEnds,
        onCopy: (text) => toast('Copied ${copiedWhat(text)}', 'success'),
        child: Listener(
          onScroll: (e) {
            final d = _wheel(e);
            setState(() {
              if ((e.modifiers & Mod.shift) != 0) {
                _codeX = (_codeX + d * 4).clamp(0, 80);
              } else {
                _codeScroll = (_codeScroll + d * 3).clamp(0, _codeMaxScroll);
              }
            });
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CellPaint((p) {
                  p.fill(0, 0, p.width, p.height, Style(bg: bg));
                  if (focused) {
                    p.vline(0, 0, p.height, t.primary, '▎');
                  }
                }),
              ),
              Positioned(
                left: 0,
                top: 1,
                right: 0,
                bottom: 1,
                child: CodeLines(
                  code: record.text,
                  x0: x0,
                  scroll: () => _codeScroll,
                  scrollX: () => _codeX,
                  scrollBy: (rows) {
                    final to = (_codeScroll + rows).clamp(0, _codeMaxScroll);
                    if (to == _codeScroll) {
                      return false;
                    }
                    setState(() => _codeScroll = to);
                    return true;
                  },
                  scrollAcross: (columns) {
                    final to = (_codeX + columns).clamp(0, 80);
                    if (to == _codeX) {
                      return false;
                    }
                    setState(() => _codeX = to);
                    return true;
                  },
                  onPaint: (p, selection) {
                    final w = p.width;
                    final viewH = p.height;
                    final lines = record.lines;
                    final maxScroll = lines.length - viewH < 0
                        ? 0
                        : lines.length - viewH;
                    if (_codeScroll > maxScroll) {
                      _codeScroll = maxScroll;
                    }
                    _codeMaxScroll = maxScroll;
                    final end = w - 2;
                    for (var y = 0; y < viewH; y++) {
                      final li = y + _codeScroll;
                      if (li >= lines.length) {
                        break;
                      }
                      final k = lit[li];
                      if (k > 0) {
                        p.bg(1, y, w - 2, 1, t.lit(bg, t.selection, k));
                      }
                      final num = '${li + 1}';
                      p.text(
                        pad + gut - 1 - widthOf(num),
                        y,
                        num,
                        Style(fg: t.dim),
                      );
                      var x = -_codeX;
                      var more = false;
                      final tokens = li < record.tokens.length
                          ? record.tokens[li]
                          : const <Token>[];
                      for (final tok in tokens) {
                        if (x >= end - x0) {
                          more = more || tok.text.isNotEmpty;
                          break;
                        }
                        final style = Style(
                          fg: t.text,
                        ).merge(_tokenStyle(syntax, tok));
                        final tw = widthOf(tok.text);
                        _clipped(p, x0, end, x, y, tok.text, style);
                        x += tw;
                      }
                      if (selection != null) {
                        _paintSelected(
                          p,
                          record.text,
                          li,
                          selection,
                          x0,
                          end,
                          y,
                          t,
                        );
                      }
                      if (more || x > end - x0) {
                        p.text(end, y, '›', Style(fg: t.dim));
                      }
                      if (_codeX > 0 && x > 0) {
                        p.text(x0 - 1, y, '‹', Style(fg: t.dim));
                      }
                    }
                    p.thumb(
                      w - 1,
                      0,
                      viewH,
                      lines.length,
                      _codeScroll,
                      t.muted,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What is selected of line [li] of [code], [selection] of it, in the
  /// selection's colour under the highlighting, on row [y] of the strip
  /// from [x0] to [end].
  void _paintSelected(
    Painter p,
    CodeText code,
    int li,
    (int, int) selection,
    int x0,
    int end,
    int y,
    Tokens t,
  ) {
    final (start, stop) = code.line(li);
    final (s, e) = selection;
    if (s >= stop || e <= start) {
      return;
    }
    final src = code.source;
    var cx = -_codeX;
    var i = start;
    while (i < stop && cx < end - x0) {
      final next = src.characterEndAfter(i);
      final cw = widthOf(src.substring(i, next));
      if (i >= s && i < e && cw > 0 && cx >= 0 && cx + cw <= end - x0) {
        p.bg(x0 + cx, y, cw, 1, t.selection);
      }
      cx += cw;
      i = next;
    }
  }

  /// Writes [text] at column [x] of a strip from [x0] to [end], clipped
  /// to it.
  static void _clipped(
    Painter p,
    int x0,
    int end,
    int x,
    int y,
    String text,
    Style style,
  ) {
    var cx = x;
    for (final r in text.runes) {
      final ch = String.fromCharCode(r);
      final cw = widthOf(ch);
      if (cx >= 0 && cx + cw <= end - x0) {
        p.text(x0 + cx, y, ch, style);
      }
      cx += cw;
    }
  }

  static Style _tokenStyle(SyntaxTheme s, Token tok) => switch (tok.kind) {
    TokenKind.plain => s.plain,
    TokenKind.keyword => s.keyword,
    TokenKind.type => s.type,
    TokenKind.function => s.function,
    TokenKind.variable => s.variable,
    TokenKind.constant => s.constant,
    TokenKind.string => s.string,
    TokenKind.escape => s.escape,
    TokenKind.number => s.number,
    TokenKind.comment => s.comment,
    TokenKind.annotation => s.annotation,
    TokenKind.key => s.key,
    TokenKind.punctuation => s.punctuation,
    TokenKind.operator => s.operator,
    TokenKind.inserted => s.inserted,
    TokenKind.deleted => s.deleted,
    TokenKind.heading => s.heading,
  };

  // ------------------------------------------------------------ inspector

  /// The hint pairs of [opt]'s control.
  static List<(String, String)> _optionHints(PageOption opt) => opt.hints;

  Widget _inspector(Tokens t, Options options, int w) {
    final opts = page.def!.options;
    final children = <Widget>[
      Positioned.fill(
        child: CellPaint((p) {
          p
            ..vline(0, 0, p.height, t.faint, '│')
            ..text(3, 1, 'OPTIONS', Style(fg: t.muted));
        }),
      ),
    ];
    var y = 3;
    final cw = w - 5;
    for (final opt in opts) {
      final h = opt.rowsIn(cw);
      children.add(
        Positioned(
          left: 1,
          top: y,
          width: cw + 2,
          height: h,
          child: _option(t, options, opt, cw, 0, h, 0),
        ),
      );
      y += h + 1;
    }
    return Stack(children: children);
  }

  /// The rows [opt] takes beside its label, [w] wide.
  static int _compactRows(PageOption opt, int w) => switch (opt) {
    ColorOption() => 2,
    ChoiceOption() => opt.rowsIn(w) - 1,
    _ => 1,
  };

  /// Whether a blank row goes before option [i]: two switches one under
  /// the other would join into one tall pill.
  static int _gapBefore(List<PageOption> opts, int i) =>
      i > 0 && opts[i] is SwitchOption && opts[i - 1] is SwitchOption ? 1 : 0;

  static int _labelColumn(List<PageOption> opts) =>
      opts.fold(0, (n, o) => widthOf(o.label) > n ? widthOf(o.label) : n) + 2;

  /// The rows the options take under the stage, [w] wide, as the design's
  /// compactHeight counts them: each choice's track in `w - 14`, although
  /// it is drawn beside the label column ([_labelColumn]).
  static int _compactHeight(List<PageOption> opts, int w) {
    var h = 2;
    for (var i = 0; i < opts.length; i++) {
      h += _gapBefore(opts, i) + _compactRows(opts[i], w - 14);
    }
    return h + 1;
  }

  Widget _compactInspector(Tokens t, Options options, int pw, int pad) {
    final opts = page.def!.options;
    final lw = _labelColumn(opts);
    final w = pw - pad - 2;
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxH < BoxConstraints.unbounded ? c.maxH : 0;
        final view = h - 1 < 0 ? 0 : h - 1;
        final rows = <({int y, int h})>[];
        var content = 0;
        for (var i = 0; i < opts.length; i++) {
          content += _gapBefore(opts, i);
          final rh = _compactRows(opts[i], w - lw);
          rows.add((y: content, h: rh));
          content += rh;
        }
        final most = content - view < 0 ? 0 : content - view;
        var target = (_optionScroll[page.key] ?? 0).clamp(0, most);
        final fi = opts.indexWhere(
          (o) => _optionNodes['${page.key}:${o.key}']?.hasFocus ?? false,
        );
        if (fi >= 0) {
          final f = rows[fi];
          if (f.y < target) {
            target = f.y;
          } else if (f.y + f.h > target + view) {
            target = f.y + f.h - view;
          }
        }
        _optionScroll[page.key] = target;
        final sc = _motion
            .glide('options:${page.key}', target.toDouble(), 160)
            .round();
        final children = <Widget>[
          Positioned.fill(
            child: Listener(
              onScroll: (e) => setState(
                () => _optionScroll[page.key] = (target + _wheel(e) * 2).clamp(
                  0,
                  most,
                ),
              ),
              child: CellPaint((p) {
                p.hline(0, 0, p.width, t.faint, '─');
                p.thumb(p.width - 1, 1, view, content, sc, t.muted);
              }),
            ),
          ),
        ];
        for (var i = 0; i < opts.length; i++) {
          final r = rows[i];
          final top = r.y - sc;
          final from = top < 0 ? -top : 0;
          final visible = (top + r.h > view ? view - top : r.h) - from;
          children.add(
            Positioned(
              left: pad - 2,
              top: 1 + (top < 0 ? 0 : (top > view ? view : top)),
              width: w + 2,
              height: visible < 0 ? 0 : visible,
              child: _option(t, options, opts[i], w, lw, r.h, from),
            ),
          );
        }
        return Stack(children: children);
      },
    );
  }

  /// The option [opt]: its label and its control, [w] wide from the
  /// label (the bar `▎` two columns before it); in a label column [lw]
  /// wide beside the control when [lw] > 0. [from] rows of it are
  /// scrolled off above.
  Widget _option(
    Tokens t,
    Options options,
    PageOption opt,
    int w,
    int lw,
    int h,
    int from,
  ) {
    final p0 = page;
    final node = _optionNode(p0, opt.key);
    final off = !options.applies(opt);
    final focused = !off && node.hasFocus && _palette == null;
    final key = '${p0.key}:${opt.key}';
    const x = 2;
    final cx = lw > 0 ? x + lw : x;
    final cw = lw > 0 ? w - lw : w;
    final cy = lw > 0 ? 0 : 1;
    final raw = options.raw(opt.key);

    // the control's geometry, for the paint and the mouse alike
    var sliderX = cx;
    var sliderW = cw;
    var sliderY = cy;
    List<SegmentHit>? segs;
    double knob = 0;
    double thumb = 0;
    switch (opt) {
      case SwitchOption():
        knob = _motion.glide('$key:knob', (raw as bool) ? 1 : 0, 130);
      case final SliderOption o:
        final value = o.show(raw as num);
        sliderW = lw > 0
            ? (cw - widthOf(value) - 2 < 28 ? cw - widthOf(value) - 2 : 28)
            : w;
        sliderX = cx;
        sliderY = lw > 0 ? 0 : 1;
        final ratio = o.max == o.min ? 0.0 : (raw - o.min) / (o.max - o.min);
        thumb = _motion.glide('$key:thumb', ratio, 90);
      case final ChoiceOption o:
        segs = segmentsOf(cx, cy, cw, o.names);
      case ColorOption():
        break;
    }
    var hx = 0;
    var hw = 0;
    if (segs != null) {
      final chosen = segs[(raw as int).clamp(0, segs.length - 1)];
      final row = _motion.targetOf('$key:segY');
      if (row != chosen.y) {
        _motion
          ..jump('$key:segX', chosen.x.toDouble())
          ..jump('$key:segW', chosen.w.toDouble())
          ..jump('$key:segY', chosen.y.toDouble());
      }
      hx = _motion.glide('$key:segX', chosen.x.toDouble(), 140).round();
      hw = _motion.glide('$key:segW', chosen.w.toDouble(), 140).round();
    }

    void press(PointerEvent e) {
      if (e.button != 0 || off) {
        return;
      }
      node.requestFocus();
      final ex = e.x;
      final ey = e.y + from;
      switch (opt) {
        case SwitchOption():
          _setOption(p0, opt, !(options.raw(opt.key) as bool));
        case final SliderOption o:
          if (ey != sliderY) {
            return;
          }
          final room = (sliderW - 1) * 8;
          final r = options.raw(opt.key) as num;
          final ratio = o.max == o.min ? 0.0 : (r - o.min) / (o.max - o.min);
          final start = sliderW > 1 ? (ratio * room).round() : 0;
          final at = ex - sliderX;
          final on = at * 8 < start + 8 && (at + 1) * 8 > start;
          _grab = (at: at, start: on ? start : at * 8);
          if (!on && room > 0) {
            _setOption(
              p0,
              opt,
              o.clampStep(o.min + (o.max - o.min) * at * 8 / room),
            );
          }
        case ChoiceOption():
          for (final s in segs!) {
            if (ey == s.y && ex >= s.x && ex < s.x + s.w) {
              _setOption(p0, opt, s.i);
            }
          }
        case final ColorOption o:
          final sy = lw > 0 ? 0 : 1;
          for (var i = 0; i < o.values.length; i++) {
            final sx = cx + i * 3;
            if (ey >= sy && ey < sy + 2 && ex >= sx && ex < sx + 2) {
              _setOption(p0, opt, i);
            }
          }
      }
    }

    void drag(PointerEvent e) {
      final g = _grab;
      if (opt is! SliderOption || g == null || off) {
        return;
      }
      final room = (sliderW - 1) * 8;
      if (room > 0) {
        final eighths = g.start + (e.x - sliderX - g.at) * 8;
        _setOption(
          p0,
          opt,
          opt.clampStep(opt.min + (opt.max - opt.min) * eighths / room),
        );
      }
    }

    return Focus(
      focusNode: node,
      autofocus: _firstFocus == 'o:${opt.key}' && identical(p0, _firstPage),
      canRequestFocus: !off,
      skipTraversal: off,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onDown: press,
        onDrag: drag,
        onUp: (_) => _grab = null,
        child: CellPaint((cell) {
          // the option's rows from its top, [from] of them above the cell:
          // a painter as tall as the option, the cell's clip keeping what
          // shows
          cell.canvas.translate(0, -from);
          final p = Painter(cell.canvas, cell.width, h);
          final labelStyle = Style(
            fg: off
                ? t.dim
                : focused
                ? t.text
                : t.muted,
            attrs: focused ? Attr.bold : 0,
          );
          if (focused) {
            p.text(0, 0, '▎', Style(fg: t.primary));
          }
          p.text(x, 0, opt.label, labelStyle);
          final valueStyle = Style(fg: focused ? t.text : t.dim);
          switch (opt) {
            case SwitchOption():
              final sx = lw > 0 ? cx : x + w - 5;
              toggle(
                p,
                sx,
                0,
                knob,
                t,
                under: focused ? t.selection : t.background,
                disabled: off,
              );
            case final SliderOption o:
              final value = o.show(raw as num);
              if (lw > 0) {
                p.text(cx + sliderW + 2, 0, value, valueStyle);
              } else {
                p.text(x + w - widthOf(value), 0, value, valueStyle);
              }
              slider(
                p,
                sliderX,
                sliderY,
                sliderW,
                thumb,
                t,
                focused: focused,
                disabled: off,
              );
            case final ColorOption o:
              final name = o.values[raw as int];
              final sy = lw > 0 ? 0 : 1;
              if (lw == 0) {
                p.text(x + w - widthOf(name), 0, name, valueStyle);
              }
              swatches(
                p,
                cx,
                sy,
                [for (final v in o.values) t.named(v)],
                raw,
                t,
                focused: focused,
              );
              if (off) {
                p.tint(cx, sy, o.values.length * 3, 2, t.background, 0.6);
              }
              if (lw > 0) {
                p.text(cx + o.values.length * 3 + 1, sy, name, valueStyle);
              }
            case final ChoiceOption o:
              segmented(
                p,
                segs!,
                o.names,
                raw as int,
                t,
                focused: focused,
                hx: hx,
                hw: hw,
                disabled: off,
              );
          }
        }),
      ),
    );
  }

  /// Keeps the focused option of a narrow page in view.
  void _keepOptionInView() {}

  // ------------------------------------------------------------ hints

  /// The hints of what has the focus, then the gallery's own.
  List<(String, String)> get hintPairs {
    if (_palette != null) {
      return const [('enter', 'run'), ('esc', 'close')];
    }
    final primary = _manager?.primaryFocus;
    final inShell = _list.hasFocus || _filter.hasFocus || _pageNode.hasFocus;
    if (_zone == Zone.filter && _filter.hasFocus) {
      return [
        ('type', 'to filter'),
        ('enter', 'to the list'),
        ('esc', filter.isNotEmpty ? 'clear' : 'leave'),
      ];
    }
    if (_zone == Zone.list && _list.hasFocus || primary == null) {
      return [
        ('↑↓', 'pages'),
        ('tab', 'into the page'),
        ('/', 'filter'),
        ('ctrl+p', 'search'),
        ('c', tab == 'code' ? 'preview' : 'code'),
        ('t', 'theme'),
      ];
    }
    List<(String, String)> own;
    final opt = page.def?.options
        .where((o) => identical(_optionNodes['${page.key}:${o.key}'], primary))
        .firstOrNull;
    if (opt != null) {
      own = _optionHints(opt);
    } else if (identical(primary, _code)) {
      own = [
        ('↑↓←→', 'scroll'),
        ('y', 'copy'),
        if (_selection.hasSelection) ('esc', 'clear'),
        ('c', 'preview'),
      ];
    } else {
      // the hinted keys as twk's KeyHintsBar lists them, as the design
      // writes them: the arrows joined (`↑↓ move`), Page Up and Down, Home
      // and End apart by a blank (`pgup pgdn a window`)
      final keys = [
        for (final (k, hint) in KeyHintsBar.entries(
          _manager?.activeKeys ?? const <ActiveKey>[],
        ))
          if (hint != null) (k, hint),
      ];
      // a layer holding the first keys of a sequence: what can follow
      // them, and nothing else
      if (_manager?.keyPath.firstOrNull?.holdsKeys ?? false) {
        return keys;
      }
      // the page's own hints first (PageHints), then its hinted keys, but
      // for keys they name already
      final first = pageHintsAt(primary) ?? const <(String, String)>[];
      final named = {for (final (k, _) in first) k};
      own = [
        ...first,
        for (final pair in keys)
          if (!named.contains(pair.$1)) pair,
      ];
    }
    final taken = {
      for (final (k, _) in own) ...k.split(' '),
    };
    if (!inShell) {
      // a modal of the page's: its keys, Tab where it moves the focus in
      // it (a dialog), Escape last
      final esc = [
        for (final o in own)
          if (o.$1 == 'esc') o,
      ];
      return [
        for (final o in own)
          if (o.$1 != 'esc') o,
        if ((page.def?.modalTab ?? true) && !taken.contains('tab'))
          ('tab', 'next'),
        ...esc,
      ];
    }
    return [
      ...own,
      for (final g in const [
        ('tab', 'next'),
        ('shift+tab', 'back'),
        ('esc', 'pages'),
      ])
        if (!taken.contains(g.$1)) g,
    ];
  }

  Widget _hints(Tokens t, int w) {
    final pairs = hintPairs;
    return CellPaint((p) {
      p.fill(0, 0, w, 1, Style(bg: t.chrome));
      keyHints(p, 2, 0, w - 4, pairs, t);
    });
  }

  // ------------------------------------------------------------ palette

  List<Widget> _paletteLayer(Tokens t, int sw, int sh) {
    final pal = _palette;
    if (pal == null) {
      return const [];
    }
    final k = easeOut(_motion.progress(pal.opened, 140));
    final m = _paletteMatches();
    final w = 72 < sw - 8 ? 72 : sw - 8;
    final x = (sw - w) >> 1;
    final y = 1 - (1 - k).round();
    var rowsN = m.length;
    if (rowsN > 12) {
      rowsN = 12;
    }
    if (rowsN > sh - 7) {
      rowsN = sh - 7;
    }
    if (rowsN < 1) {
      rowsN = 1;
    }
    final h = rowsN + 5;
    pal.selected = m.isEmpty ? 0 : pal.selected.clamp(0, m.length - 1);
    if (pal.selected < pal.scroll) {
      pal.scroll = pal.selected;
    }
    if (pal.selected >= pal.scroll + rowsN) {
      pal.scroll = pal.selected - rowsN + 1;
    }
    final count = '${m.length}';
    final dim = t.shadeAlpha * 0.75 * k;
    return [
      // the barrier: what is under it dimmed as the design mixes it, a
      // press and its release on it closing the palette
      Positioned.fill(
        child: ModalBarrier(
          color: t.shade,
          opacity: dim.clamp(0, 1).toDouble(),
          onDismiss: _closePalette,
        ),
      ),
      Positioned(
        left: x,
        top: y,
        width: w,
        height: h,
        child: FocusScope(
          child: Focus(
            focusNode: _paletteNode,
            autofocus: true,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onDown: (e) {
                if (e.button != 0) {
                  return;
                }
                final i = e.y - 3;
                if (i >= 0 && i < rowsN && i + pal.scroll < m.length) {
                  _runItem(m[i + pal.scroll].$1);
                }
              },
              onScroll: (e) => setState(() {
                pal.selected = (pal.selected + _wheel(e)).clamp(
                  0,
                  m.isEmpty ? 0 : m.length - 1,
                );
              }),
              child: CellPaint(
                (p) {
                  p
                    ..fill(0, 0, w, h, Style(bg: t.surface))
                    ..text(2, 1, '›', Style(fg: t.primary, attrs: Attr.bold));
                  if (pal.query.isNotEmpty) {
                    p.text(
                      4,
                      1,
                      pal.query,
                      Style(fg: t.text),
                      max: w - 10 - widthOf(count),
                    );
                  } else {
                    p.text(
                      4,
                      1,
                      'Search pages, themes and actions',
                      Style(fg: t.dim),
                    );
                  }
                  p
                    ..text(w - 2 - widthOf(count), 1, count, Style(fg: t.dim))
                    ..hline(
                      2,
                      2,
                      w - 4,
                      Color.lerp(t.surface, t.border, 0.8),
                      '─',
                    );
                  for (var i = 0; i < rowsN; i++) {
                    if (i + pal.scroll >= m.length) {
                      break;
                    }
                    final (it, match) = m[i + pal.scroll];
                    final ry = 3 + i;
                    final on = i + pal.scroll == pal.selected;
                    final hov = !on && _hovering(x, y + ry, w, 1);
                    if (on) {
                      p
                        ..fill(1, ry, w - 2, 1, Style(bg: t.selection))
                        ..text(1, ry, '▎', Style(fg: t.primary));
                    } else if (hov) {
                      p.bg(
                        1,
                        ry,
                        w - 2,
                        1,
                        t.lit(t.surface, t.selection, 0.4),
                      );
                    }
                    final dw = widthOf(it.detail);
                    final title = cut(it.title, w - 8 - dw);
                    p.text(
                      3,
                      ry,
                      title,
                      Style(fg: t.text, attrs: on ? Attr.bold : 0),
                    );
                    for (final at in match?.positions ?? const <int>[]) {
                      final col = widthOf(it.title.substring(0, at));
                      if (col < widthOf(title)) {
                        p.color(3 + col, ry, 1, 1, t.primary, Attr.bold);
                      }
                    }
                    p.text(
                      w - 3 - dw,
                      ry,
                      it.detail,
                      Style(fg: on ? t.muted : t.dim),
                    );
                  }
                  if (m.isEmpty) {
                    p.text(3, 3, 'no command matches', Style(fg: t.muted));
                  }
                  p.thumb(w - 1, 3, rowsN, m.length, pal.scroll, t.muted);
                  if (k < 1) {
                    p.tint(0, 0, w, h, t.background, 1 - k);
                  }
                },
                cursor: (4 + widthOf(pal.query), 1),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  // ------------------------------------------------------------ toasts

  static const _toastMs = 2600;
  static const _icons = {
    'info': 'ℹ',
    'success': '✓',
    'warning': '⚠',
    'error': '✗',
  };

  Widget? _toastLayer(Tokens t, int sw, int sh) {
    final now = _motion.now;
    if (!_clock.frozen) {
      _toasts.removeWhere(
        (x) => (now - x.at).inMilliseconds >= _toastMs,
      );
    }
    if (_toasts.isEmpty) {
      return null;
    }
    // where each goes, the newest lowest
    final placed = <({_Toast toast, int x, int y, int w, double out})>[];
    var bottom = sh - 2;
    var top = bottom;
    var left = sw;
    for (final toast in _toasts.reversed) {
      final age = _clock.frozen ? 400 : (now - toast.at).inMilliseconds;
      final kin = easeOut((age / 200).clamp(0, 1).toDouble());
      final kout = ((age - (_toastMs - 260)) / 260).clamp(0, 1).toDouble();
      if (age < 200 || kout > 0) {
        _motion.animate();
      }
      final w = widthOf(toast.message) + 8;
      final x = sw - 2 - w + ((1 - kin) * (w + 2)).round();
      final y = bottom - 3 + 1;
      placed.add((toast: toast, x: x, y: y, w: w, out: kout));
      if (x < left) {
        left = x;
      }
      top = y;
      bottom -= 4;
    }
    if (!_clock.frozen) {
      final first = _toasts.map((x) => x.at).reduce((a, b) => a < b ? a : b);
      _motion.wakeAt(first + const Duration(milliseconds: _toastMs));
    }
    if (left < 0) {
      left = 0;
    }
    final height = sh - 1 - top;
    return Positioned(
      left: left,
      top: top,
      width: sw - left,
      height: height < 0 ? 0 : height,
      child: CellPaint(hit: false, (p) {
        for (final it in placed) {
          final color = t.named(
            it.toast.kind == 'info' ? 'info' : it.toast.kind,
          );
          final x = it.x - left;
          final y = it.y - top;
          p.fill(x, y, it.w, 3, Style(bg: t.surface));
          for (var r = 0; r < 3; r++) {
            p.text(x, y + r, '▌', Style(fg: color));
          }
          p
            ..text(x + 3, y + 1, _icons[it.toast.kind] ?? 'ℹ', Style(fg: color))
            ..text(x + 5, y + 1, it.toast.message, Style(fg: t.text));
          if (it.out > 0) {
            p.tint(x, y, it.w, 3, t.background, easeInOut(it.out));
          }
        }
      }),
    );
  }
}
