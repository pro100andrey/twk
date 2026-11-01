/// The marks widgets draw with, by what they mean: [Glyphs], its presets
/// [Glyphs.unicode] and [Glyphs.ascii], in the theme ([ThemeData.glyphs]).
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show BorderType, LogLevel, LogRecord, RenderObject, TextSegmenter, log;

import '../animation/spinner.dart' show SpinnerFrames;
import '../binding/app_binding.dart' show AppBinding;
import '../framework/framework.dart' show BuildContext;
import '../text/hit_row.dart' show segmenterOf;
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
/// (in cells, not code units). A mark drawn in one cell that is not one
/// column wide (an emoji, an ambiguous mark in some terminals), or is a
/// cluster of more than one code point (a letter and a combining accent),
/// is the same field of [Glyphs.ascii] there, with one warning in the
/// app's log for each such mark; the width is the terminal's, so it is
/// known only when the mark is drawn. The rule is one for a mark filled
/// into a cell (a scrollbar's thumb, a gauge) and for one drawn as text in
/// a row (a radio button's, a switch's, a button's edge). An empty mark
/// draws nothing and breaks nothing: a blank where a cell is to be filled,
/// no width where the mark is text in a row (a bracket of [radioBrackets],
/// a button's edge, a switch's end), but a blank for [switchKnob], for the
/// track to keep its width. The checkbox is as the radio button is: its
/// marks [checkboxOn] and [checkboxOff] are one cell each, and the
/// [checkboxBrackets] around them are text of their own.
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
  });

  /// The set [t] of the way from [a] to [b]: marks do not blend, so [a]'s
  /// before halfway and [b]'s after it.
  factory Glyphs.lerp(Glyphs a, Glyphs b, double t) => t < 0.5 ? a : b;

  /// The marks the widgets draw with Unicode: the default of
  /// [ThemeData.glyphs].
  static const unicode = Glyphs();

  /// ASCII only: `>` for a cursor, `v` for a check, `x` for a cross and a
  /// close, `[`/`]` ends of a switch and a button's edge, `#` for a
  /// scrollbar's thumb on a `|` or `-` track, `=` for the filled part of a
  /// line gauge, `v` and `>` for what is open and closed, the spinner
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
    gaugeHalf: null,
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

  /// The filled part's last half cell of a `LineGauge`; null for a set
  /// that has none, whole cells then.
  final String? gaugeHalf;

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
  /// skeleton's mark is the light one (index 1).
  final List<String> shades;

  /// A solid square: a swatch of a color, the centre of a dock's target.
  final String swatch;

  /// The mark of text cut short, in the rows of a widget that cuts its own
  /// text (a breadcrumb, a page list, a JSON view). It may be longer than
  /// one column (`...`). The core's text overflow is not it.
  final String ellipsis;

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

  /// This set with the marks given in place of its own; [clearGaugeHalf]
  /// leaves it with no [gaugeHalf], whatever `gaugeHalf` says.
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
    bool clearGaugeHalf = false,
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
  }) => Glyphs(
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
    gaugeHalf: clearGaugeHalf ? null : gaugeHalf ?? this.gaugeHalf,
    gaugeEmpty: gaugeEmpty ?? this.gaugeEmpty,
    spinner: spinner ?? this.spinner,
    lines: lines ?? this.lines,
    arrowLeft: arrowLeft ?? this.arrowLeft,
    arrowRight: arrowRight ?? this.arrowRight,
    arrowUp: arrowUp ?? this.arrowUp,
    arrowDown: arrowDown ?? this.arrowDown,
    pointer: pointer ?? this.pointer,
    menu: menu ?? this.menu,
    shades: shades ?? this.shades,
    swatch: swatch ?? this.swatch,
    ellipsis: ellipsis ?? this.ellipsis,
  );

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

/// The code point the mark [glyph] of the Glyphs field [field] fills one
/// cell of [object] with, under [segmenter]'s measure: its only one while
/// it is one column wide.
///
/// Where it is any other width (an emoji, an East Asian ambiguous mark in
/// some terminals), or is a cluster of more than one code point (a letter
/// and a combining accent, which one cell cannot hold), it is [fallback],
/// the same field of [Glyphs.ascii] as the caller passes it, and the app's
/// log gets one warning for each distinct ([field], [glyph]) under the
/// [object]'s pipeline, the way a flex's overflow is warned of. An empty
/// [glyph] is no warning: a blank where [blankIfEmpty], else [fallback].
@internal
int cellRune(
  RenderObject object,
  String field,
  String glyph,
  String fallback,
  TextSegmenter segmenter, {
  bool blankIfEmpty = false,
}) {
  if (glyph.isEmpty) {
    return blankIfEmpty ? 0x20 : fallback.runes.first;
  }
  final owner = object.owner;
  if (_fits(
    owner,
    owner?.onLog,
    field,
    glyph,
    segmenter,
    "Glyphs.ascii's '$fallback'",
  )) {
    return glyph.runes.first;
  }
  return fallback.runes.first;
}

/// The code point of the optional mark [glyph] of the Glyphs field
/// [field], as [cellRune] measures it; null where it is empty (no
/// warning) or does not fit one cell (the same warning, saying that no
/// mark is drawn in its place, for a field with no ASCII mark).
@internal
int? optionalCellRune(
  RenderObject object,
  String field,
  String glyph,
  TextSegmenter segmenter,
) {
  if (glyph.isEmpty) {
    return null;
  }
  final owner = object.owner;
  if (_fits(owner, owner?.onLog, field, glyph, segmenter, 'no mark')) {
    return glyph.runes.first;
  }
  return null;
}

/// The mark [glyph] of the Glyphs field [field], a string drawn as text
/// in a widget built in [context], where it is to be one cell: [glyph]
/// while it is one column wide and one code point, else [fallback], the
/// same field of [Glyphs.ascii], with the one warning [cellRune] gives.
/// An empty [glyph] stays empty, no warning: what that draws is the
/// caller's, as the doc of its field says.
@internal
String textMark(
  BuildContext context,
  String field,
  String glyph,
  String fallback,
) {
  if (glyph.isEmpty || _plain(glyph)) {
    return glyph;
  }
  final owner = context.findRenderObject()?.owner;
  final binding = owner == null ? AppBinding.maybeOf(context) : null;
  final fits = _fits(
    owner ?? binding?.twkApp.owner,
    (owner ?? binding?.twkApp.owner)?.onLog,
    field,
    glyph,
    segmenterOf(context),
    "Glyphs.ascii's '$fallback'",
  );
  return fits ? glyph : fallback;
}

/// The straight line of the border [type] (the theme's [Glyphs.lines] when
/// null) across, for a dash drawn as text in a row (a title on a box's
/// edge, a stepper's line): the line of [Glyphs.borderOf], a blank for
/// [BorderType.none]. Its width is the text's to measure.
@internal
String lineMark(Glyphs glyphs, BorderType? type, {bool down = false}) =>
    String.fromCharCode(
      glyphs
          .borderOf(type)
          .glyph(up: down, down: down, left: !down, right: !down),
    );

/// The marks of a checkbox as [textMark] fits them for [context]: the
/// brackets, the mark that is on and the mark that is off, in `x` and a
/// blank, `[` and `]` where one does not fit its cell (with the one
/// warning); an empty one stays empty.
@internal
CheckboxMarks checkboxMarks(BuildContext context, Glyphs glyphs) {
  final (open, close) = glyphs.checkboxBrackets;
  return CheckboxMarks(
    textMark(context, 'checkboxBrackets', open, '['),
    textMark(context, 'checkboxOn', glyphs.checkboxOn, 'x'),
    textMark(context, 'checkboxOff', glyphs.checkboxOff, ' '),
    textMark(context, 'checkboxBrackets', close, ']'),
  );
}

/// The parts of a checkbox, fitted by [checkboxMarks].
@internal
final class CheckboxMarks {
  /// Marks around and in a checkbox.
  const CheckboxMarks(this.open, this.onMark, this.offMark, this.close);

  /// The bracket before the mark.
  final String open;

  /// The mark of a checkbox that is on.
  final String onMark;

  /// The mark of a checkbox that is off.
  final String offMark;

  /// The bracket after the mark.
  final String close;

  /// The whole of a checkbox that is on, as text.
  String get on => '$open$onMark$close';

  /// The whole of a checkbox that is off, as text.
  String get off => '$open$offMark$close';
}

/// [glyphs] with the marks of a switch's pill fitted for [context]: its
/// ends as [textMark] (an empty end stays, no cell), its knob too, and
/// an empty knob a blank, for the track to keep its width. [glyphs]
/// itself where all three are as they are.
@internal
Glyphs switchMarks(BuildContext context, Glyphs glyphs) {
  final start = textMark(context, 'switchStart', glyphs.switchStart, '[');
  final end = textMark(context, 'switchEnd', glyphs.switchEnd, ']');
  final knob = glyphs.switchKnob.isEmpty
      ? ' '
      : textMark(context, 'switchKnob', glyphs.switchKnob, '*');
  if (start == glyphs.switchStart &&
      end == glyphs.switchEnd &&
      knob == glyphs.switchKnob) {
    return glyphs;
  }
  return glyphs.copyWith(switchStart: start, switchEnd: end, switchKnob: knob);
}

/// The marks of a radio button as [textMark] fits them for [context]: the
/// chosen one's, and the other's, which stays empty where it is (the
/// brackets then hold no cell, and the one that is on no more than its
/// own width).
@internal
({String on, String off}) radioMarks(BuildContext context, Glyphs glyphs) => (
  on: textMark(context, 'radioOn', glyphs.radioOn, '*'),
  off: textMark(context, 'radioOff', glyphs.radioOff, ' '),
);

/// The edges of a one-row button as [textMark] fits them for [context]; an
/// edge that is empty stays empty, and the button has none there.
@internal
(String, String) buttonEdgeMarks(BuildContext context, Glyphs glyphs) => (
  textMark(context, 'buttonEdges', glyphs.buttonEdges.$1, '['),
  textMark(context, 'buttonEdges', glyphs.buttonEdges.$2, ']'),
);

// a printable ASCII character: one cell, one code point, no measuring
bool _plain(String glyph) {
  if (glyph.length != 1) {
    return false;
  }
  final c = glyph.codeUnitAt(0);
  return c >= 0x20 && c < 0x7f;
}

// whether [glyph] fills one cell: one column wide and one code point;
// else the warning, once for each owner, saying [instead] is drawn
bool _fits(
  Object? owner,
  void Function(LogRecord record)? route,
  String field,
  String glyph,
  TextSegmenter segmenter,
  String instead,
) {
  final width = segmenter.width(glyph);
  final runes = glyph.runes.length;
  if (width == 1 && runes == 1) {
    return true;
  }
  if (width == 2 && runes == 1 && _presetMarks.contains(glyph)) {
    // the preset's own mark, not the app's: the terminal is the cause, told
    // once and not for each field
    _warn(
      owner,
      route,
      'ambiguous',
      '',
      'This terminal draws East Asian ambiguous characters two cells '
          'wide, so the marks of Glyphs.unicode that are such are drawn as '
          "Glyphs.ascii's. Glyphs.ascii as the theme's set, or marks that "
          'are not ambiguous, make that the app choice.',
    );
    return false;
  }
  final what = width == 1
      ? 'a cluster of $runes code points, not one'
      : '$width cells wide, not 1';
  _warn(
    owner,
    route,
    field,
    glyph,
    "Glyphs.$field '$glyph' is $what; $instead is drawn in its place.",
  );
  return false;
}

void _warn(
  Object? owner,
  void Function(LogRecord record)? route,
  String field,
  String glyph,
  String message,
) {
  if (owner == null || (_warned[owner] ??= {}).add('$field\u0000$glyph')) {
    if (route == null) {
      log(message, level: LogLevel.warning);
    } else {
      route(LogRecord(DateTime.now(), LogLevel.warning, message));
    }
  }
}

// the marks of Glyphs.unicode that are one code point each, which a
// terminal can count two cells wide
final Set<String> _presetMarks = {
  for (final mark in Glyphs.unicode._all)
    if (mark is String && mark.runes.length == 1)
      mark
    else if (mark is (String, String)) ...[
      if (mark.$1.runes.length == 1) mark.$1,
      if (mark.$2.runes.length == 1) mark.$2,
    ],
};

// the (field, glyph) pairs each pipeline has warned of
final _warned = Expando<Set<String>>('glyph warnings');
