// A terminal with color scheme reports (DEC mode 2031), over a link in
// memory that answers the probe as a dark terminal with the mode, reports
// a switch to a light color scheme once the mode is turned on, and answers
// the query for the defaults that follows with the colors of a light one.
import 'package:test/test.dart';
import 'package:twk_core/terminal.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'fake_link.dart';
import 'on_clock.dart';

void main() {
  test('the reports are turned on while the app runs, and after one the '
      'default colors are asked for again', () async {
    final clock = FakeClock();
    final link = FakeLink()
      ..type(
        '\x1b[?2026;2\$y\x1b[?2027;0\$y\x1b[?2048;0\$y\x1b[?69;2\$y'
        '\x1b[?2031;2\$y'
        '\x1b]10;rgb:d0d0/d0d0/d0d0\x1b\\\x1b]11;rgb:1010/1212/1818\x1b\\'
        '\x1b[?0u\x1b[1;2R\x1b[?62;22c',
      );
    final term = await clock.open(
      link,
      const TerminalOptions(probeTimeout: Duration(seconds: 5)),
    );
    // what the app printed
    final printed = <String>[];
    final brightness = term.info.brightness?.name;
    printed.add(
      'brightness $brightness reports ${term.info.colorSchemeReports}',
    );
    var reported = false;
    final sub = term.events.listen((e) {
      switch (e) {
        case ColorSchemeReport(:final brightness):
          reported = true;
          printed.add('scheme ${brightness.name}');
        case ColorReport(:final which, :final rgb):
          printed.add('color $which ${rgb.toRadixString(16).padLeft(6, '0')}');
        default:
      }
    });
    addTearDown(sub.cancel);
    expect(link.text, contains('\x1b[?2031h'), reason: 'turned on');

    // the terminal reports the light scheme, and the app asks again
    final before = link.text.length;
    link.type('\x1b[?997;2n');
    await clock.flushMicrotasks();
    expect(reported, isTrue);
    final asked = link.text.indexOf(
      '\x1b]10;?\x1b\\\x1b]11;?\x1b\\',
      before,
    );
    expect(asked, greaterThanOrEqualTo(before));
    link.type(
      '\x1b]10;rgb:4c4c/4f4f/6969\x1b\\\x1b]11;rgb:efef/f1f1/f5f5\x1b\\',
    );
    await clock.flushMicrotasks();
    await clock.runUntil(term.close);

    expect(printed.join('\n'), '''
brightness dark reports true
scheme light
color 10 4c4f69
color 11 eff1f5''');
    final written = link.text;
    final on = written.indexOf('\x1b[?2031h');
    expect(written.indexOf('\x1b[?2031\$p'), inInclusiveRange(0, on));
    expect(asked, greaterThan(on));
    expect(written.indexOf('\x1b[?2031l', asked), greaterThan(asked));
    expect(written.lastIndexOf('\x1b[?2031h'), on, reason: 'turned on once');
  });
}
