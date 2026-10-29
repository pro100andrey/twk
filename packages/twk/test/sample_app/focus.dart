part of '../sample_app.dart';

/// Bumps the count.
final class _Bump extends Intent {
  const _Bump();
}

extension on _SampleAppState {
  /// [child] in a focus scope, focused at once: Shift+Up and Shift+Down
  /// bump the count, as do `g g`; Ctrl+R sets it to 0, as do `,` and `0`
  /// (the leader, then 0). A FocusBuilder around the scope sees the focus
  /// in it; an ExcludeFocus that does not exclude lets it in, and the
  /// app inside is the focused widget's active item, the hidden cursor on
  /// its first cell.
  Widget _focused(Widget child) => FocusBuilder(
    builder: (context, hasFocus, child) => child!,
    child: FocusScope(
      child: _keys(child),
    ),
  );

  /// [child] below the keys of [_focused].
  Widget _keys(Widget child) => Actions(
    {_Bump: CallbackAction<_Bump>(onInvoke: (_) => _bump())},
    child: Shortcuts(
      const {'shift+down': _Bump(), 'g g': _Bump()},
      unmatched: UnmatchedKeys.replay,
      child: LeaderKey(
        ',',
        child: KeyBindings(
          {'ctrl+r': _reset, 'leader 0': _reset},
          hints: const {'leader 0': 'reset'},
          child: Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: ExcludeFocus(
              excluding: false,
              child: ActiveItem(active: true, child: child),
            ),
          ),
        ),
      ),
    ),
  );

  void _reset() => _count.value = 0;

  /// None: the widgets of the topic wrap the app, in [_focused].
  List<Widget> _focus() => const [];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event case KeyEvent(code: KeyCode.up, modifiers: Mod.shift)) {
      _bump();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
