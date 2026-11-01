// One switch for an ASCII app: every page of the gallery under
// Glyphs.ascii (the route parameter `glyphs=ascii`) draws no cell outside
// ASCII but what the allowlist names, each with its reason.
import 'package:gallery/gallery.dart';
import 'package:gallery/src/shell/tokens.dart' show galleryThemes;
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

/// The text of the page itself: a label, a sample, a demo's own marks.
const _text = "the page's own text";

/// A page's mock terminal or the app of its Code, drawn with its own
/// frame or theme and not the gallery's.
const _frame = "the page's own frame or theme, not the gallery's";

/// A mark the page passes to a widget itself, above the theme's.
const _explicit = 'a mark the page gives the widget, above the theme';

/// A picture, not a mark.
const _image = 'an image or a drawing, not a mark';

/// The cells that stay under Glyphs.ascii, by page: the characters and
/// why. A page or a character with no entry fails the sweep, and an entry
/// that no longer shows fails it too.
const _allowed = <(String, String, String)>[
  ('Text/Text', '漢字🙂', _text),
  ('Text/Right to left', 'םולשابحرمע', _text),
  ('Text/ANSI', '⋯', _text),
  ('Layout/Box', '…', _text),
  ('Layout/SizedBox', '×', _text),
  ('Layout/LimitedBox, OverflowBox', '×', _text),
  ('Layout/FractionallySizedBox', '×', _text),
  ('Layout/IntrinsicWidth/Height', '…', _text),
  ('Layout/Grid, GridPlacement', '·', _text),
  ('Layout/Wrap', '日本語', _text),
  ('Layout/CustomPaint', '▂▅█▁▃▆▇▄', _text),
  ('Style/Theme', '╭─╮│╰╯▐●▌✓╴', _frame),
  ('Style/TerminalBrightness', '╭─╮│╰╯', _frame),
  ('Style/GradientForeground', '█╗╚═╔╝║', _text),
  ('Scrolling/Scrollable', '├─', _text),
  ('Data/Chart', 'π', _text),
  ('Data/DescriptionList', '●', _text),
  ('Data/Table', '━╸', _explicit),
  ('Data/Gauge, LineGauge', '━', _explicit),
  ('Data/TaskList', '⠴', _explicit),
  ('Editing/InputDecoration', '◐⌕↵', _text),
  ('Controls/Pressable', '★☆', _text),
  ('Controls/NumberInput', '×', _text),
  ('Controls/ListTile', '▤›', _text),
  ('Overlays/OptionList', '…', _text),
  ('Animation/Spinner', '⠴…', _explicit),
  ('Animation/ProgressList', '⠴', _explicit),
  ('Animation/TickerMode', '…', _text),
  ('Animation/Skeleton, Skeletonize', '░', _explicit),
  ('Animation/AnimationController', '●', _text),
  ('Animation/AnimationController', '━╸', _explicit),
  ('Animation/AnimatedAlign, AnimatedPadding', '◆◇', _text),
  ('Animation/AnimatedPositioned', '▣', _text),
  ('Mouse/Draggable, DragTarget', '●', _text),
  ('Focus and keys/ActiveItem', '›', _text),
  ('Navigation/Breadcrumbs', '›', _explicit),
  ('Framework/LayoutBuilder', '×', _text),
  ('Framework/NotificationListener', 'Δ', _text),
  ('App/ErrorWidget', '━', _explicit),
  ('App/Static', '╭─╮│✓┃…╰╯', _frame),
  ('App/TerminalProgress', '╭─╮│◔━╰╯', _frame),
  ('App/Viewport', '╭─╮│…╰╯', _frame),
  ('App/Window title', '╭─╮│╰╯', _frame),
  ('App/Notifications', '╭─╮│╰╯', _frame),
  ('App/Cli', '✔▎', _frame),
  ('Debugging/RepaintBoundary', '·●', _text),
  ('Debugging/FrameOverlay', 'µ⠴▃▄▅▆▇█', _frame),
  ('Debugging/Repaint rainbow', '⠴▃▄▅▆▇█', _frame),
  ('Rich/DiffView', 'Привіт', _text),
  ('Rich/BigText', '█', _image),
  ('Rich/QrCode', '█▀▄', _image),
  ('Images/Image', '▀', _image),
];

void main() {
  // what each page showed of its allowlist, for the last test
  final seen = <String, Set<String>>{};
  for (final g in catalog) {
    for (final p in g.pages) {
      final name = '${g.title}/${p.title}';
      testTwk('$name draws ASCII only under Glyphs.ascii', (t) async {
        final route = '#/${slug(g.title)}/${slug(p.title)}?glyphs=ascii';
        await t.pumpWidget(
          galleryApp(
            route: GalleryRoute.parse('$route&t=2000'),
          ),
          size: (120, 36),
          duration: Duration.zero,
          backgroundRgb:
              (galleryThemes['dark']!.$2.background.bg?.value ?? 0) & 0xFFFFFF,
        );
        await t.pump(const Duration(milliseconds: 2000));
        final cells = <String, int>{};
        for (final text in _stage(t, 120, 36)) {
          for (final r in text.runes) {
            final c = String.fromCharCode(r);
            if (r > 0x7e) {
              (seen[name] ??= {}).add(c);
              if (!_isAllowed(name, r)) {
                cells[c] = (cells[c] ?? 0) + 1;
              }
            }
          }
        }
        expect([
          for (final MapEntry(:key, :value) in cells.entries)
            "'$key' U+${key.runes.first.toRadixString(16)} x$value",
        ], isEmpty);
      });
    }
  }
  test('the allowlist holds only what the pages still show', () {
    final stale = [
      for (final (key, chars, _) in _allowed)
        for (final r in chars.runes)
          if (!(seen[key]?.contains(String.fromCharCode(r)) ?? false))
            '$key: ${String.fromCharCode(r)}',
    ];
    expect(stale, isEmpty);
  });
}

/// Whether [rune] may be drawn on the page [name].
bool _isAllowed(String name, int rune) => _allowed.any(
  (e) => e.$1 == name && e.$2.runes.contains(rune),
);

/// The cells of the page's stage, a string of one cell each: below the
/// rule under the tabs, from where it starts to the options' divider or
/// the screen's edge, down to the row above the key hints, and inside the
/// marks the gallery puts at the widget's corners when it shows them. The
/// gallery's own chrome, its rules and tabs, stays out.
List<String> _stage(TwkTester t, int width, int height) {
  final grid = [
    for (var y = 0; y < height; y++)
      [for (var x = 0; x < width; x++) t.cell(x, y).text],
  ];
  for (var y = 0; y < height; y++) {
    if (!grid[y].contains('━')) {
      continue;
    }
    final left = grid[y].indexOf('─');
    final divider = grid[y].indexOf('┬');
    var rows = [
      for (var r = y + 1; r < height - 1; r++)
        grid[r].sublist(left, divider < 0 ? width : divider),
    ];
    final top = rows.indexWhere((r) => r.contains('┌'));
    final bottom = rows.lastIndexWhere((r) => r.contains('└'));
    if (top >= 0 && bottom > top) {
      final x0 = rows[top].indexOf('┌');
      final x1 = rows[top].lastIndexOf('┐');
      if (x1 > x0) {
        rows = [
          for (var r = top + 1; r < bottom; r++) rows[r].sublist(x0 + 1, x1),
        ];
      }
    }
    return [for (final r in rows) r.join()];
  }
  throw StateError('no rule under the tabs');
}
