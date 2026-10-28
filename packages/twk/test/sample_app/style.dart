part of '../sample_app.dart';

extension on _SampleAppState {
  /// [child] in the theme of the terminal's brightness.
  Widget _themed(Widget child) => Theme.adaptive(
    dark: ThemeData.nord,
    light: ThemeData.catppuccinLatte,
    child: child,
  );

  List<Widget> _style() => [
    SizedBox(
      height: 1,
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints.tightFor(width: 8),
            child: TerminalBrightness(
              brightness: Brightness.dark,
              child: AnimatedTheme(
                data: const ThemeData.terminal(Brightness.dark),
                child: Builder(
                  builder: (context) =>
                      Text('theme', style: Theme.of(context).primary),
                ),
              ),
            ),
          ),
          const GradientBackground(
            gradient: Gradient([Color.blue, Color.magenta]),
            child: GradientForeground(
              gradient: Gradient(
                [Color.white, Color.cyan],
                stops: [0, 1],
                direction: Axis.vertical,
              ),
              child: Text('gradient'),
            ),
          ),
        ],
      ),
    ),
  ];
}
