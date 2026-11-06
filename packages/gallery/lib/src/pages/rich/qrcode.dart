// The QrCode page.
part of 'rich.dart';

/// The texts the QrCode page encodes, by the names its option gives them.
const _qrTexts = {
  'link': 'https://pub.dev/packages/twk',
  'wifi': 'WIFI:S:twk;T:WPA;P:secret;;',
  'digits': '20261019',
};

/// How many times the QrCode page has run [QrSymbol.encode]: its tests
/// count them.
var qrEncodes = 0;

/// The symbols the QrCode page has encoded, by text and level: its build
/// and its heightIn draw the same one, and a choice made again finds it.
final _qrSymbols = <(String, QrErrorCorrection), QrSymbol>{};

/// The symbol the QrCode page draws, with the options at [o].
QrSymbol _qrSymbolOf(Options o) {
  final text = _qrTexts[o(_qrCodeText)]!;
  final level = QrErrorCorrection.values.byName(o(_qrCodeLevel));
  return _qrSymbols[(text, level)] ??= () {
    qrEncodes++;
    return QrSymbol.encode(text, level: level);
  }();
}

/// The quiet zone the QrCode page gives [symbol] in [rows]: the option's
/// [quiet] modules, fewer where the symbol with them would be taller, so
/// that the whole symbol shows (as its Code's LayoutBuilder works it out).
int _qrQuietIn(QrSymbol symbol, int quiet, int rows) =>
    ((2 * rows - symbol.size) ~/ 2).clamp(0, quiet);

/// The rows of [symbol] without a quiet zone.
int _qrLeast(QrSymbol symbol) => (symbol.size + 1) ~/ 2;

/// The QrCode page's `text` option.
const _qrCodeText = ChoiceOption<String>(
  'text',
  'text',
  values: ['link', 'wifi', 'digits'],
  initial: 'digits',
);

/// The QrCode page's `level` option.
const _qrCodeLevel = ChoiceOption<String>(
  'level',
  'level',
  values: ['low', 'medium', 'quartile', 'high'],
  initial: 'medium',
);

/// The QrCode page's `quiet` option.
final _qrCodeQuiet = SliderOption(
  'quiet',
  'quiet zone',
  min: 0,
  max: 4,
  initial: 4,
  format: (v) => '$v modules',
);

/// The QrCode page's `invert` option.
const _qrCodeInvert = SwitchOption('invert', 'inverted');

final _qrCode = GalleryPage(
  group: _group,
  title: 'QrCode',
  options: [
    // the smallest symbol first: version 1, which a screen of 24 rows
    // shows whole
    _qrCodeText,
    _qrCodeLevel,
    _qrCodeQuiet,
    // light modules on dark: what fewer scanners read
    _qrCodeInvert,
  ],
  build: (context, o) {
    final theme = Theme.of(context);
    final symbol = _qrSymbolOf(o);
    final quiet = o(_qrCodeQuiet).toInt();
    final invert = o(_qrCodeInvert);
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          QrCode.symbol(
            symbol,
            quietZone: _qrQuietIn(symbol, quiet, constraints.maxHeight),
            dark: invert ? QrCode.white : QrCode.black,
            light: invert ? QrCode.black : QrCode.white,
          ),
          Text.rich([
            Span('version ', theme.muted),
            Span('${symbol.version}\n'),
            Span('mask ', theme.muted),
            Span('${symbol.mask}\n'),
            Span('mode ', theme.muted),
            Span(symbol.mode.name),
            // taller than the room even without a quiet zone, so cut off
            // at its bottom: the rows it needs
            if (_qrLeast(symbol) > constraints.maxHeight) ...[
              Span('\n\nneeds ', theme.warning),
              Span('${_qrLeast(symbol)} rows'),
            ],
          ]),
        ],
      ),
    );
  },
  // all of it asked for, as the design's size: the code's rows, its quiet
  // zone narrowed to the room, the three lines beside it; a symbol taller
  // than the room even without one is cut off at its bottom
  heightIn: (o, room) {
    final symbol = _qrSymbolOf(o);
    final quiet = _qrQuietIn(symbol, o(_qrCodeQuiet).toInt(), room.height);
    return math.max((symbol.size + 2 * quiet + 1) ~/ 2, 3);
  },
  code: (o) {
    final text = _qrTexts[o(_qrCodeText)];
    final level = o(_qrCodeLevel);
    final quiet = o(_qrCodeQuiet).toInt();
    final one = "  final symbol = QrSymbol.encode('$text', level: .$level);";
    // the quiet zone that leaves the symbol whole in the rows there are
    final zone = quiet == 0
        ? '0'
        : '((2 * constraints.maxHeight - symbol.size) ~/ 2).clamp(0, $quiet)';
    return [
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  // the mode of fewest bits, the smallest version, the',
      '  // mask the penalty rules score lowest',
      if (one.length <= 80)
        one
      else ...[
        '  final symbol = QrSymbol.encode(',
        "    '$text',",
        '    level: .$level,',
        '  );',
      ],
      '  return LayoutBuilder(',
      '    builder: (context, constraints) => Row(',
      '      mainAxisSize: .min,',
      '      crossAxisAlignment: .start,',
      '      spacing: 2,',
      '      children: [',
      if (o(_qrCodeInvert))
        '        // in half blocks, white on black; in fewer rows than it'
      else
        '        // in half blocks, black on white; in fewer rows than it',
      '        // asks for, a narrower quiet zone, the whole symbol shown',
      '        QrCode.symbol(',
      '          symbol,',
      '          quietZone: $zone,',
      if (o(_qrCodeInvert)) ...[
        '          dark: QrCode.white,',
        '          light: QrCode.black,',
      ],
      '        ),',
      '        Text.rich([',
      "          Span('version ', theme.muted),",
      r"          Span('${symbol.version}\n'),",
      "          Span('mask ', theme.muted),",
      r"          Span('${symbol.mask}\n'),",
      "          Span('mode ', theme.muted),",
      '          Span(symbol.mode.name),',
      '          // taller than the rows there are even without a quiet',
      "          // zone: cut off at its bottom, which a camera can't read",
      '          if ((symbol.size + 1) ~/ 2 > constraints.maxHeight) ...[',
      r"            Span('\n\nneeds ', theme.warning),",
      r"            Span('${(symbol.size + 1) ~/ 2} rows'),",
      '          ],',
      '        ]),',
      '      ],',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);
