// The Code tab: the page's Dart, highlighted, lit where it changed,
// scrolled both ways and selected with the mouse.
part of 'shell.dart';

extension _CodePane on GalleryShellState {
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
      rec = _codes[page.key] = CodeRecord.after(rec, src, now);
    }
    final record = rec;
    final syntax = SyntaxTheme.from(Theme.of(themed));
    final bg = t.dark ? t.well : t.chrome;
    const gut = 4;
    final focused = _code.hasFocus;
    final lit = [
      for (final c in record.changed)
        if (c == null) 0.0 else 1 - _motion.progress(c, codeLitMs),
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
        onCopy: (text) =>
            toast('Copied ${copiedWhat(text)}', ToastKind.success),
        child: Listener(
          onScroll: (e) {
            final d = e.scrollY;
            _update(() {
              if ((e.modifiers & Mod.shift) != 0) {
                _codeX = (_codeX + d * codeStepX).clamp(0, codeMaxX);
              } else {
                _codeScroll = (_codeScroll + d * wheelRows).clamp(
                  0,
                  _codeMaxScroll,
                );
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
                    _update(() => _codeScroll = to);
                    return true;
                  },
                  scrollAcross: (columns) {
                    final to = (_codeX + columns).clamp(0, codeMaxX);
                    if (to == _codeX) {
                      return false;
                    }
                    _update(() => _codeX = to);
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
}

/// Writes [text] at column [x] of a strip from [x0] to [end], clipped
/// to it.
void _clipped(
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

Style _tokenStyle(SyntaxTheme s, Token tok) => switch (tok.kind) {
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
