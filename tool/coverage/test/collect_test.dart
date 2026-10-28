import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_coverage/coverage_report.dart';
import 'package:twk_doc_snippets/packages.dart';
import 'package:twk_test/twk_test.dart' show startProcess;

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('collect_test_'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('watch', () {
    test('answers the exit code of a run that writes coverage as it '
        'goes', () async {
      final dir = Directory('${temp.path}/cov')..createSync();
      const script =
          r'for i in 1 2 3 4 5 6; do sleep 0.2; touch "$0/$i.json"; done; '
          'exit 3';
      final run = await startProcess('sh', [
        '-c',
        script,
        dir.path,
      ], group: true);
      // 1.2 s in all, never 0.6 s without a file
      expect(await watch(run, dir, const Duration(milliseconds: 600)), 3);
    });

    test('stops a run that writes no coverage for as long as it is given, '
        'and answers null', () async {
      final dir = Directory('${temp.path}/cov')..createSync();
      // the runner stuck: the first signal does not stop it
      final run = await startProcess('sh', [
        '-c',
        'trap "" TERM; touch ${dir.path}/a.json; sleep 60',
      ], group: true);
      // Real time on purpose: how long watch waits is what is measured
      final clock = Stopwatch()..start();
      expect(await watch(run, dir, const Duration(milliseconds: 500)), isNull);
      expect(clock.elapsed, lessThan(const Duration(seconds: 15)));
      expect(await run.exitCode, isNot(0));
    });
  });

  test('failedIn finds a test that failed or erred in the JSON reporter '
      'lines', () {
    const passed =
        '{"type":"testStart","test":{"id":1}}\n'
        '{"testID":1,"result":"success","hidden":false,"type":"testDone"}\n';
    expect(failedIn(passed), isFalse);
    expect(failedIn(''), isFalse);
    expect(
      failedIn('$passed{"testID":2,"result":"failure","type":"testDone"}\n'),
      isTrue,
    );
    expect(
      failedIn('{"testID":2,"result":"error","type":"testDone"}'),
      isTrue,
    );
    // the last line of a run stopped while it wrote it
    expect(
      failedIn('$passed{"testID":2,"result":"success","type":"testDone","ti'),
      isFalse,
    );
  });

  test('dropUnreadable deletes the coverage files a stopped run left half '
      'written', () {
    final dir = Directory('${temp.path}/cov/test')..createSync(recursive: true);
    final whole = File('${dir.path}/a_test.dart.vm.json')
      ..writeAsStringSync('{"type":"CodeCoverage","coverage":[]}');
    final half = File('${dir.path}/b_test.dart.vm.json')
      ..writeAsStringSync('{"type":"CodeCov');
    dropUnreadable(Directory('${temp.path}/cov'));
    expect((whole.existsSync(), half.existsSync()), (true, false));
  });

  test('unmeasured lists the test files with no coverage file, '
      'sorted', () {
    final package = RepoPackage(temp.path, 'p', 'p');
    for (final f in [
      'a_test.dart',
      'b/c_test.dart',
      'b/d_test.dart',
      'e.dart',
    ]) {
      File('${package.path}/test/$f').createSync(recursive: true);
    }
    final dir = Directory('${temp.path}/cov');
    File('${dir.path}/test/b/c_test.dart.vm.json').createSync(recursive: true);
    expect(unmeasured(package, dir), [
      'test/a_test.dart',
      'test/b/d_test.dart',
    ]);
  });
}
