part of '../sample_app.dart';

/// Moves the list of the scroll row to an item.
final _items = ListController();

/// Keeps the view of the scroll row at its end as its rows grow.
final _tail = ScrollController(stickToEnd: true);

/// The lines of the log of the scroll row.
final _log = LogController(maxLines: 100)
  ..add('started', level: LogLevel.debug)
  ..add('listening');

extension on _SampleAppState {
  List<Widget> _scroll() => [
    SizedBox(
      height: 2,
      child: Row(
        children: [
          SizedBox(
            width: 10,
            child: SingleChildScrollView(
              controller: _tail,
              style: const Style(bg: Color.indexed(235)),
              child: Column(
                children: [for (var i = 0; i < 9; i++) Text('row $i')],
              ),
            ),
          ),
          SizedBox(
            width: 8,
            child: Scrollable(
              scrollDirection: Axis.horizontal,
              viewportBuilder: (context, position) =>
                  Text('at ${position.offset}'),
            ),
          ),
          SizedBox(
            width: 13,
            child: Scrollbar(
              visibility: ScrollbarVisibility.onScroll,
              child: ListView.builder(
                itemCount: 1000,
                controller: _items,
                wheelAcceleration: const WheelAcceleration(),
                itemBuilder: (context, index) => Text('item $index'),
              ),
            ),
          ),
          SizedBox(
            width: 16,
            child: LogView(controller: _log, showTime: false),
          ),
          SizedBox(
            width: 10,
            child: ListView.separated(
              reverse: true,
              itemCount: 20,
              itemBuilder: (context, index) => Text('msg $index'),
              separatorBuilder: (context, index) => const Text('·'),
            ),
          ),
        ],
      ),
    ),
  ];
}
