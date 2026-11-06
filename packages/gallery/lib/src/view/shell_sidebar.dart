// The sidebar: the filter and the list of pages by group, its scroll and
// its mouse.
part of 'shell.dart';

/// What a row of the list is: a blank between groups, a group's title, a
/// page.
enum _Row { gap, group, page }

extension _Sidebar on GalleryShellState {
  /// The rows of the list: a group's title, its pages, a gap between
  /// groups.
  List<({_Row kind, ShellGroup? group, int count, ShellPage? page})>
  _listRows() {
    final rows =
        <({_Row kind, ShellGroup? group, int count, ShellPage? page})>[];
    for (final g in groups) {
      final shown = filtered(g.pages, filter);
      if (shown.isEmpty) {
        continue;
      }
      if (rows.isNotEmpty) {
        rows.add((kind: _Row.gap, group: null, count: 0, page: null));
      }
      rows.add((kind: _Row.group, group: g, count: shown.length, page: null));
      for (final p in shown) {
        rows.add((kind: _Row.page, group: g, count: 0, page: p));
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
    final scroll = _motion
        .glide('listScroll', target.toDouble(), glideMs)
        .round();
    final prevSel = _motion.targetOf('listSel')?.round() ?? sel;
    final selY = sel < 0
        ? -1
        : _motion
              .glide(
                'listSel',
                sel.toDouble(),
                selectionGlideMs((sel - prevSel).abs()),
              )
              .round();
    final focusedList = _zone == Zone.list && _palette == null;
    final filterActive = _zone == Zone.filter && _palette == null;
    // the chosen page's title on the screen, where the hidden cursor rests
    final selRowY = lt + selY - scroll;
    final selRow = sel >= 0 && selRowY >= lt && selRowY < lt + lh
        ? (5, selRowY)
        : null;
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
          if (r.kind == _Row.group) {
            final c = '${r.count}';
            final label = cut(
              r.group!.title.toUpperCase(),
              sw - 7 - widthOf(c),
            );
            p
              ..text(3, y, label, Style(fg: t.muted))
              ..text(sw - 3 - widthOf(c), y, c, Style(fg: t.dim));
          } else if (r.kind == _Row.page) {
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
      // the hidden cursor on the page chosen, where a terminal that marks
      // its row shows the selection
      rest: selRow,
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
                onPointerDown: (e) {
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
                  if (r.kind == _Row.page) {
                    show(r.page!);
                    _list.requestFocus();
                  } else if (r.kind == _Row.group) {
                    final g = r.group!;
                    show(
                      filtered(g.pages, filter).firstOrNull ?? g.pages.first,
                    );
                  }
                },
                onScroll: (e) => _update(() {
                  _listTarget = (_listTarget + e.scrollY * wheelRows).clamp(
                    0,
                    most,
                  );
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
}
