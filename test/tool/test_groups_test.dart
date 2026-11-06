// What goes into the entry points that join a suite's files (test_groups.dart)
// and what stays apart; the verb that writes them is xtask_test's.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/xtask/test_groups.dart';

const _plain = 'void main() {}\n';

void main() {
  test('every plain file is in one group, and a new one with no time too', () {
    final sources = {
      for (var i = 0; i < 20; i++) 'test/f${i}_test.dart': '\n$_plain',
    };
    final plan = planGroups(sources, groups: 3);
    expect(plan.groups, hasLength(3));
    expect(plan.apart, isEmpty);
    expect(plan.groups.expand((g) => g).toSet(), sources.keys.toSet());
    expect(plan.groups.expand((g) => g), hasLength(20));
  });

  test('a file whose meaning a join could change stays apart, saying why', () {
    final apart = planGroups({
      'test/on_test.dart': "@TestOn('vm')\nlibrary;\n\n$_plain",
      'test/tag_test.dart': "@Tags(['process'])\nlibrary;\n\n$_plain",
      'test/async_test.dart': '\nFuture<void> main() async {}\n',
      'test/stack_test.dart': '\n$_plain// StackTrace.current\n',
      'test/isolate_test.dart': '\n$_plain// Isolate.resolvePackageUri\n',
      'test/run_test.dart': '\n$_plain// Process.run\n',
      'test/own_test.dart': '\n$_plain// test/own_test.dart\n',
      'test/args_test.dart': '\nvoid main(List<String> args) {}\n',
      'test/plain_test.dart': '\n$_plain',
    }).apart;
    expect(apart, hasLength(8));
    expect(apart.keys, isNot(contains('test/plain_test.dart')));
    expect(apart['test/own_test.dart'], 'names its own path');
    expect(apart['test/stack_test.dart'], contains('stack'));
  });

  test('groups balance by the times given; a shuffle is its seed', () {
    final sources = {
      for (final f in 'abcd'.split('')) 'test/${f}_test.dart': '\n$_plain',
    };
    final plan = planGroups(
      sources,
      groups: 2,
      times: {
        'test/a_test.dart': 9,
        'test/b_test.dart': 5,
        'test/c_test.dart': 4,
        'test/d_test.dart': 1,
      },
    );
    expect(plan.groups, [
      ['test/a_test.dart', 'test/d_test.dart'],
      ['test/b_test.dart', 'test/c_test.dart'],
    ]);
    expect(
      planGroups(sources, groups: 2, shuffle: 3).groups,
      planGroups(sources, groups: 2, shuffle: 3).groups,
    );
  });

  test(
    'an entry imports from the package and groups each file by its path',
    () {
      final entry = entryPoint(['test/a/b_test.dart']);
      expect(entry, contains("import '../../test/a/b_test.dart' as f0;"));
      expect(entry, contains("group('test/a/b_test.dart', f0.main);"));
    },
  );

  test('dart test gets the entries and the files apart, but those of a '
      'process', () {
    final sources = {
      'test/a_test.dart': '\n$_plain',
      'test/on_test.dart': "@TestOn('mac-os')\nlibrary;\n\n$_plain",
      'test/tag_test.dart': "@Tags(['process'])\nlibrary;\n\n$_plain",
    };
    expect(testArguments(planGroups(sources), sources), [
      '.dart_tool/test_groups/group_0_test.dart',
      'test/on_test.dart',
    ]);
  });

  test("the times of a run: a group's test by its name, one apart by its "
      'suite, the loading of a suite by nothing', () {
    String event(Map<String, Object> e) => jsonEncode(e);
    Map<String, Object> started(int id, int suite, String name, int time) => {
      'type': 'testStart',
      'time': time,
      'test': {'id': id, 'suiteID': suite, 'name': name},
    };
    Map<String, Object> done(int id, int time) => {
      'type': 'testDone',
      'testID': id,
      'time': time,
    };
    expect(
      timesOf([
        'not json',
        for (final (id, path) in [
          (0, '.dart_tool/test_groups/group_0_test.dart'),
          (1, 'test/apart_test.dart'),
        ])
          event({
            'type': 'suite',
            'suite': {'id': id, 'path': path},
          }),
        event(started(1, 0, 'loading .dart_tool/x', 0)),
        event(done(1, 500)),
        event(started(2, 0, 'test/a_test.dart a test', 1000)),
        event(done(2, 3000)),
        event(started(3, 0, 'test/a_test.dart another', 3000)),
        event(done(3, 3500)),
        event(started(4, 1, 'a test apart', 0)),
        event(done(4, 1000)),
      ]),
      {'test/a_test.dart': 2.5, 'test/apart_test.dart': 1.0},
    );
  });

  test("writing groups leaves the last run's times and drops its entries", () {
    final dir = Directory.systemTemp.createTempSync('test_groups');
    addTearDown(() => dir.deleteSync(recursive: true));
    final old = File('${dir.path}/group_7_test.dart')..writeAsStringSync('x');
    final times = File('${dir.path}/times.json')..writeAsStringSync('{}');
    writeGroups(
      dir,
      const TestGroups(
        groups: [
          ['test/a_test.dart'],
        ],
        apart: {},
      ),
    );
    expect(old.existsSync(), isFalse);
    expect(times.existsSync(), isTrue);
    expect(File('${dir.path}/group_0_test.dart').existsSync(), isTrue);
  });
}
