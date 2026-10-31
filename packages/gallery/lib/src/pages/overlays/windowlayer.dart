// The WindowLayer page.
part of 'overlays.dart';

final _windowlayerPage = GalleryPage(
  group: 'Overlays',
  title: 'WindowLayer',
  options: [
    ChoiceOption(
      'frame',
      'frame',
      values: [for (final f in WindowFrame.values) f.name],
    ),
    const SwitchOption('shadow', 'shadow', initial: true),
    const SwitchOption('resizable', 'resizable', initial: true),
    const SwitchOption('minimisable', 'minimisable', initial: true),
    const SwitchOption('maximisable', 'maximisable', initial: true),
  ],
  build: (context, o) => _Windows(
    frame: WindowFrame.values.byName(o.choice('frame')),
    shadow: o.flag('shadow'),
    resizable: o.flag('resizable'),
    minimisable: o.flag('minimisable'),
    maximisable: o.flag('maximisable'),
  ),
  // the layer's SizedBox
  heightIn: (o, room) => 12,
  code: _windowsCode,
);

const _note = 'Drag me by the title bar, or resize me by an edge.';

/// The WindowLayer page's Code.
String _windowsCode(Options o) {
  final extra = [
    if (o.flag('shadow'))
      '          shadow: Panel.shadowOf(Theme.of(context)),',
    if (!o.flag('resizable')) '          resizable: false,',
    if (!o.flag('minimisable')) '          minimisable: false,',
    if (!o.flag('maximisable')) '          maximisable: false,',
  ].map((l) => '$l\n').join();
  final frame = o.choice<String>('frame') == WindowFrame.raised.name
      ? ''
      : '    frame: .${o.label('frame')},\n';
  return '''
final _notes = WindowController(left: 2, top: 3, width: 30, height: 6);
final _counter = WindowController(left: 24, top: 5, width: 26, height: 6);
final _closed = <String>{};
var _count = 0;

@override
void dispose() {
  _notes.dispose();
  _counter.dispose();
  super.dispose();
}

void _close(String title) => setState(() => _closed.add(title));

@override
Widget build(BuildContext context) => SizedBox(
  width: 50,
  height: 12,
  child: WindowLayer(
$frame    windows: [
      if (!_closed.contains('Notes'))
        Window(
          key: const ValueKey('Notes'),
          title: 'Notes',
          controller: _notes,
          onClose: () => _close('Notes'),
$extra          child: const Padding(
            padding: .x(1),
            child: Text('$_note'),
          ),
        ),
      if (!_closed.contains('Counter'))
        Window(
          key: const ValueKey('Counter'),
          title: 'Counter',
          controller: _counter,
          onClose: () => _close('Counter'),
$extra          child: Padding(
            padding: const .x(1),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text('count: \$_count'),
                Button('Add one', onPressed: () => setState(() => _count++)),
              ],
            ),
          ),
        ),
    ],
    child: Column(
      crossAxisAlignment: .start,
      children: [
        const Text('The app, under its windows.'),
        Button(
          'Open the windows closed',
          onPressed: _closed.isEmpty ? null : () => setState(_closed.clear),
        ),
      ],
    ),
  ),
);''';
}

/// Two windows over an app: Notes and a counter, that move, resize,
/// minimise, maximise and close. Where they are, which are closed and the
/// count are kept while the gallery runs.
final class _Windows extends StatefulWidget {
  const _Windows({
    required this.frame,
    required this.shadow,
    required this.resizable,
    required this.minimisable,
    required this.maximisable,
  });

  final WindowFrame frame;
  final bool shadow;
  final bool resizable;
  final bool minimisable;
  final bool maximisable;

  @override
  State<_Windows> createState() => _WindowsState();
}

final class _WindowsState extends State<_Windows> with KeptState {
  late final _notes =
      (kept['notes'] ??= WindowController(
            left: 2,
            top: 3,
            width: 30,
            height: 6,
          ))
          as WindowController;
  late final _counter =
      (kept['counter'] ??= WindowController(
            left: 24,
            top: 5,
            width: 26,
            height: 6,
          ))
          as WindowController;
  late final _closed = (kept['closed'] ??= <String>{}) as Set<String>;
  int get _count => kept['count'] as int? ?? 0;

  void _close(String title) => setState(() => _closed.add(title));

  @override
  Widget build(BuildContext context) {
    final shadow = widget.shadow ? Panel.shadowOf(Theme.of(context)) : null;
    return SizedBox(
      width: 50,
      height: 12,
      child: WindowLayer(
        frame: widget.frame,
        windows: [
          if (!_closed.contains('Notes'))
            Window(
              key: const ValueKey('Notes'),
              title: 'Notes',
              controller: _notes,
              onClose: () => _close('Notes'),
              shadow: shadow,
              resizable: widget.resizable,
              minimisable: widget.minimisable,
              maximisable: widget.maximisable,
              child: const Padding(
                padding: EdgeInsets.x(1),
                child: Text(_note),
              ),
            ),
          if (!_closed.contains('Counter'))
            Window(
              key: const ValueKey('Counter'),
              title: 'Counter',
              controller: _counter,
              onClose: () => _close('Counter'),
              shadow: shadow,
              resizable: widget.resizable,
              minimisable: widget.minimisable,
              maximisable: widget.maximisable,
              child: Padding(
                padding: const EdgeInsets.x(1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('count: $_count'),
                    Button(
                      'Add one',
                      onPressed: () =>
                          setState(() => kept['count'] = _count + 1),
                    ),
                  ],
                ),
              ),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The app, under its windows.'),
            Button(
              'Open the windows closed',
              onPressed: _closed.isEmpty ? null : () => setState(_closed.clear),
            ),
          ],
        ),
      ),
    );
  }
}
