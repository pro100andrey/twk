// The page: its title and about, the tabs, and the stage with the
// inspector beside it or under it.
part of 'shell.dart';

extension _PageArea on GalleryShellState {
  Widget _pageArea(
    BuildContext context,
    Tokens t,
    int screenW,
    int screenH,
    int pw,
    int ph,
  ) {
    final pad = pw >= padWideFrom ? pagePad : pagePadNarrow;
    final iw = pw - pad - 2;
    final short = screenH < lowScreenBelow;
    final def = page.def;
    final options = _optionsOf(page);
    final where = '${page.index + 1} of ${page.group.pages.length}';
    const tabs = [(GalleryTab.preview, 'Preview'), (GalleryTab.code, 'Code')];
    final tabsW = tabs.fold(-3, (n, tb) => n + widthOf(tb.$2) + 3);
    final opts = def?.options ?? const <PageOption<Object?>>[];
    // the inspector beside the stage where the page is wide, and the stage
    // keeps the columns its widget needs (less the marks' three each side)
    final besideW = opts.isNotEmpty ? inspectorWidth(screenW) : 0;
    final needs = def?.minWidth;
    final wide =
        pw >= inspectorBesideFrom &&
        (needs == null || pw - besideW - stageMarksWidth >= needs);
    final inspW = wide ? besideW : 0;

    // where each tab is on its row, and the underline gliding to it
    final tabX = <GalleryTab, (int, int)>{};
    var tx = short ? pw - 2 - tabsW : pad;
    for (final (id, label) in tabs) {
      tabX[id] = (tx, widthOf(label));
      tx += widthOf(label) + 3;
    }
    final (ax, aw) = tabX[tab]!;
    final ux = _motion.glide('tabX', ax.toDouble(), glideMs).round();
    final uw = _motion.glide('tabW', aw.toDouble(), glideMs).round();

    void drawTabs(Painter p, int y, {required int screenY}) {
      for (final (id, label) in tabs) {
        final (x, lw) = tabX[id]!;
        final on = tab == id;
        final can = id != GalleryTab.code || (def?.hasCode ?? false);
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
        if (tab == GalleryTab.code &&
            (def?.hasCode ?? false) &&
            e.button == 0) {
          final cx = pw - 2 - widthOf('⧉ copy');
          if (e.x >= cx - 1 && e.x < cx + 7) {
            _copy();
          }
        }
      },
      child: CellPaint(height: 1, (p) {
        drawTabs(p, 0, screenY: -1);
        if (tab == GalleryTab.code && (def?.hasCode ?? false)) {
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
    if (tab == GalleryTab.code &&
        def != null &&
        def.hasCode &&
        options != null) {
      // the Code in the room the stage would give the widget here
      body = LayoutBuilder(
        builder: (context, c) {
          final room = stageRoomIn(c.maxW, c.maxH);
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
                  control: _store.controlOf(page.key, def),
                  child: Builder(
                    // a reset of the page builds it afresh
                    key: ValueKey((page.key, _store.resetsOf(page.key))),
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
}
