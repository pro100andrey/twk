import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show runProcess;

void main() {
  test("code that breaks the framework's contracts gets analyzer "
      'warnings', () async {
    final dir = await Directory.systemTemp.createTemp('twk_contracts');
    addTearDown(() => dir.delete(recursive: true));
    await _writePackageConfig(dir);
    final sample = File('${dir.path}/lib/sample.dart');
    await sample.create(recursive: true);
    await sample.writeAsString(_sample);

    final result = await runProcess(Platform.resolvedExecutable, [
      'analyze',
      '--format=machine',
      dir.path,
    ], group: true);
    final found = <String>[
      for (final line in LineSplitter.split('${result.stdout}${result.stderr}'))
        if (line.split('|') case [_, _, final code, _, final at, ...])
          '$at ${code.toLowerCase()}',
    ];

    final lines = LineSplitter.split(_sample).toList();
    final expected = <String>[
      for (var i = 0; i < lines.length; i++)
        if (RegExp(r'// expect: (.*)$').firstMatch(lines[i]) case final m?)
          for (final code in m[1]!.split(', ')) '${i + 1} $code',
    ];
    expect(found, unorderedEquals(expected));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Writes into [dir] the package config the tests run with, its relative
/// roots made absolute, so that [_sample] there imports this package.
Future<void> _writePackageConfig(Directory dir) async {
  final uri = (await Isolate.packageConfig)!;
  final config = jsonDecode(await File.fromUri(uri).readAsString()) as Map;
  final packages = [
    for (final p in config['packages'] as List)
      {...p as Map, 'rootUri': uri.resolve(p['rootUri'] as String).toString()},
  ];
  final file = File('${dir.path}/.dart_tool/package_config.json');
  await file.create(recursive: true);
  await file.writeAsString(
    jsonEncode({'configVersion': 2, 'packages': packages}),
  );
}

/// An app's code that breaks each kind of contract; a line that is to get a
/// warning names its codes.
const _sample = '''
import 'package:twk/twk.dart';

class Sample extends StatefulWidget { // expect: must_be_immutable
  Sample({super.key});

  var taps = 0;

  @override
  State<Sample> createState() => SampleState();
}

class SampleState extends State<Sample> {
  @override
  void initState() {} // expect: must_call_super

  @override
  void didUpdateWidget(Sample oldWidget) {} // expect: must_call_super

  @override
  void didChangeDependencies() {} // expect: must_call_super

  @override
  void deactivate() {} // expect: must_call_super

  @override
  void activate() {} // expect: must_call_super

  @override
  void dispose() {} // expect: must_call_super

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class SampleKey extends LocalKey { // expect: must_be_immutable
  SampleKey();

  var hits = 0;
}

class SampleElement extends StatelessElement {
  SampleElement(super.widget);

  @override
  void mount(Element? parent, Object? newSlot) {} // expect: must_call_super

  @override
  void update(StatelessWidget newWidget) {} // expect: must_call_super

  @override
  void performRebuild() {} // expect: must_call_super

  @override
  void deactivate() {} // expect: must_call_super

  @override
  void activate() {} // expect: must_call_super

  @override
  void unmount() {} // expect: must_call_super
}

class Ping extends Notification {
  @override
  bool visitAncestor(Element element) => true; // expect: must_call_super
}

class Model extends ChangeNotifier {
  @override
  void dispose() {} // expect: must_call_super
}

void poke(
  SampleState state,
  Model model,
  Element element,
  Notification notification,
) {
  state.setState(() {}); // expect: invalid_use_of_protected_member
  element.updateChild(null, null, null); // expect: invalid_use_of_protected_member
  notification.visitAncestor(element); // expect: invalid_use_of_protected_member
  model.notifyListeners(); // expect: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
}
''';
