// A popover whose fade steps in the frame its open changes in, deeper in
// the tree than its entry, which that frame built already: closed while it
// fades in, opened while it fades out and in the frame it has faded out
// in; an Autocomplete closing as its suggestions fade in; a FilePicker's
// field cleared as they do.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData theme = ThemeData.dark;
const ms = Duration(milliseconds: 1);

/// [child] under [levels] widgets, so deeper in the tree than what the
/// entry of an overlay right above them builds.
Widget deep(Widget child, {int levels = 30}) {
  var w = child;
  for (var i = 0; i < levels; i++) {
    w = Align(alignment: Alignment.topLeft, child: w);
  }
  return w;
}

/// [child] in an overlay on the dark theme's background.
Widget app(Widget child) => Theme(
  data: theme,
  child: Box(
    style: theme.background,
    child: Overlay(child: child),
  ),
);

/// A popover saying `pop` by `anchor` while [open], deep under the
/// overlay: built again when [open] changes, in the frame its fade steps
/// in as well.
Widget popover(
  ValueNotifier<bool> open, {
  Duration fadeIn = Duration.zero,
  Duration fadeOut = Duration.zero,
}) => app(
  deep(
    ListenableBuilder(
      listenable: open,
      builder: (context, _) => Popover(
        open: open.value,
        fadeIn: fadeIn,
        fadeOut: fadeOut,
        popover: Box(style: theme.surface, child: const Text('pop')),
        child: const Text('anchor'),
      ),
    ),
  ),
);

void main() {
  final surface = theme.surface.bg!;
  final background = theme.background.bg!;

  testTwk('a popover closed with no fadeOut while it fades in is gone in '
      'that frame', (t) async {
    final open = ValueNotifier(false);
    addTearDown(open.dispose);
    await t.pumpWidget(popover(open, fadeIn: ms * 120), size: (20, 5));
    await t.pump();
    open.value = true;
    await t.pump();
    await t.pump(ms * 30);
    expect(t, styleAt(0, 1, isNot(anyOf(hasBg(background), hasBg(surface)))));
    open.value = false;
    await t.pump(ms * 20);
    expect(t, styleAt(0, 1, hasBg(background)));
    expect(t, matchesScreen('anchor'));
  });

  testTwk('a popover opened with no fadeIn while it fades out shows whole '
      'in that frame', (t) async {
    final open = ValueNotifier(true);
    addTearDown(open.dispose);
    await t.pumpWidget(popover(open, fadeOut: ms * 100), size: (20, 5));
    await t.pump();
    await t.pump();
    expect(t, styleAt(0, 1, hasBg(surface)));
    open.value = false;
    await t.pump();
    await t.pump(ms * 30);
    expect(t, styleAt(0, 1, isNot(anyOf(hasBg(background), hasBg(surface)))));
    open.value = true;
    await t.pump(ms * 20);
    expect(t, styleAt(0, 1, hasBg(surface)));
    expect(t, hasTextAt(0, 1, 'pop'));
  });

  testTwk('a popover opened again in the frame it has faded out in shows '
      'in that frame', (t) async {
    final open = ValueNotifier(true);
    addTearDown(open.dispose);
    await t.pumpWidget(popover(open, fadeOut: ms * 100), size: (20, 5));
    await t.pump();
    await t.pump();
    open.value = false;
    await t.pump();
    // its last step, to transparent, is in the frame it opens in
    await t.pump(ms * 100);
    open.value = true;
    await t.pump(ms * 20);
    expect(t, styleAt(0, 1, hasBg(surface)));
    expect(t, hasTextAt(0, 1, 'pop'));
  });

  testTwk("an Autocomplete's suggestions closed by Escape as they fade in "
      'are gone', (t) async {
    final c = TextEditingController();
    addTearDown(c.dispose);
    await t.pumpWidget(
      app(
        deep(
          Autocomplete(
            controller: c,
            suggestions: (query) => [
              for (final s in ['Apple', 'Banana'])
                if (s.toLowerCase().contains(query)) Suggestion(s),
            ],
            child: SizedBox(
              width: 20,
              child: TextField(controller: c, autofocus: true),
            ),
          ),
        ),
      ),
      size: (40, 8),
    );
    await t.pump();
    await t.type('a');
    await t.pump();
    await t.pump(ms * 30);
    expect(t, styleAt(0, 1, isNot(anyOf(hasBg(background), hasBg(surface)))));
    await t.press('escape');
    await t.pump();
    expect(t, styleAt(0, 1, hasBg(background)));
    expect(t.lines[1].trim(), isEmpty);
  });

  testTwk("a FilePicker's field cleared as the name Ctrl+Z put back is "
      'suggested, fading in, takes the suggestions away', (t) async {
    final dir = Directory.systemTemp.createTempSync('popover_fade_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/notes.txt').writeAsStringSync('');
    // the directory is listed in real time
    Future<void> until(bool Function() done, String what) =>
        waitUntil(
          done,
          what,
          between: t.pump,
        ).onError<TestFailure>(
          (e, _) => fail('${e.message}:\n${t.lines.join('\n')}'),
        );

    await t.pumpWidget(
      app(
        Column(
          children: [
            Expanded(
              child: FilePicker(
                onPicked: (_) {},
                mode: FilePickerMode.save,
                directory: dir.path,
                name: 'notes',
                autofocus: true,
              ),
            ),
          ],
        ),
      ),
      size: (dir.path.length + 40, 10),
    );
    await until(
      () => !t.lines.any((l) => l.contains('listing')),
      'the directory listed',
    );
    await t.type('x');
    await t.pumpUntilIdle();
    expect(
      t.lines.first.trim(),
      '${dir.path}${Platform.pathSeparator}notesx',
    );
    await t.press('ctrl+z');
    // the suggestion over ../, fading in
    await until(
      () => t.lines[1].contains('notes.txt'),
      'notes.txt suggested',
    );
    for (final key in ['ctrl+a', 'ctrl+k']) {
      await t.press(key);
      await t.pump();
    }
    await t.pumpUntilIdle();
    expect(t.lines.first.trim(), isEmpty);
    expect(t.lines[1].trim(), '..${Platform.pathSeparator}');
  });
}
