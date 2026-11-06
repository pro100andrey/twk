// The header: the gallery's name, where the page is, the search and
// the theme.
part of 'shell.dart';

/// The width of the header's search: `ctrl+p search`, and a cell either
/// side for the mouse.
const _searchWidth = 15;

extension _Header on GalleryShellState {
  /// Where the header's theme and search are on a header [w] wide: the
  /// theme's `label` at `themeX`, the search at `searchX`; what the mouse
  /// takes of each is a cell wider either side.
  ({String label, int themeX, int searchX}) _headerPlaces(int w) {
    final label = '◐ ${galleryThemes[themeName]!.$1}';
    final themeX = w - 2 - widthOf(label);
    return (label: label, themeX: themeX, searchX: themeX - 4 - _searchWidth);
  }

  Widget _header(Tokens t, int w) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (e) {
      if (e.button != 0) {
        return;
      }
      final at = _headerPlaces(w);
      final tw = widthOf(at.label);
      if (e.x >= at.themeX - 1 && e.x < at.themeX + tw + 1) {
        _nextTheme();
      } else if (e.x >= at.searchX - 1 && e.x < at.searchX + _searchWidth + 1) {
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
      if (w >= headerWhereFrom) {
        x += 3;
        x += p.text(x, 0, page.group.title, Style(fg: t.dim));
        x += p.text(x, 0, '  ›  ', Style(fg: t.faint));
        p.text(x, 0, page.title, Style(fg: t.muted));
      }
      final at = _headerPlaces(w);
      final tw = widthOf(at.label);
      final themeHover = _hovering(at.themeX - 1, 0, tw + 2, 1);
      p.text(
        at.themeX,
        0,
        at.label,
        Style(fg: themeHover ? t.text : t.muted),
      );
      final sx = at.searchX;
      final searchHover = _hovering(sx - 1, 0, _searchWidth + 2, 1);
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
}
