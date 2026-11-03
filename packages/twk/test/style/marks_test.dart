// The drawn mark of each theme field, whichever widget draws it: one width
// rule, one warning for each (field, glyph), and what an empty mark is as
// its descriptor says.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart'
    show PipelineOwner, RenderConstrainedBox, RenderObject;
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

/// A mark two columns wide everywhere.
const wide = '【';

/// Every mark of a set given as [mark].
Glyphs allAs(String mark) => Glyphs.unicode.copyWith(
  cursor: mark,
  accent: mark,
  check: mark,
  checkBold: mark,
  cross: mark,
  info: mark,
  warning: mark,
  checkboxOn: mark,
  checkboxOff: mark,
  checkboxBrackets: (mark, mark),
  shades: [mark, mark],
  radioOn: mark,
  radioOff: mark,
  radioBrackets: (mark, mark),
  switchStart: mark,
  switchEnd: mark,
  switchKnob: mark,
  stepCurrent: mark,
  ring: mark,
  expanded: mark,
  collapsed: mark,
  up: mark,
  down: mark,
  previous: mark,
  next: mark,
  close: mark,
  maximise: mark,
  restore: mark,
  minimise: mark,
  bullet: mark,
  taskPending: mark,
  taskSkipped: mark,
  separator: mark,
  buttonEdges: (mark, mark),
  trackVertical: mark,
  trackHorizontal: mark,
  thumbVertical: mark,
  thumbHorizontal: mark,
  thumbSlim: mark,
  gaugeFilled: mark,
  gaugeHalf: mark,
  gaugeEmpty: mark,
  arrowLeft: mark,
  arrowRight: mark,
  arrowUp: mark,
  arrowDown: mark,
  pointer: mark,
  menu: mark,
  swatch: mark,
);

/// [Marks.all] resolved in a widget: as text, and as the code point of a
/// cell.
({Map<Mark, String> text, Map<Mark, int?> cell}) resolve(
  BuildContext context,
) {
  final marks = ThemeMarks.of(context);
  return (
    text: {for (final m in Marks.all) m: marks.text(m)},
    cell: {for (final m in Marks.all) m: marks.cell(m)},
  );
}

Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

List<String> warnings(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level == LogLevel.warning) r.message,
];

void main() {
  test('every field of the set has one descriptor', () {
    final names = {for (final m in Marks.all) m.name};
    // the three pairs (brackets, button edges) are one field each
    expect(Marks.all, hasLength(52));
    expect(names, hasLength(49));
    expect(names, isNot(contains('ellipsis')));
  });

  test('a descriptor knows its field, its ASCII mark and its glyph', () {
    expect(Marks.close.name, 'close');
    expect(Marks.close.fallback, Glyphs.ascii.close);
    expect(Marks.close.of(Glyphs.unicode), '×');
    expect(Marks.checkboxClose.name, 'checkboxBrackets');
    expect(Marks.checkboxClose.fallback, ']');
    expect(Marks.buttonEdgeStart.of(Glyphs.unicode), '▕');
  });

  testTwk('a mark two columns wide is the ASCII one in text and in a cell, '
      'and warned of once for each field', (t) async {
    late ({Map<Mark, String> text, Map<Mark, int?> cell}) got;
    await t.pumpWidget(
      themed(
        allAs(wide),
        Builder(
          builder: (context) {
            got = resolve(context);
            return const SizedBox();
          },
        ),
      ),
    );
    for (final m in Marks.all) {
      expect(got.text[m], m.fallback, reason: '$m as text');
      final fallback = m.fallback;
      expect(
        got.cell[m],
        fallback.isEmpty ? null : fallback.runes.first,
        reason: '$m in a cell',
      );
    }
    final fields = {for (final m in Marks.all) m.name};
    expect(warnings(t), hasLength(fields.length));
    for (final field in fields) {
      expect(
        warnings(t).where((w) => w.startsWith("Glyphs.$field '$wide' is 2")),
        hasLength(1),
        reason: field,
      );
    }
  });

  testTwk('the warning is given once, whatever the asking and the '
      'rebuilding', (t) async {
    Widget app() => themed(
      Glyphs.unicode.copyWith(close: wide),
      Builder(
        builder: (context) {
          final marks = ThemeMarks.of(context);
          for (var i = 0; i < 3; i++) {
            expect(marks.text(Marks.close), 'x');
            expect(marks.cell(Marks.close), 'x'.codeUnitAt(0));
          }
          return Text(ThemeMarks.of(context).text(Marks.close));
        },
      ),
    );
    await t.pumpWidget(app());
    await t.pumpWidget(themed(Glyphs.unicode.copyWith(close: wide), app()));
    expect(warnings(t), hasLength(1));
  });

  testTwk('a custom mark of one column is kept', (t) async {
    late ({Map<Mark, String> text, Map<Mark, int?> cell}) got;
    await t.pumpWidget(
      themed(
        allAs('λ'),
        Builder(
          builder: (context) {
            got = resolve(context);
            return const SizedBox();
          },
        ),
      ),
    );
    for (final m in Marks.all) {
      expect(got.text[m], 'λ', reason: '$m');
      expect(got.cell[m], 'λ'.runes.first, reason: '$m');
    }
    expect(warnings(t), isEmpty);
  });

  testTwk('a cluster of two code points is the ASCII mark', (t) async {
    late String got;
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(ring: 'é'),
        Builder(
          builder: (context) {
            got = ThemeMarks.of(context).text(Marks.ring);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(got, 'o');
    expect(warnings(t), hasLength(1));
  });

  testTwk('an empty mark is what its descriptor says, with no warning', (
    t,
  ) async {
    late ({Map<Mark, String> text, Map<Mark, int?> cell}) got;
    await t.pumpWidget(
      themed(
        allAs(''),
        Builder(
          builder: (context) {
            got = resolve(context);
            return const SizedBox();
          },
        ),
      ),
    );
    for (final m in Marks.all) {
      switch (m.onEmpty) {
        case OnEmpty.blank:
          expect(got.text[m], ' ', reason: '$m');
          expect(got.cell[m], 0x20, reason: '$m');
        case OnEmpty.none:
          expect(got.text[m], '', reason: '$m');
          expect(got.cell[m], isNull, reason: '$m');
        case OnEmpty.fallback:
          expect(got.text[m], m.fallback, reason: '$m');
          expect(got.cell[m], m.fallback.runes.first, reason: '$m');
      }
    }
    expect(warnings(t), isEmpty);
    expect(Marks.switchKnob.onEmpty, OnEmpty.blank);
    expect(Marks.gaugeHalf.onEmpty, OnEmpty.none);
    expect(Marks.thumbVertical.onEmpty, OnEmpty.fallback);
  });

  test('on an ambiguous-wide terminal the marks that are ambiguous are '
      'ASCII, with the one line naming the terminal', () async {
    late ({Map<Mark, String> text, Map<Mark, int?> cell}) got;
    final app = await WideApp.start(
      Builder(
        builder: (context) {
          got = resolve(context);
          return const SizedBox();
        },
      ),
    );
    final log = [
      for (final r in app.binding.twkApp.logs.records)
        if (r.level == LogLevel.warning) r.message,
    ];
    await app.quit();
    final seg = TextSegmenter(ambiguousWidth: 2);
    var swapped = 0;
    for (final m in Marks.all) {
      final own = m.of(Glyphs.unicode);
      final fits = own.isEmpty || seg.width(own) == 1;
      expect(got.text[m], fits ? own : m.fallback, reason: '$m as text');
      if (!fits) {
        swapped++;
      }
    }
    expect(swapped, greaterThan(5));
    expect(log, hasLength(1));
    expect(log.single, contains('ambiguous'));
  });

  test('the ASCII theme beats the border type of a line', () {
    final marks = ThemeMarks.ofObject(null, TextSegmenter());
    expect(marks.dash(BorderType.double, glyphs: Glyphs.ascii), '-');
    expect(marks.dash(BorderType.heavy, down: true, glyphs: Glyphs.ascii), '|');
    expect(marks.line(BorderType.rounded, glyphs: Glyphs.ascii), 0x2D);
    expect(marks.dash(null, glyphs: Glyphs.unicode), '─');
    expect(marks.dash(BorderType.double, glyphs: Glyphs.unicode), '═');
  });

  test('a line two columns wide is ASCII, and a shade list is a ramp', () {
    final marks = ThemeMarks.ofObject(null, TextSegmenter(ambiguousWidth: 2));
    expect(marks.dash(null, glyphs: Glyphs.unicode), '-');
    expect(ThemeMarks.ramp(Glyphs.unicode.copyWith()), Glyphs.unicode.shades);
    expect(ThemeMarks.ramp(const Glyphs(shades: [])), Glyphs.ascii.shades);
    expect(ThemeMarks.ramp(const Glyphs(shades: ['#'])), [' ', '#']);
  });

  test("a render object's marks warn to its own pipeline, though another "
      "object's asked for theirs after it", () {
    final seg = TextSegmenter();
    final logs = <String, List<String>>{'a': [], 'b': []};
    RenderObject objectOf(String name) {
      final object = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints(0, 1, 0, 1),
      );
      PipelineOwner(() {}, segmenter: seg)
        ..onLog = (r) {
          logs[name]!.add(r.message);
        }
        ..root = object;
      return object;
    }

    final a = ThemeMarks.ofObject(objectOf('a'), seg);
    ThemeMarks.ofObject(objectOf('b'), seg);
    a.cell(Marks.cursor, Glyphs.unicode.copyWith(cursor: '日'));
    expect(logs['a'], hasLength(1));
    expect(logs['b'], isEmpty);
  });

  test("a render object's marks take their glyphs with each mark, and say "
      'so where none are given', () {
    final marks = ThemeMarks.ofObject(null, TextSegmenter());
    expect(
      () => marks.cell(Marks.cursor),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '$e',
          'message',
          contains('ThemeMarks.ofObject'),
        ),
      ),
    );
    expect(marks.cell(Marks.cursor, Glyphs.ascii), isNotNull);
  });
}
