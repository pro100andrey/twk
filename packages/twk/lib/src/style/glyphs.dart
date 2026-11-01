/// The marks widgets draw with, by what they mean: [Glyphs], its presets
/// [Glyphs.unicode] and [Glyphs.ascii], in the theme ([ThemeData.glyphs]).
library;

import 'package:meta/meta.dart';

import '../animation/spinner.dart' show SpinnerFrames;
import 'theme.dart' show Theme, ThemeData;

/// The marks widgets draw, by what each means (a check, a cross, a cursor
/// bar, a scrollbar's thumb) and not by the widget that draws it: a mark
/// is one field, whichever widgets show it. An app picks a set for itself
/// or for a part of it, in the theme ([ThemeData.glyphs]), as it picks
/// colors.
///
/// The presets: [Glyphs.unicode], the default, the marks the widgets drew
/// before the theme held them; and [Glyphs.ascii], ASCII only, for a
/// terminal or a font without the others. [copyWith] changes some marks of
/// a set; each mark is a string of one column unless its doc says
/// otherwise, and the widgets lay out by the width the terminal gives it.
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
    this.checkboxOn = '[x]',
    this.checkboxOff = '[ ]',
    this.radioOn = '(●)',
    this.radioOff = '( )',
    this.switchStart = '▐',
    this.switchEnd = '▌',
    this.dot = '●',
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
    this.capOpen = '▕',
    this.capClose = '▏',
    this.trackVertical = '│',
    this.trackHorizontal = '─',
    this.thumbVertical = '┃',
    this.thumbHorizontal = '━',
    this.thumbEdge = '▐',
    this.eighths = true,
    this.gaugeFilled = '─',
    this.gaugeHalf = '╴',
    this.gaugeEmpty = '─',
    this.spinner = SpinnerFrames.dots,
  });

  /// The set [t] of the way from [a] to [b]: marks do not blend, so [a]'s
  /// before halfway and [b]'s after it.
  factory Glyphs.lerp(Glyphs a, Glyphs b, double t) => t < 0.5 ? a : b;

  /// The marks the widgets drew before the theme held them, with Unicode:
  /// the default of [ThemeData.glyphs].
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
    radioOn: '(*)',
    switchStart: '[',
    switchEnd: ']',
    dot: '*',
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
    capOpen: '[',
    capClose: ']',
    trackVertical: '|',
    trackHorizontal: '-',
    thumbVertical: '#',
    thumbHorizontal: '#',
    thumbEdge: '#',
    eighths: false,
    gaugeFilled: '=',
    gaugeHalf: '',
    gaugeEmpty: '-',
    spinner: SpinnerFrames.line,
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

  /// A checkbox that is on, before its label; [checkboxOff] has its
  /// width.
  final String checkboxOn;

  /// A checkbox that is off.
  final String checkboxOff;

  /// A radio button that is chosen, before its label, brackets included:
  /// `(●)`; [radioOff] has its width. A glyph of three characters or more
  /// has its first and last for brackets, in the brackets' style and
  /// what is between in the mark's; one of fewer (`◉`) is all mark.
  /// `RadioGroup.mark` replaces what is between the brackets.
  final String radioOn;

  /// A radio button that is not chosen: `( )`. Without brackets, a ring
  /// as `○`, in the brackets' style.
  final String radioOff;

  /// The left end of a switch's track; the knob is [dot].
  final String switchStart;

  /// The right end of a switch's track.
  final String switchEnd;

  /// A filled dot: a switch's knob, the step in
  /// hand of a stepper.
  final String dot;

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

  /// The mark of a task not started.
  final String taskPending;

  /// The mark of a task skipped.
  final String taskSkipped;

  /// The line between the segments of a segmented button, and the edge of
  /// a button where [capOpen] is not one column.
  final String separator;

  /// The left edge of a one-row button.
  final String capOpen;

  /// The right edge of a one-row button.
  final String capClose;

  /// A vertical scrollbar's track.
  final String trackVertical;

  /// A horizontal scrollbar's track.
  final String trackHorizontal;

  /// A vertical scrollbar's thumb at rest.
  final String thumbVertical;

  /// A horizontal scrollbar's thumb at rest.
  final String thumbHorizontal;

  /// The thumb of an options list, in its last column.
  final String thumbEdge;

  /// Whether a scrollbar's thumb and a slider's may use the block elements
  /// that cover an eighth of a cell, where the terminal draws them one
  /// column wide; else whole cells of [thumbVertical] and
  /// [thumbHorizontal].
  final bool eighths;

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

  /// This set with the marks given in place of its own.
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
    String? radioOn,
    String? radioOff,
    String? switchStart,
    String? switchEnd,
    String? dot,
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
    String? capOpen,
    String? capClose,
    String? trackVertical,
    String? trackHorizontal,
    String? thumbVertical,
    String? thumbHorizontal,
    String? thumbEdge,
    bool? eighths,
    String? gaugeFilled,
    String? gaugeHalf,
    String? gaugeEmpty,
    SpinnerFrames? spinner,
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
    radioOn: radioOn ?? this.radioOn,
    radioOff: radioOff ?? this.radioOff,
    switchStart: switchStart ?? this.switchStart,
    switchEnd: switchEnd ?? this.switchEnd,
    dot: dot ?? this.dot,
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
    capOpen: capOpen ?? this.capOpen,
    capClose: capClose ?? this.capClose,
    trackVertical: trackVertical ?? this.trackVertical,
    trackHorizontal: trackHorizontal ?? this.trackHorizontal,
    thumbVertical: thumbVertical ?? this.thumbVertical,
    thumbHorizontal: thumbHorizontal ?? this.thumbHorizontal,
    thumbEdge: thumbEdge ?? this.thumbEdge,
    eighths: eighths ?? this.eighths,
    gaugeFilled: gaugeFilled ?? this.gaugeFilled,
    gaugeHalf: gaugeHalf ?? this.gaugeHalf,
    gaugeEmpty: gaugeEmpty ?? this.gaugeEmpty,
    spinner: spinner ?? this.spinner,
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
    radioOn,
    radioOff,
    switchStart,
    switchEnd,
    dot,
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
    capOpen,
    capClose,
    trackVertical,
    trackHorizontal,
    thumbVertical,
    thumbHorizontal,
    thumbEdge,
    eighths,
    gaugeFilled,
    gaugeHalf,
    gaugeEmpty,
    spinner,
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
