// The shell's model and its reading of keys, without a widget: the
// palette's ranking, the toasts, the Code's record of what changed, the
// list's filter, the page store, the options' conversions and the names
// of keys. Each is a module of its own, so its test imports it.
import 'package:gallery/src/input/line_edit.dart';
import 'package:gallery/src/model/catalog_pages.dart';
import 'package:gallery/src/model/code_record.dart';
import 'package:gallery/src/model/page_store.dart';
import 'package:gallery/src/model/palette.dart';
import 'package:gallery/src/model/toasts.dart';
import 'package:gallery/testing.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  group('the palette', () {
    final items = [
      for (final t in ['Button', 'Badge', 'Theme: Nord', 'Box'])
        PaletteItem(t, '', () {}),
    ];
    List<String> titles(String q, [List<String> recent = const []]) => [
      for (final (it, _) in rankPalette(items, q, recent)) it.title,
    ];

    test('with nothing typed, all, the ones run before first', () {
      expect(titles(''), ['Button', 'Badge', 'Theme: Nord', 'Box']);
      expect(titles('', ['Box', 'Badge']), [
        'Box',
        'Badge',
        'Button',
        'Theme: Nord',
      ]);
    });

    test('what matches, by score, ties by when each was run', () {
      expect(titles('bo'), containsAllInOrder(['Box']));
      expect(titles('b'), isNot(contains('Theme: Nord')));
      final tied = titles('b', ['Box']);
      expect(tied.indexOf('Box'), lessThan(tied.indexOf('Badge')));
    });

    test('a run goes first in the recent list, once', () {
      final recent = ['Badge', 'Box'];
      ranLast(recent, 'Box');
      expect(recent, ['Box', 'Badge']);
      ranLast(recent, 'Button');
      expect(recent, ['Button', 'Box', 'Badge']);
    });
  });

  group('a line of text', () {
    KeyEvent char(String c) => KeyEvent(KeyCode.char, char: c);

    test('takes characters, backspace and ctrl+u', () {
      expect(editLine('ab', char('c')), 'abc');
      expect(editLine('ab', char('C')), 'abC');
      expect(editLine('a👍', const KeyEvent(KeyCode.backspace)), 'a');
      expect(editLine('', const KeyEvent(KeyCode.backspace)), '');
      expect(editLine('ab', keyEvent('ctrl+u')!), '');
    });

    test('leaves other keys to whoever has it', () {
      expect(editLine('ab', const KeyEvent(KeyCode.enter)), isNull);
      expect(editLine('ab', keyEvent('ctrl+p')!), isNull);
    });
  });

  test('a key name is the event it names', () {
    for (final name in [
      'tab',
      'shift+tab',
      'ctrl+p',
      'space',
      'pageup',
      'pagedown',
      't',
      'T',
      'escape',
      'ctrl+u',
      'alt+down',
    ]) {
      expect(keyName(keyEvent(name)!), name, reason: name);
    }
    expect(keyName(keyEvent('esc')!), 'escape');
    expect(keyEvent('nokey'), isNull);
  });

  group('the toasts', () {
    Toast at(int ms, [String m = 'x']) =>
        Toast(m, ToastKind.info, Duration(milliseconds: ms));

    test('the oldest goes past the cap, but for a route', () {
      final toasts = Toasts();
      for (var i = 0; i < toastCap + 1; i++) {
        toasts.add(at(i, '$i'));
      }
      expect([for (final t in toasts.list) t.message], ['1', '2', '3']);
      toasts.add(at(9, 'route'), capped: false);
      expect(toasts.list, hasLength(toastCap + 1));
    });

    test('each goes after its time; the next end is the first of them', () {
      final toasts = Toasts()
        ..add(at(0, 'a'))
        ..add(at(1000, 'b'));
      expect(toasts.nextEnd, const Duration(milliseconds: toastMs));
      toasts.expire(const Duration(milliseconds: toastMs));
      expect([for (final t in toasts.list) t.message], ['b']);
      toasts.expire(const Duration(milliseconds: toastMs + 1000));
      expect(toasts.isEmpty, isTrue);
      expect(toasts.nextEnd, isNull);
    });
  });

  test("the Code's record: the lines that changed, when", () {
    const t1 = Duration(seconds: 1);
    const t2 = Duration(seconds: 2);
    final first = CodeRecord.after(null, 'a\nb', t1);
    expect(first.changed, [null, null]);
    final second = CodeRecord.after(first, 'a\nB\nc', t2);
    expect(second.changed, [null, t2, t2]);
    final third = CodeRecord.after(second, 'a\nB', t1);
    expect(third.changed, [null, t2]);
    expect(third.tokens, hasLength(2));
  });

  test("the list's filter: all for none, else what fuzzyMatch finds", () {
    final groups = joinCatalog(galleryPages);
    final pages = [for (final g in groups) ...g.pages];
    expect(filtered(pages, ''), hasLength(pages.length));
    final found = filtered(pages, 'checkbox');
    expect(found.map((p) => p.title), contains('Checkbox, Switch'));
    expect(found.length, lessThan(pages.length));
  });

  group('the page store', () {
    final button = galleryPages.firstWhere((p) => p.title == 'Button');
    PageOption<Object?> optionOf(String key) =>
        button.options.firstWhere((o) => o.key == key);
    final look = optionOf('look') as ChoiceOption<String>;
    final tall = optionOf('tall') as SwitchOption;
    const key = 'controls/button';
    var updates = 0;
    final toasts = <(String, ToastKind)>[];
    PageStore store() => PageStore(
      update: (change) {
        change();
        updates++;
      },
      toast: (m, k) => toasts.add((m, k)),
    );

    test("a page's control sets its options by value, its state kept", () {
      final s = store();
      final control = s.controlOf(key, button)..setOption(look, 'filled');
      expect(s.optionsOf(key, button)(look), 'filled');
      final before = updates;
      control
        ..setOption(look, 'filled')
        ..setOption(look, 'no such look')
        ..setOption(const SwitchOption('nothing', 'nothing'), true);
      expect(updates, before, reason: 'nothing changed');
      control.state['saved'] = 2;
      expect(s.optionsOf(key, button).pageState['saved'], 2);
      control.toast('hi', ToastKind.success);
      expect(toasts.last, ('hi', ToastKind.success));
    });

    test('a reset empties both and counts', () {
      final s = store();
      final control = s.controlOf(key, button)..setOption(tall, true);
      control.state['saved'] = 1;
      s.reset(key);
      expect(s.optionsOf(key, button).route, isEmpty);
      expect(control.state, isEmpty);
      expect(s.resetsOf(key), 1);
    });
  });

  group("an option's values", () {
    test('a choice: by value, by name, round with the keys', () {
      const o = ChoiceOption(
        'k',
        'k',
        values: [null, 10, 4],
        labels: ['none', 'ten', 'four'],
      );
      expect(o.rawOf(10), 1);
      expect(o.rawOf(5), isNull);
      expect(o.rawNamed('four'), 2);
      expect(o.rawNamed('4'), isNull);
      expect(o.stepped(0, 'left'), 2);
      expect(o.stepped(2, 'right'), 0);
      expect(o.stepped(1, 'end'), 2);
      expect(o.stepped(1, 'up'), isNull);
    });

    test('a switch: a bool, true or on or 1, space and enter', () {
      const o = SwitchOption('k', 'k');
      expect(o.rawOf(true), isTrue);
      expect(o.rawOf(1), isNull);
      expect(o.rawNamed('on'), isTrue);
      expect(o.rawNamed('no'), isFalse);
      expect(o.stepped(false, 'space'), isTrue);
      expect(o.stepped(true, 'enter'), isFalse);
      expect(o.stepped(true, 'left'), isNull);
    });

    test('a slider: a number on its steps, a tenth for page keys', () {
      const o = SliderOption('k', 'k', min: 0, max: 100, step: 5);
      expect(o.rawOf(12), 12);
      expect(o.rawNamed('12'), 10);
      expect(o.rawNamed('200'), 100);
      expect(o.rawNamed('x'), isNull);
      expect(o.stepped(50, 'right'), 55);
      expect(o.stepped(50, 'pageup'), 60);
      expect(o.stepped(98, 'up'), 100);
      expect(o.stepped(50, 'home'), 0);
      expect(o.stepped(50, 'space'), isNull);
    });

    test("a colour: by the theme slot's name", () {
      const o = ColorOption('k', 'k', values: ['primary', 'accent']);
      expect(o.rawOf('accent'), 1);
      expect(o.rawOf(1), isNull);
      expect(o.rawNamed('primary'), 0);
      expect(o.stepped(1, 'right'), 0);
    });
  });
}
