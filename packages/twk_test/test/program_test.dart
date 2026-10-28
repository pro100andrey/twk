// compiledProgram: a program of a temporary directory compiled once and
// kept, compiled again when a file it is compiled from changes.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

/// Long before any compile of the test's: a kernel that still has it was
/// not written again.
final _long = DateTime(2001);

void main() {
  late Directory dir;
  late String packages;
  late String cache;
  late File said;

  setUpAll(() async => packages = (await Isolate.packageConfig)!.toFilePath());

  setUp(() {
    dir = Directory.systemTemp.createTempSync('twk_program_');
    cache = '${dir.path}/cache';
    // the program prints what the library it imports says
    File('${dir.path}/app.dart').writeAsStringSync('''
import 'said.dart';

void main() => print(said);
''');
    said = File('${dir.path}/said.dart')
      ..writeAsStringSync("const said = 'one';\n");
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String> compile() =>
      compiledProgram('${dir.path}/app.dart', packages: packages, cache: cache);

  Future<String> run(String kernel) async {
    final res = await runProcess(Platform.resolvedExecutable, [kernel]);
    expect(res.exitCode, 0, reason: '${res.stderr}');
    // a line ends in CR LF on Windows
    return '${res.stdout}'.replaceAll('\r\n', '\n');
  }

  test('compiled to a kernel in the cache, which runs', () async {
    final kernel = await compile();
    expect(kernel, startsWith('$cache/app-'));
    expect(kernel, endsWith('.dill'));
    expect(await run(kernel), 'one\n');
  });

  test('a program in a directory below, by a path with / or with the '
      "platform's separator: its kernel in the cache itself", () async {
    final below = Directory('${dir.path}/lib/src')..createSync(recursive: true);
    File('${below.path}/deep.dart').writeAsStringSync(
      "void main() => print('deep');\n",
    );
    for (final path in [
      '${dir.path}/lib/src/deep.dart',
      [dir.path, 'lib', 'src', 'deep.dart'].join(Platform.pathSeparator),
    ]) {
      final kernel = await compiledProgram(
        path,
        packages: packages,
        cache: cache,
      );
      expect(kernel, startsWith('$cache/deep-'));
      expect(await run(kernel), 'deep\n');
    }
  });

  test('called again, its files unchanged: the kernel kept, nothing '
      'compiled', () async {
    final kernel = await compile();
    File(kernel).setLastModifiedSync(_long);
    expect(await compile(), kernel);
    expect(File(kernel).lastModifiedSync(), _long);
    expect(await run(kernel), 'one\n');
  });

  test('a library it imports changed: compiled again', () async {
    final kernel = await compile();
    File(kernel).setLastModifiedSync(_long);
    said.writeAsStringSync("const said = 'two';\n");
    expect(await compile(), kernel);
    expect(File(kernel).lastModifiedSync(), isNot(_long));
    expect(await run(kernel), 'two\n');
  });

  test('a file it imports that is new, by an import added: compiled with '
      'it, and again when it changes', () async {
    await compile();
    File('${dir.path}/more.dart').writeAsStringSync("const more = 'a';\n");
    said.writeAsStringSync(r'''
import 'more.dart';

const said = 'one $more';
''');
    final kernel = await compile();
    expect(await run(kernel), 'one a\n');
    File(kernel).setLastModifiedSync(_long);
    File('${dir.path}/more.dart').writeAsStringSync("const more = 'b';\n");
    await compile();
    expect(await run(kernel), 'one b\n');
  });

  test('a file it was compiled from that is gone: compiled again, failing '
      'without it', () async {
    await compile();
    said.deleteSync();
    await expectLater(
      compile(),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          allOf(contains('app.dart does not compile'), contains('said.dart')),
        ),
      ),
    );
  });

  test('another program or another cache: a kernel of its own', () async {
    File('${dir.path}/other.dart').writeAsStringSync(
      "void main() => print('other');\n",
    );
    final kernel = await compile();
    final other = await compiledProgram(
      '${dir.path}/other.dart',
      packages: packages,
      cache: cache,
    );
    final elsewhere = await compiledProgram(
      '${dir.path}/app.dart',
      packages: packages,
      cache: '${dir.path}/elsewhere',
    );
    expect({kernel, other, elsewhere}, hasLength(3));
    expect(await run(other), 'other\n');
    expect(await run(elsewhere), 'one\n');
  });

  test('declarations it is compiled with: a kernel of their own, whose '
      'constants they are, as the run cannot change them', () async {
    File('${dir.path}/word.dart').writeAsStringSync(
      "void main() => print(const String.fromEnvironment('word'));\n",
    );
    Future<String> word(Map<String, String> defines) => compiledProgram(
      '${dir.path}/word.dart',
      packages: packages,
      cache: cache,
      defines: defines,
    );
    final plain = await word({});
    final a = await word({'word': 'a'});
    final b = await word({'word': 'b'});
    expect({plain, a, b}, hasLength(3));
    expect(await run(plain), '\n');
    expect(await run(a), 'a\n');
    expect(await run(b), 'b\n');
    final res = await runProcess(Platform.resolvedExecutable, [
      '-Dword=c',
      a,
    ]);
    expect(res.stdout, 'a\n');
  });

  test('not in product mode, as `dart <program>` runs it, unless asked '
      'for', () async {
    File('${dir.path}/product.dart').writeAsStringSync(
      "void main() => print(const bool.fromEnvironment('dart.vm.product'));\n",
    );
    Future<String> product(Map<String, String> defines) async => run(
      await compiledProgram(
        '${dir.path}/product.dart',
        packages: packages,
        cache: cache,
        defines: defines,
      ),
    );
    expect(await product({}), 'false\n');
    expect(await product({'dart.vm.product': 'true'}), 'true\n');
  });

  test('called twice at once: both get the kernel, which runs', () async {
    final [a, b] = await Future.wait([compile(), compile()]);
    expect(a, b);
    expect(await run(a), 'one\n');
    expect(
      Directory(cache).listSync().map((f) => f.path.split('/').last),
      unorderedEquals([
        matches(r'^app-[0-9a-f]{16}\.dill$'),
        matches(r'^app-[0-9a-f]{16}\.deps$'),
        matches(r'^app-[0-9a-f]{16}\.lock$'),
      ]),
      reason: 'no temporary file left',
    );
  });
}
