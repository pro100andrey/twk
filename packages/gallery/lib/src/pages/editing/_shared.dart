// What the pages of the group share.
part of 'editing.dart';

/// The options of a field's cursor: its shape, the terminal's own among
/// them, and whether it blinks.
const List<PageOption> _cursorOptions = [
  ChoiceOption(
    'cursor',
    'cursor',
    values: ['bar', 'block', 'underline', 'terminalDefault'],
    labels: ['bar', 'block', 'underline', 'terminal'],
  ),
  SwitchOption('blink', 'blinking', disabled: _terminalCursor),
];

/// Whether the cursor of [o] is the terminal's own, which blinks as the
/// terminal says.
bool _terminalCursor(Options o) =>
    o.choice<String>('cursor') == 'terminalDefault';

/// The cursor shape of [o].
CursorShape _shapeOf(Options o) {
  final shape = o.choice<String>('cursor');
  if (_terminalCursor(o) || !o.flag('blink')) {
    return CursorShape.values.byName(shape);
  }
  return CursorShape.values.byName(
    'blinking${shape[0].toUpperCase()}${shape.substring(1)}',
  );
}

/// The Code's `cursorShape:` line, [pad] columns in, where it is not the
/// default.
List<String> _shapeArg(Options o, String pad) => [
  if (_shapeOf(o) != CursorShape.bar)
    '${pad}cursorShape: .${_shapeOf(o).name},',
];

/// The Code of a Box whose border is primary while the focus is in
/// [child], a FocusBuilder's, [pad] columns in.
List<String> _focusBox(String pad, String child) => [
  '$pad// the border primary while the focus is in it',
  '${pad}child: FocusBuilder(',
  '$pad  builder: (context, hasFocus, $child) => Box(',
  '$pad    border: .all(',
  '$pad      type: .rounded,',
  '$pad      style: hasFocus ? theme.primary : theme.border,',
  '$pad    ),',
  '$pad    child: $child,',
  '$pad  ),',
];

/// [child] in a rounded box, its border primary while the focus is in it.
Widget _focusBoxed(Widget child) => FocusBuilder(
  builder: (context, hasFocus, child) {
    final theme = Theme.of(context);
    return Box(
      border: Border.all(
        type: BorderType.rounded,
        style: hasFocus ? theme.primary : theme.border,
      ),
      child: child,
    );
  },
  child: child,
);
