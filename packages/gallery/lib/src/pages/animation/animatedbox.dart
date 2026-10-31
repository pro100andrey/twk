// The AnimatedBox page.
part of 'animation.dart';

/// The AnimatedBox page's `big` option.
const _boxBig = SwitchOption('big', 'big');

// ------------------------------------------------------------ AnimatedBox

final _box = GalleryPage(
  group: _group,
  title: 'AnimatedBox',
  options: [
    _boxBig,
    _curveOption,
    _cycleOption,
  ],
  build: (context, o) => _Cycled(o, _boxBig, const [false, true], (context, i) {
    final theme = Theme.of(context);
    final big = i == 1;
    return _inFrame(
      _overshoot(o, 34, 7, 5, 1),
      AnimatedBox(
        width: big ? 34 : 16,
        height: big ? 7 : 3,
        style: big ? theme.selection : theme.surface,
        border: .all(
          type: big ? .double : .rounded,
          style: big ? theme.accent : theme.border,
        ),
        padding: big ? const .only(left: 4, top: 1) : .zero,
        duration: _duration,
        curve: _curveOf(o),
        child: const Text('a box'),
      ),
    );
  }),
  code: (o) {
    final room = _overshoot(o, 34, 7, 5, 1);
    // the value written, or null for the Code's `big`
    List<String> body(bool? big) {
      String pick(String yes, String no) => switch (big) {
        true => yes,
        false => no,
        null => 'big ? $yes : $no',
      };
      return [
        'final theme = Theme.of(context);',
        ..._framed(o, room, 'the box at its biggest', [
          'AnimatedBox(',
          '  width: ${pick('34', '16')},',
          '  height: ${pick('7', '3')},',
          '  style: ${pick('theme.selection', 'theme.surface')},',
          '  border: .all(',
          '    type: ${pick('.double', '.rounded')},',
          '    style: ${pick('theme.accent', 'theme.border')},',
          '  ),',
          if (big ?? true)
            '  padding: ${pick('const .only(left: 4, top: 1)', '.zero')},',
          '  duration: $_dur,',
          ..._curveLine(o, 2),
          "  child: const Text('a box'),",
          ')',
        ]),
      ];
    }

    if (!o(_cycleOption)) {
      return body(o(_boxBig)).join('\n');
    }
    return _ticking(
      ['var _big = ${o(_boxBig)};'],
      '() => _big = !_big',
      'big, then small again, every 1.2 s',
      ['final big = _big;', ...body(null)],
    ).join('\n');
  },
);
