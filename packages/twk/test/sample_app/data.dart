part of '../sample_app.dart';

/// Sorts the table of the data rows, selects a cell of it and widens its
/// last column.
final _files = TableController(sortColumn: 0, columnWidths: {2: 7});

/// The rows of the table, read one at a time.
final _pairs = _Pairs();

final class _Pairs extends TableSource<(String, int)> {
  static const _rows = [('b', 2), ('a', 1)];

  @override
  int get rowCount => _rows.length;

  @override
  (String, int) rowAt(int index) => _rows[index];
}

/// Expands the tree of the data rows and selects a node of it.
final _nodes = TreeController(selectedKey: 'lib/a.dart', expanded: ['lib']);

/// The files the directory tree of the data rows lists.
final _tree = InMemoryFileSystem(
  ['/app/lib/main.dart', '/app/build/'],
  contents: {'/app/.gitignore': 'build/\n'},
);

/// Expands the tree table of the data rows and sorts it by size.
final _sized = TreeController(expanded: ['lib']);
final _sizedOrder = TableController(sortColumn: 1, sortAscending: false);

extension on _SampleAppState {
  List<Widget> _data() => [
    SizedBox(
      height: 8,
      child: Row(
        children: [
          const SizedBox(width: 8, child: Sparkline(data: [1, 3, 2, 5, 4])),
          const SizedBox(
            width: 6,
            child: TaskList(
              tasks: [
                TaskItem(
                  'task',
                  status: TaskStatus.done,
                  children: [TaskItem('step', id: 1)],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8, child: Gauge(ratio: 0.4, label: '40%')),
          const SizedBox(
            width: 8,
            child: LineGauge(ratio: 0.6, type: BorderType.double),
          ),
          const SizedBox(
            width: 16,
            child: BarChart(
              direction: Axis.horizontal,
              groups: [
                BarGroup([Bar(3, label: 'a'), Bar(5)], label: 'g'),
              ],
            ),
          ),
          const Expanded(
            child: Chart(
              datasets: [
                Dataset(
                  data: [(0, 0), (1, 1)],
                  name: 'line',
                  type: GraphType.line,
                  color: Color.green,
                ),
              ],
              xAxis: ChartAxis(bounds: (0, 1), title: 'x'),
              yAxis: ChartAxis(bounds: (0, 1), labels: ['0', '1']),
              legendPosition: LegendPosition.topLeft,
            ),
          ),
          SizedBox(
            width: 16,
            child: DotCanvas(
              xBounds: (0, 10),
              yBounds: (0, 10),
              marker: Marker.halfBlock,
              background: Color.black,
              draw: (dots) => dots
                ..draw(const Shape.circle(5, 5, 3, color: Color.cyan))
                ..layer()
                ..label(1, 1, 'dots'),
            ),
          ),
          SizedBox(
            width: 12,
            child: TreeView<String>(
              roots: const ['lib', 'test'],
              children: (path) => switch (path) {
                'lib' => const ['lib/a.dart', 'lib/b.dart'],
                'test' => Future.value(const ['test/a_test.dart']),
                _ => const [],
              },
              hasChildren: (path) => !path.endsWith('.dart'),
              label: (context, entry) => Text(entry.node.split('/').last),
              controller: _nodes,
              onActivated: (_) => _bump(),
            ),
          ),
          SizedBox(width: 20, child: Calendar(today: DateTime(2026, 10, 19))),
          SizedBox(
            width: 22,
            child: Table<(String, int)>.source(
              source: _pairs,
              rowKey: (row) => row.$1,
              controller: _files,
              selection: TableSelection.cell,
              border: BorderType.single,
              onActivated: (_) => _bump(),
              columns: [
                TableColumn(
                  title: 'name',
                  cell: (row) => TableCell(row.$1),
                  compare: (a, b) => a.$1.compareTo(b.$1),
                ),
                TableColumn(
                  title: 'count',
                  width: const GridTrack.fr(1, max: 8),
                  align: TextAlign.right,
                  cell: (row) => TableCell.rich(['${row.$2}'.bold]),
                ),
                TableColumn(
                  title: 'live',
                  width: const GridTrack.fixed(6),
                  cell: (row) => TableCell.widget(Gauge(ratio: row.$2 / 2)),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    // in a row of its own: beside the others it has no room
    SizedBox(
      height: 8,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: TreeTable<(String, int)>(
              roots: const [('lib', 3), ('test', 1)],
              children: (node) => switch (node.$1) {
                'lib' => const [('a.dart', 1), ('b.dart', 2)],
                'test' => Future.value(const [('a_test.dart', 1)]),
                _ => const [],
              },
              hasChildren: (node) => !node.$1.endsWith('.dart'),
              nodeKey: (node) => node.$1,
              controller: _sized,
              tableController: _sizedOrder,
              onActivated: (_) => _bump(),
              columns: [
                TableColumn(
                  title: 'name',
                  cell: (node) => TableCell(node.$1),
                  width: const GridTrack.fr(1),
                ),
                TableColumn(
                  title: 'size',
                  align: TextAlign.right,
                  cell: (node) => TableCell('${node.$2}'),
                  compare: (a, b) => a.$2.compareTo(b.$2),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 7,
            child: Heatmap(
              rows: 2,
              columns: 3,
              value: (row, column) => (row + column).toDouble(),
              tooltip: (row, column) => '$row, $column',
              onSelected: (_) => _bump(),
            ),
          ),
          SizedBox(
            width: 19,
            child: ActivityHeatmap(
              counts: {DateTime(2026, 10, 19): 3},
              end: DateTime(2026, 10, 21),
              weeks: 8,
              scale: const HeatmapScale.colors(
                Gradient([Color.black, Color.green]),
              ),
            ),
          ),
          SizedBox(
            width: 16,
            child: DirectoryTree(
              root: '/app',
              fileSystem: _tree,
              showSizes: true,
              filter: const FileFilter('Dart', ['dart']),
              icon: (entry) => entry.isDirectory ? '+' : null,
              onOpened: (_) => _bump(),
            ),
          ),
          SizedBox(
            width: 20,
            child: DescriptionList(
              items: [
                DescriptionItem.text('Status', 'Running'),
                const DescriptionItem.group('Limits'),
                const DescriptionItem('Load', ProgressBar(value: 0.5)),
              ],
            ),
          ),
        ],
      ),
    ),
  ];
}
