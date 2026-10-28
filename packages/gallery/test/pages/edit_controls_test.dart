// The Editing and Controls pages: each builds at both sizes, its options
// apply and its keys do what the design's do.
import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] in a terminal of [size], a frame for the
/// route's focus after the first.
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = (120, 36),
}) async {
  await t.pumpWidget(galleryApp(route: GalleryRoute.parse(route)), size: size);
  await t.pump();
}

/// Presses [keys] (apart by commas), a frame after each.
Future<void> keys(TwkTester t, String keys) async {
  for (final k in keys.split(',')) {
    await t.press(k);
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 500));
}

/// Types [text], then a frame.
Future<void> type(TwkTester t, String text) async {
  await t.type(text);
  await t.pump(const Duration(milliseconds: 500));
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

/// Each page's route and a text its stage shows.
const _pages = {
  'editing/textfield': 'submitted: nothing',
  'editing/textarea': 'line 2 of 2, column 21',
  'editing/autocomplete': 'chosen: nothing',
  'controls/button': 'saved: 0',
  'controls/checkbox-switch': 'dark mode',
  'controls/radiogroup': 'chosen: nothing',
  'controls/selectionlist': 'Mercury',
  'controls/select-multiselect': 'some fruit',
  'controls/confirminput': 'Delete 3 files?',
  'controls/slider': 'volume: 50%',
  'controls/numberinput': '1 × 9.50 = 9.50',
  'controls/datepicker': 'picked: nothing',
  'controls/filepicker': 'In a dialog',
  'controls/form-formfield': 'I accept the terms',
  'controls/tabbar-tabview': 'wrap lines',
  'controls/keyhintsbar': 'did: nothing',
  'controls/statusmessage-badge': 'Saving runs in the background.',
  'controls/link': 'The Dart language',
  'controls/statusbar': 'NORMAL',
};

void main() {
  group('each page builds', () {
    for (final size in const [(120, 36), (80, 24)]) {
      for (final MapEntry(key: page, value: shows) in _pages.entries) {
        testTwk('$page at ${size.$1}x${size.$2}', (t) async {
          await open(t, '#/$page?t=2000', size: size);
          expect(screen(t), contains(shows));
          expect(screen(t), isNot(contains('drawn in the next part')));
          expect(problems(t), isEmpty);
        });
      }
    }
  });

  group('the options apply', () {
    const routes = {
      'editing/textfield?o=obscure:true;maxLength:8': [
        'obscureText: true',
        'maxLength: 8',
      ],
      'editing/textarea?o=enter:submits;cursor:block': [
        'cursorShape: .block',
        'onSubmitted:',
      ],
      'editing/autocomplete?o=trigger:none;rows:4': ['rows: 4', '_fruit'],
      'controls/radiogroup?o=direction:horizontal': ['.horizontal'],
      'controls/selectionlist?o=multiple:true': ['multiple: true'],
      'controls/select-multiselect?o=inline:true;rows:8': [
        'inline: true',
        'rows: 8',
      ],
      'controls/confirminput?o=default:no;labels:Delete, Keep': [
        'defaultValue: false',
        "yes: 'Delete'",
      ],
      'controls/slider?o=divisions:4;width:20': ['divisions: 4', 'width: 20'],
      'controls/datepicker?o=time:true;week:sunday': [
        'showTime: true',
        'DateTime.sunday',
      ],
      'controls/filepicker?o=mode:directory': ['mode: .directory'],
      'controls/form-formfield?o=validate:always': ['.always'],
      'controls/tabbar-tabview?o=tabs:7': ['length: 7'],
      'controls/keyhintsbar?o=unhinted:true': ['showUnhinted: true'],
      'controls/statusmessage-badge?o=kind:error': ['kind: .error'],
      'controls/link?o=color:accent': ['theme.accent'],
      'controls/statusbar?o=width:20': ['width: 20'],
    };
    for (final MapEntry(key: route, value: code) in routes.entries) {
      testTwk('$route, in the Code', (t) async {
        await open(t, '#/$route&tab=code&t=2000', size: (160, 90));
        for (final c in code) {
          expect(screen(t), contains(c), reason: route);
        }
        expect(problems(t), isEmpty);
      });
    }

    testTwk('the stage follows them', (t) async {
      await open(t, '#/controls/radiogroup?o=direction:horizontal&t=2000');
      expect(screen(t), contains('( ) apple  ( ) banana'));
      await open(t, '#/controls/confirminput?o=labels:Delete, Keep&t=2000');
      expect(screen(t), contains('Delete'));
      expect(screen(t), contains('Keep'));
      await open(t, '#/controls/statusmessage-badge?o=kind:error&t=2000');
      expect(screen(t), contains('Could not save 3 files.'));
      await open(t, '#/controls/tabbar-tabview?o=tabs:7&t=2000');
      expect(screen(t), contains('Plugins'));
      expect(problems(t), isEmpty);
    });
  });

  group('the keys', () {
    testTwk("the file picker's tree is the design's, on no disk", (t) async {
      await open(t, '#/controls/filepicker?t=2000');
      await t.pump(const Duration(milliseconds: 100));
      var s = screen(t);
      expect(s, contains('/home/user/twk/'));
      expect(s, contains('example/'));
      expect(s, contains('test/'));
      await keys(t, 'tab');
      await type(t, 'example/widgets/');
      await keys(t, 'enter');
      s = screen(t);
      expect(s, contains('/home/user/twk/example/widgets/'));
      expect(s, contains('controls.dart'));
      await keys(t, 'ctrl+a,ctrl+k');
      await type(t, '~/notes.md');
      await keys(t, 'enter');
      // on a line of its own beside the two buttons
      expect(screen(t), contains('picked:'));
      expect(screen(t), contains('/home/user/notes.md'));
    });

    testTwk('a field submits on Enter', (t) async {
      await open(t, '#/editing/textfield?t=2000');
      await keys(t, 'tab');
      await type(t, 'hello');
      await keys(t, 'enter');
      expect(screen(t), contains('submitted: hello'));
    });

    testTwk('an obscured field takes eight characters at most', (t) async {
      await open(t, '#/editing/textfield?o=obscure:true;maxLength:8&t=2000');
      await keys(t, 'tab');
      await type(t, 'secret words');
      await keys(t, 'enter');
      expect(screen(t), contains('submitted: ••••••••'));
      expect(screen(t), isNot(contains('•••••••••')));
    });

    testTwk('Ctrl+Z undoes in a field', (t) async {
      await open(t, '#/editing/textfield?t=2000');
      await keys(t, 'tab');
      await type(t, 'hello');
      await keys(t, 'shift+left,backspace');
      expect(screen(t), contains('hell '));
      await keys(t, 'ctrl+z,enter');
      expect(screen(t), contains('submitted: hello'));
    });

    testTwk('an area says where its caret is, and submits', (t) async {
      await open(t, '#/editing/textarea?o=enter:submits&t=2000');
      await keys(t, 'tab,ctrl+end');
      expect(screen(t), contains('line 2 of 2, column 21'));
      await keys(t, 'enter');
      expect(screen(t), contains('submitted: 2 lines, 72 characters'));
    });

    testTwk('suggestions show after the trigger; Enter puts one in', (t) async {
      await open(t, '#/editing/autocomplete?t=2000');
      await keys(t, 'tab');
      await type(t, '/s');
      expect(screen(t), contains('in the files'));
      await keys(t, 'down,enter');
      expect(screen(t), contains('chosen: search'));
    });

    testTwk('Enter and Space press the buttons', (t) async {
      await open(t, '#/controls/button?t=2000');
      await keys(t, 'tab,enter,tab,space');
      expect(screen(t), contains('saved: 1  sent: 1'));
    });

    testTwk('Space flips the checkbox and the switch', (t) async {
      await open(t, '#/controls/checkbox-switch?t=2000');
      expect(screen(t), contains('[x] wrap lines'));
      await keys(t, 'tab,space');
      expect(screen(t), contains('[ ] wrap lines'));
    });

    testTwk('the arrows choose in a radio group, past a disabled one', (
      t,
    ) async {
      await open(t, '#/controls/radiogroup?t=2000');
      await keys(t, 'tab,down');
      expect(screen(t), contains('chosen: apple'));
      await keys(t, 'down,down,down');
      expect(screen(t), contains('chosen: apple'));
    });

    testTwk('a single selection follows the cursor, past Venus', (t) async {
      await open(t, '#/controls/selectionlist?t=2000');
      await keys(t, 'tab,up');
      // what is selected is listed beside the list's first row
      bool beside(String selected) =>
          t.lines.any((l) => RegExp('Mercury +│  $selected').hasMatch(l));
      expect(beside('Mercury'), isTrue);
      await keys(t, 'down');
      expect(beside('Earth'), isTrue);
    });

    testTwk('Space selects several in a multiple selection', (t) async {
      await open(t, '#/controls/selectionlist?o=multiple:true&t=2000');
      await keys(t, 'tab,down,space');
      expect(screen(t), contains('Mars'));
    });

    testTwk('a Select opens on Enter and chooses', (t) async {
      await open(t, '#/controls/select-multiselect?t=2000');
      await keys(t, 'tab,enter');
      expect(t.lines.last, contains('esc close'));
      await keys(t, 'down,enter');
      expect(screen(t), contains('apricot'));
    });

    testTwk('y answers a ConfirmInput', (t) async {
      await open(t, '#/controls/confirminput?t=2000');
      await keys(t, 'tab,n');
      expect(screen(t), contains('answer: no'));
    });

    testTwk('the arrows move a slider', (t) async {
      await open(t, '#/controls/slider?o=divisions:4&t=2000');
      await keys(t, 'tab,right');
      expect(screen(t), contains('volume: 75%'));
    });

    testTwk('Up steps a number input; the total follows', (t) async {
      await open(t, '#/controls/numberinput?t=2000');
      await keys(t, 'tab,up');
      expect(screen(t), contains('2 × 9.50 = 19.00'));
    });

    testTwk('Up steps a date picker from today', (t) async {
      await open(t, '#/controls/datepicker?t=2000');
      await keys(t, 'tab,up');
      expect(screen(t), contains('picked: Monday, 19 October'));
      await keys(t, 'alt+down');
      expect(screen(t), contains('October 2026'));
      expect(
        t.lines.last.trim(),
        '←↑↓→ day   pgup pgdn month   enter pick   esc close',
      );
    });

    testTwk('a form says what is wrong when submitted empty', (t) async {
      await open(t, '#/controls/form-formfield?t=2000');
      await keys(t, 'tab,tab,tab,tab,enter');
      expect(screen(t), contains('a name, please'));
      expect(screen(t), contains('submitted: nothing'));
    });

    testTwk('the arrows pick a tab', (t) async {
      await open(t, '#/controls/tabbar-tabview?t=2000');
      await keys(t, 'tab,right');
      expect(screen(t), contains('Indent with'));
    });

    testTwk('the bar lists the keys bound where the focus is', (t) async {
      await open(t, '#/controls/keyhintsbar?t=2000');
      await keys(t, 'tab');
      expect(screen(t), contains('ctrl+s save   ctrl+x ctrl+o open'));
      await keys(t, 'ctrl+s');
      expect(screen(t), contains('did: save'));
    });
  });
}
