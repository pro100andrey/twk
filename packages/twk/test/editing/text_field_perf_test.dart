// A TextField draws its whole text at each change: the field puts it
// together from the controller's pieces for itself, once a change, and
// onChanged, given the text of the same value, puts it together no more.
import 'package:test/test.dart';
import 'package:twk/src/editing/text_buffer.dart' show TextBuffer;
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('a change in a long field puts its text together once, for the '
      'field: onChanged puts it together no more', (t) async {
    // 10k characters: more than one of the pieces the controller keeps
    final text = List.filled(1000, 'some words').join(' ').substring(0, 10000);
    final c = TextEditingController(text: text)..moveCaret(text.length ~/ 2);
    final told = <String>[];
    Widget app({bool changed = false}) => TextField(
      controller: c,
      autofocus: true,
      onChanged: changed ? told.add : null,
    );

    /// How many times a text was put together for five keys typed, a frame
    /// after each.
    Future<int> joins() async {
      final before = TextBuffer.joins;
      for (final key in 'hello'.split('')) {
        await t.type(key);
        await t.pump();
      }
      return TextBuffer.joins - before;
    }

    await t.pumpWidget(app(), size: (40, 3));
    expect(await joins(), 5, reason: 'nobody told');
    await t.pumpWidget(app(changed: true), size: (40, 3));
    expect(await joins(), 5, reason: 'onChanged');
    expect(told, hasLength(5));
    expect(told.last, c.text);
    expect(c.text, hasLength(10010));
  });
}
