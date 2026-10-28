// Pty.start in a process with no descriptor to spare, which pty_test.dart
// runs in a process of its own under a low RLIMIT_NOFILE. For each number
// of descriptors left free, a line of JSON: what Pty.start threw, and the
// descriptors open after it that were not before.
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

// the library of twk_term it runs on, not all of twk_term (its view
// imports twk): it compiles in a tenth of the time
import 'package:twk_term/src/pty/pty.dart';

/// The descriptors this process has open, but its sockets: Pty.start
/// opens none, and those of a VM service (the coverage tool's connection
/// to it) come and go as they will.
Set<String> open() => {
  // the links themselves, not what they name: one may be closed meanwhile
  for (final e in Directory('/proc/self/fd').listSync(followLinks: false))
    if (_target(e.path) case final target? when !target.startsWith('socket:'))
      e.path.split('/').last,
};

/// What the descriptor link at [path] names; null once it is closed.
String? _target(String path) {
  try {
    return Link(path).targetSync();
  } on FileSystemException {
    return null;
  }
}

Future<void> main() async {
  // A VM service the process was started with (the coverage tool's) opens
  // descriptors as it comes up, which may be after main has begun: up
  // first, or it finds none and the process, paused on exit for it, waits
  // for good.
  if (Platform.executableArguments.any(
    (a) => a.startsWith('--enable-vm-service') || a.startsWith('--observe'),
  )) {
    await Service.controlWebServer(enable: true, silenceOutput: true);
  }
  for (final free in [0, 2, 3, 4]) {
    final before = open();
    // every descriptor taken, then [free] of them given back
    final taken = <RandomAccessFile>[];
    try {
      for (;;) {
        taken.add(File('/dev/null').openSync());
      }
    } on FileSystemException {
      // none left
    }
    for (var i = 0; i < free; i++) {
      taken.removeLast().closeSync();
    }
    Object? thrown;
    try {
      Pty.start('/bin/true', const []).close();
    } on ProcessException catch (e) {
      thrown = {'message': e.message, 'errorCode': e.errorCode};
    }
    for (final f in taken) {
      f.closeSync();
    }
    final kept = open().difference(before).toList()..sort();
    stdout.writeln(jsonEncode({'free': free, 'thrown': thrown, 'kept': kept}));
  }
}
