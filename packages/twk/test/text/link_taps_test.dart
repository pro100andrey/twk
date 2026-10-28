// Text.rich's onLinkTap: a click on a span that links (Style.link) tells
// its link, one beside the text or on a span without one tells nothing; a
// press released elsewhere or with another button is no tap; in a
// SelectionArea, on a wrapped line or a span with a gradient it is still
// one; the callback follows the widget as it is built again, and the
// terminal reports the buttons only while there is one.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';

const dart = 'https://dart.dev';
const pub = 'https://pub.dev';

/// `see dart and pub.` with the two names linked.
Text links(void Function(String url)? onLinkTap) => Text.rich([
  const Span('see '),
  'dart'.link(dart),
  const Span(' and '),
  'pub'.link(pub).underline,
  const Span('.'),
], onLinkTap: onLinkTap);

void main() {
  group('Text.rich onLinkTap', () {
    testTwk('a click on a link tells its link', (t) async {
      final taps = <String>[];
      await t.pumpWidget(links(taps.add), size: (20, 3));
      expect(t.lines.first, 'see dart and pub.');
      await t.click(4, 0);
      await t.click(7, 0);
      await t.click(13, 0);
      await t.click(15, 0);
      expect(taps, [dart, dart, pub, pub]);
      expect(t.cell(4, 0).link, dart, reason: 'still a hyperlink');
    });

    testTwk('a click beside a link, or past the text, tells nothing', (
      t,
    ) async {
      final taps = <String>[];
      await t.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [links(taps.add)],
        ),
        size: (20, 3),
      );
      for (final (x, y) in [(0, 0), (3, 0), (8, 0), (12, 0), (16, 0)]) {
        await t.click(x, y);
      }
      await t.click(18, 0);
      await t.click(2, 1);
      expect(taps, isEmpty);
    });

    testTwk('a press released elsewhere, or with another button, is no '
        'tap', (t) async {
      final taps = <String>[];
      await t.pumpWidget(links(taps.add), size: (20, 3));
      await t.mouse(MouseKind.down, 4, 0);
      await t.mouse(MouseKind.drag, 5, 0);
      await t.mouse(MouseKind.up, 5, 0);
      await t.mouse(MouseKind.down, 4, 0);
      await t.mouse(MouseKind.up, 13, 0);
      await t.click(4, 0, button: 2);
      expect(taps, isEmpty);
    });

    testTwk('a link on a wrapped line, with a gradient, in a SelectionArea', (
      t,
    ) async {
      final taps = <String>[];
      await t.pumpWidget(
        SelectionArea(
          child: Text.rich(const [
            Span('read the '),
            Span.gradient(
              'docs',
              Gradient([Color.red, Color.blue]),
              Style(link: dart),
            ),
          ], onLinkTap: taps.add),
        ),
        size: (10, 3),
      );
      expect(t.lines.take(2), ['read the', 'docs']);
      await t.click(1, 1);
      await t.click(5, 0);
      expect(taps, [dart]);
    });

    testTwk('follows the callback built: none, another, none again', (
      t,
    ) async {
      final first = <String>[];
      final second = <String>[];
      final which = ValueNotifier<void Function(String)?>(null);
      await t.pumpWidget(
        ValueListenableBuilder(
          valueListenable: which,
          builder: (_, onLinkTap, _) => links(onLinkTap),
        ),
        size: (20, 3),
      );
      await t.click(4, 0);
      which.value = first.add;
      await t.pump();
      await t.click(4, 0);
      which.value = second.add;
      await t.pump();
      await t.click(13, 0);
      which.value = null;
      await t.pump();
      await t.click(13, 0);
      expect(first, [dart]);
      expect(second, [pub]);
    });

    testTwk('the terminal reports the buttons while a Text tells its '
        'taps: not without the callback, nor once the Text is gone', (
      t,
    ) async {
      final taps = <String>[];
      final shown = ValueNotifier<Widget>(links(null));
      await t.pumpWidget(
        ValueListenableBuilder(
          valueListenable: shown,
          builder: (_, child, _) => child,
        ),
        size: (20, 3),
      );
      expect(t.terminal.mouseTracking, MouseTracking.off);
      shown.value = links(taps.add);
      await t.pump();
      expect(t.terminal.mouseTracking, MouseTracking.buttons);
      shown.value = links(null);
      await t.pump();
      expect(t.terminal.mouseTracking, MouseTracking.off);
      shown.value = links(taps.add);
      await t.pump();
      expect(t.terminal.mouseTracking, MouseTracking.buttons);
      shown.value = const SizedBox();
      await t.pump();
      expect(t.terminal.mouseTracking, MouseTracking.off);
      await t.click(4, 0);
      expect(taps, isEmpty);
    });
  });
}
