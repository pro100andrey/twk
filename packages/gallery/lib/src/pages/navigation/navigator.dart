// The Navigator page.
part of 'navigation.dart';

final _navigatorPage = GalleryPage(
  group: 'Navigation',
  title: 'Navigator',
  options: const [
    ChoiceOption(
      'backKey',
      'back key',
      values: ['escape', 'backspace', null],
      labels: ['escape', 'backspace', 'none'],
    ),
  ],
  build: (context, o) => SizedBox(
    width: 44,
    height: 9,
    child: Box(
      border: Border.all(
        type: BorderType.rounded,
        style: Theme.of(context).border,
      ),
      padding: const EdgeInsets.x(1),
      child: Navigator(
        backKey: o.choice('backKey'),
        home: const _Home(),
        onGenerateRoute: (settings) => settings.name == '/settings'
            ? _slide(context, (_) => const _Settings(), settings)
            : null,
      ),
    ),
  ),
  code: _code,
);

/// The Navigator page's Code.
String _code(Options o) {
  final backKey = o.choice<String?>('backKey');
  final back = switch (backKey) {
    'escape' => '',
    null => '      backKey: null,\n',
    final key => "      backKey: '$key',\n",
  };
  return '''
@override
Widget build(BuildContext context) => SizedBox(
  width: 44,
  height: 9,
  child: Box(
    border: .all(type: .rounded, style: Theme.of(context).border),
    padding: const .x(1),
    child: Navigator(
$back      home: const _Home(),
      onGenerateRoute: (settings) => settings.name == '/settings'
          ? _Slide.route((_) => const _Settings(), settings)
          : null,
    ),
  ),
);

/// The routes of the screens: each slides in from the right over the one
/// under it, which dims, and out again as it is popped.
abstract final class _Slide {
  static PageRoute<void> route(
    Widget Function(BuildContext context) builder, [
    RouteSettings settings = const RouteSettings(),
  ]) => PageRoute(
    builder: builder,
    settings: settings,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
  );
}

/// The first route: buttons that push the others.
final class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      const Text('Home'),
      Button(
        'Open item 7',
        onPressed: () =>
            Navigator.push(context, _Slide.route((_) => const _Item(7))),
      ),
      Button(
        'Open /settings',
        onPressed: () => Navigator.pushNamed<void>(context, '/settings'),
      ),
    ],
  );
}

/// Item [n], with a button that pops it and one that pushes the next.
final class _Item extends StatelessWidget {
  const _Item(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      Text('Item \$n', style: Theme.of(context).primary),
      Row(
        gap: 2,
        children: [
          Button(
            'Back',
            autofocus: true,
            onPressed: () => Navigator.pop(context),
          ),
          Button(
            'Open item \${n + 1}',
            onPressed: () =>
                Navigator.push(context, _Slide.route((_) => _Item(n + 1))),
          ),
        ],
      ),
    ],
  );
}

/// The route named /settings, with a button that pops it.
final class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    gap: 1,
    children: [
      Text('Settings', style: Theme.of(context).primary),
      Button(
        'Back',
        autofocus: true,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}''';
}

/// A screen that slides in from the right over the one under it, which
/// dims, and out again as it is popped; there at once while the gallery's
/// clock stands still, as its other motion is.
PageRoute<void> _slide(
  BuildContext context,
  Widget Function(BuildContext context) builder, [
  RouteSettings settings = const RouteSettings(),
]) {
  final still = Clock.of(context).frozen;
  return PageRoute(
    builder: builder,
    settings: settings,
    transitionDuration: still
        ? Duration.zero
        : const Duration(milliseconds: 220),
    reverseTransitionDuration: still
        ? Duration.zero
        : const Duration(milliseconds: 180),
  );
}

/// The first route: buttons that push the others.
final class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      const Text('Home'),
      Button(
        'Open item 7',
        onPressed: () =>
            Navigator.push(context, _slide(context, (_) => const _Item(7))),
      ),
      Button(
        'Open /settings',
        onPressed: () => Navigator.pushNamed<void>(context, '/settings'),
      ),
    ],
  );
}

/// Item [n], with a button that pops it and one that pushes the next.
final class _Item extends StatelessWidget {
  const _Item(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Text('Item $n', style: Theme.of(context).primary),
      Row(
        gap: 2,
        children: [
          Button(
            'Back',
            autofocus: true,
            onPressed: () => Navigator.pop(context),
          ),
          Button(
            'Open item ${n + 1}',
            onPressed: () =>
                Navigator.push(context, _slide(context, (_) => _Item(n + 1))),
          ),
        ],
      ),
    ],
  );
}

/// The route named /settings, with a button that pops it.
final class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      Text('Settings', style: Theme.of(context).primary),
      Button(
        'Back',
        autofocus: true,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  );
}
