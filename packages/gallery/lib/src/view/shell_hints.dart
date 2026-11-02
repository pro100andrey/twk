// The hint bar: the focused widget's keys, then the gallery's own.
part of 'shell.dart';

extension _Hints on GalleryShellState {
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
        ('c', tab.other.name),
        ('t', 'theme'),
      ];
    }
    List<(String, String)> own;
    final opt = page.def?.options
        .where((o) => identical(_optionNodes['${page.key}:${o.key}'], primary))
        .firstOrNull;
    if (opt != null) {
      own = opt.hints;
    } else if (identical(primary, _code)) {
      own = [
        ('↑↓←→', 'scroll'),
        ('y', 'copy'),
        if (_selection.hasSelection) ('esc', 'clear'),
        ('c', GalleryTab.preview.name),
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
}
