// One switch for an ASCII app: the lines of the borders and the marks the
// widgets drew by themselves are fields of the set, so Glyphs.ascii makes
// them ASCII and Glyphs.unicode draws them as it always did.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

bool isAscii(List<String> lines) =>
    lines.every((l) => l.runes.every((r) => r < 0x80));

void main() {
  group('lines', () {
    test('the presets: single and ASCII', () {
      expect(Glyphs.unicode.lines, BorderType.single);
      expect(Glyphs.ascii.lines, BorderType.ascii);
    });

    test("borderOf: null is the set's, ASCII caps every line but none", () {
      expect(Glyphs.unicode.borderOf(null), BorderType.single);
      expect(Glyphs.unicode.borderOf(BorderType.rounded), BorderType.rounded);
      expect(Glyphs.ascii.borderOf(null), BorderType.ascii);
      for (final type in [
        BorderType.single,
        BorderType.rounded,
        BorderType.heavy,
        BorderType.double,
      ]) {
        expect(Glyphs.ascii.borderOf(type), BorderType.ascii);
      }
      expect(Glyphs.ascii.borderOf(BorderType.none), BorderType.none);
      final rounded = Glyphs.unicode.copyWith(lines: BorderType.rounded);
      expect(rounded.borderOf(null), BorderType.rounded);
      expect(rounded.borderOf(BorderType.heavy), BorderType.heavy);
    });

    const box = Box(
      border: Border.all(),
      child: SizedBox(width: 2, height: 1),
    );

    testTwk("a Box with no type draws the set's lines", (t) async {
      await t.pumpWidget(themed(Glyphs.unicode, box), size: (4, 3));
      expect(t.lines, ['┌──┐', '│  │', '└──┘']);
      await t.pumpWidget(themed(Glyphs.ascii, box), size: (4, 3));
      expect(t.lines, ['+--+', '|  |', '+--+']);
      await t.pumpWidget(
        themed(Glyphs.unicode.copyWith(lines: BorderType.rounded), box),
        size: (4, 3),
      );
      expect(t.lines, ['╭──╮', '│  │', '╰──╯']);
    });

    testTwk('a type of its own: kept in unicode, ASCII in ASCII', (t) async {
      const heavy = Box(
        border: Border.all(type: BorderType.heavy),
        child: SizedBox(width: 2, height: 1),
      );
      await t.pumpWidget(themed(Glyphs.unicode, heavy), size: (4, 3));
      expect(t.lines.first, '┏━━┓');
      await t.pumpWidget(themed(Glyphs.ascii, heavy), size: (4, 3));
      expect(t.lines.first, '+--+');
    });

    testTwk('Divider and VerticalDivider follow the set', (
      t,
    ) async {
      await t.pumpWidget(themed(Glyphs.ascii, const Divider()), size: (3, 1));
      expect(t.lines.single, '---');
      await t.pumpWidget(
        themed(Glyphs.ascii, const VerticalDivider()),
        size: (1, 2),
      );
      expect(t.lines, ['|', '|']);
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(lines: BorderType.double),
          const Divider(),
        ),
        size: (3, 1),
      );
      expect(t.lines.single, '═══');
    });

    testTwk('a Callout: its title dashes follow its lines', (t) async {
      const callout = Callout.text('hi', title: 'T');
      await t.pumpWidget(themed(Glyphs.unicode, callout), size: (12, 3));
      expect(t.lines.first, startsWith('┌─ ℹ T ─'));
      await t.pumpWidget(themed(Glyphs.ascii, callout), size: (12, 3));
      expect(t.lines.first, startsWith('+- i T -'));
      expect(isAscii(t.lines), isTrue);
      await t.pumpWidget(
        themed(
          Glyphs.unicode,
          const Callout.text('hi', title: 'T', borderType: BorderType.heavy),
        ),
        size: (12, 3),
      );
      expect(t.lines.first, startsWith('┏━ ℹ T ━'));
    });

    testTwk('a LineGauge given a type draws ASCII in ASCII', (t) async {
      const gauge = SizedBox(
        width: 6,
        height: 1,
        child: LineGauge(ratio: 0.5, type: BorderType.heavy),
      );
      await t.pumpWidget(themed(Glyphs.unicode, gauge), size: (6, 1));
      expect(t.lines.single, '━━━━━━');
      await t.pumpWidget(themed(Glyphs.ascii, gauge), size: (6, 1));
      expect(t.lines.single, '------');
    });

    testTwk('a Table border given as single is ASCII in ASCII', (t) async {
      const table = Table<String>(
        rows: ['a'],
        columns: [
          TableColumn(title: 'h', cell: TableCell.new),
        ],
        border: BorderType.single,
      );
      await t.pumpWidget(themed(Glyphs.ascii, table), size: (5, 3));
      expect(isAscii(t.lines), isTrue);
    });
  });

  group('marks', () {
    test('the new fields of the presets', () {
      expect(Glyphs.unicode.arrowLeft, '←');
      expect(Glyphs.unicode.arrowDown, '↓');
      expect(Glyphs.unicode.pointer, '▶');
      expect(Glyphs.unicode.menu, '≡');
      expect(Glyphs.unicode.shades, [' ', '░', '▒', '▓', '█']);
      expect(Glyphs.unicode.swatch, '■');
      expect(Glyphs.unicode.ellipsis, '…');
      expect(Glyphs.ascii.arrowLeft, '<');
      expect(Glyphs.ascii.arrowUp, '^');
      expect(Glyphs.ascii.shades, [' ', '.', ':', '+', '#']);
      expect(Glyphs.ascii.ellipsis, '...');
    });

    test('shades compare by their marks', () {
      final a = Glyphs.unicode.copyWith(shades: [' ', 'a']);
      final b = Glyphs.unicode.copyWith(shades: [' ', 'a']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(Glyphs.unicode));
    });

    test("the arrows of a key hint are the set's", () {
      final up = KeyCombo.parse('up');
      expect(KeyHintsBar.signs(up), '↑');
      expect(KeyHintsBar.signs(up, Glyphs.ascii), '^');
      expect(
        KeyHintsBar.signs(KeyCombo.parse('alt+down'), Glyphs.ascii),
        'alt+v',
      );
    });

    testTwk("Breadcrumbs with no separator take the set's next", (t) async {
      const crumbs = Breadcrumbs(items: ['a', 'b', 'c']);
      await t.pumpWidget(themed(Glyphs.unicode, crumbs), size: (20, 1));
      expect(t.lines.single.trimRight(), 'a › b › c');
      await t.pumpWidget(themed(Glyphs.ascii, crumbs), size: (20, 1));
      expect(t.lines.single.trimRight(), 'a > b > c');
      await t.pumpWidget(
        themed(
          Glyphs.ascii,
          const Breadcrumbs(items: ['a', 'b'], separator: '/'),
        ),
        size: (20, 1),
      );
      expect(t.lines.single.trimRight(), 'a/b');
    });

    testTwk("Breadcrumbs cut with the set's ellipsis", (t) async {
      const crumbs = Breadcrumbs(items: ['aaaa', 'bbbb', 'cccc', 'dddd']);
      await t.pumpWidget(themed(Glyphs.ascii, crumbs), size: (20, 1));
      expect(t.lines.single, contains('...'));
      expect(isAscii(t.lines), isTrue);
    });

    testTwk('a Skeleton with no glyph shows the light shade of the set', (
      t,
    ) async {
      const skeleton = SizedBox(width: 3, height: 1, child: Skeleton());
      await t.pumpWidget(themed(Glyphs.unicode, skeleton), size: (3, 1));
      expect(t.lines.single, '░░░');
      await t.pumpWidget(themed(Glyphs.ascii, skeleton), size: (3, 1));
      expect(t.lines.single, '...');
    });

    testTwk("a Heatmap on the default scale takes the set's shades", (
      t,
    ) async {
      final heatmap = Heatmap(
        rows: 1,
        columns: 5,
        cellWidth: 1,
        value: (r, c) => c.toDouble(),
      );
      await t.pumpWidget(themed(Glyphs.unicode, heatmap), size: (5, 1));
      expect(t.lines.single, ' ░▒▓█');
      await t.pumpWidget(themed(Glyphs.ascii, heatmap), size: (5, 1));
      expect(t.lines.single, ' .:+#');
    });
  });
}
