// openNamed: the identity a look is told with when the name changes across
// every open.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/src/platform/io.dart' show openNamed;

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('twk_open'));
  tearDown(() => dir.delete(recursive: true));

  test(
    'a name that changes across every open is given up on with the '
    'identity read before the open: the next look finds the change',
    () async {
      final file = File('${dir.path}${Platform.pathSeparator}app.log')
        ..writeAsStringSync('a');
      var opens = 0;
      var reads = 0;
      final opened = await openNamed(
        open: () {
          opens++;
          return file.open();
        },
        // one file at the name before an open, another after it, every time
        identity: () => (reads++).isEven ? 'A' : 'B',
      );
      addTearDown(() => opened!.$1.close());
      expect(opens, 4);
      expect(opened!.$2, 'A');
    },
  );

  test(
    'a name that settles is told with its identity, a handle kept',
    () async {
      final file = File('${dir.path}${Platform.pathSeparator}app.log')
        ..writeAsStringSync('a');
      var reads = 0;
      final opened = await openNamed(
        open: file.open,
        // changes across the first open only
        identity: () => (reads++) == 1 ? 'B' : 'A',
      );
      addTearDown(() => opened!.$1.close());
      expect(opened!.$2, 'A');
    },
  );

  test('no file is null', () async {
    final opened = await openNamed(
      open: File('${dir.path}${Platform.pathSeparator}none').open,
      identity: () => null,
    );
    expect(opened, isNull);
  });
}
