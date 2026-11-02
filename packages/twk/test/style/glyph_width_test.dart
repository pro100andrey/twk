// One width rule for every theme mark: a mark that is not one cell wide, or
// is a cluster of more than one code point, is Glyphs.ascii's mark of the
// same meaning with one warning, drawn as text (a radio button, a switch, a
// checkbox, a button's edge) as it is filled into a cell. Glyphs' copyWith,
// == and hashCode cover every field.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

List<String> warnings(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level == LogLevel.warning && r.message.startsWith('Glyphs.'))
      r.message,
];

const accent = 'é'; // one column, two code points

Widget radios(Glyphs glyphs, {String chosen = 'a'}) => themed(
  glyphs,
  RadioGroup<String>(
    value: chosen,
    choices: const [Choice('a', 'A'), Choice('b', 'B')],
    onChanged: (_) {},
  ),
);

void main() {
  group('text marks', () {
    testTwk('the default marks draw as they did, with no warning', (t) async {
      await t.pumpWidget(radios(Glyphs.unicode), size: (8, 2));
      expect(t.lines, ['(●) A', '( ) B']);
      expect(warnings(t), isEmpty);
    });

    testTwk('a wide radioOn is the ASCII one, so the columns align', (
      t,
    ) async {
      await t.pumpWidget(
        radios(Glyphs.unicode.copyWith(radioOn: '🙂')),
        size: (8, 2),
      );
      expect(t.lines, ['(*) A', '( ) B']);
      expect(
        warnings(t).single,
        "Glyphs.radioOn '🙂' is 2 cells wide, not 1; Glyphs.ascii's '*' is "
        'drawn in its place.',
      );
      // once, however many frames
      await t.pumpWidget(
        radios(Glyphs.unicode.copyWith(radioOn: '🙂'), chosen: 'b'),
        size: (8, 2),
      );
      expect(warnings(t), hasLength(1));
    });

    testTwk('a cluster of two code points is not one cell either', (t) async {
      await t.pumpWidget(
        radios(Glyphs.unicode.copyWith(radioOn: accent)),
        size: (8, 2),
      );
      expect(t.lines.first, startsWith('(*) A'));
      expect(
        warnings(t).single,
        "Glyphs.radioOn '$accent' is a cluster of 2 code points, not one; "
        "Glyphs.ascii's '*' is drawn in its place.",
      );
    });

    testTwk('a wide radioOff is a blank, an empty one stays empty', (t) async {
      await t.pumpWidget(
        radios(Glyphs.unicode.copyWith(radioOff: '🙂')),
        size: (8, 2),
      );
      expect(t.lines, ['(●) A', '( ) B']);
      expect(warnings(t), hasLength(1));
    });

    testTwk('a wide switch knob and ends are the ASCII ones', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(
            switchKnob: '🙂',
            switchStart: accent,
            switchEnd: '🙂',
          ),
          Switch(value: true, onChanged: (_) {}),
        ),
        size: (5, 1),
      );
      expect(t.lines.single, '[  *]');
      expect(warnings(t), hasLength(3));
    });

    testTwk('an empty knob is a blank, the track keeps its width', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(switchKnob: ''),
          Switch(value: true, onChanged: (_) {}),
        ),
        size: (5, 1),
      );
      expect(t.lines.single, '▐   ▌');
      expect(warnings(t), isEmpty);
    });

    testTwk('a checkbox mark of two columns is the ASCII one, brackets kept', (
      t,
    ) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(checkboxOn: '🙂'),
          Checkbox(value: true, onChanged: (_) {}),
        ),
        size: (5, 1),
      );
      expect(t.lines.single.trimRight(), '[x]');
      expect(warnings(t), hasLength(1));
      // brackets of one cell stay
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(checkboxBrackets: ('<', '>')),
          Checkbox(value: true, onChanged: (_) {}),
        ),
        size: (5, 1),
      );
      expect(t.lines.single.trimRight(), '<x>');
      expect(warnings(t), hasLength(1));
    });

    testTwk('a MultiSelect with boxes of two widths lists the ASCII pair', (
      t,
    ) async {
      final values = ValueNotifier(<String>{'a'});
      addTearDown(values.dispose);
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(checkboxOn: '🙂'),
          Overlay(
            child: MultiSelect<String>(
              choices: const [Choice('a', 'Apple'), Choice('b', 'Banana')],
              values: values.value,
              onChanged: (_) {},
              hint: 'none',
              autofocus: true,
            ),
          ),
        ),
        size: (24, 4),
      );
      await t.press('enter');
      await t.pumpUntilIdle();
      final text = t.lines.join('\n');
      expect(text, contains('[x] Apple'));
      expect(text, contains('[ ] Banana'));
      expect(text, isNot(contains('🙂')));
      expect(warnings(t), hasLength(1));
    });

    testTwk('a multiple SelectionList with boxes of two widths shows the '
        'ASCII pair', (t) async {
      final c = SelectionController<String>(multiple: true, selected: ['a']);
      addTearDown(c.dispose);
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(checkboxOn: '🙂'),
          SelectionList<String>(
            itemCount: 2,
            keyOf: (i) => '$i',
            itemBuilder: (context, i) => Text(['a', 'b'][i]),
            controller: c,
          ),
        ),
        size: (8, 2),
      );
      expect(t.lines.first, startsWith(' [ ] a'));
      expect(t.lines.join(), isNot(contains('🙂')));
      expect(warnings(t), hasLength(1));
    });

    testTwk('a multiple FilePicker with boxes of two widths shows the ASCII '
        'pair, a directory a blank as wide', (t) async {
      final dir = Directory.systemTemp.createTempSync('glyph_width_');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/dd').createSync();
      File('${dir.path}/ff').writeAsStringSync('x');
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(checkboxOff: '🙂'),
          Overlay(
            child: FilePicker(
              onPicked: (_) {},
              directory: dir.path,
              multiple: true,
              autofocus: true,
            ),
          ),
        ),
        size: (40, 12),
      );
      await waitUntil(
        () => t.lines.any((l) => l.contains('[ ] ff')),
        'the listing',
        between: t.pump,
      );
      final file = t.lines.firstWhere((l) => l.contains('[ ] ff'));
      final directory = t.lines.firstWhere((l) => l.contains('dd'));
      expect(directory.indexOf('dd'), file.indexOf('ff'));
      expect(t.lines.join(), isNot(contains('🙂')));
      expect(warnings(t), hasLength(1));
    });

    testTwk('a button edge that does not fit is the ASCII edge', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(buttonEdges: ('🙂', accent)),
          Button.outlined('Go', onPressed: () {}),
        ),
        size: (8, 1),
      );
      expect(t.lines.single, startsWith('[  Go  ]'));
      expect(warnings(t), hasLength(2));
    });

    testTwk('empty button edges are no edges, not separators', (t) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(buttonEdges: ('', '')),
          Button.outlined('Go', onPressed: () {}),
        ),
        size: (8, 1),
      );
      expect(t.lines.single, '   Go');
      expect(t.lines.single, isNot(contains('│')));
      expect(warnings(t), isEmpty);
    });
  });

  group('cells', () {
    testTwk('a cluster of two code points filled into a cell is ASCII', (
      t,
    ) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(gaugeFilled: accent),
          const SizedBox(width: 10, height: 1, child: LineGauge(ratio: 0.45)),
        ),
        size: (10, 1),
      );
      expect(t.lines.single, startsWith('====╴'));
      expect(warnings(t), hasLength(1));
    });
  });

  group('the fields', () {
    // every field of the constructor, with a value that is not its default
    final changes = <String, Glyphs Function(Glyphs, String)>{
      'cursor': (g, v) => g.copyWith(cursor: v),
      'accent': (g, v) => g.copyWith(accent: v),
      'check': (g, v) => g.copyWith(check: v),
      'checkBold': (g, v) => g.copyWith(checkBold: v),
      'cross': (g, v) => g.copyWith(cross: v),
      'info': (g, v) => g.copyWith(info: v),
      'warning': (g, v) => g.copyWith(warning: v),
      'checkboxOn': (g, v) => g.copyWith(checkboxOn: v),
      'checkboxOff': (g, v) => g.copyWith(checkboxOff: v),
      'checkboxBrackets': (g, v) => g.copyWith(checkboxBrackets: (v, v)),
      'radioOn': (g, v) => g.copyWith(radioOn: v),
      'radioOff': (g, v) => g.copyWith(radioOff: v),
      'radioBrackets': (g, v) => g.copyWith(radioBrackets: (v, v)),
      'switchStart': (g, v) => g.copyWith(switchStart: v),
      'switchEnd': (g, v) => g.copyWith(switchEnd: v),
      'switchKnob': (g, v) => g.copyWith(switchKnob: v),
      'stepCurrent': (g, v) => g.copyWith(stepCurrent: v),
      'ring': (g, v) => g.copyWith(ring: v),
      'expanded': (g, v) => g.copyWith(expanded: v),
      'collapsed': (g, v) => g.copyWith(collapsed: v),
      'up': (g, v) => g.copyWith(up: v),
      'down': (g, v) => g.copyWith(down: v),
      'previous': (g, v) => g.copyWith(previous: v),
      'next': (g, v) => g.copyWith(next: v),
      'first': (g, v) => g.copyWith(first: v),
      'last': (g, v) => g.copyWith(last: v),
      'close': (g, v) => g.copyWith(close: v),
      'maximise': (g, v) => g.copyWith(maximise: v),
      'restore': (g, v) => g.copyWith(restore: v),
      'minimise': (g, v) => g.copyWith(minimise: v),
      'bullet': (g, v) => g.copyWith(bullet: v),
      'taskPending': (g, v) => g.copyWith(taskPending: v),
      'taskSkipped': (g, v) => g.copyWith(taskSkipped: v),
      'separator': (g, v) => g.copyWith(separator: v),
      'buttonEdges': (g, v) => g.copyWith(buttonEdges: (v, v)),
      'trackVertical': (g, v) => g.copyWith(trackVertical: v),
      'trackHorizontal': (g, v) => g.copyWith(trackHorizontal: v),
      'thumbVertical': (g, v) => g.copyWith(thumbVertical: v),
      'thumbHorizontal': (g, v) => g.copyWith(thumbHorizontal: v),
      'thumbSlim': (g, v) => g.copyWith(thumbSlim: v),
      'partialBlocks': (g, v) => g.copyWith(partialBlocks: false),
      'gaugeFilled': (g, v) => g.copyWith(gaugeFilled: v),
      'gaugeHalf': (g, v) => g.copyWith(gaugeHalf: v),
      'gaugeEmpty': (g, v) => g.copyWith(gaugeEmpty: v),
      'spinner': (g, v) => g.copyWith(spinner: SpinnerFrames.line),
      'lines': (g, v) => g.copyWith(lines: BorderType.double),
      'arrowLeft': (g, v) => g.copyWith(arrowLeft: v),
      'arrowRight': (g, v) => g.copyWith(arrowRight: v),
      'arrowUp': (g, v) => g.copyWith(arrowUp: v),
      'arrowDown': (g, v) => g.copyWith(arrowDown: v),
      'pointer': (g, v) => g.copyWith(pointer: v),
      'menu': (g, v) => g.copyWith(menu: v),
      'shades': (g, v) => g.copyWith(shades: [' ', v]),
      'swatch': (g, v) => g.copyWith(swatch: v),
      'ellipsis': (g, v) => g.copyWith(ellipsis: v),
      'omitted': (g, v) => g.copyWith(omitted: v),
    };

    test('the table names every field of the constructor', () {
      final source = File('lib/src/style/glyphs.dart').readAsStringSync();
      final start = source.indexOf('const Glyphs({');
      final end = source.indexOf('});', start);
      final fields = {
        for (final m in RegExp(
          r'this\.(\w+)',
        ).allMatches(source.substring(start, end)))
          m.group(1)!,
      };
      expect(fields.length, 56);
      expect(changes.keys.toSet(), fields);
    });

    for (final MapEntry(:key, :value) in changes.entries) {
      test('$key: copyWith changes it alone, == and hashCode see it', () {
        const base = Glyphs.unicode;
        final changed = value(base, '§');
        expect(changed, isNot(base), reason: '$key is in ==');
        expect(
          changed.hashCode,
          isNot(base.hashCode),
          reason: '$key is in the hash',
        );
        // the others are kept: undoing it with the base's value gives the base
        expect(
          changed,
          isNot(value(Glyphs.ascii, '§')),
          reason: 'the others are kept by $key',
        );
        expect(value(base, '§'), changed);
        expect(value(base, '§').hashCode, changed.hashCode);
      });
    }
  });
}
