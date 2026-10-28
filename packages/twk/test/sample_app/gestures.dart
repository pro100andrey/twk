part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _gestures() => [
    SizedBox(
      height: 3,
      child: Row(
        children: [
          MouseRegion(
            onEnter: (_) => _bump(),
            cursor: PointerShape.pointer,
            child: Listener(
              onDown: (event) => _count.value += event.button,
              behavior: HitTestBehavior.opaque,
              child: const Box(
                style: Style(bg: Color.indexed(236)),
                border: Border.all(type: BorderType.rounded),
                titles: [BorderTitle('box', alignment: Alignment.topCenter)],
                padding: EdgeInsets.x(1),
                child: Text('boxed'),
              ),
            ),
          ),
          IgnorePointer(
            ignoring: false,
            child: GestureDetector(
              onTap: (_) => _bump(),
              onDoubleTap: (event) => _count.value += event.button,
              onDragUpdate: (drag) => _count.value += drag.dx,
              child: const Text('tap'),
            ),
          ),
          AbsorbPointer(
            absorbing: false,
            child: SelectionArea(
              copyKey: 'ctrl+y',
              onCopy: (text) => _count.value += text.length,
              child: const Text('select'),
            ),
          ),
        ],
      ),
    ),
    Overlay(
      child: Row(
        children: [
          Draggable<int>(
            data: 2,
            feedback: const Text('[2]'),
            childWhenDragging: const Text('    '),
            onDragCompleted: _bump,
            child: const Text('two '),
          ),
          DragTarget<int>(
            onWillAccept: (drag) => drag.data > 0,
            onAccept: (drop) => _count.value += drop.data,
            builder: (context, candidate, rejected) =>
                Text(candidate == null ? 'drop' : 'drop $candidate'),
          ),
        ],
      ),
    ),
  ];
}
