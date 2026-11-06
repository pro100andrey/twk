// `twk create` run as an agent or CI runs it, in a process of its own whose
// stdin and stdout are not a terminal: it asks nothing and finishes. The
// case that must never hang, so each run is bounded, and a run that does
// not end fails the test and is killed rather than waited for.
@Tags(['process'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show startProcess;

import 'create_cycle.dart';
import 'twk.dart';

/// How long `twk create` may take without a terminal, a compiled program
/// writing a few files: a hang is told from slowness by far more than
/// that.
const _bound = Duration(seconds: 60);

void main() {
  setUpAll(compileTwk);

  /// `twk create <dir>` with [arguments] in a process of its own, its
  /// stdin a pipe that is held open (nobody types, nobody closes it, as
  /// under an agent's harness) and its stdout a pipe: its exit code, and
  /// what it wrote.
  Future<(int, String, String)> run(List<String> arguments) async {
    final process = await startProcess(Platform.resolvedExecutable, [
      twkProgram,
      'create',
      ...arguments,
    ]);
    final out = utf8.decodeStream(process.stdout);
    final err = utf8.decodeStream(process.stderr);
    final code = await process.exitCode.timeout(
      _bound,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        fail(
          'twk create ${arguments.join(' ')} did not end in $_bound: it is '
          'waiting for an answer nobody can give',
        );
      },
    );
    return (code, await out, await err);
  }

  test('asks nothing and takes the defaults: the app, no files for agents, '
      'the output as it was before it asked', () async {
    final dir = p.join(await temporary(), 'my_app');
    final (code, out, err) = await run([dir]);

    expect(code, 0, reason: err);
    expect(out, contains('of the template app'));
    expect(out, isNot(contains('?')));
    expect(File(p.join(dir, 'lib', 'my_app.dart')).existsSync(), isTrue);
    expect(filesIn(dir), isNot(contains('AGENTS.md')));
    expect(
      filesIn(dir)
          .where((f) => f.startsWith('.agents') || f.contains('.claude')),
      isEmpty,
    );
  });

  test('--agents says the files, and --template the app, without a '
      'terminal as with one', () async {
    final dir = p.join(await temporary(), 'my_app');
    final (code, out, err) = await run([
      dir,
      '--template=form',
      '--agents=agents-md,skill',
    ]);

    expect(code, 0, reason: err);
    expect(out, contains('of the template form'));
    final files = filesIn(dir);
    expect(files, contains('AGENTS.md'));
    expect(files, contains(p.join('.agents', 'skills', 'twk', 'SKILL.md')));
    expect(files, contains(p.join('.claude', 'skills', 'twk', 'SKILL.md')));
  });

  test('a bad --agents is refused with 64', () async {
    final dir = p.join(await temporary(), 'my_app');
    final (code, _, err) = await run([dir, '--agents=bogus']);

    expect(code, 64);
    expect(err, contains('agents'));
    expect(Directory(dir).existsSync(), isFalse);
  });
}
