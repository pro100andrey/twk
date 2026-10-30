// SGR sequences and OSC 8 links: the style of the text written after them.
import 'package:test/test.dart';
import 'package:twk/twk.dart';

/// The style of `x` written after `CSI [params] m`.
Style after(String params) {
  final span = parseAnsi('\x1B[${params}mx').single.single;
  expect(span.text, 'x');
  return span.style;
}

void main() {
  group('colors', () {
    final cases = <(String, Style)>[
      ('31', const Style(fg: Color.red)),
      ('37', const Style(fg: Color.white)),
      ('90', const Style(fg: Color.brightBlack)),
      ('97', const Style(fg: Color.brightWhite)),
      ('40', const Style(bg: Color.black)),
      ('42', const Style(bg: Color.green)),
      ('100', const Style(bg: Color.brightBlack)),
      ('107', const Style(bg: Color.brightWhite)),
      ('38;5;208', const Style(fg: Color.indexed(208))),
      ('38:5:208', const Style(fg: Color.indexed(208))),
      ('48;5;17', const Style(bg: Color.indexed(17))),
      ('48:5:17', const Style(bg: Color.indexed(17))),
      ('38;2;255;128;0', const Style(fg: Color.rgb(255, 128, 0))),
      ('38:2::255:128:0', const Style(fg: Color.rgb(255, 128, 0))),
      ('38:2:255:128:0', const Style(fg: Color.rgb(255, 128, 0))),
      ('38:2:0:255:128:0', const Style(fg: Color.rgb(255, 128, 0))),
      ('48;2;1;2;3', const Style(bg: Color.rgb(1, 2, 3))),
      ('48:2::1:2:3', const Style(bg: Color.rgb(1, 2, 3))),
      ('38;2;;;', const Style(fg: Color.rgb(0, 0, 0))),
      ('58:5:9', const Style(underlineColor: Color.indexed(9))),
      ('58;5;9', const Style(underlineColor: Color.indexed(9))),
      ('58:2::1:2:3', const Style(underlineColor: Color.rgb(1, 2, 3))),
      ('58;2;1;2;3', const Style(underlineColor: Color.rgb(1, 2, 3))),
      ('31;42', const Style(fg: Color.red, bg: Color.green)),
      ('31;32', const Style(fg: Color.green)),
      ('38;5;1;1', const Style(fg: Color.red, attrs: Attr.bold)),
      (
        '38;2;1;2;3;4',
        const Style(fg: Color.rgb(1, 2, 3), attrs: Attr.underline),
      ),
      ('38:5:1;1', const Style(fg: Color.red, attrs: Attr.bold)),
    ];
    for (final (params, style) in cases) {
      test(params, () => expect(after(params), style));
    }
  });

  group('attributes', () {
    final cases = <(String, int)>[
      ('1', Attr.bold),
      ('2', Attr.dim),
      ('3', Attr.italic),
      ('4', Attr.underline),
      ('4:1', Attr.underline),
      ('4:2', Attr.doubleUnderline),
      ('4:3', Attr.curlyUnderline),
      ('4:4', Attr.dottedUnderline),
      ('4:5', Attr.dashedUnderline),
      ('21', Attr.doubleUnderline),
      ('5', Attr.blink),
      ('6', Attr.blink),
      ('7', Attr.reverse),
      ('8', Attr.hidden),
      ('9', Attr.strike),
      ('53', Attr.overline),
      ('1;2;3', Attr.bold | Attr.dim | Attr.italic),
      ('4:3;4', Attr.underline),
      ('4;4:2', Attr.doubleUnderline),
      ('4;21', Attr.doubleUnderline),
    ];
    for (final (params, attrs) in cases) {
      test(params, () => expect(after(params), Style(attrs: attrs)));
    }
  });

  group('resets', () {
    final cases = <(String, Style)>[
      ('', const Style()),
      ('0', const Style()),
      ('1;3;4;31;42;58:5:1;0', const Style()),
      ('1;31;', const Style()),
      ('31;39', const Style()),
      ('41;49', const Style()),
      ('58:5:1;59', const Style()),
      ('1;22', const Style()),
      ('2;22', const Style()),
      ('1;2;3;22', const Style(attrs: Attr.italic)),
      ('3;23', const Style()),
      ('4;24', const Style()),
      ('4:3;24', const Style()),
      ('4:3;4:0', const Style()),
      ('21;24', const Style()),
      ('5;25', const Style()),
      ('7;27', const Style()),
      ('8;28', const Style()),
      ('9;29', const Style()),
      ('53;55', const Style()),
      ('1;31;42;22;39', const Style(bg: Color.green)),
    ];
    for (final (params, style) in cases) {
      test('"$params"', () => expect(after(params), style));
    }
  });

  group('ignored', () {
    final cases = [
      '38;5',
      '38;2;1;2',
      '38;5;256',
      '38;2;1;2;300',
      '38:2::1:2:256',
      '38:5',
      '38:2:1:2',
      '38;9;1',
      '38;9;1;1',
      '1:2',
      '99999999999999999999',
      '38;5;99999999999999999999',
      '10',
      '26',
      '51',
      '73',
    ];
    for (final params in cases) {
      test(
        '"$params" sets nothing',
        () => expect(after(params), const Style()),
      );
    }

    test('only CSI m without a private marker or intermediate is SGR', () {
      for (final sequence in [
        '\x1B[>4;2m',
        '\x1B[?1m',
        '\x1B[<1m',
        '\x1B[=1m',
        '\x1B[1 m',
        '\x1B[1\$m',
        '\x1B[1;3n',
      ]) {
        expect(parseAnsi('${sequence}x'), [
          [const Span('x')],
        ], reason: sequence);
      }
    });
  });

  test('styles carry over to the next lines', () {
    expect(parseAnsi('\x1B[31ma\nb\x1B[0m\nc'), [
      [const Span('a', Style(fg: Color.red))],
      [const Span('b', Style(fg: Color.red))],
      [const Span('c')],
    ]);
  });

  test('text in one style is one span', () {
    expect(parseAnsi('a\x1B[31mb\x1B[39m\x1B[1;22mc\x1B[31md\x1B[32m\x1B[m'), [
      [
        const Span('a'),
        const Span('b', Style(fg: Color.red)),
        const Span('c'),
        const Span('d', Style(fg: Color.red)),
      ],
    ]);
  });

  test('the 8-bit CSI selects a rendition too', () {
    expect(parseAnsi('\u009B1mx'), [
      [const Span('x', Style(attrs: Attr.bold))],
    ]);
  });

  group('links', () {
    const url = 'https://x.dev/a?b=c;d';

    test('OSC 8 ended by ST', () {
      expect(parseAnsi('\x1B]8;;$url\x1B\\here\x1B]8;;\x1B\\ not'), [
        [const Span('here', Style(link: url)), const Span(' not')],
      ]);
    });

    test('OSC 8 ended by BEL, with parameters', () {
      expect(parseAnsi('\x1B]8;id=7:x=y;$url\x07here\x1B]8;;\x07 not'), [
        [const Span('here', Style(link: url)), const Span(' not')],
      ]);
    });

    test('OSC 8 in 8-bit controls', () {
      expect(parseAnsi('\u009D8;;$url\u009Chere\u009D8;;\u009C not'), [
        [const Span('here', Style(link: url)), const Span(' not')],
      ]);
    });

    test('a link spans lines and SGR resets', () {
      expect(parseAnsi('\x1B]8;;u\x07\x1B[1ma\n\x1B[0mb\x1B]8;;\x07c'), [
        [const Span('a', Style(attrs: Attr.bold, link: 'u'))],
        [const Span('b', Style(link: 'u')), const Span('c')],
      ]);
    });

    test('an OSC 8 without its parameters is ignored', () {
      expect(parseAnsi('\x1B]8;https://x.dev\x07here'), [
        [const Span('here')],
      ]);
    });

    test('controls in a target are dropped', () {
      expect(parseAnsi('\x1B]8;;ht\ttp:\x00//a\x7F\x07x'), [
        [const Span('x', Style(link: 'http://a'))],
      ]);
    });
  });
}
