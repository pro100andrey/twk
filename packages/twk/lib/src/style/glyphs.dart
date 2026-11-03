/// The marks widgets draw with, by what they mean: [Glyphs], its presets
/// [Glyphs.unicode] and [Glyphs.ascii], in the theme ([ThemeData.glyphs]).
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show BorderType;

import '../animation/spinner.dart' show SpinnerFrames;
import 'marks.dart' show Mark, Marks, ThemeMarks;
import 'theme.dart' show Theme, ThemeData;

/// The marks widgets draw, by what each means (a check, a cross, a cursor
/// bar, a scrollbar's thumb) and not by the widget that draws it: a mark
/// is one field, whichever widgets show it. An app picks a set for itself
/// or for a part of it, in the theme ([ThemeData.glyphs]), as it picks
/// colors.
///
/// The presets: [Glyphs.unicode], the default, the marks the widgets
/// draw without a theme of their own; and [Glyphs.ascii], ASCII only, for
/// a terminal or a font without the others. [copyWith] changes some marks
/// of a set; each mark is a string of one column unless its doc says
/// otherwise, and the widgets lay out by the width the terminal gives it
/// (in cells, not code units).
///
/// One rule, kept in one place ([ThemeMarks], with a descriptor for each
/// mark in [Marks]): a mark drawn in one cell or as text in a row that is
/// not one column wide (an emoji, an ambiguous mark in some terminals), or
/// is a cluster of more than one code point (a letter and a combining
/// accent), is the same field of [Glyphs.ascii] there, with one warning in
/// the app's log for each such mark; the width is the terminal's, so it is
/// known only when the mark is drawn. It holds for a mark filled into a
/// cell (a scrollbar's thumb, a gauge) and for one drawn as text (a radio
/// button's, a switch's, a button's edge, a chip's close, a pagination's
/// arrows) alike. An empty mark draws nothing and breaks nothing: what it
/// draws is the [Mark.onEmpty] of its descriptor, nothing for most, a
/// blank for the track of a scrollbar, a slider's, [switchKnob] and
/// [previous] and [next], and [Glyphs.ascii]'s for a thumb or the line of a
/// gauge. The checkbox is as the radio button is: its marks [checkboxOn]
/// and [checkboxOff] are one cell each, and the [checkboxBrackets] around
/// them are text of their own. A widget gets the marks with
/// `ThemeMarks.of(context)`, a render object with `ThemeMarks.ofObject`.
///
/// Borders are in it too: [lines] is the line of every box, divider, split
/// and callout given no type of its own, and a set of ASCII lines draws
/// every type but `none` as ASCII ([borderOf]), also where a widget names
/// a type of its own (`rounded`, `heavy`, `double`), so [Glyphs.ascii] makes
/// the whole app ASCII. The charts are in it, where [partialBlocks] is false:
/// bars in the ramp of [shades], dots as the shade as dense as their number.
/// So is the ellipsis a `Text` or a `Box` title is cut with: [ellipsis],
/// whose columns are counted in the room. Not in it: the pictures of
/// images.
///
/// A widget's own parameter for a mark it has (`Spinner.frames`,
/// `RadioGroup.mark`, `Skeleton.glyph`, a `Callout`'s `icon`) stays above
/// the theme: the glyph set is what a widget draws when it is not given
/// one.
///
/// A check of another shape in the whole app, or ASCII for it all:
///
/// ```dart
/// final data = ThemeData.dark.copyWith(
///   glyphs: Glyphs.unicode.copyWith(check: '✔'),
/// );
/// final plain = ThemeData.dark.copyWith(glyphs: Glyphs.ascii);
/// ```
///
/// For one part of the app, a [Theme] around it:
///
/// ```dart
/// Theme(
///   data: ThemeData.dark.copyWith(glyphs: Glyphs.ascii),
///   child: const Scrollbar(child: Text('plain')),
/// )
/// ```
///
/// See also:
///
///  * [ThemeData], which holds the set.
@immutable
final class Glyphs {
  /// A set of marks; each one left out is that of [Glyphs.unicode].
  const Glyphs({
    this.cursor = '▎',
    this.accent = '▌',
    this.check = '✓',
    this.checkBold = '✔',
    this.cross = '✗',
    this.info = 'ℹ',
    this.warning = '⚠',
    this.checkboxOn = 'x',
    this.checkboxOff = ' ',
    this.checkboxBrackets = ('[', ']'),
    this.radioOn = '●',
    this.radioOff = ' ',
    this.radioBrackets = ('(', ')'),
    this.switchStart = '▐',
    this.switchEnd = '▌',
    this.switchKnob = '●',
    this.stepCurrent = '●',
    this.ring = '○',
    this.expanded = '▾',
    this.collapsed = '▸',
    this.up = '▴',
    this.down = '▾',
    this.previous = '‹',
    this.next = '›',
    this.first = '«',
    this.last = '»',
    this.close = '×',
    this.maximise = '□',
    this.restore = '▣',
    this.minimise = '_',
    this.bullet = '•',
    this.taskPending = '◦',
    this.taskSkipped = '↓',
    this.separator = '│',
    this.buttonEdges = ('▕', '▏'),
    this.trackVertical = '│',
    this.trackHorizontal = '─',
    this.thumbVertical = '┃',
    this.thumbHorizontal = '━',
    this.thumbSlim = '▐',
    this.partialBlocks = true,
    this.gaugeFilled = '─',
    this.gaugeHalf = '╴',
    this.gaugeEmpty = '─',
    this.spinner = SpinnerFrames.dots,
    this.lines = BorderType.single,
    this.arrowLeft = '←',
    this.arrowRight = '→',
    this.arrowUp = '↑',
    this.arrowDown = '↓',
    this.pointer = '▶',
    this.menu = '≡',
    this.shades = const [' ', '░', '▒', '▓', '█'],
    this.swatch = '■',
    this.ellipsis = '…',
    this.omitted = '⋯',
  });

  /// The set [t] of the way from [a] to [b]: marks do not blend, so [a]'s
  /// before halfway and [b]'s after it.
  factory Glyphs.lerp(Glyphs a, Glyphs b, double t) => t < 0.5 ? a : b;

  /// The marks the widgets draw with Unicode: the default of
  /// [ThemeData.glyphs].
  static const unicode = Glyphs();

  /// ASCII only: `+-|` for lines, `>` for a cursor, `v` for a check, `x`
  /// for a cross and a close, `[`/`]` ends of a switch and a button's edge,
  /// `#` for a scrollbar's thumb on a `|` or `-` track, `=` for the filled
  /// part of a line gauge, `v` and `>` for what is open and closed, `<>^v`
  /// for arrows, `.:+#` for shades, `...` for an ellipsis, the spinner
  /// `-\|/`; no mark in eighths of a cell.
  static const ascii = Glyphs(
    cursor: '>',
    accent: '|',
    check: 'v',
    checkBold: 'v',
    cross: 'x',
    info: 'i',
    warning: '!',
    radioOn: '*',
    switchStart: '[',
    switchEnd: ']',
    switchKnob: '*',
    stepCurrent: '*',
    ring: 'o',
    expanded: 'v',
    collapsed: '>',
    up: '^',
    down: 'v',
    previous: '<',
    next: '>',
    first: '<<',
    last: '>>',
    close: 'x',
    maximise: '+',
    restore: '=',
    bullet: '*',
    taskPending: '.',
    taskSkipped: '-',
    separator: '|',
    buttonEdges: ('[', ']'),
    trackVertical: '|',
    trackHorizontal: '-',
    thumbVertical: '#',
    thumbHorizontal: '#',
    thumbSlim: '#',
    partialBlocks: false,
    gaugeFilled: '=',
    gaugeHalf: '',
    gaugeEmpty: '-',
    spinner: SpinnerFrames.line,
    lines: BorderType.ascii,
    arrowLeft: '<',
    arrowRight: '>',
    arrowUp: '^',
    arrowDown: 'v',
    pointer: '>',
    menu: '=',
    shades: [' ', '.', ':', '+', '#'],
    swatch: '#',
    ellipsis: '...',
    omitted: '...',
  );

  /// The bar at the left of the row the cursor is on in a list, a menu or
  /// a file picker.
  final String cursor;

  /// The heavier bar at the edge of a toast.
  final String accent;

  /// A done, chosen or succeeded mark: a menu's checked entry, a chip's
  /// selection, a segmented button's, a finished task, the `success` kind.
  final String check;

  /// The check of a finished prompt or step, heavier than [check].
  final String checkBold;

  /// A failed or invalid mark: the `error` kind, a failed task, an error
  /// line of a prompt.
  final String cross;

  /// The icon of the `info` kind of status and toast.
  final String info;

  /// The icon of the `warning` kind of status and toast.
  final String warning;

  /// The mark of a checkbox that is on, between its [checkboxBrackets] and
  /// before its label: `x`, so `[x]`. [checkboxOff] has its width.
  final String checkboxOn;

  /// The mark of a checkbox that is off, a space by default (`[ ]`). Drawn
  /// in the mark's style, as [checkboxOn] is.
  final String checkboxOff;

  /// The characters either side of a checkbox's mark, `[` and `]`; an
  /// empty string for none, as in `('', '')` for `✓ ·`. Drawn in the
  /// `Checkbox`'s `bracketStyle`.
  final (String, String) checkboxBrackets;

  /// The mark of a radio button that is chosen, between its
  /// [radioBrackets] and before its label: `●`, so `(●)`. [radioOff] has
  /// its width. `RadioGroup.mark` replaces it.
  final String radioOn;

  /// The mark of a radio button that is not chosen, a space by default
  /// (`( )`); a ring as `○` for a set with no brackets. Drawn in the
  /// brackets' style.
  final String radioOff;

  /// The characters either side of a radio button's mark, `(` and `)`;
  /// an empty string for none, as in `('', '')` for `◉ ○`. Drawn in the
  /// `RadioGroup`'s `bracketStyle`.
  final (String, String) radioBrackets;

  /// The left end of a switch's track; the knob is [switchKnob].
  final String switchStart;

  /// The right end of a switch's track.
  final String switchEnd;

  /// A switch's knob, a filled dot, on its track between [switchStart]
  /// and [switchEnd].
  final String switchKnob;

  /// The step in hand of a stepper, being edited: a filled dot, as
  /// [ring] is a step not done yet.
  final String stepCurrent;

  /// An empty ring: a step not done yet.
  final String ring;

  /// What is open: a tree's or an expansion tile's node that shows its
  /// children, the closed select's arrow.
  final String expanded;

  /// What is closed: a node that hides its children, a menu entry with a
  /// submenu.
  final String collapsed;

  /// A small arrow up: a stepper's increase, a table sorted ascending.
  final String up;

  /// A small arrow down: a stepper's decrease, a table sorted
  /// descending, a select's or a date picker's list to open.
  final String down;

  /// Go to the previous: a tab strip's edge, a stepper's left arrow, a
  /// pagination's previous page.
  final String previous;

  /// Go to the next.
  final String next;

  /// Go to the first page. A string of one or two columns.
  final String first;

  /// Go to the last page.
  final String last;

  /// Close, remove or dismiss: a chip's, a window's, a callout's.
  final String close;

  /// A window's maximise button.
  final String maximise;

  /// A maximised window's button to restore it.
  final String restore;

  /// A window's minimise button.
  final String minimise;

  /// A bullet between items on a line, and the mask of a hidden text.
  final String bullet;

  /// The mark of a task not started (`TaskStatus.pending`).
  final String taskPending;

  /// The mark of a task skipped (`TaskStatus.skipped`).
  final String taskSkipped;

  /// The line between the segments of a segmented button.
  final String separator;

  /// The left and the right edge of a one-row button, a column each: `▕`
  /// and `▏`, so a chip's label stands between thin bars. An edge that is
  /// not one column wide and one code point is Glyphs.ascii's `[` or `]`,
  /// with a warning; an empty one is no edge.
  final (String, String) buttonEdges;

  /// A vertical scrollbar's track.
  final String trackVertical;

  /// A horizontal scrollbar's track.
  final String trackHorizontal;

  /// A vertical scrollbar's thumb at rest.
  final String thumbVertical;

  /// A horizontal scrollbar's thumb at rest.
  final String thumbHorizontal;

  /// The thumb of an options list, in its last column: a half cell at the
  /// edge, on the list's own background, where [thumbVertical] is a whole
  /// cell's line over a [trackVertical] the list does not draw.
  final String thumbSlim;

  /// Whether a scrollbar's thumb and a slider's may draw with the block
  /// elements that cover a part of a cell (eighths), where the terminal
  /// draws them one column wide; else whole cells of [thumbVertical] and
  /// [thumbHorizontal].
  final bool partialBlocks;

  /// The filled part of a `LineGauge`.
  final String gaugeFilled;

  /// The filled part's last half cell of a `LineGauge`; empty for a set
  /// that has none, whole cells then.
  final String gaugeHalf;

  /// The rest of a `LineGauge`.
  final String gaugeEmpty;

  /// The frames of a `Spinner` given none, and of the running task of a
  /// list.
  final SpinnerFrames spinner;

  /// The lines of a box, a divider, a split's bar, a callout, a tree's
  /// guides and a rule, for every one given no type of its own
  /// (`Border.type`, `Divider.type` and the like are null then):
  /// [BorderType.single], or [BorderType.ascii] (`+-|`).
  ///
  /// A set whose `lines` is [BorderType.ascii] draws every line ASCII,
  /// also where a widget says `rounded`, `heavy` or `double`: see
  /// [borderOf].
  final BorderType lines;

  /// An arrow to the left: a key hint's, a dock's side to drop on.
  final String arrowLeft;

  /// An arrow to the right.
  final String arrowRight;

  /// An arrow up: a key hint's, a dock's side to drop on.
  final String arrowUp;

  /// An arrow down: a key hint's, a dock's side, the log view's "new lines
  /// below".
  final String arrowDown;

  /// What points at a row: the row of a traceback the error is in.
  final String pointer;

  /// The menu toggle of a scaffold: three bars.
  final String menu;

  /// The shades of a fill, from none to full, at least two: a blank, a
  /// light, a medium, a dark and a full cell. A heatmap's ramp; the
  /// skeleton's mark is the light one (index 1). A `const` constructor
  /// cannot check the length, so only [copyWith] asserts it, and only of a
  /// list it is given; the charts, `Skeleton` and `Heatmap` draw with a
  /// shorter one ([ThemeMarks.ramp]) rather than throw. The list
  /// [copyWith] is given is copied unmodifiable, so the caller's list
  /// changing later does not change the set; a `const` constructor cannot
  /// copy, so a list given to it is the caller's own.
  final List<String> shades;

  /// A solid square: a swatch of a color, the centre of a dock's target.
  final String swatch;

  /// The mark of text cut short, in the rows of a widget that cuts its own
  /// text (a breadcrumb, a page list, a JSON view), and that of a cut `Text`
  /// and `Box` title, which the core takes as a value
  /// (`RenderParagraph.ellipsis`). It may be longer than one column
  /// (`...`): its columns come out of the room.
  final String ellipsis;

  /// The mark of lines left out of a view, a row standing for what is not
  /// shown (the unchanged lines a diff folds): a midline `⋯` in
  /// [Glyphs.unicode], `...` in [Glyphs.ascii], so a row that begins with it
  /// reads the same in both. Text in a row, not a cell: it may be longer
  /// than one column, and the row measures it; the one-column
  /// rule of [Marks] is not applied to it.
  final String omitted;

  /// [type] as it is drawn in this set: [lines] where [type] is null, and
  /// [BorderType.ascii] where [lines] is that and [type] is any line but
  /// [BorderType.none]; else [type] as it is.
  BorderType borderOf(BorderType? type) {
    if (type == null) {
      return lines;
    }
    return lines == BorderType.ascii && type != BorderType.none
        ? BorderType.ascii
        : type;
  }

  /// This set with the marks given in place of its own; a `gaugeHalf` of
  /// `''` leaves it with no half cell.
  Glyphs copyWith({
    String? cursor,
    String? accent,
    String? check,
    String? checkBold,
    String? cross,
    String? info,
    String? warning,
    String? checkboxOn,
    String? checkboxOff,
    (String, String)? checkboxBrackets,
    String? radioOn,
    String? radioOff,
    (String, String)? radioBrackets,
    String? switchStart,
    String? switchEnd,
    String? switchKnob,
    String? stepCurrent,
    String? ring,
    String? expanded,
    String? collapsed,
    String? up,
    String? down,
    String? previous,
    String? next,
    String? first,
    String? last,
    String? close,
    String? maximise,
    String? restore,
    String? minimise,
    String? bullet,
    String? taskPending,
    String? taskSkipped,
    String? separator,
    (String, String)? buttonEdges,
    String? trackVertical,
    String? trackHorizontal,
    String? thumbVertical,
    String? thumbHorizontal,
    String? thumbSlim,
    bool? partialBlocks,
    String? gaugeFilled,
    String? gaugeHalf,
    String? gaugeEmpty,
    SpinnerFrames? spinner,
    BorderType? lines,
    String? arrowLeft,
    String? arrowRight,
    String? arrowUp,
    String? arrowDown,
    String? pointer,
    String? menu,
    List<String>? shades,
    String? swatch,
    String? ellipsis,
    String? omitted,
  }) {
    assert(
      shades == null || shades.length >= 2,
      'Glyphs.shades are at least two: a blank and a mark',
    );
    return Glyphs(
      cursor: cursor ?? this.cursor,
      accent: accent ?? this.accent,
      check: check ?? this.check,
      checkBold: checkBold ?? this.checkBold,
      cross: cross ?? this.cross,
      info: info ?? this.info,
      warning: warning ?? this.warning,
      checkboxOn: checkboxOn ?? this.checkboxOn,
      checkboxOff: checkboxOff ?? this.checkboxOff,
      checkboxBrackets: checkboxBrackets ?? this.checkboxBrackets,
      radioOn: radioOn ?? this.radioOn,
      radioOff: radioOff ?? this.radioOff,
      radioBrackets: radioBrackets ?? this.radioBrackets,
      switchStart: switchStart ?? this.switchStart,
      switchEnd: switchEnd ?? this.switchEnd,
      switchKnob: switchKnob ?? this.switchKnob,
      stepCurrent: stepCurrent ?? this.stepCurrent,
      ring: ring ?? this.ring,
      expanded: expanded ?? this.expanded,
      collapsed: collapsed ?? this.collapsed,
      up: up ?? this.up,
      down: down ?? this.down,
      previous: previous ?? this.previous,
      next: next ?? this.next,
      first: first ?? this.first,
      last: last ?? this.last,
      close: close ?? this.close,
      maximise: maximise ?? this.maximise,
      restore: restore ?? this.restore,
      minimise: minimise ?? this.minimise,
      bullet: bullet ?? this.bullet,
      taskPending: taskPending ?? this.taskPending,
      taskSkipped: taskSkipped ?? this.taskSkipped,
      separator: separator ?? this.separator,
      buttonEdges: buttonEdges ?? this.buttonEdges,
      trackVertical: trackVertical ?? this.trackVertical,
      trackHorizontal: trackHorizontal ?? this.trackHorizontal,
      thumbVertical: thumbVertical ?? this.thumbVertical,
      thumbHorizontal: thumbHorizontal ?? this.thumbHorizontal,
      thumbSlim: thumbSlim ?? this.thumbSlim,
      partialBlocks: partialBlocks ?? this.partialBlocks,
      gaugeFilled: gaugeFilled ?? this.gaugeFilled,
      gaugeHalf: gaugeHalf ?? this.gaugeHalf,
      gaugeEmpty: gaugeEmpty ?? this.gaugeEmpty,
      spinner: spinner ?? this.spinner,
      lines: lines ?? this.lines,
      arrowLeft: arrowLeft ?? this.arrowLeft,
      arrowRight: arrowRight ?? this.arrowRight,
      arrowUp: arrowUp ?? this.arrowUp,
      arrowDown: arrowDown ?? this.arrowDown,
      pointer: pointer ?? this.pointer,
      menu: menu ?? this.menu,
      shades: shades == null ? this.shades : List.unmodifiable(shades),
      swatch: swatch ?? this.swatch,
      ellipsis: ellipsis ?? this.ellipsis,
      omitted: omitted ?? this.omitted,
    );
  }

  List<Object?> get _all => [
    cursor,
    accent,
    check,
    checkBold,
    cross,
    info,
    warning,
    checkboxOn,
    checkboxOff,
    checkboxBrackets,
    radioOn,
    radioOff,
    radioBrackets,
    switchStart,
    switchEnd,
    switchKnob,
    stepCurrent,
    ring,
    expanded,
    collapsed,
    up,
    down,
    previous,
    next,
    first,
    last,
    close,
    maximise,
    restore,
    minimise,
    bullet,
    taskPending,
    taskSkipped,
    separator,
    buttonEdges,
    trackVertical,
    trackHorizontal,
    thumbVertical,
    thumbHorizontal,
    thumbSlim,
    partialBlocks,
    gaugeFilled,
    gaugeHalf,
    gaugeEmpty,
    spinner,
    lines,
    arrowLeft,
    arrowRight,
    arrowUp,
    arrowDown,
    pointer,
    menu,
    // a list by its marks, not by identity
    shades.join('\u0000'),
    swatch,
    ellipsis,
    omitted,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! Glyphs) {
      return false;
    }
    final a = _all;
    final b = other._all;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_all);
}
