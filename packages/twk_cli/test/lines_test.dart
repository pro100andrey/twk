import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_cli/src/lines.dart';
import 'package:twk_cli/twk_cli.dart';

List<String> _texts(List<List<Span>> lines) => [
  for (final line in lines) line.map((s) => s.text).join(),
];

void main() {
  group('messageLines', () {
    test('a string is read as a terminal shows it', () {
      final lines = messageLines(
        '\x1B[1mbold\x1B[0m plain\x1B[2J',
        const Style(),
      );
      expect(_texts(lines), ['bold plain']);
      expect(lines.single.first.style.attrs, Attr.bold);
      expect(lines.single.last.style.attrs, 0);
    });

    test('a carriage return writes over the line, as a progress line', () {
      expect(_texts(messageLines('10%\r50%\r100%', const Style())), ['100%']);
    });

    test('lines break at line breaks, not one at the end', () {
      expect(_texts(messageLines('a\nb', const Style())), ['a', 'b']);
      expect(_texts(messageLines('a\n', const Style())), ['a']);
      expect(_texts(messageLines('a\n\n', const Style())), ['a', '']);
      expect(_texts(messageLines('', const Style())), ['']);
      expect(_texts(messageLines(null, const Style())), ['']);
    });

    test('spans and lists of them, strings among them', () {
      final lines = messageLines([
        'Saved'.bold,
        ' to ',
        ['disk'.fg(Color.green), '\n', 'done'],
      ], const Style());
      expect(_texts(lines), ['Saved to disk', 'done']);
      expect(lines.first.last.style.fg, Color.green);
    });

    test('anything else by its toString', () {
      expect(_texts(messageLines(42, const Style())), ['42']);
      expect(_texts(messageLines(Uri.parse('a:b'), const Style())), ['a:b']);
    });

    test("the channel's style goes under the message's", () {
      final lines = messageLines([
        'red',
        'green'.fg(Color.green),
      ], const Style(fg: Color.red, attrs: Attr.bold));
      expect(lines.single[0].style.fg, Color.red);
      expect(lines.single[1].style.fg, Color.green);
      expect(lines.single[1].style.attrs, Attr.bold);
    });
  });

  group('encodeLine', () {
    test('the text alone without ANSI', () {
      expect(
        encodeLine(['a'.bold, const Span('b')], ansi: false),
        'ab',
      );
    });

    test('colors in the color mode', () {
      final line = ['x'.fg(const Color.rgb(255, 0, 0))];
      expect(encodeLine(line, ansi: true), '\x1B[38;2;255;0;0mx\x1B[0m');
      expect(
        encodeLine(line, ansi: true, colorMode: ColorMode.ansi256),
        '\x1B[38;5;196mx\x1B[0m',
      );
    });

    test('a styled underline a plain one where the terminal shows none', () {
      final line = ['x'.curlyUnderline];
      expect(encodeLine(line, ansi: true), '\x1B[4:3mx\x1B[0m');
      // Terminal.app reads 4:3 as 43, a yellow background
      expect(
        encodeLine(line, ansi: true, styledUnderlines: false),
        '\x1B[4mx\x1B[0m',
      );
    });

    test('links only where hyperlinks are taken', () {
      final line = ['dart'.link('https://dart.dev')];
      expect(encodeLine(line, ansi: true), 'dart');
      expect(
        encodeLine(line, ansi: true, hyperlinks: true),
        '\x1B]8;;https://dart.dev\x1B\\dart\x1B]8;;\x1B\\',
      );
    });

    test('a link percent-encoded past printable ASCII, as the presenter '
        'writes it, so it cannot end the sequence early', () {
      final line = ['café'.link('https://x.dev/café a\x07\x1B\\b')];
      expect(
        encodeLine(line, ansi: true, hyperlinks: true),
        '\x1B]8;;https://x.dev/caf%C3%A9%20a%07%1B\\b\x1B\\café'
        '\x1B]8;;\x1B\\',
      );
    });
  });

  group('widgetLines', () {
    test('as tall as the widget, the blanks at the ends of rows left out', () {
      expect(
        widgetLines(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('a'), Text('bc')],
          ),
          10,
        ),
        ['a', 'bc'],
      );
    });

    test('nothing for a widget of no height or no width', () {
      expect(widgetLines(const SizedBox(), 10), isEmpty);
      expect(widgetLines(const Text('a'), 0), isEmpty);
    });

    test('a background shown to the end of the row with ANSI', () {
      expect(
        widgetLines(
          const ColoredBox(
            color: Color.blue,
            child: SizedBox(height: 1, child: Text('a')),
          ),
          3,
          ansi: true,
        ),
        ['\x1B[44ma  \x1B[0m'],
      );
    });

    test('a styled underline of a row a plain one where the terminal shows '
        'none', () {
      expect(
        widgetLines(
          Text.rich(['x'.dottedUnderline]),
          1,
          ansi: true,
          styledUnderlines: false,
        ),
        ['\x1B[4mx\x1B[0m'],
      );
    });

    test('a link of a row percent-encoded past printable ASCII', () {
      expect(
        widgetLines(
          Text.rich(['é'.link('https://x.dev/é\x07')]),
          3,
          ansi: true,
          hyperlinks: true,
        ),
        ['\x1B]8;;https://x.dev/%C3%A9%07\x1B\\é\x1B]8;;\x1B\\'],
      );
    });

    test('disposes what it built', () {
      var disposed = false;
      widgetLines(_Disposes(() => disposed = true), 10);
      expect(disposed, isTrue);
    });
  });

  test('the console exports messageLines', () {
    expect(_texts(messageLines('x', const CliTheme().info)), ['x']);
  });
}

final class _Disposes extends StatefulWidget {
  const _Disposes(this.onDispose);

  final void Function() onDispose;

  @override
  State<_Disposes> createState() => _DisposesState();
}

final class _DisposesState extends State<_Disposes> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('x');
}
