// The layout guide's cell text (doc/guides/layout.md, "Text in cells"): a
// string cut to a width, a row painted across, a gutter on every wrapped
// line, a string padded and a trailing space kept; q quits.
//
//   dart run example/guides/cell_text.dart
import 'package:twk/twk.dart';

Future<void> main() => runApp(const CellText());

final class CellText extends StatelessWidget {
  const CellText({super.key});

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'q': () => AppBinding.of(context).quit()},
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        // a String cut to 12 cells, wide letters whole
        Text(fitText(segmenterOf(context), 'Warnings (12) and 你好世界', 12)),
        // the row's background across its whole width, not under its text
        const ColoredBox(color: Color.blue, child: Text(' NORMAL ')),
        // a gutter on every line the text breaks into: a left border
        const Box(
          border: Border(left: Style()),
          padding: EdgeInsets.only(left: 1),
          child: Text('A quotation with 你好世界 that wraps over lines.'),
        ),
        // a String padded to 10 cells by the cells it takes, not its length
        Text('[${padCells(segmenterOf(context), '你好', 10)}]'),
        // a space at the end of a wrapped text hangs; with none it stays
        const Row(
          children: [
            Text('◐ '),
            Text('|'),
            Text('◐ ', wrap: .none),
            Text('|'),
          ],
        ),
      ],
    ),
  );
}
