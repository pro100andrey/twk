import 'dart:isolate';

import 'package:test/test.dart';
// Imported so that this file fails to load when a library that twk.dart
// exports is missing or does not compile.
// ignore: unused_import
import 'package:twk/twk.dart';
// Imported so that this file fails to load when cli.dart does not
// compile.
// ignore: unused_import
import 'package:twk_test/cli.dart';
// Imported so that this file fails to load when twk_test.dart does not
// compile.
// ignore: unused_import
import 'package:twk_test/twk_test.dart';

Future<Uri> resolve(String library) async =>
    (await Isolate.resolvePackageUri(Uri.parse(library)))!;

void main() {
  test('twk and twk_core resolve to the packages of this repository', () async {
    final tester = await resolve('package:twk_test/twk_test.dart');
    expect(
      await resolve('package:twk/twk.dart'),
      tester.resolve('../../twk/lib/twk.dart'),
    );
    expect(
      await resolve('package:twk_core/twk_core.dart'),
      tester.resolve('../../twk_core/lib/twk_core.dart'),
    );
  });
}
