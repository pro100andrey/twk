import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:twk_dev/twk_dev.dart';
import 'package:twk_test/twk_test.dart' show compiledProgram, startProcess;

/// This package's directory.
Future<String> packageDirectory() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:twk_dev/twk_dev.dart'),
  );
  return library!.resolve('..').toFilePath();
}

/// The program at [path] in this package (`example/tally.dart`) compiled
/// to a kernel, which a test runs as `dart <kernel>` in a process of its
/// own: compiled once, in `setUpAll`, and kept for the runs after
/// ([compiledProgram]).
Future<String> compiled(String path) async {
  final dir = await packageDirectory();
  return compiledProgram(
    p.join(dir, path),
    packages: (await Isolate.packageConfig)!.toFilePath(),
    cache: p.join(dir, '.dart_tool', 'twk_test', 'programs'),
  );
}

/// The `twk` command compiled to a kernel by [compileTwk].
String? _twk;

/// Compiles the `twk` command ([compiled]) for [twkProgram]: a suite that
/// runs it in a process of its own calls it in `setUpAll`.
Future<void> compileTwk() async => _twk ??= await compiled('bin/twk.dart');

/// The kernel of the `twk` command, which [compileTwk] compiled: what a
/// test runs as `dart <kernel> <arguments>` for `twk <arguments>`.
String get twkProgram =>
    _twk ?? (throw StateError('compileTwk() not called in setUpAll'));

/// Starts `dart run twk_dev:twk` with [arguments] from this package's
/// directory, the way a developer starts it: for what takes a process of
/// its own (a signal sent to it, what its children write to its stdio).
///
/// `dart run` builds the executable first whenever a package it depends
/// on changed, which on a busy machine takes much of a test's time limit:
/// whatever does not need the process runs here ([twkHere]).
Future<Process> startTwk(List<String> arguments) async => startProcess(
  Platform.resolvedExecutable,
  ['run', 'twk_dev:twk', ...arguments],
  workingDirectory: await packageDirectory(),
  group: true,
);

/// Runs the `twk` command on [arguments] in this process ([runTwk]),
/// without a terminal: its exit code, and what it printed and wrote to
/// stdout and stderr.
Future<ProcessResult> twkHere(List<String> arguments) async {
  final run = TwkHere.start(arguments);
  final code = await run.exitCode;
  return ProcessResult(0, code, '${run.out}', '${run.err}');
}

/// The `twk` command running in this process ([runTwk]) as in one
/// started without a terminal: stdin and stdout are none (stdin gives
/// nothing), and what it prints and writes to stdout and stderr is kept.
///
/// A child it starts inheriting stdio gets this process's, as the child
/// of a `twk` process gets that one's.
final class TwkHere {
  TwkHere._(this.exitCode, this.out, this.err);

  /// Starts the command on [arguments]: [runTwk], or [twk] in its place.
  factory TwkHere.start(
    List<String> arguments, {
    Future<int> Function(List<String> arguments) twk = runTwk,
  }) {
    final out = StringBuffer();
    final err = StringBuffer();
    // one each: IOOverrides calls these at every use of stdout or stderr,
    // and a character can be split between two writes
    final stdout = Captured(out);
    final stderr = Captured(err);
    final code = IOOverrides.runZoned(
      () => runZoned(
        () => twk(arguments),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => out.writeln(line),
        ),
      ),
      stdin: _NoInput.new,
      stdout: () => stdout,
      stderr: () => stderr,
    );
    return TwkHere._(
      code.whenComplete(() => Future.wait([stdout.close(), stderr.close()])),
      out,
      err,
    );
  }

  /// The command's exit code, once it ended.
  final Future<int> exitCode;

  /// What it printed and wrote to stdout so far.
  final StringBuffer out;

  /// What it wrote to stderr so far.
  final StringBuffer err;
}

/// A stdout or a stderr, no terminal, whose text goes to a [StringBuffer].
final class Captured implements Stdout {
  /// A stdout whose text goes to [text].
  Captured(StringBuffer text)
    : _text = text,
      _bytes = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
        StringConversionSink.fromStringSink(text),
      );

  final StringBuffer _text;

  /// Decodes what [add] is given, a character split between two adds
  /// whole.
  final ByteConversionSink _bytes;

  @override
  bool get hasTerminal => false;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  void write(Object? object) => _text.write(object);

  @override
  void writeln([Object? object = '']) => _text.writeln(object);

  @override
  void add(List<int> data) => _bytes.add(data);

  @override
  Future<void> flush() async {}

  /// Ends the text: a character [add] left unfinished is U+FFFD.
  @override
  Future<void> close() async => _bytes.close();

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('stdout.${invocation.memberName}');
}

/// A stdin that is no terminal and gives nothing, as `/dev/null` does.
final class _NoInput extends Stream<List<int>> implements Stdin {
  @override
  bool get hasTerminal => false;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<List<int>>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('stdin.${invocation.memberName}');
}
