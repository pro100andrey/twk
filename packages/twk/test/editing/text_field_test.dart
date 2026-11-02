// A line of text edited through the parser: mixed scripts and emoji typed
// and pasted, the caret moved and the text selected and deleted by
// characters and words, the keys it does not take going up; the
// terminal's cursor, a bar, at the caret of the focused field only,
// whatever else repaints, hidden once it loses the focus or goes; the text
// scrolled sideways to keep the caret in view; placeholder, obscured
// text, maxLength, onChanged and onSubmitted; undo and redo; and a
// keystroke repainting nothing but the field.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../data/shot.dart' show Counted, PaintCount;

/// A focused field of [c], [width] columns wide.
Widget field(
  TextEditingController c, {
  int width = 20,
  String? placeholder,
  bool obscureText = false,
  int? maxLength,
  void Function(String)? onChanged,
  void Function(String)? onSubmitted,
}) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(
    width: width,
    child: TextField(
      controller: c,
      autofocus: true,
      placeholder: placeholder,
      obscureText: obscureText,
      maxLength: maxLength,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    ),
  ),
);

/// Its [child] painted in full once, then, each time [repaints] notifies,
/// only its first row: as a view that scrolled repaints only the rows the
/// scroll exposed.
final class FirstRow extends SingleChildRenderObjectWidget {
  const FirstRow(this.repaints, {super.child});

  final Listenable repaints;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFirstRow(repaints);
}

final class _RenderFirstRow extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderFirstRow(Listenable repaints) {
    repaints.addListener(markNeedsPaint);
  }

  var _painted = false;

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    child?.layout(c);
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    final child = this.child!;
    if (!_painted) {
      _painted = true;
      paintChild(ctx, child);
      return;
    }
    ctx.canvas
      ..save()
      ..clipRect(0, 0, width, 1);
    paintChild(ctx, child);
    ctx.canvas.restore();
  }
}

/// Whether the terminal shows the cursor as a bar.
bool barCursor(TwkTester t) => t.vt.cursorShape == CursorShape.bar.code;

void main() {
  group('its fill', () {
    testTwk("none of its own: over what is under it, the page's or a box's, "
        'a field of an Autocomplete too: no square inside the box', (t) async {
      final c = TextEditingController(text: 'ab');
      for (final theme in [
        ThemeData.dark,
        ThemeData.light,
        const ThemeData.terminal(Brightness.dark),
      ]) {
        // nothing painted under it: the terminal's own background
        await t.pumpWidget(
          Theme(data: theme, child: field(c)),
          size: (20, 1),
        );
        expect(t, styleAt(10, 0, hasBg(Color.defaultColor)), reason: '$theme');
        expect(t, styleAt(10, 0, isNot(hasAttr(Attr.underline))));
        final page = theme.background.bg!;
        await t.pumpWidget(
          Theme(
            data: theme,
            child: Overlay(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 20,
                  child: Box(
                    style: theme.background,
                    border: Border.all(style: theme.border),
                    child: Autocomplete(
                      controller: c,
                      suggestions: (_) => const <Suggestion>[],
                      child: TextField(controller: c),
                    ),
                  ),
                ),
              ),
            ),
          ),
          size: (20, 3),
        );
        for (final x in [1, 10, 18]) {
          expect(t, styleAt(x, 1, hasBg(page)), reason: '$theme at $x');
        }
      }
    });

    testTwk('in a dialog and on a gradient: their colors under it, as typed '
        'and with a selection gone', (t) async {
      const theme = ThemeData.terminal(Brightness.dark);
      final panel = theme.surface.bg!;
      const from = Color.rgb(0, 0, 96);
      const to = Color.rgb(0, 0, 0);
      final c = TextEditingController(text: 'abc');
      final g = TextEditingController(text: 'abc');
      await t.pumpWidget(
        Theme(
          data: theme,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 20,
              child: Column(
                children: [
                  Box(
                    style: theme.surface,
                    child: TextField(controller: c, autofocus: true),
                  ),
                  GradientBackground(
                    gradient: const Gradient([from, to]),
                    child: TextField(controller: g),
                  ),
                ],
              ),
            ),
          ),
        ),
        size: (20, 2),
      );
      final under = [for (var x = 0; x < 20; x++) t.cell(x, 1).bg];
      expect(t, styleAt(10, 0, hasBg(panel)));
      expect(under.first, isNot(under.last), reason: 'a gradient');
      // a selection, then a character typed over it: repainted on its own
      await t.press('shift+left shift+left');
      await t.pump();
      expect(t, styleAt(1, 0, isNot(hasBg(panel))), reason: 'selected');
      await t.type('x');
      await t.pump();
      for (final x in [1, 2, 10]) {
        expect(t, styleAt(x, 0, hasBg(panel)), reason: 'at $x');
      }
      g.text = 'abcd';
      await t.pump();
      expect([for (var x = 0; x < 20; x++) t.cell(x, 1).bg], under);
    });

    testTwk("a gauge on a Table's selected row: the row's color under it", (
      t,
    ) async {
      const theme = ThemeData.dark;
      final c = TableController(selectedKey: 1);
      await t.pumpWidget(
        Theme(
          data: theme,
          child: Table<int>(
            rows: const [0, 1],
            controller: c,
            autofocus: true,
            columns: [
              TableColumn(
                title: 'load',
                cell: (i) => const TableCell.widget(LineGauge(ratio: 0.5)),
              ),
            ],
          ),
        ),
        size: (20, 3),
      );
      expect(t, styleAt(10, 2, hasBg(theme.selection.bg!)));
      expect(t, styleAt(10, 1, isNot(hasBg(theme.selection.bg!))));
    });
  });

  testTwk('takes mixed scripts and emoji typed through the parser, the '
      'cursor a bar after them', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(Theme.terminal(child: field(c)), size: (30, 3));
    expect(t.cursorVisible, isTrue);
    expect(t, cursorAt(0, 0));
    await t.type('héllo мир 日本 👋🏽!');
    await t.pump();
    expect(c.text, 'héllo мир 日本 👋🏽!');
    expect(t.lines[0], 'héllo мир 日本 👋🏽!');
    expect(t, cursorAt(18, 0));
    expect(barCursor(t), isTrue);
  });

  testTwk('moves the caret a character, a cluster of code points of any '
      'width, and puts what is typed there', (t) async {
    final c = TextEditingController(text: 'aé日👨‍👩‍👧z');
    await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
    expect(t, cursorAt(7, 0));
    final columns = <int>[];
    for (var i = 0; i < 5; i++) {
      await t.press('left');
      await t.pump();
      columns.add(t.cursor.$1);
    }
    expect(columns, [6, 4, 2, 1, 0]);
    await t.press('right right');
    await t.type('я');
    await t.pump();
    expect(c.text, 'aéя日👨‍👩‍👧z');
    expect(t.lines[0], 'ae\u0301я日👨‍👩‍👧z');
    expect(t, cursorAt(3, 0));
  });

  testTwk('moves by words with Ctrl, Alt, Alt+B and Alt+F, to the ends with '
      'Home, End, Ctrl+A and Ctrl+E', (t) async {
    final c = TextEditingController(text: 'say "привет, мир" now');
    await t.pumpWidget(
      Theme.terminal(child: field(c, width: 30)),
      size: (30, 1),
    );
    final carets = <int>[];
    for (final key in [
      'ctrl+left',
      'ctrl+left',
      'alt+left',
      'alt+b',
      'ctrl+a',
      'alt+f',
      'ctrl+right',
      'alt+right',
      'end',
      'home',
      'ctrl+e',
    ]) {
      await t.press(key);
      carets.add(c.selection.extentOffset);
    }
    expect(carets, [18, 16, 13, 11, 0, 3, 5, 11, 21, 0, 21]);
    await t.pump();
    expect(t, cursorAt(21, 0));
  });

  testTwk('selects with Shift, shows the selection, and puts what is typed '
      'in its place', (t) async {
    final c = TextEditingController(text: 'foo bar baz');
    await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
    await t.press('ctrl+left shift+ctrl+left shift+left');
    await t.pump();
    expect(c.selection, const TextSelection(baseOffset: 8, extentOffset: 3));
    expect(t, cursorAt(3, 0));
    for (var x = 0; x < 11; x++) {
      expect(
        t,
        styleAt(
          x,
          0,
          x >= 3 && x < 8
              ? hasBg(const Color.indexed(237))
              : isNot(hasBg(const Color.indexed(237))),
        ),
      );
    }
    await t.press('shift+right');
    expect(c.selection, const TextSelection(baseOffset: 8, extentOffset: 4));
    await t.type('я');
    await t.pump();
    expect(c.text, 'foo яbaz');
    expect(t, cursorAt(5, 0));
    expect(t, styleAt(4, 0, isNot(hasBg(const Color.indexed(237)))));
  });

  testTwk('Left and Right without Shift end the selection at its start and '
      'its end; Shift with Home and End selects to them', (t) async {
    final c = TextEditingController(text: 'abcdef');
    await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
    await t.press('left shift+left shift+left left');
    expect(c.selection, const TextSelection.collapsed(offset: 3));
    await t.press('shift+right shift+right right');
    expect(c.selection, const TextSelection.collapsed(offset: 5));
    await t.press('shift+home');
    expect(c.selection, const TextSelection(baseOffset: 5, extentOffset: 0));
    await t.press('shift+end');
    expect(c.selection, const TextSelection(baseOffset: 5, extentOffset: 6));
  });

  testTwk('deletes a character, a word with Ctrl, Alt, Alt+D and Ctrl+W, '
      'and to the ends with Ctrl+U and Ctrl+K', (t) async {
    final c = TextEditingController(text: 'git commit -m "fix 👋🏽"');
    await t.pumpWidget(
      Theme.terminal(child: field(c, width: 30)),
      size: (30, 1),
    );
    final texts = <String>[];
    Future<void> press(String key) async {
      await t.press(key);
      texts.add(c.text);
    }

    await press('backspace');
    await press('backspace');
    await press('ctrl+w');
    await press('alt+backspace');
    await press('ctrl+backspace');
    await press('home');
    await press('delete');
    await press('ctrl+d');
    await press('alt+d');
    await press('ctrl+delete');
    expect(texts, [
      'git commit -m "fix 👋🏽',
      'git commit -m "fix ',
      'git commit -m ',
      'git commit -',
      'git commit ',
      'git commit ',
      'it commit ',
      't commit ',
      ' commit ',
      ' ',
    ]);
    c.text = 'one two three';
    await t.press('ctrl+left ctrl+left ctrl+k');
    expect(c.text, 'one ');
    await t.press('left ctrl+u');
    expect(c.text, ' ');
    expect(c.selection, const TextSelection.collapsed(offset: 0));
  });

  testTwk('a deleting key deletes the selection when there is one', (t) async {
    final c = TextEditingController(text: 'one two three');
    await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
    await t.press('ctrl+left shift+ctrl+left ctrl+w');
    expect(c.text, 'one three');
    await t.press('shift+end delete');
    expect(c.text, 'one ');
  });

  testTwk('takes a paste as typed, its lines joined by blanks, without the '
      'line break at its end and other control characters', (t) async {
    final c = TextEditingController(text: 'say: ');
    await t.pumpWidget(
      Theme.terminal(child: field(c, width: 30)),
      size: (30, 1),
    );
    await t.paste('line one\r\nline\ttwo 🇺🇦\x07\n');
    await t.pump();
    expect(c.text, 'say: line one line\ttwo 🇺🇦');
    expect(t, cursorAt(25, 0));
    await t.press('shift+ctrl+left');
    await t.paste('три');
    expect(c.text, 'say: line one line\ttwo три');
  });

  testTwk('only the focused field takes a paste or a key, and only it shows '
      'the cursor', (t) async {
    final a = TextEditingController(text: 'a');
    final b = TextEditingController(text: 'bb');
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          children: [
            TextField(controller: a, autofocus: true),
            TextField(controller: b),
          ],
        ),
      ),
      size: (20, 2),
    );
    expect(t, cursorAt(1, 0));
    await t.type('1');
    await t.paste('2');
    await t.press('tab');
    await t.pump();
    expect(t, cursorAt(2, 1));
    await t.type('3');
    await t.paste('4');
    await t.pump();
    expect((a.text, b.text), ('a12', 'bb34'));
    expect(t, cursorAt(4, 1));
    expect(barCursor(t), isTrue);
  });

  testTwk('shows focusedStyle over its style while it has the focus only', (
    t,
  ) async {
    const on = Color.rgb(1, 2, 3);
    const off = Color.rgb(4, 5, 6);
    await t.pumpWidget(
      const Theme.terminal(
        child: Column(
          children: [
            TextField(
              autofocus: true,
              style: Style(bg: off),
              focusedStyle: Style(bg: on),
            ),
            TextField(
              style: Style(bg: off),
              focusedStyle: Style(bg: on),
            ),
          ],
        ),
      ),
      size: (20, 2),
    );
    expect(t, styleAt(5, 0, hasBg(on)));
    expect(t, styleAt(5, 1, hasBg(off)));
    await t.press('tab');
    await t.pump();
    expect(t, styleAt(5, 0, hasBg(off)));
    expect(t, styleAt(5, 1, hasBg(on)));
  });

  testTwk('the cursor stays at the caret while other parts of the app '
      'repaint, the field or not', (t) async {
    final c = TextEditingController(text: 'abc')
      ..selection = const TextSelection.collapsed(offset: 1);
    final other = TextEditingController(text: 'x');
    final label = ValueNotifier('one');
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: c, autofocus: true),
            TextField(controller: other),
            ValueListenableBuilder(
              valueListenable: label,
              builder: (context, text, _) => Text(text),
            ),
          ],
        ),
      ),
      size: (20, 3),
    );
    expect(t, cursorAt(1, 0));
    final frames = t.terminal.frames.length;
    other.text = 'yy';
    await t.pump();
    expect(t.terminal.frames.length, frames + 1);
    expect(t.lines[1], 'yy');
    expect(t, cursorAt(1, 0));
    label.value = 'two';
    await t.pump();
    expect(t.lines[2], 'two');
    expect(t, cursorAt(1, 0));
    expect(barCursor(t), isTrue);
  });

  testTwk('the cursor stays at the caret while it is painted cut off, by a '
      'repaint of only some rows', (t) async {
    final c = TextEditingController(text: 'abc');
    final repaints = ValueNotifier(0);
    await t.pumpWidget(
      Theme.terminal(
        child: FirstRow(
          repaints,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('first'),
              TextField(controller: c, autofocus: true),
            ],
          ),
        ),
      ),
      size: (20, 2),
    );
    expect(t, cursorAt(3, 1));
    repaints.value++;
    await t.pump();
    expect(t, cursorAt(3, 1));
  });

  testTwk('hides the cursor once it loses the focus, and once it goes', (
    t,
  ) async {
    final c = TextEditingController(text: 'abc');
    final node = FocusNode();
    Widget app({required bool shown}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shown) TextField(controller: c, focusNode: node),
        const Focus(child: Text('elsewhere')),
      ],
    );
    await t.pumpWidget(Theme.terminal(child: app(shown: true)), size: (20, 2));
    expect(t.cursorVisible, isFalse);
    node.requestFocus();
    await t.pump();
    expect(t, cursorAt(3, 0));
    await t.press('tab');
    await t.pump();
    expect(t.cursorVisible, isFalse);
    await t.press('shift+tab');
    await t.pump();
    expect(t, cursorAt(3, 0));
    await t.pumpWidget(Theme.terminal(child: app(shown: false)));
    expect(t.lines[0], 'elsewhere');
    expect(t.cursorVisible, isFalse);
    node.dispose();
  });

  testTwk('hides the cursor where the field is cut off', (t) async {
    final c = TextEditingController(text: 'abc');
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('one'),
            const Text('two'),
            TextField(controller: c, autofocus: true),
          ],
        ),
      ),
      size: (20, 2),
    );
    expect(t.lines, ['one', 'two']);
    expect(t.cursorVisible, isFalse);
  });

  testTwk('in the inline mode the cursor is on the row of the field in the '
      'region', (t) async {
    final c = TextEditingController(text: 'ls');
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('prompt'),
            TextField(controller: c, autofocus: true),
          ],
        ),
      ),
      size: (20, 6),
      mode: ScreenMode.inline,
      history: ['earlier', 'output'],
    );
    expect(t.lines.sublist(0, 4), ['earlier', 'output', 'prompt', 'ls']);
    expect(t, cursorAt(2, 3));
    await t.type(' -la');
    await t.pump();
    expect(t.lines[3], 'ls -la');
    expect(t, cursorAt(6, 3));
  });

  testTwk('scrolls sideways to keep the caret in view, a wide character '
      'whole', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(child: field(c, width: 6)),
      size: (10, 1),
    );
    await t.type('abcdefghij');
    await t.pump();
    expect(t.lines[0], 'fghij');
    expect(t, cursorAt(5, 0));
    await t.press('left left left');
    await t.pump();
    expect(t.lines[0], 'fghij');
    expect(t, cursorAt(2, 0));
    await t.press('home');
    await t.pump();
    expect(t.lines[0], 'abcdef');
    expect(t, cursorAt(0, 0));
    c.text = '日本語の文';
    await t.pump();
    expect(t.lines[0], 'の文');
    expect(t, cursorAt(4, 0));
    await t.press('backspace backspace');
    await t.pump();
    // the caret after the text takes a column of its own
    expect(t.lines[0], '本語');
    expect(t, cursorAt(4, 0));
  });

  testTwk("shows the controller's composing range underlined", (t) async {
    final c = TextEditingController(text: 'nihon')
      ..composing = const TextRange(start: 2, end: 5);
    await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
    for (var x = 0; x < 6; x++) {
      expect(
        t,
        styleAt(
          x,
          0,
          x >= 2 && x < 5
              ? hasAttr(Attr.underline)
              : isNot(hasAttr(Attr.underline)),
        ),
      );
    }
    await t.type('!');
    await t.pump();
    expect(c.composing, TextRange.empty);
    expect(t, styleAt(3, 0, isNot(hasAttr(Attr.underline))));
  });

  testTwk('puts the caret where the terminal draws it: a tab is a column, a '
      'mark without a base none', (t) async {
    // a skin tone after a tab has no emoji to join: the canvas drops it
    final c = TextEditingController(text: 'a\t\u{1F3FD}b');
    await t.pumpWidget(Theme.terminal(child: field(c)), size: (20, 1));
    expect(t, hasTextAt(2, 0, 'b'));
    expect(t, cursorAt(3, 0));
    await t.press('left');
    await t.pump();
    expect(t, cursorAt(2, 0));
  });

  testTwk('shows its placeholder while empty, in the muted style, the '
      'caret over it', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(child: field(c, placeholder: 'Search')),
      size: (20, 1),
    );
    expect(t.lines[0], 'Search');
    expect(t, styleAt(0, 0, hasFg(const Color.indexed(245))));
    expect(t, cursorAt(0, 0));
    await t.type('x');
    await t.pump();
    expect(t.lines[0], 'x');
    expect(t, styleAt(0, 0, isNot(hasFg(const Color.indexed(245)))));
  });

  testTwk('shows each character obscured, the caret moving by characters', (
    t,
  ) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(child: field(c, obscureText: true)),
      size: (20, 1),
    );
    await t.type('pä日👋🏽');
    await t.press('left');
    await t.pump();
    expect(c.text, 'pä日👋🏽');
    expect(t.lines[0], '••••');
    expect(t, cursorAt(3, 0));
  });

  testTwk('takes no more characters than maxLength from the user', (t) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(child: field(c, maxLength: 4)),
      size: (20, 1),
    );
    await t.type('ab👋🏽');
    await t.paste('cdef');
    expect(c.text, 'ab👋🏽c');
    await t.type('g');
    expect(c.text, 'ab👋🏽c');
    await t.press('shift+left shift+left');
    await t.paste('xyz');
    expect(c.text, 'abxy');
    c.text = 'longer than four';
    await t.pump();
    expect(c.text, 'longer than four');
  });

  testTwk('calls onChanged after each change the user makes, onSubmitted '
      'with the text on Enter', (t) async {
    final c = TextEditingController(text: 'a');
    final changed = <String>[];
    final submitted = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: field(c, onChanged: changed.add, onSubmitted: submitted.add),
      ),
      size: (20, 1),
    );
    await t.type('bc');
    await t.press('left left backspace');
    c.text = 'set';
    await t.paste('!');
    await t.press('enter');
    expect(changed, ['ab', 'abc', 'bc', 'set!']);
    expect(submitted, ['set!']);
  });

  testTwk('Ctrl+Z undoes typing a word at a time, a paste and a deletion '
      'at once; Ctrl+Y redoes', (t) async {
    final c = TextEditingController();
    final changed = <String>[];
    await t.pumpWidget(
      Theme.terminal(child: field(c, onChanged: changed.add)),
      size: (20, 1),
    );
    await t.type('git commit');
    await t.paste(' -m');
    await t.press('ctrl+w');
    final texts = <String>[];
    for (final key in ['ctrl+z', 'ctrl+z', 'ctrl+z', 'ctrl+z', 'ctrl+y']) {
      await t.press(key);
      texts.add(c.text);
    }
    expect(texts, [
      'git commit -m',
      'git commit',
      'git ',
      '',
      'git ',
    ]);
    expect(changed.sublist(changed.length - 5), texts);
    await t.pump();
    expect(t, cursorAt(4, 0));
  });

  testTwk('Ctrl+Shift+Z redoes, where the terminal tells it apart', (
    t,
  ) async {
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(child: field(c)),
      size: (20, 1),
      kittyKeyboard: true,
    );
    await t.type('ab');
    await t.press('ctrl+z ctrl+shift+z');
    expect(c.text, 'ab');
  });

  testTwk('the keys it does not take go up to the nodes above it', (t) async {
    final c = TextEditingController(text: 'abc');
    final above = <String>[];
    await t.pumpWidget(
      Theme.terminal(
        child: Focus(
          onKeyEvent: (node, event) {
            above.add('${KeyCombo.fromEvent(event)}');
            return KeyEventResult.handled;
          },
          child: field(c),
        ),
      ),
      size: (20, 1),
    );
    await t.press(
      'escape up down pagedown tab enter ctrl+s f1 ctrl+d ctrl+z ctrl+y a',
    );
    expect(above, [
      'escape',
      'up',
      'down',
      'pagedown',
      'tab',
      'enter',
      'ctrl+s',
      'f1',
      'ctrl+d',
      'ctrl+z',
      'ctrl+y',
    ]);
    expect(c.text, 'abca');
  });

  testTwk('a keystroke repaints nothing but the field', (t) async {
    final count = PaintCount();
    final c = TextEditingController();
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          children: [
            Counted(count),
            TextField(controller: c, autofocus: true),
            Counted(count),
          ],
        ),
      ),
      size: (20, 3),
    );
    final paints = count.paints;
    for (final key in ['a', 'я', 'left', 'shift+right', 'backspace']) {
      await t.press(key);
      await t.pump();
    }
    expect(c.text, 'a');
    expect(t.lines[1], 'a');
    expect(t, cursorAt(1, 1));
    expect(count.paints, paints);
  });

  testTwk('fills the width its constraints allow; asked, it would be as '
      'wide as its text and a column for the caret', (t) async {
    final c = TextEditingController(text: 'ab');
    await t.pumpWidget(
      Theme.terminal(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicWidth(child: TextField(controller: c, autofocus: true)),
            const Text('|'),
          ],
        ),
      ),
      size: (20, 1),
    );
    expect(t.lines[0], 'ab |');
    await t.type('日');
    await t.pump();
    expect(t.lines[0], 'ab日 |');
    expect(t, cursorAt(4, 0));
  });

  testTwk('shows the cursor in its cursorShape, and rebuilt with another '
      'in that one', (t) async {
    final c = TextEditingController(text: 'ab');
    Widget field(CursorShape shape) =>
        TextField(controller: c, autofocus: true, cursorShape: shape);
    await t.pumpWidget(
      Theme.terminal(child: field(CursorShape.block)),
      size: (10, 1),
    );
    expect(t, cursorAt(2, 0));
    expect(t.vt.cursorShape, CursorShape.block.code);
    await t.pumpWidget(
      Theme.terminal(child: field(CursorShape.blinkingUnderline)),
    );
    expect(t.vt.cursorShape, CursorShape.blinkingUnderline.code);
  });
}
