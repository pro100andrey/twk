// What the tests that run `twk` in this process (twk.dart's TwkHere) see
// of its stdout and stderr.
import 'package:test/test.dart';

import 'twk.dart';

void main() {
  test('a character split between two writes is kept whole', () {
    final text = StringBuffer();
    // Ж, 0xD0 0x96 in UTF-8
    Captured(text)
      ..add([0x61, 0xD0])
      ..add([0x96, 0x62]);
    expect('$text', 'aЖb');
  });

  test('text and bytes keep their order', () {
    final text = StringBuffer();
    Captured(text)
      ..write('a')
      ..add([0xD0, 0xB1]) // б
      ..writeln('c');
    expect('$text', 'aбc\n');
  });

  test('a character left unfinished at the close is U+FFFD', () async {
    final text = StringBuffer();
    final captured = Captured(text)..add([0x61, 0xD0]);
    await captured.close();
    expect('$text', 'a\u{FFFD}');
  });

  test("the command's output is whole once it ended", () async {
    final run = TwkHere.start(['--help']);
    expect(await run.exitCode, 0);
    expect('${run.out}', contains('Usage: twk'));
  });
}
