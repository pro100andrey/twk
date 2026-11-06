// The first keys of a sequence that a layer replays (UnmatchedKeys.replay)
// go to the nodes above the layer; those that a dialog's keysSkip skips
// (the app's bindings between the navigator and the overlay above it) must
// not hear them: the replay goes by the key path, as a key does.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

Future<void> openDialog(TwkTester t) async {
  await press(t, 'd');
  await t.pump(const Duration(milliseconds: 300));
}

/// A sequence `z z` of a layer that replays, round a focused text.
Widget sequenceLayer(String name, List<String> heard) => KeyBindings(
  {'z z': () => heard.add('sequence')},
  unmatched: UnmatchedKeys.replay,
  child: Focus(autofocus: true, child: Text(name)),
);

/// The app binds `z`, above the navigator inside App; the screen opens a
/// dialog on `d`, whose body is the sequence layer when [inDialog].
Widget app(List<String> heard, {required bool inDialog}) => App(
  child: KeyBindings(
    {'z': () => heard.add('app z')},
    hints: const {'z': 'app'},
    child: Navigator(
      home: Builder(
        builder: (context) => KeyBindings(
          {
            'd': () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                title: 'Dialog',
                child: sequenceLayer('in dialog', heard),
              ),
            ),
          },
          child: inDialog
              ? const Focus(autofocus: true, child: Text('screen'))
              : sequenceLayer('on screen', heard),
        ),
      ),
    ),
  ),
);

void main() {
  testTwk('guard: a layer on the screen replays the held z to the app '
      'bindings above it', (t) async {
    final heard = <String>[];
    await t.pumpWidget(app(heard, inDialog: false), size: (30, 8));
    await press(t, 'z x');
    expect(heard, ['app z']);
  });

  testTwk('guard: in a dialog z z completes the sequence and the app hears '
      'nothing', (t) async {
    final heard = <String>[];
    await t.pumpWidget(app(heard, inDialog: true), size: (30, 8));
    await openDialog(t);
    expect(t, containsLine(contains('in dialog')));
    await press(t, 'z z');
    expect(heard, ['sequence']);
  });

  testTwk('guard: a plain z in the dialog is not heard by the app', (t) async {
    final heard = <String>[];
    await t.pumpWidget(app(heard, inDialog: true), size: (30, 8));
    await openDialog(t);
    await press(t, 'x');
    expect(heard, isEmpty);
  });

  testTwk("a held z of a dialog's sequence, let go of by another key, is not "
      "replayed to the app's z past the dialog's keysSkip", (t) async {
    final heard = <String>[];
    await t.pumpWidget(app(heard, inDialog: true), size: (30, 8));
    await openDialog(t);
    expect(t, containsLine(contains('in dialog')));
    await press(t, 'z x');
    expect(heard, isEmpty, reason: 'what the app heard');
  });
}
