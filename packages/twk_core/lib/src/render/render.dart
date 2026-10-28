/// A Flutter-style retained render tree on top of the core: [RenderObject]s
/// that a [PipelineOwner] lays out and paints onto a canvas, a frame at a
/// time, redoing only what was marked:
///
///  * layout: `BoxConstraints` down, sizes up (like Flutter);
///    `markNeedsLayout()` marks up to the nearest *relayout boundary* (an
///    object whose size can't change its parent's layout), and a frame lays
///    out only the marked boundaries' subtrees;
///  * paint: `markNeedsPaint()` marks the nearest *repaint boundary*; a frame
///    repaints only dirty boundaries (clipped to their bounds), and the
///    surface turns exactly those writes into damage for the presenter;
///  * intrinsic sizes: before laying a child out, a parent may ask how wide
///    or tall it would like to be (`getMaxIntrinsicWidth(height)` and the
///    like); text answers in the columns the canvas draws it in;
///  * flex: a row or a column lays its children out along one axis, the
///    flexible ones sharing the cells the others leave in whole cells;
///  * wrap: children one after another along an axis, a gap apart, in
///    runs that break where the next would not fit, the children of a run
///    and the runs placed by alignments in whole cells;
///  * stack: children on top of each other, placed by an alignment or
///    pinned to its edges and painted in order; a repaint boundary under
///    another child repaints without erasing it;
///  * effects: a child shown through a function over the cells of its
///    bounds, of what it painted and what was under it; a repaint boundary
///    that shows a new frame of the effect from what it kept, without
///    painting the child, which repaints normally underneath;
///  * grid: children in the cells of columns and rows that are fixed,
///    fractions of the cells left or as long as their content asks for,
///    spanning several, the cells shared out in whole cells;
///  * boxes with one child: padding around it, an alignment that places it
///    in whole cells, limits on its size, fractions of the room it gets
///    rounded to whole cells, the size it would like to be;
///  * layout callbacks: an object may change what is below it while it is
///    laid out (a widget layer builds its children there with the
///    constraints), and what changed is laid out in the same frame;
///  * borders: a box with a border of box drawing lines on any of its
///    sides, titles on its top and bottom edges and padding inside, and
///    dividers across;
///  * text: spans in their own pens broken into lines by word, by grapheme
///    or not at all, cut off with an ellipsis at the end, the start or the
///    middle, placed or justified across the width;
///  * scrolling: a list, or a window onto a child as long as it likes,
///    that scrolled shifts its rows on the surface and declares the
///    scroll, so the terminal scrolls in hardware and only the exposed rows
///    are painted;
///  * hit testing: the objects at a cell, found from the root down, each
///    child in its own coordinates and cut off at its parent's bounds as
///    paint cuts it, the one painted on top first; each object opaque,
///    translucent or deferring to its children; into a result reused
///    between events, so that a mouse move allocates nothing;
///  * errors: what a layout or a paint throws stays in the object that
///    threw it, which shows the message in white on red instead, and the
///    owner reports it;
///  * diagnostics: an object describes itself and those below it when
///    asked (`describe()`: properties, size, flags such as a repaint
///    boundary), as text with guides or as JSON; a frame never does;
///  * debug paints, per owner and off by default: each repaint tinted in
///    the next colour of a cycle, so that needless repaints show, and the
///    objects laid out since the last frame outlined.
///
/// A widget layer (build, state, keys) sits above it as Flutter's does,
/// `package:twk`: its elements create these render objects and set their
/// properties.
library;

import 'dart:typed_data';

import '../canvas.dart';
import '../fill.dart';
import '../log.dart';
import '../presenter.dart';
import '../style.dart';
import '../surface.dart';
import '../unicode/bidi.dart';
import '../unicode/bidi_data.g.dart' show bidiBrackets;
import '../unicode/unicode.dart';
import 'diagnostics.dart';

export 'diagnostics.dart';

part 'boxes.dart';
part 'debug_paint.dart';
part 'decoration.dart';
part 'effect.dart';
part 'error_box.dart';
part 'flex.dart';
part 'grid.dart';
part 'list.dart';
part 'log.dart';
part 'object.dart';
part 'pipeline.dart';
part 'stack.dart';
part 'text.dart';
part 'viewport.dart';
part 'wrap.dart';
