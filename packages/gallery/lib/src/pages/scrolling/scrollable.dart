// The Scrollable page.
part of 'scrolling.dart';

final _scrollablePage = GalleryPage(
  group: _group,
  title: 'Scrollable',
  build: (context, o) => const _RulerPage(),
  code: (o) => _rulerCode,
);

/// The ruler's rows.
const _ruler = 100;

/// The Code's lines too long for a line of Dart.
const _rulerLine =
    '                  _Ruler(position, offset: position.offset, length: '
    '$_ruler),';

const _rulerConstructor =
    '  const _Ruler(this.position, {required this.offset, '
    'required this.length});';

const _rulerUpdate =
    '  void updateRenderObject(BuildContext context, '
    '_RenderRuler renderObject) =>';

/// A ruler of numbered rows that a Scrollable scrolls.
final class _RulerPage extends StatefulWidget {
  const _RulerPage();

  @override
  State<_RulerPage> createState() => _RulerPageState();
}

final class _RulerPageState extends State<_RulerPage> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      _boxed(
        _boxW,
        _scrollH,
        Scrollable(
          controller: _controller,
          viewportBuilder: (context, position) => ListenableBuilder(
            listenable: position,
            builder: (_, _) =>
                _Ruler(position, offset: position.offset, length: _ruler),
          ),
        ),
      ),
      _offsetLine(_controller),
    ],
  );
}

/// A viewport of [length] numbered rows from [offset] on, which tells
/// [position] its extents as it is laid out.
final class _Ruler extends LeafRenderObjectWidget {
  const _Ruler(this.position, {required this.offset, required this.length});

  final ScrollPosition position;
  final int offset;
  final int length;

  @override
  _RenderRuler createRenderObject(BuildContext context) =>
      _RenderRuler(position, offset, length);

  @override
  void updateRenderObject(BuildContext context, _RenderRuler renderObject) =>
      renderObject
        ..position = position
        ..offset = offset
        ..length = length;
}

final class _RenderRuler extends RenderObject {
  _RenderRuler(this._position, this._offset, this._length);

  ScrollPosition _position;
  int _offset;
  int _length;

  ScrollPosition get position => _position;
  set position(ScrollPosition value) {
    if (value != _position) {
      _position = value;
      markNeedsLayout();
    }
  }

  int get offset => _offset;
  set offset(int value) {
    if (value != _offset) {
      _offset = value;
      markNeedsPaint();
    }
  }

  int get length => _length;
  set length(int value) {
    if (value != _length) {
      _length = value;
      markNeedsLayout();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    _position.applyExtents(height, _length);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = canvas.styles.pen(const Pen());
    final tick = canvas.styles.pen(const Pen(attrs: Attr.dim));
    for (var y = 0; y < height && _offset + y < _length; y++) {
      final row = _offset + y + 1;
      final x = canvas.text(0, y, '${row.toString().padLeft(3)} ', pen);
      canvas.text(
        x,
        y,
        row % 10 == 0 ? '├─────────' : (row % 5 == 0 ? '├────' : '├─'),
        tick,
      );
    }
  }
}

final String _rulerCode = [
  'final _controller = ScrollController();',
  '',
  '@override',
  'void dispose() {',
  '  _controller.dispose();',
  '  super.dispose();',
  '}',
  '',
  '@override',
  'Widget build(BuildContext context) {',
  '  final theme = Theme.of(context);',
  '  return Column(',
  '    mainAxisSize: .min,',
  '    crossAxisAlignment: .start,',
  '    gap: 1,',
  '    children: [',
  '      SizedBox(',
  '        width: $_boxW,',
  '        height: $_scrollH,',
  ..._focusBox('        '),
  '          child: Scrollable(',
  '            controller: _controller,',
  '            viewportBuilder: (context, position) => ListenableBuilder(',
  '              listenable: position,',
  '              builder: (_, _) =>',
  _rulerLine,
  '            ),',
  '          ),',
  '        ),',
  '      ),',
  ..._offsetCode('_controller'),
  '    ],',
  '  );',
  '}',
  '',
  '/// A viewport of [length] numbered rows from [offset] on, which tells',
  '/// [position] its extents as it is laid out.',
  'final class _Ruler extends LeafRenderObjectWidget {',
  _rulerConstructor,
  '',
  '  final ScrollPosition position;',
  '  final int offset;',
  '  final int length;',
  '',
  '  @override',
  '  _RenderRuler createRenderObject(BuildContext context) =>',
  '      _RenderRuler(position, offset, length);',
  '',
  '  @override',
  _rulerUpdate,
  '      renderObject',
  '        ..position = position',
  '        ..offset = offset',
  '        ..length = length;',
  '}',
  '',
  'final class _RenderRuler extends RenderObject {',
  '  _RenderRuler(this._position, this._offset, this._length);',
  '',
  '  ScrollPosition _position;',
  '  int _offset;',
  '  int _length;',
  '',
  '  set position(ScrollPosition value) {',
  '    if (value != _position) {',
  '      _position = value;',
  '      markNeedsLayout();',
  '    }',
  '  }',
  '',
  '  set offset(int value) {',
  '    if (value != _offset) {',
  '      _offset = value;',
  '      markNeedsPaint();',
  '    }',
  '  }',
  '',
  '  set length(int value) {',
  '    if (value != _length) {',
  '      _length = value;',
  '      markNeedsLayout();',
  '    }',
  '  }',
  '',
  '  @override',
  '  void performLayout(BoxConstraints c) {',
  '    width = c.maxW;',
  '    height = c.maxH;',
  '    _position.applyExtents(height, _length);',
  '  }',
  '',
  '  @override',
  '  void paint(PaintContext ctx) {',
  '    final canvas = ctx.canvas;',
  '    final pen = canvas.styles.pen(const Pen());',
  '    final tick = canvas.styles.pen(const Pen(attrs: Attr.dim));',
  '    for (var y = 0; y < height && _offset + y < _length; y++) {',
  '      final row = _offset + y + 1;',
  r"      final x = canvas.text(0, y, '${row.toString().padLeft(3)} ', pen);",
  '      canvas.text(',
  '        x,',
  '        y,',
  "        row % 10 == 0 ? '├─────────' : (row % 5 == 0 ? '├────' : '├─'),",
  '        tick,',
  '      );',
  '    }',
  '  }',
  '}',
].join('\n');
