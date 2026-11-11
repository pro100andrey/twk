@Tags(['process'])
library;

// A RenderPositionedBox given a child bigger than it can be (which the
// size-within-constraints assert forbids, so a release build is the only
// place it happens) places it by a negative offset and cuts it off. The
// case runs in a process without asserts.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('cuts off a child that sticks out of it, with asserts off', () async {
    final r = await Process.run(Platform.resolvedExecutable, [
      'run',
      'test/render/positioned_oversized_child_app.dart',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect('${r.stdout}'.split('\n'), [
      'asserts=false',
      '',
      '   cde',
      '',
      'dx=-2',
      '',
      '   abc',
      '',
      '',
    ]);
  });
}
