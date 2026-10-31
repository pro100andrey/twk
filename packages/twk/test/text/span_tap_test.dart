// Span.tap: a click on a span calls its onTap, with no OSC 8 link in the
// text; the span it is on among several, on a wrapped line, with a
// gradient, in a SelectionArea; beside it, released elsewhere or with
// another button it calls nothing; it follows the widget as it is built
// again, and the terminal reports the buttons only while a span has one;
// together with onLinkTap both are told.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';

/// `open one or two.` with the two names tapped.
Text phrases(List<String> log) => Text.rich([
  const Span('open '),
  'one'.tap(() => log.add('one')),
  const Span(' or '),
  'two'.underline.tap(() => log.add('two')),
  const Span('.'),
]);

void main() {
  group('Span.tap', () {
    testTwk('a click on a span calls its own tap and no other; the text '
        'is no hyperlink', (t) async {
      final log = <String>[];
      await t.pumpWidget(phrases(log), size: (20, 3));
      expect(t.lines.first, 'open one or two.');
      await t.click(5, 0);
      await t.click(7, 0);
      await t.click(12, 0);
      await t.click(0, 0);
      await t.click(8, 0);
      await t.click(15, 0);
      await t.click(2, 1);
      expect(log, ['one', 'one', 'two']);
      expect(t.cell(5, 0).link, isNull);
    });

    testTwk('a press released elsewhere, or with another button, is no '
        'tap', (t) async {
      final log = <String>[];
      await t.pumpWidget(phrases(log), size: (20, 3));
      await t.mouse(MouseKind.down, 5, 0);
      await t.mouse(MouseKind.up, 6, 0);
      await t.click(5, 0, button: 2);
      expect(log, isEmpty);
    });

    testTwk('on a wrapped line, with a gradient, in a SelectionArea', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        SelectionArea(
          child: Text.rich([
            const Span('read the '),
            const Span.gradient(
              'docs',
              Gradient([Color.red, Color.blue]),
            ).tap(() => log.add('docs')),
          ]),
        ),
        size: (10, 3),
      );
      expect(t.lines.take(2), ['read the', 'docs']);
      await t.click(1, 1);
      await t.click(5, 0);
      expect(log, ['docs']);
    });

    testTwk('follows the spans built: none, a tap, another, none', (
      t,
    ) async {
      final first = <String>[];
      final second = <String>[];
      final which = ValueNotifier<List<String>?>(null);
      await t.pumpWidget(
        ValueListenableBuilder(
          valueListenable: which,
          builder: (_, log, _) => log == null
              ? const Text('go')
              : Text.rich(['go'.tap(() => log.add('go'))]),
        ),
        size: (20, 3),
      );
      expect(t.terminal.mouseTracking, MouseTracking.off);
      which.value = first;
      await t.pump();
      expect(t.terminal.mouseTracking, MouseTracking.buttons);
      await t.click(0, 0);
      which.value = second;
      await t.pump();
      await t.click(0, 0);
      which.value = null;
      await t.pump();
      await t.click(0, 0);
      expect(first, ['go']);
      expect(second, ['go']);
      expect(t.terminal.mouseTracking, MouseTracking.off);
    });

    testTwk('a linked span with a tap tells both the tap and onLinkTap', (
      t,
    ) async {
      final log = <String>[];
      await t.pumpWidget(
        Text.rich(
          ['task'.link('bl-1').tap(() => log.add('tap'))],
          onLinkTap: log.add,
        ),
        size: (10, 1),
      );
      await t.click(1, 0);
      expect(log, ['tap', 'bl-1']);
    });

    test('a span with a tap is not equal to one without, nor to another', () {
      void a() {}
      expect(const Span('x').tap(a), const Span('x').tap(a));
      expect(const Span('x').tap(a), isNot(const Span('x')));
      expect(const Span('x').tap(a).bold.onTap, a, reason: 'kept by style');
    });
  });
}
