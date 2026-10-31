// The shell's keys: its own, the list's, the filter's, the Code's and
// an option's, and the list's hinted layer.
part of 'shell.dart';

/// Past the end of any Code, for `home` and `end`: the paint keeps the
/// scroll to the Code's last row.
const _pastTheEnd = 1000000;

extension _Keys on GalleryShellState {
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
        if (tab == GalleryTab.code && _clearSelection()) {
          break;
        }
        if (_zone == Zone.page && _pageNode.hasFocus) {
          _list.requestFocus();
        } else if (filter.isNotEmpty) {
          _update(() => filter = '');
        } else {
          return KeyEventResult.ignored;
        }
      case 't':
        _nextTheme();
      case 'T':
        _nextTheme(-1);
      case 'c':
        _setTab(tab.other);
      case 'y':
        if (tab != GalleryTab.code) {
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
  List<ShellPage> get visiblePages => filtered(pages, filter);

  /// Shows the page [step] rows from this one in the list.
  void _listStep(int step) {
    final visible = visiblePages;
    final i = visible.indexOf(page);
    if (visible.isNotEmpty) {
      show(visible[(i < 0 ? 0 : i + step).clamp(0, visible.length - 1)]);
    }
  }

  // The keys of the list, bound in a hinted layer around it, so that
  // FocusManager.activeKeys lists them (a KeyHintsBar on the stage):
  // tear-offs, the same binding at each build. The page's Tab, Shift+Tab
  // and Escape are not bound: Tab goes to the page's InputListeners before
  // it moves the focus, and a page's own KeyHintsBar lists its keys alone

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
      'c': tab.other.name,
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
        return go(i - pageStep);
      case 'pagedown':
        return go(i + pageStep);
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
          _update(() => filter = '');
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
    }
    final edited = editLine(filter, e);
    if (edited == null) {
      return false;
    }
    if (edited != filter) {
      _update(() => filter = edited);
    }
    if (name != 'backspace' && name != 'ctrl+u') {
      // a character typed: the first page it matches, if this is none
      final v = visiblePages;
      if (v.isNotEmpty && !v.contains(page)) {
        show(v.first, keepZone: true);
      }
    }
    return true;
  }

  bool _codeKey(KeyEvent e) {
    if (e.kind == KeyKind.release) {
      return false;
    }
    final name = keyName(e);
    final step = const {
      'up': -1,
      'down': 1,
      'pageup': -pageStep,
      'pagedown': pageStep,
      'home': -_pastTheEnd,
      'end': _pastTheEnd,
    }[name];
    if (step != null) {
      _update(() => _codeScroll = (_codeScroll + step).clamp(0, _pastTheEnd));
      return true;
    }
    final side = const {'left': -codeStepX, 'right': codeStepX}[name];
    if (side != null) {
      _update(() => _codeX = (_codeX + side).clamp(0, codeMaxX));
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
    final next = opt.stepped(options.raw(opt.key), name);
    if (next != null) {
      _store.set(p.key, opt, next);
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
}

KeyEventResult _handled(bool taken) =>
    taken ? KeyEventResult.handled : KeyEventResult.ignored;
