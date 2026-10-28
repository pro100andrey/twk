// Slider: the thumb as far along the track as the value, in eighths of a
// cell, in whole cells where block elements are two columns wide; the
// keys, the press, the drag and the wheel that move it, within min and max
// and on the divisions; its styles; a disabled slider out of the focus and
// the mouse; a slider in a FormField.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

/// A cell as text: its glyph, after `~` when it is in reverse video.
String cellText(VtCell cell) =>
    '${cell.attrs & Attr.reverse != 0 ? '~' : ''}${cell.text}';

/// The cells of row [y], columns 0 to [columns] - 1, as one string.
String row(TwkTester t, int columns, {int y = 0}) => [
  for (var x = 0; x < columns; x++) cellText(t.cell(x, y)),
].join();

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// Presses each key of [keys], pumping a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

Future<void> mouse(TwkTester t, MouseKind kind, int x, [int y = 0]) async {
  await t.mouse(kind, x, y);
  await t.pump();
}

/// A [Slider] whose value [value] holds, [width] cells wide, above a node
/// `next`; [changes] gets each value it gives.
Widget slider(
  ValueNotifier<double> value, {
  List<double>? changes,
  int width = 11,
  double min = 0,
  double max = 1,
  int? divisions,
  bool enabled = true,
  bool autofocus = false,
}) {
  final node = FocusNode(debugLabel: 'slider');
  addTearDown(node.dispose);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: width,
        child: ValueListenableBuilder<double>(
          valueListenable: value,
          builder: (context, v, _) => Slider(
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: enabled
                ? (next) {
                    changes?.add(next);
                    value.value = next;
                  }
                : null,
            focusNode: node,
            autofocus: autofocus,
          ),
        ),
      ),
      const Focus(debugLabel: 'next', child: Text('next')),
    ],
  );
}

void main() {
  group('the thumb', () {
    testTwk('is a cell as far along the track as the value, in eighths of '
        'a cell: at the start for min, at the end for max; the line before '
        'it in its color', (t) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      await t.pumpWidget(
        Theme(data: ThemeData.dark, child: slider(value)),
        size: (20, 3),
      );
      expect(row(t, 11), '~ ──────────');
      value.value = 1;
      await t.pump();
      expect(row(t, 11), '──────────~ ');
      // 80 eighths of room: the thumb from the 20th
      value.value = 0.25;
      await t.pump();
      expect(row(t, 11), '──~▌▌───────');
      value.value = 0.3;
      await t.pump();
      // from the 24th: a whole cell
      expect(row(t, 11), '───~ ───────');
      value.value = 0.33;
      await t.pump();
      // from the 26th
      expect(row(t, 11), '───~▎▎──────');
      final text = ThemeData.dark.text.fg;
      final muted = ThemeData.dark.muted.fg;
      expect(t.cell(0, 0).fg, text);
      expect(t.cell(2, 0).fg, text);
      expect(t.cell(3, 0).fg, text);
      expect(t.cell(4, 0).fg, text);
      expect(t.cell(5, 0).fg, muted);
      expect(t.cell(10, 0).fg, muted);
      expect(t.cell(10, 0).bg, ThemeData.dark.background.bg);
    });

    testTwk('shows a value beyond min and max as the nearest, one that is '
        'not a number as min, and one between divisions on the nearest', (
      t,
    ) async {
      final value = ValueNotifier<double>(-3);
      addTearDown(value.dispose);
      await t.pumpWidget(slider(value, divisions: 2), size: (20, 3));
      expect(row(t, 11), '~ ──────────');
      value.value = 7;
      await t.pump();
      expect(row(t, 11), '──────────~ ');
      value.value = double.nan;
      await t.pump();
      expect(row(t, 11), '~ ──────────');
      value.value = 0.4;
      await t.pump();
      expect(row(t, 11), '─────~ ─────');
    });

    testTwk('is in the middle row of a taller slider', (t) async {
      await t.pumpWidget(
        Column(
          children: [
            SizedBox(
              width: 5,
              height: 3,
              child: Slider(value: 1, onChanged: (_) {}),
            ),
          ],
        ),
        size: (5, 3),
      );
      expect(
        [row(t, 5), row(t, 5, y: 1), row(t, 5, y: 2)],
        [
          '     ',
          '────~ ',
          '     ',
        ],
      );
    });

    test('is in whole cells, and the line ASCII, where block elements and '
        'box drawing are two columns wide', () async {
      final app = await WideApp.start(
        Slider(value: 0.33, onChanged: (_) {}),
        width: 11,
        height: 1,
      );
      await app.quit();
      final vt = Vt(11, 1, segmenter: TextSegmenter(ambiguousWidth: 2));
      app.terminal.frames.forEach(vt.feed);
      expect(
        [for (var x = 0; x < 11; x++) cellText(vt.cell(x, 0))].join(),
        '---~ -------',
      );
    });
  });

  group('the keys', () {
    testTwk('Right and Up take it a hundredth of the range up, Left and '
        'Down down, Page Up and Page Down a tenth, Home and End to min and '
        'max; only while it has the focus; Left and Right hinted', (t) async {
      final value = ValueNotifier<double>(50);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        slider(value, changes: changes, max: 200),
        size: (20, 3),
      );
      await press(t, 'right');
      expect(changes, isEmpty);
      await press(t, 'tab');
      expect(focused(t), 'slider');
      expect(hints(t), ['left decrease', 'right increase']);
      await press(t, 'right up');
      expect(changes, [52, 54]);
      await press(t, 'left down down');
      expect(changes, [52, 54, 52, 50, 48]);
      await press(t, 'pageup pageup pagedown');
      expect(changes.skip(5), [68, 88, 68]);
      await press(t, 'home');
      expect(value.value, 0);
      await press(t, 'end');
      expect(value.value, 200);
      expect(row(t, 11), '──────────~ ');
      value.value = 100;
      await t.pump();
      await press(t, 'left');
      expect(value.value, 98);
    });

    testTwk('step a division, and Page Up and Page Down a tenth of them, a '
        'division at least', (t) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        slider(
          value,
          changes: changes,
          max: 10,
          divisions: 40,
          autofocus: true,
        ),
        size: (20, 3),
      );
      await press(t, 'right right pageup left');
      expect(changes, [0.25, 0.5, 1.5, 1.25]);
      final few = ValueNotifier<double>(0);
      addTearDown(few.dispose);
      changes.clear();
      await t.pumpWidget(
        slider(few, changes: changes, divisions: 4, autofocus: true),
        size: (20, 3),
      );
      await press(t, 'tab tab pageup pageup right');
      expect(focused(t), 'slider');
      expect(changes, [0.25, 0.5, 0.75]);
    });

    testTwk('reach max on the last division, exactly', (t) async {
      final value = ValueNotifier<double>(0.2);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        slider(
          value,
          changes: changes,
          min: 0.2,
          max: 0.9,
          divisions: 7,
          autofocus: true,
        ),
        size: (20, 3),
      );
      await press(t, 'right right right right right right right');
      expect(changes, hasLength(7));
      expect(changes.last, 0.9);
    });

    testTwk('stop at min and max, giving nothing there', (t) async {
      final value = ValueNotifier<double>(0.995);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        slider(value, changes: changes, autofocus: true),
        size: (20, 3),
      );
      await press(t, 'right right pageup end');
      expect(changes, [1]);
      await press(t, 'home left down pagedown home');
      expect(changes, [1, 0]);
    });

    testTwk('that come before the app builds it again step from the value '
        'the last one gave', (t) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        slider(value, changes: changes, max: 100, autofocus: true),
        size: (20, 3),
      );
      // three keys in one read
      await t.input('\x1b[C\x1b[C\x1b[A'.codeUnits);
      await t.pump();
      expect(changes, [1, 2, 3]);
      expect(value.value, 3);
    });
  });

  group('the mouse', () {
    testTwk('a press on the track moves the thumb there and focuses the '
        'slider; a drag moves it as many cells as the mouse, wherever the '
        'mouse goes, until the release', (t) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(slider(value, changes: changes), size: (20, 3));
      await mouse(t, MouseKind.down, 5);
      expect(focused(t), 'slider');
      expect(changes, [0.5]);
      expect(row(t, 11), '─────~ ─────');
      await mouse(t, MouseKind.drag, 7);
      await mouse(t, MouseKind.drag, 7, 2);
      await mouse(t, MouseKind.drag, 19, 1);
      expect(changes, [0.5, 0.7, 1]);
      await mouse(t, MouseKind.drag, 2);
      await mouse(t, MouseKind.up, 2);
      expect(changes, [0.5, 0.7, 1, 0.2]);
      await mouse(t, MouseKind.drag, 4);
      await mouse(t, MouseKind.move, 6);
      expect(changes, [0.5, 0.7, 1, 0.2]);
      expect(row(t, 11), '──~ ────────');
    });

    testTwk('a press on the thumb grabs it where it is, in eighths of a '
        'cell: the drag moves it from there', (t) async {
      final value = ValueNotifier<double>(0.25);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(slider(value, changes: changes), size: (20, 3));
      expect(row(t, 11), '──~▌▌───────');
      await mouse(t, MouseKind.down, 3);
      expect(changes, isEmpty);
      await mouse(t, MouseKind.drag, 4);
      // the thumb from the 28th eighth: 0.35
      expect(changes, [0.35]);
      expect(row(t, 11), '───~▌▌──────');
      await mouse(t, MouseKind.drag, 0);
      await mouse(t, MouseKind.up, 0);
      expect(changes, [0.35, 0]);
      await mouse(t, MouseKind.down, 0);
      await mouse(t, MouseKind.drag, 1);
      await mouse(t, MouseKind.up, 1);
      expect(changes, [0.35, 0, 0.1]);
    });

    testTwk('a drag goes on the divisions', (t) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      final changes = <double>[];
      await t.pumpWidget(
        slider(value, changes: changes, divisions: 4),
        size: (20, 3),
      );
      await mouse(t, MouseKind.down, 0);
      for (var x = 1; x <= 10; x++) {
        await mouse(t, MouseKind.drag, x);
      }
      await mouse(t, MouseKind.up, 10);
      expect(changes, [0.25, 0.5, 0.75, 1]);
    });

    testTwk('a press of the track is its own: a GestureDetector around it '
        'gets no tap and no drag', (t) async {
      final value = ValueNotifier<double>(0);
      addTearDown(value.dispose);
      final told = <String>[];
      await t.pumpWidget(
        GestureDetector(
          onTap: (_) => told.add('tap'),
          onDragStart: (_) => told.add('drag'),
          child: slider(value),
        ),
        size: (20, 3),
      );
      await mouse(t, MouseKind.down, 3);
      await mouse(t, MouseKind.drag, 5);
      await mouse(t, MouseKind.up, 5);
      await t.click(8, 0);
      await t.pump(const Duration(seconds: 1));
      expect(told, isEmpty);
      expect(value.value, 0.8);
      await t.click(1, 1);
      await t.pump(const Duration(seconds: 1));
      expect(told, ['tap']);
    });

    testTwk('the wheel steps it as the arrows while it has the focus, and '
        'goes to the views around while it has not', (t) async {
      final value = ValueNotifier<double>(50);
      addTearDown(value.dispose);
      final changes = <double>[];
      final wheel = <int>[];
      await t.pumpWidget(
        Listener(
          onScroll: (e) => wheel.add(e.scrollY),
          child: slider(value, changes: changes, max: 100),
        ),
        size: (20, 3),
      );
      await mouse(t, MouseKind.wheelUp, 4);
      expect(wheel, [-1]);
      expect(changes, isEmpty);
      await press(t, 'tab');
      await mouse(t, MouseKind.wheelUp, 4);
      await mouse(t, MouseKind.wheelUp, 4);
      await mouse(t, MouseKind.wheelDown, 4);
      await mouse(t, MouseKind.wheelRight, 4);
      await mouse(t, MouseKind.wheelLeft, 4);
      expect(changes, [51, 52, 51, 52, 51]);
      expect(wheel, [-1]);
    });
  });

  group('the styles', () {
    testTwk('the thumb and the line before it are in the primary color '
        'while it has the focus, the style and focusedStyle given', (
      t,
    ) async {
      const mine = Color.rgb(200, 0, 0);
      const myFocus = Color.rgb(0, 200, 0);
      const myTrack = Color.rgb(0, 0, 200);
      final node = FocusNode(debugLabel: 'mine');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: Column(
            children: [
              Slider(value: 0.5, onChanged: (_) {}, autofocus: true),
              Slider(
                value: 0.5,
                onChanged: (_) {},
                focusNode: node,
                style: const Style(fg: mine),
                focusedStyle: const Style(fg: myFocus),
                trackStyle: const Style(fg: myTrack),
              ),
            ],
          ),
        ),
        size: (11, 2),
      );
      final primary = ThemeData.dark.primary.fg;
      expect([t.cell(0, 0).fg, t.cell(5, 0).fg], [primary, primary]);
      expect(t.cell(5, 0).attrs & Attr.reverse, Attr.reverse);
      expect(t.cell(6, 0).fg, ThemeData.dark.muted.fg);
      expect(
        [t.cell(0, 1).fg, t.cell(5, 1).fg, t.cell(6, 1).fg],
        [
          mine,
          mine,
          myTrack,
        ],
      );
      node.requestFocus();
      await t.pump();
      expect(
        [t.cell(0, 1).fg, t.cell(5, 1).fg, t.cell(6, 1).fg],
        [
          myFocus,
          myFocus,
          myTrack,
        ],
      );
      expect(t.cell(0, 0).fg, ThemeData.dark.text.fg);
    });
  });

  testTwk('disabled, with no onChanged, it is muted and takes neither the '
      'focus, which Tab passes by, nor the mouse', (t) async {
    final value = ValueNotifier<double>(0.5);
    addTearDown(value.dispose);
    final wheel = <int>[];
    final drags = <int>[];
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark,
        child: GestureDetector(
          onDragStart: (d) => drags.add(d.x),
          child: Listener(
            onScroll: (e) => wheel.add(e.scrollY),
            child: slider(value, enabled: false),
          ),
        ),
      ),
      size: (20, 3),
    );
    final muted = ThemeData.dark.muted.fg;
    expect(
      [t.cell(0, 0).fg, t.cell(5, 0).fg, t.cell(9, 0).fg],
      [
        muted,
        muted,
        muted,
      ],
    );
    await press(t, 'tab');
    expect(focused(t), 'next');
    await mouse(t, MouseKind.down, 1);
    await mouse(t, MouseKind.drag, 3);
    await mouse(t, MouseKind.up, 3);
    await mouse(t, MouseKind.wheelUp, 3);
    expect(focused(t), 'next');
    // the drag is the detector's
    expect(drags, [1]);
    expect(value.value, 0.5);
    expect(wheel, [-1]);
  });

  testTwk('the terminal reports the presses and the drags of a slider, and '
      'none of a disabled one', (t) async {
    await t.pumpWidget(const Slider(value: 0, onChanged: null), size: (10, 1));
    expect(t.terminal.mouseTracking, MouseTracking.off);
    await t.pumpWidget(Slider(value: 0, onChanged: (_) {}));
    expect(t.terminal.mouseTracking, MouseTracking.drags);
  });

  testTwk('in a FormField: its value validated, reset and saved; Enter '
      'goes to the form', (t) async {
    final form = GlobalKey<FormState>();
    double? saved;
    var submitted = 0;
    await t.pumpWidget(
      Form(
        key: form,
        onSubmitted: () => submitted++,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: FormField<double>(
          initialValue: 0.2,
          validator: (v) => v! < 0.5 ? 'too low' : null,
          onSaved: (v) => saved = v,
          builder: (field) => SizedBox(
            width: 11,
            child: Slider(
              value: field.value!,
              onChanged: field.didChange,
              divisions: 10,
              autofocus: true,
            ),
          ),
        ),
      ),
      size: (20, 3),
    );
    expect(form.currentState!.submit(), isFalse);
    await t.pump();
    expect(row(t, 11), '──~ ────────');
    expect(t.lines.skip(1), ['too low', '']);
    await press(t, 'right right right');
    expect(row(t, 11), '─────~ ─────');
    expect(t.lines.skip(1), ['', '']);
    await press(t, 'enter');
    expect(submitted, 1);
    expect(saved, 0.5);
    form.currentState!.reset();
    await t.pump();
    expect(row(t, 11), '──~ ────────');
  });
}
