// App: a dialog in its theme, the app's root keys not hearing the dialog's,
// the state below kept as a theme is given or taken away.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [t] given [key] and a frame.
Future<void> press(TwkTester t, String key) async {
  await t.press(key);
  await t.pump();
}

/// An app whose root binds `d`, which opens a dialog of a button, or of
/// a text field with [field], and `q`, which adds to [quits].
final class Home extends StatelessWidget {
  const Home(this.quits, {this.field = false, super.key});

  final List<String> quits;
  final bool field;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {
      'd': () => unawaited(
        showDialog<void>(
          context,
          (_) => Dialog(
            title: 'Find',
            child: field
                ? const TextField(autofocus: true)
                : Button('OK', autofocus: true, onPressed: () {}),
          ),
          fadeIn: Duration.zero,
        ),
      ),
      'q': () => quits.add('q'),
    },
    child: const Focus(autofocus: true, child: Text('home')),
  );
}

void main() {
  testTwk('a dialog shows in the theme given, over the app', (t) async {
    await t.pumpWidget(
      const App(theme: ThemeData.nord, child: Home([])),
      size: (30, 7),
    );
    await press(t, 'd');
    final row = t.lines.indexWhere((l) => l.contains('Find'));
    final x = t.lines[row].indexOf('Find');
    expect(t, styleAt(x, row, hasBg(ThemeData.nord.surface.bg!)));
  });

  testTwk("the app's root keys do not hear the keys a dialog leaves while it "
      'is open', (t) async {
    final quits = <String>[];
    await t.pumpWidget(App(child: Home(quits)), size: (30, 7));
    await press(t, 'd');
    await press(t, 'q');
    expect(quits, isEmpty);
    await press(t, 'escape');
    await press(t, 'q');
    expect(quits, ['q']);
  });

  testTwk('a theme given or taken away keeps the dialog open and the state '
      'below', (t) async {
    await t.pumpWidget(const App(child: Home([], field: true)), size: (30, 7));
    await press(t, 'd');
    await press(t, 'a');
    await t.pumpWidget(
      const App(theme: ThemeData.nord, child: Home([], field: true)),
    );
    await press(t, 'b');
    await t.pumpWidget(const App(child: Home([], field: true)));
    expect(t.lines.any((l) => l.contains('ab')), isTrue);
  });
}
