import 'dart:io';

import 'package:ssh_template/ssh_template.dart';
import 'package:test/test.dart';
import 'package:twk_ssh/twk_ssh.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('greets the user and counts with Up; q quits', (t) async {
    await t.pumpWidget(const Counter(user: 'ann'), size: (30, 7));
    expect(t, containsLine(contains('Hello, ann')));
    expect(t, containsLine(contains('30x7')));
    expect(t, containsLine(contains('Count: 0')));

    await t.press('up up');
    await t.pump();
    expect(t, containsLine(contains('Count: 2')));

    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  test('the server listens, makes its host key and closes', () async {
    final dir = await Directory.systemTemp.createTemp('ssh_template_test');
    addTearDown(() => dir.delete(recursive: true));
    final server = await serveCounter(
      port: 0,
      hostKeyPath: '${dir.path}/host_ed25519',
      authorizedKeysPath: '${dir.path}/authorized_keys',
    );
    expect(server.port, greaterThan(0));
    expect(File('${dir.path}/host_ed25519').existsSync(), isTrue);
    await server.close();
  });

  test('with no authorized_keys file only a key gets in, no password', () {
    final auth = SshAuth.authorizedKeys('/nonexistent/authorized_keys');
    expect(auth.methods, ['publickey']);
  });
}
