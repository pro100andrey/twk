/// Text being edited: the [TextEditingController] a field edits, the
/// [TextEditingValue] it holds (the text, its [TextSelection] and the
/// composing [TextRange]), and [TextBoundaries], where a caret stops in a
/// text.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show ClusterScan, TextSegmenter;

import '../foundation/change_notifier.dart';
import 'text_buffer.dart';

/// The part of a text from [start] to [end], [end] not included: offsets
/// in its UTF-16 code units, as `String.substring` takes them. [empty]
/// stands for none.
///
/// Two ranges are equal when their ends are.
///
/// ```dart
/// const word = TextRange(start: 6, end: 11);
/// final hello = word.textInside('Hello world!'); // 'world'
/// ```
@immutable
final class TextRange {
  /// The range from [start] to [end].
  const TextRange({required this.start, required this.end});

  /// The empty range at [offset].
  const TextRange.collapsed(int offset) : start = offset, end = offset;

  /// No range.
  static const empty = TextRange(start: -1, end: -1);

  /// The offset of its first code unit; -1 for [empty].
  final int start;

  /// The offset after its last code unit; -1 for [empty].
  final int end;

  /// Whether this is a range, not [empty].
  bool get isValid => start >= 0 && end >= start;

  /// Whether the range is empty.
  bool get isCollapsed => start == end;

  /// The part of [text] in the range.
  String textInside(String text) => text.substring(start, end);

  @override
  bool operator ==(Object other) =>
      other is TextRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextRange($start, $end)';
}

/// What is selected of a text: the offsets from [baseOffset], where the
/// selection was started, to [extentOffset], where the caret is, which
/// moves as the selection grows or shrinks; empty ([isCollapsed]) when
/// both are the caret's. Offsets are in UTF-16 code units, as
/// [TextRange]'s.
///
/// The word `world` selected backwards, the caret before it:
///
/// ```dart
/// const selection = TextSelection(baseOffset: 11, extentOffset: 6);
/// ```
@immutable
final class TextSelection {
  /// The selection from [baseOffset] to the caret at [extentOffset].
  const TextSelection({required this.baseOffset, required this.extentOffset});

  /// The caret at [offset], nothing selected.
  const TextSelection.collapsed({required int offset})
    : baseOffset = offset,
      extentOffset = offset;

  /// Where the selection was started.
  final int baseOffset;

  /// The caret.
  final int extentOffset;

  /// The smaller of the two offsets.
  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;

  /// The larger of the two offsets.
  int get end => baseOffset < extentOffset ? extentOffset : baseOffset;

  /// Whether nothing is selected.
  bool get isCollapsed => baseOffset == extentOffset;

  /// What is selected, from [start] to [end].
  TextRange get range => TextRange(start: start, end: end);

  /// The selection from the same base to [offset].
  TextSelection extendTo(int offset) =>
      TextSelection(baseOffset: baseOffset, extentOffset: offset);

  @override
  bool operator ==(Object other) =>
      other is TextSelection &&
      other.baseOffset == baseOffset &&
      other.extentOffset == extentOffset;

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);

  @override
  String toString() => baseOffset == extentOffset
      ? 'TextSelection.collapsed($extentOffset)'
      : 'TextSelection($baseOffset, $extentOffset)';
}

/// A text as it is edited: the [text], its [selection], and the part of
/// it being composed ([composing]; [TextRange.empty] for none), which a
/// field shows underlined.
///
/// A controller's value keeps its text in pieces, which an edit shares
/// with the value before it: its [text] is put together from them the
/// first time it is asked for, which for a large text costs a copy of it.
///
/// ```dart
/// const value = TextEditingValue(
///   text: 'Hello world',
///   selection: TextSelection.collapsed(offset: 5),
/// );
/// final controller = TextEditingController.fromValue(value);
/// ```
@immutable
final class TextEditingValue {
  /// [text], with the caret at its start unless [selection] says
  /// otherwise, nothing composed unless [composing] is.
  const TextEditingValue({
    String text = '',
    this.selection = const TextSelection.collapsed(offset: 0),
    this.composing = TextRange.empty,
    // ignore: prefer_initializing_formals, a String kept as an Object
  }) : _text = text;

  const TextEditingValue._(this._text, this.selection, this.composing);

  /// No text, the caret at its start.
  static const empty = TextEditingValue();

  // the text: a String, or the TextBuffer a controller keeps it in
  final Object _text;

  /// What is selected, and where the caret is.
  final TextSelection selection;

  /// The part being composed, by an input method; [TextRange.empty] for
  /// none.
  final TextRange composing;

  /// The text.
  String get text {
    final t = _text;
    return t is TextBuffer ? t.text : t as String;
  }

  /// The text in pieces.
  TextBuffer get _buffer {
    final t = _text;
    return t is TextBuffer ? t : TextBuffer(t as String);
  }

  /// How many code units the text has.
  int get _length {
    final t = _text;
    return t is TextBuffer ? t.length : (t as String).length;
  }

  /// This value with [text], [selection] or [composing] in place of its
  /// own, for each that is not null.
  TextEditingValue copyWith({
    String? text,
    TextSelection? selection,
    TextRange? composing,
  }) => TextEditingValue._(
    text ?? _text,
    selection ?? this.selection,
    composing ?? this.composing,
  );

  @override
  bool operator ==(Object other) =>
      other is TextEditingValue &&
      other.selection == selection &&
      other.composing == composing &&
      _sameText(other._text, _text);

  static bool _sameText(Object a, Object b) {
    if (identical(a, b)) {
      return true;
    }
    if (a is TextBuffer) {
      return a.sameText(b);
    }
    return b is TextBuffer ? b.sameText(a) : a == b;
  }

  @override
  int get hashCode => Object.hash(_length, selection, composing);

  @override
  String toString() =>
      'TextEditingValue("$text", $selection'
      '${composing.isValid ? ', composing $composing' : ''})';
}

/// The text of [value] in the pieces a [TextEditingController] keeps it
/// in: what the editing widgets read, which does not put the text
/// together.
TextBuffer textBufferOf(TextEditingValue value) => value._buffer;

/// The [TextEditingValue] a field edits, which notifies its listeners of
/// each change. What a field's keys do are its methods, for an app that
/// binds keys of its own: [insert] types, [moveCaret] moves the caret or
/// selects, [deleteTo] deletes, the offsets from [TextBoundaries]; [undo]
/// and [redo] take changes back and make them again.
///
/// A value set is kept within its text: offsets past its end are moved to
/// it, a composing range that does not fit is dropped. An edit ([replace],
/// [insert], [deleteTo]) ends the composing.
///
/// The text is kept in pieces, so that an edit costs the size of the edit,
/// not of the text: a keystroke in a megabyte of text is as quick as in a
/// line. Asked for as a String ([text], [TextEditingValue.text]), the text
/// is put together once after each change, which for a large text costs a
/// copy of it: a listener that does not need the text does not ask for it.
///
/// Each change of the text is a step [undo] takes back, the last
/// [undoLimit] kept: what [replace] puts in and takes out, and a text set
/// ([value], [text]) as the part it changes; not a [reset], which starts
/// the history afresh. Edits of a character each,
/// one after the other, make one step a word at a time: typing a word and
/// the blanks after it, Backspace over a word and the blanks before it,
/// Delete over a word and the blanks after it. A step ends where the caret
/// is moved, and at an [undo] or a [redo]. An edit drops the steps undone.
///
/// A field whose text the app reads as it changes, and a key that clears
/// it:
///
/// ```dart
/// final controller = TextEditingController(text: 'draft');
/// controller.addListener(() => print('now: ${controller.text}'));
/// final field = KeyBindings(
///   {'ctrl+l': controller.clear},
///   child: TextField(controller: controller, autofocus: true),
/// );
/// ```
final class TextEditingController extends ValueNotifier<TextEditingValue> {
  /// [text] with the caret at its end.
  TextEditingController({String text = ''})
    : super(
        TextEditingValue._(
          TextBuffer(text),
          TextSelection.collapsed(offset: text.length),
          TextRange.empty,
        ),
      );

  /// [value], kept within its text.
  TextEditingController.fromValue(TextEditingValue value)
    : super(_within(value, TextBuffer.empty));

  /// The most steps [undo] takes back.
  static const undoLimit = 100;

  // the steps undo takes back, the last last, and those redo makes again
  final _done = <_Step>[];
  final _undone = <_Step>[];

  // whether an edit of a character may join the last step
  var _open = false;

  @override
  set value(TextEditingValue newValue) {
    final old = super.value;
    var v = _within(newValue, _buffer);
    if (identical(v._text, old._text)) {
      if (v.selection != old.selection) {
        _open = false;
      }
    } else {
      final (head, tail) = _changed(old.text, v.text);
      // the composing as it was, kept by a value made from the old one
      // (copyWith), over text changed outside it: its offsets are the old
      // text's, and the composing has ended
      final c = v.composing;
      if (c.isValid &&
          c == old.composing &&
          (head < c.start || old.text.length - tail > c.end)) {
        v = TextEditingValue._(v._text, v.selection, TextRange.empty);
      }
      _recordChange(old, v, head, tail);
    }
    super.value = v;
  }

  TextBuffer get _buffer => super.value._buffer;

  /// Whether there is a step to take back.
  bool get canUndo => _done.isNotEmpty;

  /// Whether there is a step undone to make again.
  bool get canRedo => _undone.isNotEmpty;

  /// Takes the last step back: its text as it was, and the selection as it
  /// was before it. Nothing without one ([canUndo]).
  void undo() {
    if (_done.isEmpty) {
      return;
    }
    final s = _done.removeLast();
    _undone.add(s);
    _apply(s.start, s.inserted.length, s.removed, s.before);
  }

  /// Makes the last step undone again, the selection as it was after it.
  /// Nothing without one ([canRedo]).
  void redo() {
    if (_undone.isEmpty) {
      return;
    }
    final s = _undone.removeLast();
    _done.add(s);
    _apply(s.start, s.removed.length, s.inserted, s.after);
  }

  void _apply(int start, int length, String text, TextSelection selection) {
    _open = false;
    super.value = _within(
      TextEditingValue._(
        _buffer.replace(start, start + length, text),
        selection,
        TextRange.empty,
      ),
      _buffer,
    );
  }

  /// How many code units [a] and [b] start with alike and, after those,
  /// end with alike, whole code points: a surrogate pair is not split.
  static (int, int) _changed(String a, String b) {
    final shorter = a.length < b.length ? a.length : b.length;
    var head = 0;
    while (head < shorter && a.codeUnitAt(head) == b.codeUnitAt(head)) {
      head++;
    }
    if (head > 0 && _isHigh(a.codeUnitAt(head - 1))) {
      head--;
    }
    var tail = 0;
    while (tail < shorter - head &&
        a.codeUnitAt(a.length - 1 - tail) ==
            b.codeUnitAt(b.length - 1 - tail)) {
      tail++;
    }
    if (tail > 0 && _isLow(a.codeUnitAt(a.length - tail))) {
      tail--;
    }
    return (head, tail);
  }

  static bool _isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  /// Records the change from [old] to [now] as a step of its own: the part
  /// of the text between the [head] and [tail] code units they start and
  /// end with alike ([_changed]).
  void _recordChange(
    TextEditingValue old,
    TextEditingValue now,
    int head,
    int tail,
  ) {
    final a = old.text;
    final b = now.text;
    _open = false;
    _record(
      head,
      a.substring(head, a.length - tail),
      b.substring(head, b.length - tail),
      old.selection,
      now.selection,
    );
  }

  /// Records [removed] taken out at [start] and [inserted] put in its
  /// place, joined to the last step when it goes on with it.
  void _record(
    int start,
    String removed,
    String inserted,
    TextSelection before,
    TextSelection after,
  ) {
    _undone.clear();
    final last = _done.isEmpty ? null : _done.last;
    final single = _isCharacter(inserted.isEmpty ? removed : inserted);
    if (_open &&
        last != null &&
        single &&
        last.joins(start, removed, inserted)) {
      last.join(start, removed, inserted, after);
    } else {
      if (_done.length == undoLimit) {
        _done.removeAt(0);
      }
      _done.add(_Step(start, removed, inserted, before, after));
    }
    _open = single;
  }

  static final _segmenter = TextSegmenter();
  static final _scan = ClusterScan();

  /// Whether [text] is one character.
  static bool _isCharacter(String text) {
    if (text.isEmpty) {
      return false;
    }
    _segmenter.scan(text, 0, _scan);
    return _scan.end == text.length;
  }

  /// The text, put together from its pieces the first time it is asked
  /// for after a change. Set, the caret goes to its end and the composing
  /// ends.
  String get text => value.text;

  set text(String text) => value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  /// What is selected, the caret at its [TextSelection.extentOffset].
  TextSelection get selection => value.selection;

  set selection(TextSelection selection) =>
      value = value.copyWith(selection: selection);

  /// The part of the text being composed; [TextRange.empty] for none.
  TextRange get composing => value.composing;

  set composing(TextRange composing) =>
      value = value.copyWith(composing: composing);

  /// Empties the text.
  void clear() => text = '';

  /// Puts [text] in, the caret at its end and the composing ended, and
  /// starts the history afresh: the text is no step to [undo], and the
  /// steps before it, those undone too, are gone. For a text the app
  /// puts in rather than one typed, such as a path a picker goes to.
  /// Listeners are told when the value changes or a step is gone.
  void reset([String text = '']) {
    final had = _done.isNotEmpty || _undone.isNotEmpty;
    _done.clear();
    _undone.clear();
    _open = false;
    final v = _within(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
      _buffer,
    );
    if (v == super.value) {
      if (had) {
        notifyListeners();
      }
    } else {
      super.value = v;
    }
  }

  /// Puts [text] in place of the part from [start] to [end], the caret
  /// after it.
  void replace(int start, int end, String text) {
    final buffer = _buffer;
    RangeError.checkValidRange(start, end, buffer.length);
    final removed = buffer.substring(start, end);
    final selection = TextSelection.collapsed(offset: start + text.length);
    if (removed == text) {
      value = TextEditingValue._(buffer, selection, TextRange.empty);
      return;
    }
    final now = TextEditingValue._(
      buffer.replace(start, end, text),
      selection,
      TextRange.empty,
    );
    _record(start, removed, text, super.value.selection, selection);
    super.value = now;
  }

  /// Puts [text] in place of the selection, the caret after it.
  void insert(String text) {
    final s = selection;
    replace(s.start, s.end, text);
  }

  /// Moves the caret to [offset]: the selection ends, or with [extend] it
  /// grows or shrinks from its base to there.
  void moveCaret(int offset, {bool extend = false}) => selection = extend
      ? selection.extendTo(offset)
      : TextSelection.collapsed(offset: offset);

  /// Deletes what is selected, if anything; else the text between the
  /// caret and [offset].
  void deleteTo(int offset) {
    final s = selection;
    if (!s.isCollapsed) {
      replace(s.start, s.end, '');
    } else if (offset != s.extentOffset) {
      final o = offset.clamp(0, _buffer.length);
      final caret = s.extentOffset;
      replace(o < caret ? o : caret, o < caret ? caret : o, '');
    }
  }

  /// Selects the whole text, the caret at its end.
  void selectAll() => selection = TextSelection(
    baseOffset: 0,
    extentOffset: _buffer.length,
  );

  /// [value] with its text in pieces, [current] where it is the same text,
  /// and kept within its text.
  static TextEditingValue _within(TextEditingValue value, TextBuffer current) {
    final t = value._text;
    final TextBuffer text;
    if (current.sameText(t)) {
      text = current;
    } else {
      text = t is TextBuffer ? t : TextBuffer(t as String);
    }
    final length = text.length;
    final s = value.selection;
    final c = value.composing;
    final base = s.baseOffset.clamp(0, length);
    final extent = s.extentOffset.clamp(0, length);
    final composing = c.isValid && c.end <= length ? c : TextRange.empty;
    return identical(text, t) &&
            base == s.baseOffset &&
            extent == s.extentOffset &&
            identical(composing, c)
        ? value
        : TextEditingValue._(
            text,
            TextSelection(baseOffset: base, extentOffset: extent),
            composing,
          );
  }
}

/// A change [TextEditingController.undo] takes back: [removed] taken out
/// at [start] and [inserted] put in its place, the selection [before] and
/// [after] it.
final class _Step {
  _Step(this.start, this.removed, this.inserted, this.before, this.after);

  int start;
  String removed;
  String inserted;
  final TextSelection before;
  TextSelection after;

  /// Whether the edit of a character, [removed] taken out at [start] and
  /// [inserted] put in, goes on with this step: typing after what it typed,
  /// Backspace before what it deleted, Delete where it deleted; not into
  /// the next word.
  bool joins(int start, String removed, String inserted) {
    final typed = this.inserted;
    if (inserted.isNotEmpty) {
      return removed.isEmpty &&
          typed.isNotEmpty &&
          start == this.start + typed.length &&
          !(_blankAt(typed, typed.length - 1) && !_blankAt(inserted, 0));
    }
    final deleted = this.removed;
    if (typed.isNotEmpty) {
      return false;
    }
    if (start + removed.length == this.start) {
      return !(_blankAt(deleted, 0) && !_blankAt(removed, 0));
    }
    return start == this.start &&
        !(_blankAt(deleted, deleted.length - 1) && !_blankAt(removed, 0));
  }

  /// Takes the edit [joins] tells goes on with this step into it.
  void join(int start, String removed, String inserted, TextSelection after) {
    if (inserted.isNotEmpty) {
      this.inserted += inserted;
    } else if (start < this.start) {
      this.start = start;
      this.removed = removed + this.removed;
    } else {
      this.removed += removed;
    }
    this.after = after;
  }

  static bool _blankAt(String text, int offset) =>
      TextStops.blankAt(text, offset);
}

/// Where a caret stops in a text: between its characters, the extended
/// grapheme clusters of Unicode (UAX #29: a letter with its accents, an
/// emoji sequence, a flag), and at the ends of its words.
///
/// A character is a blank (white space), a word character (a letter, a
/// digit, a mark, a connector such as `_`, an emoji, a flag) or neither
/// (punctuation, symbols). A word is a run of word characters, or a run
/// of the others; with `blankDelimited`, a run of characters that are not
/// blanks. Offsets are in UTF-16 code units; one inside a character
/// counts as the character's start.
///
/// The ends of a character or a word are found from the characters around
/// the offset, as far as the word goes; counting the characters goes
/// through the text.
extension TextBoundaries on String {
  /// How many characters the text has.
  int get characterCount => _bounds(this).length - 1;

  /// How many characters the text has before [offset].
  int characterIndexAt(int offset) => _indexOf(_bounds(this), offset);

  /// The offset the character [index] starts at; the text's length for
  /// the index past the last.
  int characterOffset(int index) {
    final b = _bounds(this);
    RangeError.checkValueInInterval(index, 0, b.length - 1, 'index');
    return b[index];
  }

  /// The start of the character before [offset]; 0 at the start.
  int characterStartBefore(int offset) =>
      _stops.characterStartBefore(substring, 0, length, offset);

  /// The end of the character at [offset]; the text's length at its end.
  int characterEndAfter(int offset) =>
      _stops.characterEndAfter(substring, 0, length, offset);

  /// The start of the word before [offset], past the blanks before it.
  int wordStartBefore(int offset, {bool blankDelimited = false}) =>
      _stops.wordStartBefore(
        substring,
        0,
        length,
        offset,
        blankDelimited: blankDelimited,
      );

  /// The end of the word after [offset], past the blanks before it.
  int wordEndAfter(int offset, {bool blankDelimited = false}) =>
      _stops.wordEndAfter(
        substring,
        0,
        length,
        offset,
        blankDelimited: blankDelimited,
      );

  /// The index of the last bound in [b] at or before [offset].
  static int _indexOf(Int32List b, int offset) {
    var lo = 0;
    var hi = b.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (b[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  static final _stops = TextStops();

  // the text whose bounds were worked out last, and those
  static String? _boundsText;
  static var _boundsOf = Int32List(1);
  static final _segmenter = TextSegmenter();
  static final _scan = ClusterScan();

  /// The offsets the characters of [text] start at, and its length.
  static Int32List _bounds(String text) {
    if (identical(text, _boundsText)) {
      return _boundsOf;
    }
    final bounds = <int>[0];
    for (var i = 0; i < text.length; i = _scan.end) {
      _segmenter.scan(text, i, _scan);
      bounds.add(_scan.end);
    }
    _boundsText = text;
    return _boundsOf = Int32List.fromList(bounds);
  }
}
