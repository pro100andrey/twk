/// A stderr that keeps what is written to it: [FakeStderr].
///
/// @docImport 'tester.dart';
library;

import 'dart:io';

// Examples can assume:
// import 'dart:io';
// import 'package:test/test.dart';

/// A stderr that keeps what is written to it, for code run under
/// [IOOverrides] with it in place of the process's own, which stays
/// untouched.
///
/// Each [write] or [writeln] is a write ([writes]), the text whole; with
/// [tag], it is kept as `<tag>: <text>`, the tag asked for when the write
/// comes: the state of something else at that moment, as whether a
/// terminal was restored. [lines] is every write's text split at its line
/// breaks. Only [write] and [writeln] are there; any other member of
/// [Stdout] throws an [UnsupportedError] naming it.
///
/// What a test's code writes to stderr, kept:
///
/// ```dart
/// final stderr = FakeStderr();
/// IOOverrides.runZoned(
///   () => stderr.writeln('warning: low\non disk'),
///   stderr: () => stderr,
/// );
/// expect(stderr.lines, ['warning: low', 'on disk']);
/// ```
///
/// See also:
///
///  * [TwkTester.stderrLines], what an app under test wrote to its
///    stderr, which the tester keeps in one of these.
final class FakeStderr implements Stdout {
  /// A stderr that keeps each write, tagged by [tag] when given.
  FakeStderr({this.tag});

  /// What a write is tagged with when it comes; null for no tag.
  final String Function()? tag;

  /// The writes so far, in order, each as [FakeStderr] says.
  final writes = <String>[];

  /// The lines written so far: the text of [writes] split at its line
  /// breaks, a write's tag on its first line alone.
  List<String> get lines => [for (final w in writes) ...w.split('\n')];

  /// Keeps [object]'s text as a write.
  @override
  void writeln([Object? object = '']) {
    final tag = this.tag;
    writes.add(tag == null ? '$object' : '${tag()}: $object');
  }

  /// Keeps [object]'s text as a write, as [writeln] does: a write is a
  /// line of its own.
  @override
  void write(Object? object) => writeln(object);

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('stderr.${invocation.memberName}');
}
