/// The mouse in a text field: [FieldMouse], what a `TextField` and a
/// `TextArea` put around their text to place the caret and select with
/// the left button. Not exported.
library;

import 'dart:async';

import 'package:twk_core/twk_core.dart' show HitTestBehavior;

import '../focus/focus_tree.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/mouse.dart';
import '../gestures/selection.dart' show takePressFromSelectionArea;
import 'text_buffer.dart';
import 'text_editing.dart';

/// Places the caret of [controller] where the left button is pressed over
/// [child], the text of a field drawn from its top left, and focuses
/// [focusNode]; a drag selects from there to the mouse, a double press
/// selects the word there ([wordAt]), a triple press the line ([lineAt]),
/// and a drag after either goes on by words or by lines. A press is the
/// next of a double or triple one when it comes in the same cell within
/// [multiClickInterval] of the release before it; with Shift, a single one
/// selects from the selection's base to there.
///
/// [offsetAt] maps a cell of [child] to the offset the caret goes to
/// there: the character drawn in it, a wide one's second cell too, the
/// end of the text past it, through the field's scroll; null while the
/// field is not laid out.
///
/// The press is the field's: a `SelectionArea` around it clears its
/// selection and selects nothing by it, and its drags go to no
/// `GestureDetector` around it that drags. A field whose node takes no
/// focus, when it is built, takes no press, and has the terminal report
/// none.
final class FieldMouse extends StatefulWidget {
  /// The mouse over [child], a field of [controller] whose node is
  /// [focusNode].
  const FieldMouse({
    required this.controller,
    required this.focusNode,
    required this.offsetAt,
    required this.wordAt,
    required this.lineAt,
    required this.child,
    this.multiClickInterval = const Duration(milliseconds: 300),
    super.key,
  });

  /// What the presses place the caret of and select in.
  final TextEditingController controller;

  /// What a press focuses; a node that takes no focus takes no press.
  final FocusNode focusNode;

  /// The offset of a cell of [child], from its top left; null where it
  /// is not laid out.
  final int? Function(int x, int y) offsetAt;

  /// The word of a text a double press at an offset selects.
  final TextRange Function(TextBuffer text, int offset) wordAt;

  /// The line of a text a triple press at an offset selects.
  final TextRange Function(TextBuffer text, int offset) lineAt;

  /// How long after a release a press in the same cell is the next of a
  /// double or triple one.
  final Duration multiClickInterval;

  /// The text of the field, drawn from its top left.
  final Widget child;

  @override
  State<FieldMouse> createState() => _FieldMouseState();
}

final class _FieldMouseState extends State<FieldMouse> {
  // the presses of a double or triple one so far, the cell of the screen
  // the last was in, and a timer from its release while the next can be
  // one more
  var _clicks = 0;
  (int, int)? _clickedAt;
  Timer? _interval;

  // what the press under way selected first, which a drag after it keeps
  // selected; null while no press of this field is under way
  TextRange? _anchor;

  @override
  void dispose() {
    _interval?.cancel();
    super.dispose();
  }

  /// The range a press at [offset] selects by [_clicks].
  TextRange _unitAt(int offset) {
    final text = textBufferOf(widget.controller.value);
    final o = offset > text.length ? text.length : offset;
    return switch (_clicks) {
      2 => widget.wordAt(text, o),
      3 => widget.lineAt(text, o),
      _ => TextRange.collapsed(o),
    };
  }

  void _down(PointerEvent event) {
    final node = widget.focusNode;
    if (event.button != 0 || !node.canRequestFocus) {
      _anchor = null;
      return;
    }
    final offset = widget.offsetAt(event.x, event.y);
    if (offset == null) {
      _anchor = null;
      return;
    }
    if (MouseTracker.of(context) case final tracker?) {
      takePressFromSelectionArea(tracker);
    }
    node.requestFocus();
    final at = (event.screenX, event.screenY);
    final again = (_interval?.isActive ?? false) && _clickedAt == at;
    _interval?.cancel();
    _clicks = again ? _clicks % 3 + 1 : 1;
    _clickedAt = at;
    final c = widget.controller;
    if (_clicks == 1 && event.shift) {
      final base = c.selection.baseOffset;
      _anchor = TextRange.collapsed(base);
      c.selection = TextSelection(baseOffset: base, extentOffset: offset);
      return;
    }
    final unit = _anchor = _unitAt(offset);
    c.selection = TextSelection(
      baseOffset: unit.start,
      extentOffset: unit.end,
    );
  }

  void _drag(DragDetails details) {
    final anchor = _anchor;
    if (anchor == null) {
      return;
    }
    final offset = widget.offsetAt(details.x, details.y);
    if (offset == null) {
      return;
    }
    final unit = _unitAt(offset);
    widget.controller.selection = unit.start < anchor.start
        ? TextSelection(baseOffset: anchor.end, extentOffset: unit.start)
        : TextSelection(
            baseOffset: anchor.start,
            extentOffset: unit.end > anchor.end ? unit.end : anchor.end,
          );
  }

  void _up(PointerEvent event) {
    if (event.button != 0 || _anchor == null) {
      return;
    }
    _interval = Timer(widget.multiClickInterval, () {});
  }

  @override
  Widget build(BuildContext context) {
    // a field that takes no focus has the terminal report no mouse
    final listens = widget.focusNode.canRequestFocus;
    return Listener(
      onDown: listens ? _down : null,
      onUp: listens ? _up : null,
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onDragUpdate: listens ? _drag : null,
        behavior: HitTestBehavior.opaque,
        child: widget.child,
      ),
    );
  }
}

/// The word of [text] the character at [offset] is in, or the run of
/// blanks it is in, within [from] to [to] (a line): as the editing keys
/// find words ([TextBoundaries]). At [to], the character before it; the
/// empty range at [offset] for an empty part.
TextRange wordIn(TextBuffer text, int offset, int from, int to) {
  if (from >= to) {
    return TextRange.collapsed(offset);
  }
  final c = offset >= to
      ? text.characterStartBefore(to, from: from, to: to)
      : (offset < from ? from : offset);
  final ce = text.characterEndAfter(c, from: from, to: to);
  if (!_blank(text, c, ce)) {
    return TextRange(
      start: text.wordStartBefore(ce, from: from, to: to),
      end: text.wordEndAfter(c, from: from, to: to),
    );
  }
  var s = c;
  while (s > from) {
    final before = text.characterStartBefore(s, from: from, to: to);
    if (!_blank(text, before, s)) {
      break;
    }
    s = before;
  }
  var e = ce;
  while (e < to) {
    final after = text.characterEndAfter(e, from: from, to: to);
    if (!_blank(text, e, after)) {
      break;
    }
    e = after;
  }
  return TextRange(start: s, end: e);
}

/// Whether the character of [text] from [start] to [end] is a blank.
bool _blank(TextBuffer text, int start, int end) =>
    end > start && TextStops.blankAt(text.substring(start, end), 0);
