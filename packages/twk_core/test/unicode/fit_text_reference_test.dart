// fitText cuts without materialising the clusters of the text; this holds it
// to the cut of a plain version that does, over many texts, widths, modes
// and overflows.
import 'package:test/test.dart';
import 'package:twk_core/src/unicode/unicode.dart' show isLeadingMark;
import 'package:twk_core/twk_core.dart';

/// [fitText] by the book: the clusters in two lists, then the cut.
String reference(
  TextSegmenter seg,
  String text,
  int width,
  TextOverflow overflow,
) {
  if (seg.width(text) <= width) {
    return text;
  }
  if (width <= 0) {
    return '';
  }
  const ellipsis = '…';
  final ew = seg.width(ellipsis);
  final clip = overflow == TextOverflow.clip;
  final room = clip || width < ew ? width : width - ew;
  final mark = clip || width < ew ? '' : ellipsis;
  final scan = ClusterScan();
  final ends = <int>[0];
  final cols = <int>[];
  for (var i = 0; i < text.length;) {
    final start = i;
    seg.scan(text, i, scan);
    i = scan.end;
    var cells = scan.width;
    if (cells == 0) {
      cells = scan.first == 0x09 ? 1 : 0;
    } else if (seg.mode == TextMode.graphemes && isLeadingMark(scan.first)) {
      i = start + (scan.first > 0xFFFF ? 2 : 1);
      cells = 0;
    }
    ends.add(i);
    cols.add(cells);
  }
  int head(int r, [int to = -1]) {
    final n = to < 0 ? cols.length : to;
    var w = 0;
    var k = 0;
    for (; k < n && w + cols[k] <= r; k++) {
      w += cols[k];
    }
    return k;
  }

  int tail(int r, [int from = 0]) {
    var w = 0;
    var k = cols.length;
    for (; k > from && w + cols[k - 1] <= r; k--) {
      w += cols[k - 1];
    }
    return k;
  }

  bool blank(int k) =>
      ends[k + 1] - ends[k] == 1 && ' 　 '.contains(text[ends[k]]);
  int back(int from) {
    var k = from;
    while (k > 0 && blank(k - 1)) {
      k--;
    }
    return k;
  }

  int front(int from) {
    var k = from;
    while (k < cols.length && blank(k)) {
      k++;
    }
    return k;
  }

  int sum(int a, int b) => cols.sublist(a, b).fold(0, (x, y) => x + y);
  switch (overflow) {
    case TextOverflow.ellipsisStart:
      final t = mark.isEmpty ? tail(room) : front(tail(room));
      return '$mark${text.substring(ends[t])}';
    case TextOverflow.ellipsisMiddle when !clip && width >= ew:
      final first = back(head((room + 1) >> 1));
      final t = front(tail(room - sum(0, first), first));
      final h = back(head(room - sum(t, cols.length), t));
      return '${text.substring(0, ends[h])}$ellipsis${text.substring(ends[t])}';
    case TextOverflow.clip:
    case TextOverflow.ellipsis:
    case TextOverflow.ellipsisMiddle:
      final h = head(room);
      return '${text.substring(0, ends[mark.isEmpty ? h : back(h)])}$mark';
  }
}

void main() {
  const texts = [
    'Warnings (12) and more',
    '  leading and   inner   blanks  trailing  ',
    '日本語のテキスト and 你好 world',
    'αβγδ εζηθ ικλμ',
    'a\tb\tc tabs and\u0000controls here',
    'école 👍🏽 family 👨‍👩‍👧 flags 🇫🇷🇩🇪 end',
    '̀mark first ؀prepend next',
    'x　y　z wide blanks   em',
    '',
    'a',
  ];
  for (final mode in TextMode.values) {
    for (final ambiguous in [1, 2]) {
      test('same as the reference, $mode, ambiguous $ambiguous', () {
        final seg = TextSegmenter(mode: mode, ambiguousWidth: ambiguous);
        for (final text in texts) {
          for (final overflow in TextOverflow.values) {
            for (var width = -1; width <= 30; width++) {
              expect(
                fitText(seg, text, width, overflow: overflow),
                reference(seg, text, width, overflow),
                reason: '$text / $width / $overflow',
              );
            }
          }
        }
      });
    }
  }
}
