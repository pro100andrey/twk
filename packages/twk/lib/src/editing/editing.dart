/// Text editing: single-line text fields and multi-line text areas, what
/// is drawn around a field, suggestions for what to put in them, and the
/// terminal's cursor at a caret.
library;

export 'autocomplete.dart'
    hide autocompleteKeys, autocompleteShowing, autocompleteTook;
export 'caret.dart' show hideCaret, showCaret;
export 'input_decoration.dart' hide decoratedField;
export 'text_area.dart';
export 'text_editing.dart' hide textBufferOf;
export 'text_field.dart';
