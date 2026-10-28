// FakeStderr: the writes kept, whole and as lines, each tagged as it comes.
// ignore_for_file: close_sinks, each stands in for stderr, which stays open
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  test('each write is kept whole, and lines splits them at their line '
      'breaks; write is kept as writeln is', () {
    final err = FakeStderr()
      ..writeln('one\ntwo')
      ..write('three')
      ..writeln();
    expect(err.writes, ['one\ntwo', 'three', '']);
    expect(err.lines, ['one', 'two', 'three', '']);
  });

  test('with a tag, a write is kept after what the tag says when it '
      'comes', () {
    var state = 'on screen';
    final err = FakeStderr(tag: () => state)..writeln('a\nb');
    state = 'restored';
    err.writeln('c');
    expect(err.writes, ['on screen: a\nb', 'restored: c']);
    expect(err.lines, ['on screen: a', 'b', 'restored: c']);
  });

  test("it stands in for the process's stderr under IOOverrides; any "
      'other member throws, naming it', () {
    final err = FakeStderr();
    IOOverrides.runZoned(
      () => stderr.writeln('warning'),
      stderr: () => err,
    );
    expect(err.lines, ['warning']);
    expect(
      () => err.add([0x61]),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('add'),
        ),
      ),
    );
  });
}
