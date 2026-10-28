part of '../sample_app.dart';

extension on _SampleAppState {
  /// [child] taking the events nothing below took: `q` quits, the wheel up
  /// bumps the count.
  Widget _listening(Widget child) =>
      InputListener(onEvent: _onEvent, child: child);

  List<Widget> _binding() => [
    SizedBox(
      height: 1,
      child: TerminalProgress(
        state: ProgressState.paused,
        value: .5,
        child: WindowTitle(
          title: 'sample app',
          child: Static<String>(
            items: const ['finished'],
            builder: (_, item) => Text(item),
          ),
        ),
      ),
    ),
    const SizedBox(height: 1, child: ErrorWidget('an error shown in place')),
  ];

  bool _onEvent(InputEvent event) => switch (event) {
    KeyEvent(code: KeyCode.char, char: 'q', kind: KeyKind.press) => _quit(),
    MouseEvent(kind: MouseKind.wheelUp) => _bump(),
    ColorSchemeReport(brightness: Brightness.light) => false,
    KeyEvent() ||
    MouseEvent() ||
    PasteEvent() ||
    FocusEvent() ||
    ResizeEvent() ||
    ModeReport() ||
    KeyboardFlagsReport() ||
    DeviceAttributes() ||
    ColorReport() ||
    ColorSchemeReport() ||
    CursorReport() ||
    UnknownSequence() => false,
  };

  bool _quit() {
    final binding = AppBinding.of(context);
    if (binding.textOrder != TextOrder.logical) {
      log(
        'text in visual order where the terminal orders it',
        level: LogLevel.warning,
      );
    }
    if (TerminalStatus.of(context)?.showsPointerShape != true) {
      log(
        'no pointer shape where the terminal shows it',
        level: LogLevel.warning,
      );
    }
    log('quitting', level: LogLevel.debug);
    binding.quit();
    return true;
  }
}
