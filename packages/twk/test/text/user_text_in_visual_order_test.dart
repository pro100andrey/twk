// In visual order the user's text a render object paints itself reads as a
// Text draws it, through a TextPainter it keeps: a ProgressList's labels, a
// TaskList's, the console's messages, the labels, titles and names of the
// charts, gauges and the heatmap, the DotCanvas's labels, the calendar's
// month and weekday names and the key labels of a menu's entries. Text('שלום
// עולם') draws 'םלוע םולש'; a left-to-right text draws as it did.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show PipelineTextOrder, TextOrder;
import 'package:twk_test/twk_test.dart';

const hebrew = 'שלום עולם';
const reversed = 'םלוע םולש';

Future<void> draw(TwkTester t, TextOrder order) async {
  t.binding.twkApp.owner.textOrder = order;
  await t.pump();
}

Future<void> visual(TwkTester t) => draw(t, TextOrder.visual);

Future<void> logical(TwkTester t) => draw(t, TextOrder.logical);

Widget top(Widget child) => Align(alignment: Alignment.topLeft, child: child);

void main() {
  testTwk('a ProgressList label reads as a Text does, cut at its end', (
    t,
  ) async {
    final tracker = ProgressTracker(clock: t.clock.stopwatch);
    addTearDown(tracker.dispose);
    tracker
      ..add(hebrew)
      ..add('plain');
    const columns = [ProgressColumn.label];
    await t.pumpWidget(
      top(ProgressList(tracker: tracker, columns: columns)),
      size: (12, 2),
    );
    await logical(t);
    expect(t.lines, [hebrew, 'plain']);
    await visual(t);
    expect(t.lines, [reversed, 'plain']);
    // too long for its room: its end is cut, with the ellipsis, as a Text's
    await t.pumpWidget(
      top(ProgressList(tracker: tracker, columns: columns)),
      size: (6, 2),
    );
    await logical(t);
    expect(t.lines, ['שלום…', 'plain']);
    await visual(t);
    expect(t.lines, ['…םולש', 'plain']);
  });

  testTwk('a TaskList label reads as a Text does', (t) async {
    await t.pumpWidget(
      top(
        const TaskList(
          showElapsed: false,
          tasks: [TaskItem(hebrew, status: TaskStatus.done)],
        ),
      ),
      size: (14, 1),
    );
    await visual(t);
    expect(t.lines[0], contains(reversed));
  });

  testTwk('a console message reads as a Text does, cut at its end', (t) async {
    final sink = LogSink()
      ..add(LogRecord(DateTime(2026), LogLevel.info, hebrew));
    final controller = ConsoleController(sink)..open();
    await t.pumpWidget(
      Console(controller: controller, rows: 3, child: const SizedBox()),
      size: (40, 4),
    );
    await logical(t);
    expect(t.lines[2], contains(' $hebrew'));
    await visual(t);
    expect(t.lines[2], contains(' $reversed'));
    // the record shown whole: its lines read so too
    controller
      ..selectNext()
      ..showSelected();
    await t.pump();
    expect(t.lines.join('\n'), contains(reversed));
    controller.close();
  });

  testTwk('a Gauge label and a LineGauge label read as a Text does', (t) async {
    await t.pumpWidget(
      top(
        const SizedBox(
          width: 20,
          child: Column(
            children: [
              Gauge(ratio: 0.5, label: hebrew),
              LineGauge(ratio: 0.5, label: hebrew),
            ],
          ),
        ),
      ),
      size: (20, 2),
    );
    await logical(t);
    expect(t.lines[0], contains(hebrew));
    expect(t.lines[1], startsWith(hebrew));
    await visual(t);
    expect(t.lines[0], contains(reversed));
    expect(t.lines[1], startsWith(reversed));
  });

  testTwk('a BarChart bar label and a group label read as a Text does', (
    t,
  ) async {
    await t.pumpWidget(
      top(
        const SizedBox(
          width: 24,
          height: 3,
          child: BarChart(
            direction: Axis.horizontal,
            groups: [
              BarGroup([Bar(4, label: hebrew, text: '')], label: hebrew),
            ],
            groupGap: 1,
          ),
        ),
      ),
      size: (24, 3),
    );
    await visual(t);
    expect(t.lines[0], startsWith(reversed));
    expect(t.lines.join('\n'), contains(reversed));
    await logical(t);
    expect(t.lines[0], startsWith(hebrew));
  });

  testTwk('a Chart axis title, label and dataset name read as a Text does', (
    t,
  ) async {
    await t.pumpWidget(
      top(
        const SizedBox(
          width: 40,
          height: 12,
          child: Chart(
            datasets: [
              Dataset(data: [(0, 0), (10, 10)], name: hebrew),
            ],
            xAxis: ChartAxis(bounds: (0, 10), title: hebrew, labels: ['0']),
            yAxis: ChartAxis(bounds: (0, 10), title: hebrew, labels: [hebrew]),
          ),
        ),
      ),
      size: (40, 12),
    );
    await logical(t);
    final before = t.lines.join('\n');
    expect(before, contains(hebrew));
    await visual(t);
    final after = t.lines.join('\n');
    expect(after, isNot(contains(hebrew)));
    // the y title, the y label, the x title and the legend's name
    expect(RegExp(reversed).allMatches(after).length, 4);
  });

  testTwk('Heatmap row labels and legend labels read as a Text does', (
    t,
  ) async {
    await t.pumpWidget(
      top(
        Heatmap(
          rows: 1,
          columns: 2,
          value: (r, c) => c.toDouble(),
          rowLabels: const [hebrew],
          showLegend: true,
          legendLabels: (hebrew, 'more'),
        ),
      ),
      size: (30, 2),
    );
    await logical(t);
    expect(t.lines.join('\n'), contains(hebrew));
    await visual(t);
    final shown = t.lines.join('\n');
    expect(shown, isNot(contains(hebrew)));
    expect(RegExp(reversed).allMatches(shown).length, 2);
  });

  testTwk('a DotCanvas label reads as a Text does', (t) async {
    await t.pumpWidget(
      top(
        DotCanvas(
          draw: (c) => c.label(0, 0, hebrew),
          xBounds: const (0, 10),
          yBounds: const (0, 10),
        ),
      ),
      size: (20, 4),
    );
    await logical(t);
    expect(t.lines.join('\n'), contains(hebrew));
    await visual(t);
    expect(t.lines.join('\n'), contains(reversed));
  });

  testTwk('a Calendar month and weekday names read as a Text does', (t) async {
    final names = [for (var i = 0; i < 12; i++) hebrew];
    final days = ['אב', 'גד', 'הו', 'זח', 'טי', 'כל', 'מנ'];
    await t.pumpWidget(
      top(
        Calendar(
          controller: CalendarController(cursor: DateTime(2026, 10, 7)),
          monthNames: names,
          weekdayNames: days,
        ),
      ),
      size: (20, 8),
    );
    await logical(t);
    expect(t.lines[0], contains(hebrew));
    expect(t.lines[1], contains('אב'));
    await visual(t);
    expect(t.lines[0], contains(reversed));
    expect(t.lines[1], contains('בא'));
    expect(t.lines[1], isNot(contains('אב')));
  });

  testTwk('the key label of a menu entry reads as a Text does', (t) async {
    void run() {}
    await t.pumpWidget(
      Theme.terminal(
        child: KeyBindings(
          {'ctrl+q': run},
          child: Overlay(
            child: MenuBar(
              look: PanelLook.bordered,
              keyLabel: (_) => hebrew,
              menus: [
                Menu('&File', items: [MenuItem('&Quit', onSelected: run)]),
              ],
              child: const SizedBox(),
            ),
          ),
        ),
      ),
      size: (30, 5),
    );
    await t.press('f10');
    await t.press('enter');
    await t.pump();
    await logical(t);
    expect(t.lines.join('\n'), contains('Quit  $hebrew'));
    await visual(t);
    expect(t.lines.join('\n'), contains('Quit  $reversed'));
  });

  testTwk('an OptionList label too long for its row is cut at its end, with '
      "the theme's ellipsis, as a Text with TextOverflow.ellipsis is", (
    t,
  ) async {
    await t.pumpWidget(
      top(
        const OptionList(
          options: [Option(hebrew), Option('abcdefghijklmn')],
        ),
      ),
      size: (8, 2),
    );
    await logical(t);
    expect(t.lines, [' שלום…', ' abcde…']);
    await visual(t);
    // the start of the label (on the right) is kept, its end cut
    expect(t.lines, [' …םולש', ' abcde…']);
  });
}
