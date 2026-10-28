// Status messages and badges in the colors of their kinds, and links as
// OSC 8 hyperlinks the emulator reads back.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [children] one below another at their left edge.
Column column(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

void main() {
  group('StatusMessage', () {
    testTwk("shows the message after its kind's icon, in the kind's color "
        'and bold', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: column([
            for (final kind in StatusKind.values)
              StatusMessage('${kind.name} said', kind: kind),
          ]),
        ),
        size: (20, 4),
      );
      expect(t.lines, [
        'ℹ info said',
        '✓ success said',
        '⚠ warning said',
        '✗ error said',
      ]);
      final colors = [Color.cyan, Color.green, Color.yellow, Color.red];
      for (var y = 0; y < 4; y++) {
        expect(
          t,
          styleAt(0, y, allOf(hasFg(colors[y]), hasAttr(Attr.bold))),
        );
        expect(t, styleAt(2, y, isNot(hasAttr(Attr.bold))));
      }
    });

    testTwk('puts a title after the icon and the message below it, which '
        'wraps under itself', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: column([
            const StatusMessage(
              'the disk is almost full',
              kind: StatusKind.warning,
              title: 'Disk',
            ),
            const StatusMessage(
              'fine',
              icon: '*',
              style: Style(attrs: Attr.italic),
            ),
          ]),
        ),
        size: (14, 5),
      );
      expect(t.lines, [
        '⚠ Disk',
        '  the disk is',
        '  almost full',
        '* fine',
        '',
      ]);
      expect(t, styleAt(2, 0, allOf(hasFg(Color.yellow), hasAttr(Attr.bold))));
      expect(t, styleAt(0, 3, hasFg(Color.cyan)));
      expect(t, styleAt(2, 3, hasAttr(Attr.italic)));
    });
  });

  group('Badge', () {
    testTwk("shows its label set off by the primary color, or its kind's, "
        'reversed and bold', (t) async {
      await t.pumpWidget(
        const Theme.terminal(
          child: Row(
            gap: 1,
            children: [
              Badge('3'),
              Badge('failed', kind: StatusKind.error),
              Badge('x', style: Style(attrs: Attr.italic)),
            ],
          ),
        ),
        size: (20, 1),
      );
      expect(t.lines, [' 3   failed   x']);
      expect(
        t,
        styleAt(
          0,
          0,
          allOf(
            hasBg(Color.blue),
            hasFg(const Color.rgb(255, 255, 255)),
            hasAttr(Attr.bold),
          ),
        ),
      );
      expect(t, styleAt(4, 0, hasBg(Color.red)));
      expect(t, styleAt(13, 0, hasAttr(Attr.italic)));
    });
  });

  group('Link', () {
    testTwk('links its text to the URL as an OSC 8 hyperlink, underlined in '
        'the primary color; the URL itself without a text', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: column([
            const Link('https://dart.dev', text: 'Dart'),
            const Link('https://pub.dev'),
            const Text('plain'),
          ]),
        ),
        size: (20, 3),
      );
      expect(t.lines, ['Dart', 'https://pub.dev', 'plain']);
      expect(t.cell(0, 0).link, 'https://dart.dev');
      expect(t.cell(3, 0).link, 'https://dart.dev');
      expect(t.cell(4, 0).link, isNull);
      expect(t.cell(14, 1).link, 'https://pub.dev');
      expect(t.cell(0, 2).link, isNull);
      expect(
        t,
        styleAt(0, 0, allOf(hasFg(Color.blue), hasAttr(Attr.underline))),
      );
      final written = utf8.decode(t.terminal.frames.expand((f) => f).toList());
      expect(written, contains('\x1b]8;;https://dart.dev\x1b\\Dart'));
    });

    testTwk('keeps the link under a style of its own', (t) async {
      await t.pumpWidget(
        const Theme.terminal(
          child: Link(
            'https://dart.dev',
            text: 'Dart',
            style: Style(fg: Color.green),
          ),
        ),
        size: (10, 1),
      );
      expect(t.cell(1, 0).link, 'https://dart.dev');
      expect(
        t,
        styleAt(
          1,
          0,
          allOf(hasFg(Color.green), isNot(hasAttr(Attr.underline))),
        ),
      );
    });
  });
}
