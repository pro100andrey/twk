// TerminalInfo.terminalVersion: the name and version the terminal told by
// XTVERSION, empty where it did not.
import 'package:test/test.dart';
import 'package:twk_core/src/terminal/terminal.dart';

import 'fake_link.dart';

Future<String> versionOf(String answers) async {
  final link = FakeLink(environment: const {'TERM': 'xterm-256color'})
    ..type('$answers\x1b[?62;22c');
  final term = await openOwnOrShell(
    link,
    const TerminalOptions(probeTimeout: Duration(seconds: 5)),
  );
  await term.close();
  return term.info.terminalVersion;
}

void main() {
  test('is what XTVERSION answered', () async {
    expect(await versionOf('\x1bP>|kitty(0.39.1)\x1b\\'), 'kitty(0.39.1)');
  });

  test('is empty where the terminal did not answer it', () async {
    expect(await versionOf(''), '');
  });
}
