/// The drawn mark of a theme field: [Marks], one descriptor for each mark of
/// [Glyphs], and [ThemeMarks], what resolves them under the one width rule.
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show
        BorderType,
        ClusterScan,
        LogLevel,
        LogRecord,
        PipelineOwner,
        RenderObject,
        TextSegmenter,
        log;

import '../binding/app_binding.dart' show AppBinding;
import '../framework/framework.dart' show BuildContext;
import '../text/hit_row.dart' show segmenterOf;
import 'glyphs.dart';
import 'theme.dart' show Theme;

// Examples can assume:
// late BuildContext context;

/// What an empty mark of [Glyphs] is, as a [Mark] says it.
enum OnEmpty {
  /// A blank: a space, where the mark is a cell to be filled or a place in
  /// a row to be held.
  blank,

  /// Nothing: no cell is drawn and no text stands in the row.
  none,

  /// The same field of [Glyphs.ascii].
  fallback,
}

// the Glyphs fields that are marks: one cell, one column
enum _Field {
  cursor,
  accent,
  check,
  checkBold,
  cross,
  info,
  warning,
  checkboxOn,
  checkboxOff,
  checkboxOpen('checkboxBrackets'),
  checkboxClose('checkboxBrackets'),
  radioOn,
  radioOff,
  radioOpen('radioBrackets'),
  radioClose('radioBrackets'),
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
  close,
  maximise,
  restore,
  minimise,
  bullet,
  taskPending,
  taskSkipped,
  separator,
  buttonEdgeStart('buttonEdges'),
  buttonEdgeEnd('buttonEdges'),
  trackVertical,
  trackHorizontal,
  thumbVertical,
  thumbHorizontal,
  thumbSlim,
  gaugeFilled,
  gaugeHalf,
  gaugeEmpty,
  arrowLeft,
  arrowRight,
  arrowUp,
  arrowDown,
  pointer,
  menu,
  swatch,
  shade('shades');

  const _Field([this._name]);

  final String? _name;

  /// The field of Glyphs it is, by the name an app writes it with.
  String get field => _name ?? name;

  String of(Glyphs g) => switch (this) {
    cursor => g.cursor,
    accent => g.accent,
    check => g.check,
    checkBold => g.checkBold,
    cross => g.cross,
    info => g.info,
    warning => g.warning,
    checkboxOn => g.checkboxOn,
    checkboxOff => g.checkboxOff,
    checkboxOpen => g.checkboxBrackets.$1,
    checkboxClose => g.checkboxBrackets.$2,
    radioOn => g.radioOn,
    radioOff => g.radioOff,
    radioOpen => g.radioBrackets.$1,
    radioClose => g.radioBrackets.$2,
    switchStart => g.switchStart,
    switchEnd => g.switchEnd,
    switchKnob => g.switchKnob,
    stepCurrent => g.stepCurrent,
    ring => g.ring,
    expanded => g.expanded,
    collapsed => g.collapsed,
    up => g.up,
    down => g.down,
    previous => g.previous,
    next => g.next,
    close => g.close,
    maximise => g.maximise,
    restore => g.restore,
    minimise => g.minimise,
    bullet => g.bullet,
    taskPending => g.taskPending,
    taskSkipped => g.taskSkipped,
    separator => g.separator,
    buttonEdgeStart => g.buttonEdges.$1,
    buttonEdgeEnd => g.buttonEdges.$2,
    trackVertical => g.trackVertical,
    trackHorizontal => g.trackHorizontal,
    thumbVertical => g.thumbVertical,
    thumbHorizontal => g.thumbHorizontal,
    thumbSlim => g.thumbSlim,
    gaugeFilled => g.gaugeFilled,
    gaugeHalf => g.gaugeHalf,
    gaugeEmpty => g.gaugeEmpty,
    arrowLeft => g.arrowLeft,
    arrowRight => g.arrowRight,
    arrowUp => g.arrowUp,
    arrowDown => g.arrowDown,
    pointer => g.pointer,
    menu => g.menu,
    swatch => g.swatch,
    shade => ThemeMarks.ramp(g)[1],
  };
}

/// A mark of [Glyphs] as the module sees it: which field it reads, what
/// that field is in [Glyphs.ascii], and what an empty one means.
///
/// A [CellMark] or a [TextMark] says how the field is mostly drawn; either
/// resolves under [ThemeMarks.cell] and [ThemeMarks.text].
@immutable
sealed class Mark {
  const Mark._(this._field, this.onEmpty);

  final _Field _field;

  /// What an empty value of the field draws.
  final OnEmpty onEmpty;

  /// The name of the field in [Glyphs], as the warning says it.
  String get name => _field.field;

  /// The field of [glyphs].
  String of(Glyphs glyphs) => _field.of(glyphs);

  /// The same field of [Glyphs.ascii], the mark where [of] does not fit.
  String get fallback => _field.of(Glyphs.ascii);

  @override
  String toString() => 'Marks.${_field.name}';
}

/// A mark filled into one cell by a render object (a scrollbar's thumb, a
/// gauge's line, the cursor bar of a list).
final class CellMark extends Mark {
  const CellMark._(super._field, [super.onEmpty = OnEmpty.none]) : super._();
}

/// A mark drawn as text in a widget (a radio button's, a chip's close, an
/// arrow of a key hint).
final class TextMark extends Mark {
  const TextMark._(super._field, [super.onEmpty = OnEmpty.none]) : super._();
}

/// The marks of [Glyphs], one descriptor for each field that is one cell
/// wide. The fields that are not (the ellipsis, the shades, the spinner,
/// the `first` and `last` of a pagination, the lines) are not here.
abstract final class Marks {
  /// Every mark, in the order of [Glyphs].
  static const all = <Mark>[
    cursor,
    accent,
    check,
    checkBold,
    cross,
    info,
    warning,
    checkboxOn,
    checkboxOff,
    checkboxOpen,
    checkboxClose,
    radioOn,
    radioOff,
    radioOpen,
    radioClose,
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
    close,
    maximise,
    restore,
    minimise,
    bullet,
    taskPending,
    taskSkipped,
    separator,
    buttonEdgeStart,
    buttonEdgeEnd,
    trackVertical,
    trackHorizontal,
    thumbVertical,
    thumbHorizontal,
    thumbSlim,
    gaugeFilled,
    gaugeHalf,
    gaugeEmpty,
    arrowLeft,
    arrowRight,
    arrowUp,
    arrowDown,
    pointer,
    menu,
    swatch,
    shade,
  ];

  /// [Glyphs.cursor].
  static const cursor = CellMark._(_Field.cursor);

  /// [Glyphs.accent].
  static const accent = CellMark._(_Field.accent);

  /// [Glyphs.check].
  static const check = TextMark._(_Field.check);

  /// [Glyphs.checkBold].
  static const checkBold = TextMark._(_Field.checkBold);

  /// [Glyphs.cross].
  static const cross = TextMark._(_Field.cross);

  /// [Glyphs.info].
  static const info = TextMark._(_Field.info);

  /// [Glyphs.warning].
  static const warning = TextMark._(_Field.warning);

  /// [Glyphs.checkboxOn].
  static const checkboxOn = TextMark._(_Field.checkboxOn);

  /// [Glyphs.checkboxOff].
  static const checkboxOff = TextMark._(_Field.checkboxOff);

  /// The first of [Glyphs.checkboxBrackets].
  static const checkboxOpen = TextMark._(_Field.checkboxOpen);

  /// The second of [Glyphs.checkboxBrackets].
  static const checkboxClose = TextMark._(_Field.checkboxClose);

  /// [Glyphs.radioOn].
  static const radioOn = TextMark._(_Field.radioOn);

  /// [Glyphs.radioOff].
  static const radioOff = TextMark._(_Field.radioOff);

  /// The first of [Glyphs.radioBrackets].
  static const radioOpen = TextMark._(_Field.radioOpen);

  /// The second of [Glyphs.radioBrackets].
  static const radioClose = TextMark._(_Field.radioClose);

  /// [Glyphs.switchStart].
  static const switchStart = TextMark._(_Field.switchStart);

  /// [Glyphs.switchEnd].
  static const switchEnd = TextMark._(_Field.switchEnd);

  /// [Glyphs.switchKnob]; an empty one is a blank, for the track to keep
  /// its width.
  static const switchKnob = TextMark._(_Field.switchKnob, OnEmpty.blank);

  /// [Glyphs.stepCurrent].
  static const stepCurrent = TextMark._(_Field.stepCurrent);

  /// [Glyphs.ring].
  static const ring = TextMark._(_Field.ring);

  /// [Glyphs.expanded].
  static const expanded = TextMark._(_Field.expanded);

  /// [Glyphs.collapsed].
  static const collapsed = TextMark._(_Field.collapsed);

  /// [Glyphs.up].
  static const up = TextMark._(_Field.up);

  /// [Glyphs.down].
  static const down = TextMark._(_Field.down);

  /// [Glyphs.previous]; an empty one is a blank.
  static const previous = TextMark._(_Field.previous, OnEmpty.blank);

  /// [Glyphs.next]; an empty one is a blank.
  static const next = TextMark._(_Field.next, OnEmpty.blank);

  /// [Glyphs.close].
  static const close = TextMark._(_Field.close);

  /// [Glyphs.maximise].
  static const maximise = TextMark._(_Field.maximise);

  /// [Glyphs.restore].
  static const restore = TextMark._(_Field.restore);

  /// [Glyphs.minimise].
  static const minimise = TextMark._(_Field.minimise);

  /// [Glyphs.bullet].
  static const bullet = TextMark._(_Field.bullet);

  /// [Glyphs.taskPending].
  static const taskPending = TextMark._(_Field.taskPending);

  /// [Glyphs.taskSkipped].
  static const taskSkipped = TextMark._(_Field.taskSkipped);

  /// [Glyphs.separator].
  static const separator = TextMark._(_Field.separator);

  /// The first of [Glyphs.buttonEdges].
  static const buttonEdgeStart = TextMark._(_Field.buttonEdgeStart);

  /// The second of [Glyphs.buttonEdges].
  static const buttonEdgeEnd = TextMark._(_Field.buttonEdgeEnd);

  /// [Glyphs.trackVertical]; an empty one is a blank.
  static const trackVertical = CellMark._(
    _Field.trackVertical,
    OnEmpty.blank,
  );

  /// [Glyphs.trackHorizontal]; an empty one is a blank.
  static const trackHorizontal = CellMark._(
    _Field.trackHorizontal,
    OnEmpty.blank,
  );

  /// [Glyphs.thumbVertical]; an empty one is [Glyphs.ascii]'s.
  static const thumbVertical = CellMark._(
    _Field.thumbVertical,
    OnEmpty.fallback,
  );

  /// [Glyphs.thumbHorizontal]; an empty one is [Glyphs.ascii]'s.
  static const thumbHorizontal = CellMark._(
    _Field.thumbHorizontal,
    OnEmpty.fallback,
  );

  /// [Glyphs.thumbSlim].
  static const thumbSlim = CellMark._(_Field.thumbSlim);

  /// [Glyphs.gaugeFilled]; an empty one is [Glyphs.ascii]'s.
  static const gaugeFilled = CellMark._(_Field.gaugeFilled, OnEmpty.fallback);

  /// [Glyphs.gaugeHalf]; an empty one is no half cell.
  static const gaugeHalf = CellMark._(_Field.gaugeHalf);

  /// [Glyphs.gaugeEmpty]; an empty one is [Glyphs.ascii]'s.
  static const gaugeEmpty = CellMark._(_Field.gaugeEmpty, OnEmpty.fallback);

  /// [Glyphs.arrowLeft].
  static const arrowLeft = TextMark._(_Field.arrowLeft);

  /// [Glyphs.arrowRight].
  static const arrowRight = TextMark._(_Field.arrowRight);

  /// [Glyphs.arrowUp].
  static const arrowUp = TextMark._(_Field.arrowUp);

  /// [Glyphs.arrowDown].
  static const arrowDown = TextMark._(_Field.arrowDown);

  /// [Glyphs.pointer].
  static const pointer = TextMark._(_Field.pointer);

  /// [Glyphs.menu].
  static const menu = TextMark._(_Field.menu);

  /// [Glyphs.swatch].
  static const swatch = TextMark._(_Field.swatch);

  /// The light shade of [Glyphs.shades] (the one at 1, a skeleton's); an
  /// empty one is a blank.
  static const shade = CellMark._(_Field.shade, OnEmpty.blank);
}

/// The marks of the theme as a terminal draws them: each [Mark] resolved to
/// the theme's own where it is one column wide and one code point, else to
/// [Glyphs.ascii]'s, with one warning in the app's log for each such
/// (field, glyph).
///
/// This is the one place the rule is kept. A widget asks for
/// [ThemeMarks.of] in its `build` and [text]; a render object asks for
/// [ThemeMarks.ofObject] and [cell]. A mark is measured once for each
/// segmenter, and the resolvers are kept (a few for each segmenter), so
/// asking again in each build or frame allocates nothing.
///
/// ```dart
/// final marks = ThemeMarks.of(context);
/// final close = marks.text(Marks.close); // 'x' where '×' is two columns
/// ```
final class ThemeMarks {
  ThemeMarks._(this._cache, this._owner, this._glyphs);

  /// The marks of the theme around [context], measured by the segmenter
  /// the app draws with. The same object is returned while the theme's
  /// [Glyphs], the segmenter and the pipeline are the same.
  factory ThemeMarks.of(BuildContext context) {
    final object = context.findRenderObject();
    final owner = object?.owner ?? AppBinding.maybeOf(context)?.twkApp.owner;
    return _cacheOf(
      segmenterOf(context),
    ).resolver(owner, Theme.of(context).glyphs);
  }

  /// The marks as [segmenter], the measure of the canvas [object] draws
  /// on, draws them; their glyphs are the second argument of [cell], which
  /// it takes. The same object is returned for the same segmenter and
  /// pipeline, so a paint takes no allocation, and one kept while another
  /// object asks for its own warns to its own pipeline. [object] is null
  /// in code that has none (a markdown render to lines): a warning then
  /// goes to the log of [log].
  factory ThemeMarks.ofObject(RenderObject? object, TextSegmenter segmenter) =>
      _cacheOf(segmenter).resolver(object?.owner, null);

  final _Cache _cache;
  final PipelineOwner? _owner;
  final Glyphs? _glyphs;

  // the glyphs a mark is of: [glyphs] where given, else the theme's of
  // [ThemeMarks.of]; one of [ThemeMarks.ofObject] has none of its own
  Glyphs _of(Glyphs? glyphs) =>
      glyphs ??
      _glyphs ??
      (throw ArgumentError.notNull(
        'glyphs (ThemeMarks.ofObject takes them with each mark)',
      ));

  /// [mark] as the code point to fill one cell with, of [glyphs] (the
  /// theme's of [ThemeMarks.of], when null); null where nothing is to be
  /// drawn.
  ///
  /// Of the theme's own while it is one column wide and one code point,
  /// else [Mark.fallback], with the one warning. An empty mark is what
  /// [Mark.onEmpty] says, with no warning.
  int? cell(Mark mark, [Glyphs? glyphs]) {
    final value = mark.of(_of(glyphs));
    if (value.isEmpty) {
      return switch (mark.onEmpty) {
        OnEmpty.blank => 0x20,
        OnEmpty.none => null,
        OnEmpty.fallback =>
          mark.fallback.isEmpty ? null : mark.fallback.runes.first,
      };
    }
    if (_fits(mark, value)) {
      return value.runes.first;
    }
    final fallback = mark.fallback;
    return fallback.isEmpty ? null : fallback.runes.first;
  }

  /// [mark] as text in a row, of [glyphs] (the theme's of [ThemeMarks.of],
  /// when null): the theme's own while it is one column wide and one code
  /// point, else [Mark.fallback], with the one warning. An empty mark is
  /// what [Mark.onEmpty] says (an empty string, a space, or the
  /// fallback), with no warning.
  String text(Mark mark, [Glyphs? glyphs]) {
    final value = mark.of(_of(glyphs));
    if (value.isEmpty) {
      return switch (mark.onEmpty) {
        OnEmpty.blank => ' ',
        OnEmpty.none => '',
        OnEmpty.fallback => mark.fallback,
      };
    }
    if (_plain(value) || _fits(mark, value)) {
      return value;
    }
    return mark.fallback;
  }

  /// The straight line of the border [type] (the theme's [Glyphs.lines]
  /// when null) as text across, or down for [down], for a dash in a row (a
  /// title on a box's edge, a stepper's line): [line] as a string.
  String dash(BorderType? type, {bool down = false, Glyphs? glyphs}) =>
      String.fromCharCode(line(type, vertical: down, glyphs: glyphs));

  /// The code point of the straight line of the border [type] (the theme's
  /// [Glyphs.lines] when null) for one cell: the line of [Glyphs.borderOf],
  /// so the ASCII theme's lines win over any type, and ASCII's `-` or `|`
  /// where the terminal does not draw it one column wide.
  int line(BorderType? type, {bool vertical = false, Glyphs? glyphs}) {
    final border = _of(glyphs).borderOf(type);
    final cp = border.glyph(
      up: vertical,
      down: vertical,
      left: !vertical,
      right: !vertical,
    );
    if (cp == 0x20 || border == BorderType.ascii || _cache.strict(cp)) {
      return cp;
    }
    return BorderType.ascii.glyph(
      up: vertical,
      down: vertical,
      left: !vertical,
      right: !vertical,
    );
  }

  /// [cp], a glyph of a widget's own that no theme field holds (an eighth
  /// block, a corner), where the terminal draws it one column wide; else
  /// [instead].
  int fixed(int cp, int instead) => _cache.strict(cp) ? cp : instead;

  /// [type], or [BorderType.ascii] where a piece of it is not one column
  /// as [segmenter] measures: the type a box, a rule or a gauge is to be
  /// drawn in. Measured once for each type and segmenter.
  static BorderType border(TextSegmenter segmenter, BorderType type) {
    final cache = _cacheOf(segmenter)..refresh();
    final fits = cache.borders[type] ??= allOneColumn(segmenter, [
      for (var arms = 1; arms < 16; arms++)
        type.glyph(
          up: arms & 1 != 0,
          right: arms & 2 != 0,
          down: arms & 4 != 0,
          left: arms & 8 != 0,
        ),
    ]);
    return fits ? type : BorderType.ascii;
  }

  /// Whether each of [codePoints], a fixed set of glyphs (the eighths of a
  /// bar, braille, a font's blocks), takes one column of a canvas
  /// [segmenter] measures, whatever its neighbours, and does so on every
  /// terminal.
  static bool allOneColumn(TextSegmenter segmenter, Iterable<int> codePoints) {
    final cache = _cacheOf(segmenter);
    for (final cp in codePoints) {
      if (!cache.strict(cp)) {
        return false;
      }
    }
    return true;
  }

  /// [Glyphs.shades] as a ramp of two steps or more, the blank first: as
  /// given when it has two or more, a blank before the one it has, or the
  /// ASCII ramp of [Glyphs.ascii] when it has none, so that a theme's
  /// short list draws rather than throws.
  static List<String> ramp(Glyphs glyphs) {
    final shades = glyphs.shades;
    return shades.length >= 2
        ? shades
        : shades.length == 1
        ? [' ', shades[0]]
        : Glyphs.ascii.shades;
  }

  bool _fits(Mark mark, String glyph) {
    final cache = _cache..refresh();
    final seen = cache.verdicts[mark];
    if (seen != null) {
      if (identical(seen.glyph, glyph) || seen.glyph == glyph) {
        if (!seen.fits) {
          _warnOnce(mark, glyph, seen.told);
        }
        return seen.fits;
      }
      if (identical(seen.other, glyph) || seen.other == glyph) {
        if (!seen.otherFits) {
          _warnOnce(mark, glyph, seen.otherTold);
        }
        return seen.otherFits;
      }
    }
    final width = _cache.segmenter.width(glyph);
    final fits = width == 1 && glyph.runes.length == 1;
    final told = _Told();
    if (!fits) {
      _warnOnce(mark, glyph, told);
    }
    if (seen == null) {
      cache.verdicts[mark] = _Verdict(glyph, fits, told);
    } else {
      // two kept: the sets of two subtrees (Glyphs.ascii under a
      // Glyphs.unicode app), asked in turn, measure once each
      seen
        ..other = seen.glyph
        ..otherFits = seen.fits
        ..otherTold = seen.told
        ..glyph = glyph
        ..fits = fits
        ..told = told;
    }
    return fits;
  }

  // the warning that [glyph], of [mark], does not fit, once for each
  // pipeline that meets it: the verdict is a segmenter's, which pipelines
  // share, and [told] the ones it has warned, so a frame asking again
  // warns no more and allocates nothing
  void _warnOnce(Mark mark, String glyph, _Told told) {
    final owner = _owner;
    if (owner == null) {
      if (told.none) {
        return;
      }
      told.none = true;
    } else {
      if (told.owners[owner] != null) {
        return;
      }
      told.owners[owner] = true;
    }
    final width = _cache.segmenter.width(glyph);
    final runes = glyph.runes.length;
    final fallback = mark.fallback;
    final instead = fallback.isEmpty ? 'no mark' : "Glyphs.ascii's '$fallback'";
    if (width == 2 && runes == 1 && _isPreset(glyph)) {
      // the preset's own mark, not the app's: the terminal is the cause,
      // told once and not for each field
      _warn(
        'ambiguous',
        '',
        'This terminal draws East Asian ambiguous characters two cells '
            'wide, so the marks of Glyphs.unicode that are such are drawn as '
            "Glyphs.ascii's. Glyphs.ascii as the theme's set, or marks that "
            'are not ambiguous, make that the app choice.',
      );
      return;
    }
    final what = width == 1
        ? 'a cluster of $runes code points, not one'
        : '$width cells wide, not 1';
    _warn(
      mark.name,
      glyph,
      "Glyphs.${mark.name} '$glyph' is $what; $instead is drawn in its place.",
    );
  }

  void _warn(String field, String glyph, String message) {
    final owner = _owner;
    if (owner != null && !(_warned[owner] ??= {}).add('$field\u0000$glyph')) {
      return;
    }
    final route = owner?.onLog;
    if (route == null) {
      log(message, level: LogLevel.warning);
    } else {
      route(LogRecord(DateTime.now(), LogLevel.warning, message));
    }
  }
}

// a printable ASCII character: one cell, one code point, no measuring
bool _plain(String glyph) {
  if (glyph.length != 1) {
    return false;
  }
  final c = glyph.codeUnitAt(0);
  return c >= 0x20 && c < 0x7f;
}

// the marks of Glyphs.unicode that are one code point each, which a
// terminal can count two cells wide
final Set<String> _presetMarks = {
  for (final field in _Field.values)
    if (field.of(Glyphs.unicode).runes.length == 1) field.of(Glyphs.unicode),
};

bool _isPreset(String glyph) => _presetMarks.contains(glyph);

// the (field, glyph) pairs each pipeline has warned of
final _warned = Expando<Set<String>>('glyph warnings');

// the verdicts of one segmenter, dropped when its settings change
final _caches = Expando<_Cache>('mark verdicts');

_Cache _cacheOf(TextSegmenter segmenter) =>
    _caches[segmenter] ??= _Cache(segmenter);

final class _Verdict {
  _Verdict(this.glyph, this.fits, this.told);

  // the glyph asked last and the one before, with whether each fits and
  // the pipelines warned that it does not
  String glyph;
  bool fits;
  _Told told;
  String? other;
  var otherFits = false;
  var otherTold = _Told();
}

// the pipelines a verdict has warned: weakly, as pipelines come and go
// while the segmenter they share stays; [none] for the asking of no
// pipeline
final class _Told {
  final owners = Expando<bool>('told of a glyph');
  var none = false;
}

final _scan = ClusterScan();

// how many resolvers of different glyph sets or pipelines a segmenter keeps
const _kept = 4;

final class _Cache {
  _Cache(this.segmenter);

  final TextSegmenter segmenter;
  final verdicts = <Mark, _Verdict>{};
  final _stricts = <int, bool>{};
  final borders = <BorderType, bool>{};
  var _mode = -1;
  var _ambiguous = -1;

  // the resolvers of the last glyph sets, a ring so that a theme that
  // makes a set each frame cannot grow it; those of render objects (no
  // set of their own, one a pipeline) in a ring apart, so that neither
  // pushes the other's out
  final _resolvers = List<ThemeMarks?>.filled(_kept, null);
  var _next = 0;
  final _objects = List<ThemeMarks?>.filled(2, null);
  var _nextObject = 0;

  ThemeMarks resolver(PipelineOwner? owner, Glyphs? glyphs) {
    final ring = glyphs == null ? _objects : _resolvers;
    for (final r in ring) {
      if (r != null && identical(r._glyphs, glyphs) && r._owner == owner) {
        return r;
      }
    }
    final made = ThemeMarks._(this, owner, glyphs);
    if (glyphs == null) {
      ring[_nextObject] = made;
      _nextObject = (_nextObject + 1) % ring.length;
    } else {
      ring[_next] = made;
      _next = (_next + 1) % ring.length;
    }
    return made;
  }

  // forgets what was measured when the segmenter's settings changed
  void refresh() {
    if (segmenter.mode.index == _mode &&
        segmenter.ambiguousWidth == _ambiguous) {
      return;
    }
    _mode = segmenter.mode.index;
    _ambiguous = segmenter.ambiguousWidth;
    verdicts.clear();
    _stricts.clear();
    borders.clear();
  }

  bool strict(int cp) {
    refresh();
    return _stricts[cp] ??= _strictOne(cp);
  }

  bool _strictOne(int cp) {
    // the glyph twice: two clusters of a column each
    final two = String.fromCharCodes([cp, cp]);
    segmenter.scan(two, 0, _scan);
    return _scan.end * 2 == two.length &&
        _scan.width == 1 &&
        !_scan.joinsNext &&
        !_scan.uncertain;
  }
}
