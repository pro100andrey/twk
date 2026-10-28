part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _foundation() => [
    SizedBox(
      height: 1,
      child: Row(
        gap: 1,
        children: [
          ListenableBuilder(
            listenable: _count,
            builder: (context, child) => Text('${_count.value}'),
          ),
          ValueListenableBuilder(
            valueListenable: _count,
            builder: (context, value, child) => Text('$value'),
          ),
          FutureBuilder(
            future: Future.value(1),
            builder: (context, snapshot) => Text('${snapshot.data}'),
          ),
          StreamBuilder(
            stream: _ticks.stream,
            initialData: 0,
            builder: (context, snapshot) => Text('${snapshot.data}'),
          ),
          Counted(stream: _ticks.stream),
        ],
      ),
    ),
  ];
}

/// How many events [stream] gave.
final class Counted extends StreamBuilderBase<int, int> {
  const Counted({required super.stream, super.key});

  @override
  int initial() => 0;

  @override
  int afterData(int current, int data) => current + 1;

  @override
  Widget build(BuildContext context, int currentSummary) =>
      Text('$currentSummary');
}
