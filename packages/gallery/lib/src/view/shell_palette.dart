// The palette: what it lists and runs, its keys, and how it is drawn
// (doc/design.md, "The palette").
part of 'shell.dart';

extension _Palette on GalleryShellState {
  List<PaletteItem> get _paletteItems => [
    for (final p in pages) PaletteItem(p.title, p.group.title, () => show(p)),
    for (final MapEntry(key: n, value: (label, _)) in galleryThemes.entries)
      PaletteItem('Theme: $label', 'theme', () => _setTheme(n)),
    PaletteItem('Show the code', 'action', () => _setTab(GalleryTab.code)),
    PaletteItem(
      'Show the preview',
      'action',
      () => _setTab(GalleryTab.preview),
    ),
    PaletteItem('Copy the code', 'action', _copyCode),
    PaletteItem('Reset the options', 'action', () {
      _store.reset(page.key);
      toast('Options reset');
    }),
    for (final g in groups)
      PaletteItem(
        'Group: ${g.title}',
        '${g.pages.length} pages',
        () => show(g.pages.first),
      ),
  ];

  /// The items that match the palette's query, ranked.
  List<(PaletteItem, FuzzyMatch?)> _paletteMatches() =>
      rankPalette(_paletteItems, _palette?.query ?? '', _recent);

  void _openPalette(String query) {
    final primary = _manager?.primaryFocus;
    _update(() {
      _palette = PaletteState(query, _motion.now);
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
    _update(() => _palette = null);
    final before = _beforePalette;
    _beforePalette = null;
    if (before != null && before.context != null) {
      before.requestFocus();
    } else {
      _list.requestFocus();
    }
  }

  void _runItem(PaletteItem it) {
    _closePalette();
    ranLast(_recent, it.title);
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
          _update(() => pal.selected = (pal.selected - 1 + n) % n);
        }
        return;
      case 'down':
        if (n > 0) {
          _update(() => pal.selected = (pal.selected + 1) % n);
        }
        return;
      case 'tab' || 'shift+tab':
        return;
      case 'enter':
        if (pal.selected < n) {
          _runItem(m[pal.selected].$1);
        }
        return;
    }
    final edited = editLine(pal.query, e);
    // a backspace in an empty query changes nothing, the choice neither
    if (edited != null && (edited != pal.query || name != 'backspace')) {
      _update(() {
        pal
          ..query = edited
          ..selected = 0;
      });
    }
  }

  List<Widget> _paletteLayer(Tokens t, int sw, int sh) {
    final pal = _palette;
    if (pal == null) {
      return const [];
    }
    final k = easeOut(_motion.progress(pal.opened, paletteOpenMs));
    final m = _paletteMatches();
    final w = paletteWidth < sw - 8 ? paletteWidth : sw - 8;
    final x = (sw - w) >> 1;
    final y = 1 - (1 - k).round();
    var rowsN = m.length;
    if (rowsN > paletteRows) {
      rowsN = paletteRows;
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
              onScroll: (e) => _update(() {
                pal.selected = (pal.selected + e.scrollY).clamp(
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
}
