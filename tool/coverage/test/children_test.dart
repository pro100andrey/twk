// ChildCoverage over a package of its own in a temporary directory: a
// script run as the copied SDK's dart measured, and the processes it can't
// measure left to end as they would.
@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_coverage/children.dart';
import 'package:twk_doc_snippets/packages.dart';
import 'package:twk_test/twk_test.dart'
    show compiledProgram, runProcess, waitUntil;

void main() {
  // let_go.dart, run in a process of its own, compiled once
  late String letGo;
  setUpAll(
    () async => letGo = await compiledProgram(
      'test/let_go.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  late Directory temp;
  late RepoPackage package;
  late ChildCoverage children;
  late Directory out;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('children_test_');
    package = RepoPackage(temp.path, 'probe', 'probe');
    void write(String path, String text) => File('${package.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    write('lib/probe.dart', '''
int twice(int x) => x * 2;

int thrice(int x) => x * 3;
''');
    write('.dart_tool/package_config.json', '''
{"configVersion": 2, "packages": [
  {"name": "probe", "rootUri": "../", "packageUri": "lib/"}
]}
''');
    write('bin/main.dart', '''
import 'dart:io';
import 'package:probe/probe.dart';

void main(List<String> args) {
  print(twice(2));
  if (args.contains('exit')) exit(3);
  if (args.contains('sleep')) sleep(const Duration(seconds: 2));
}
''');
    out = Directory('${temp.path}/out');
    children = ChildCoverage.start(
      package,
      Directory('${temp.path}/work')..createSync(),
      out,
    )!;
  });
  tearDown(() async {
    await children.stop(grace: Duration.zero);
    temp.deleteSync(recursive: true);
  });

  Future<ProcessResult> run(List<String> args) => runProcess(
    children.dart,
    [
      '--packages=${package.path}/.dart_tool/package_config.json',
      ...args,
    ],
    workingDirectory: package.path,
    group: true,
  );

  test('a process started as the copied dart is measured, its output its '
      'own, and ends', () async {
    final res = await run(['bin/main.dart']).timeout(
      const Duration(seconds: 60),
    );
    expect((res.exitCode, res.stdout, res.stderr), (0, '4\n', ''));
    await children.stop();
    expect((children.measured, children.lost), (1, 0));
    final [file] = out.listSync();
    final coverage =
        (jsonDecode((file as File).readAsStringSync())
                as Map<String, Object?>)['coverage']!
            as List<Object?>;
    final hits = {
      for (final c in coverage.cast<Map<String, Object?>>())
        c['source']: c['hits'],
    };
    // line 1 ran; thrice, on line 3, never called, was never compiled
    expect(hits.keys, ['package:probe/probe.dart']);
    expect(hits['package:probe/probe.dart'], [1, isPositive]);
  });

  test('a compile to a kernel as the copied dart, as compiledProgram '
      'compiles under coverage, is no process measured; the kernel run as '
      'it is, as its source is', () async {
    final kernel = '${temp.path}/main.dill';
    final compiled = await runProcess(
      children.dart,
      [
        'compile',
        'kernel',
        '--no-link-platform',
        '--packages=${package.path}/.dart_tool/package_config.json',
        '--depfile=${temp.path}/main.d',
        '-Ddart.vm.product=false',
        '-o',
        kernel,
        'bin/main.dart',
      ],
      workingDirectory: package.path,
      group: true,
    ).timeout(const Duration(seconds: 60));
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    final res = await run([kernel]).timeout(const Duration(seconds: 60));
    expect((res.exitCode, res.stdout, res.stderr), (0, '4\n', ''));
    await children.stop();
    expect((children.measured, children.lost), (1, 0));
    final [file] = out.listSync();
    final coverage =
        (jsonDecode((file as File).readAsStringSync())
                as Map<String, Object?>)['coverage']!
            as List<Object?>;
    expect(
      [for (final c in coverage.cast<Map<String, Object?>>()) c['source']],
      ['package:probe/probe.dart'],
    );
  });

  test('a process ending by exit() is not measured, and ends', () async {
    final res = await run(['bin/main.dart', 'exit']).timeout(
      const Duration(seconds: 60),
    );
    expect(res.exitCode, 3);
    await children.stop();
    expect((children.measured, children.lost), (0, 1));
  });

  test('a kernel ending by exit() at once, before its VM service is up and '
      'has said where it listens, is not measured all the same', () async {
    // a kernel's main runs before the service is up (no compile to wait
    // for), and its exit() ends it before the service writes its file
    final kernel = '${temp.path}/main.dill';
    final compiled = await runProcess(
      Platform.resolvedExecutable,
      [
        'compile',
        'kernel',
        '--no-link-platform',
        '--packages=${package.path}/.dart_tool/package_config.json',
        '-o',
        kernel,
        'bin/main.dart',
      ],
      workingDirectory: package.path,
      group: true,
    ).timeout(const Duration(seconds: 60));
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    final res = await run([kernel, 'exit']).timeout(
      const Duration(seconds: 60),
    );
    expect((res.exitCode, res.stdout), (3, '4\n'));
    await children.stop();
    expect((children.measured, children.lost), (0, 1));
  });

  test('a process with VM service flags of its own runs without the '
      "coverage tool's", () async {
    final res = await run([
      '--enable-vm-service=0',
      'bin/main.dart',
    ]).timeout(const Duration(seconds: 60));
    expect(res.exitCode, 0);
    // its own service announced, as it would be
    expect(res.stdout, contains('The Dart VM service is listening on'));
    await children.stop();
    expect((children.measured, children.lost), (0, 0));
  });

  test('a process still running when the watch stops is let go: it ends '
      'without pausing, after the watch has', () async {
    final res = await runProcess(Platform.resolvedExecutable, [
      letGo,
      package.path,
      'bin/main.dart',
      '100',
    ], group: true);
    expect(res.exitCode, 0, reason: '${res.stderr}');
    final [pid, lost] = '${res.stdout}'
        .trim()
        .split(' ')
        .map(int.parse)
        .toList();
    expect(lost, 1);
    // it sleeps 2 s, then ends: paused on exit, it would not (and is
    // killed with the group of let_go.dart when the test ends)
    await waitUntil(
      () => !alive(pid),
      'the process let go to end',
      timeout: const Duration(seconds: 15),
    );
  });
}
