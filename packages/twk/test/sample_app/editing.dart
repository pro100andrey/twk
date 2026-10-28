part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _editing() => const [
    SizedBox(
      height: 1,
      child: Row(
        gap: 1,
        children: [
          SizedBox(width: 12, child: TextField(placeholder: 'type here')),
          SizedBox(width: 12, child: TextArea(placeholder: 'notes')),
          SizedBox(width: 12, child: _Completing()),
          _Block(),
        ],
      ),
    ),
    SizedBox(
      height: 1,
      child: Row(
        gap: 1,
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: Text('@'),
                suffixText: '.org',
                border: InputBorder.none,
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: InputDecorator(
              decoration: InputDecoration(
                icon: Text('>'),
                prefixText: 'https://',
                border: InputBorder.none,
              ),
              child: Text('twk'),
            ),
          ),
        ],
      ),
    ),
  ];
}

/// A field that completes the commands typed after `/`.
final class _Completing extends StatefulWidget {
  const _Completing();

  @override
  State<_Completing> createState() => _CompletingState();
}

final class _CompletingState extends State<_Completing> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(
    child: Autocomplete(
      controller: _controller,
      trigger: '/',
      suggestions: (query) => [
        for (final command in const ['bump', 'quit'])
          if (fuzzyMatch(query, command) != null) Suggestion(command),
      ],
      child: TextField(controller: _controller, placeholder: '/command'),
    ),
  );
}

/// A cell the terminal's cursor shows at, a block, while it has the focus.
final class _Block extends StatefulWidget {
  const _Block();

  @override
  State<_Block> createState() => _BlockState();
}

final class _BlockState extends State<_Block> {
  final _node = FocusNode();

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    child: ListenableBuilder(
      listenable: _node,
      builder: (context, _) => _BlockCell(focused: _node.hasFocus),
    ),
  );
}

final class _BlockCell extends LeafRenderObjectWidget {
  const _BlockCell({required this.focused});

  final bool focused;

  @override
  _RenderBlockCell createRenderObject(BuildContext context) =>
      _RenderBlockCell()..focused = focused;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBlockCell renderObject,
  ) => renderObject.focused = focused;
}

final class _RenderBlockCell extends RenderObject {
  var _focused = false;

  /// Whether the cursor shows.
  bool get focused => _focused;
  set focused(bool f) {
    if (f != _focused) {
      _focused = f;
      markNeedsPaint();
    }
  }

  // what painted it last
  PaintContext? _painted;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(1);
    height = c.constrainH(1);
  }

  @override
  void detach() {
    final ctx = _painted;
    if (ctx != null) {
      hideCaret(ctx, this);
    }
    super.detach();
  }

  @override
  void paint(PaintContext ctx) {
    _painted = ctx;
    if (_focused) {
      showCaret(ctx, this, 0, 0, shape: CursorShape.block);
    } else {
      hideCaret(ctx, this);
    }
  }
}
