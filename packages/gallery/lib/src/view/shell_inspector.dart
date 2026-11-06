// The inspector: each option's control, beside the stage or under it,
// painted and pressed.
part of 'shell.dart';

extension _Inspector on GalleryShellState {
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

  Widget _compactInspector(Tokens t, Options options, int pw, int pad) {
    final opts = page.def!.options;
    final lw = _labelColumn(opts);
    final w = pw - pad - 2;
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight < BoxConstraints.unbounded ? c.maxHeight : 0;
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
            .glide('options:${page.key}', target.toDouble(), glideMs)
            .round();
        final children = <Widget>[
          Positioned.fill(
            child: Listener(
              onScroll: (e) => _update(
                () => _optionScroll[page.key] =
                    (target + e.scrollY * wheelOptionRows).clamp(
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
    PageOption<Object?> opt,
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
        knob = _motion.glide('$key:knob', (raw as bool) ? 1 : 0, knobMs);
      case final SliderOption o:
        final value = o.show(raw as num);
        sliderW = lw > 0
            ? (cw - widthOf(value) - 2 < 28 ? cw - widthOf(value) - 2 : 28)
            : w;
        sliderX = cx;
        sliderY = lw > 0 ? 0 : 1;
        final ratio = o.max == o.min ? 0.0 : (raw - o.min) / (o.max - o.min);
        thumb = _motion.glide('$key:thumb', ratio, thumbMs);
      case final ChoiceOption<Object?> o:
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
      hx = _motion
          .glide('$key:segX', chosen.x.toDouble(), segmentGlideMs)
          .round();
      hw = _motion
          .glide('$key:segW', chosen.w.toDouble(), segmentGlideMs)
          .round();
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
          _store.set(p0.key, opt, !(options.raw(opt.key) as bool));
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
            _store.set(
              p0.key,
              opt,
              o.clampStep(o.min + (o.max - o.min) * at * 8 / room),
            );
          }
        case ChoiceOption():
          for (final s in segs!) {
            if (ey == s.y && ex >= s.x && ex < s.x + s.w) {
              _store.set(p0.key, opt, s.i);
            }
          }
        case final ColorOption o:
          final sy = lw > 0 ? 0 : 1;
          for (var i = 0; i < o.values.length; i++) {
            final sx = cx + i * 3;
            if (ey >= sy && ey < sy + 2 && ex >= sx && ex < sx + 2) {
              _store.set(p0.key, opt, i);
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
        _store.set(
          p0.key,
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
            case final ChoiceOption<Object?> o:
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
}

/// The rows [opt] takes beside its label, [w] wide.
int _compactRows(PageOption<Object?> opt, int w) => switch (opt) {
  ColorOption() => 2,
  ChoiceOption() => opt.rowsIn(w) - 1,
  _ => 1,
};

/// Whether a blank row goes before option [i]: two switches one under
/// the other would join into one tall pill.
int _gapBefore(List<PageOption<Object?>> opts, int i) =>
    i > 0 && opts[i] is SwitchOption && opts[i - 1] is SwitchOption ? 1 : 0;

int _labelColumn(List<PageOption<Object?>> opts) =>
    opts.fold(0, (n, o) => widthOf(o.label) > n ? widthOf(o.label) : n) + 2;

/// The rows the options take under the stage, [w] wide, as the design's
/// compactHeight counts them: each choice's track in `w - 14`, although
/// it is drawn beside the label column ([_labelColumn]).
int _compactHeight(List<PageOption<Object?>> opts, int w) {
  var h = 2;
  for (var i = 0; i < opts.length; i++) {
    h += _gapBefore(opts, i) + _compactRows(opts[i], w - 14);
  }
  return h + 1;
}
