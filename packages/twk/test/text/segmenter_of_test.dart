// segmenterOf: the segmenter an app's own cell text is measured and cut
// with, the terminal's, so that on a terminal taking East Asian ambiguous
// characters as two columns its cut agrees with what is drawn.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'ambiguous.dart';

void main() {
  test('segmenterOf(context) measures and cuts as the terminal draws, '
      'ambiguous letters two columns on an ambiguous-wide one', () async {
    late TextSegmenter seen;
    final app = await WideApp.start(
      Builder(
        builder: (context) {
          seen = segmenterOf(context);
          return Text.line(fitText(seen, 'a─b─c', 4));
        },
      ),
    );
    addTearDown(app.quit);
    expect(seen.width('─'), 2);
    expect(seen.width(fitText(seen, 'a─b─c', 4)), lessThanOrEqualTo(4));
    expect(app.lines()[0], fitText(seen, 'a─b─c', 4));
  });
}
