/// A hot restart of an app in its process, which a tool asks for over the
/// VM service (the twk extension for VS Code). On the VM only, loaded with
/// `io.dart`, which exports it; nothing here is public: a tool calls it by
/// the VM service's `evaluate` in this library, `package:twk/src/platform/hot_restart.dart`.
library;

import 'dart:io';
import 'dart:isolate';

// A hot restart in the process, which a tool asks for over the VM service
// (the twk extension for VS Code): the app is ended (`ext.twk.teardown`)
// and its isolate killed, then its `main` runs again in a new isolate of
// the same group, whose statics are new, whose code is what the tool
// reloaded and whose `Platform.script` is the app's own. The tool calls
// the two below by `evaluate` in this library, in the root isolate, which
// they keep (the process ends with it): [_restartBegin] before the app is
// ended, [_restartWith] with the app's `main` to run it again. The new app
// ending by itself ends the process, as the first one's end would have.

// keeps the root isolate once its own app was torn down
RawReceivePort? _restartKeep;
// the app started last, whose end alone ends the process
var _restartGeneration = 0;
// between _restartBegin and the new app: an app's end is no end
var _restartReplacing = false;

@pragma('vm:entry-point')
void _restartBegin() {
  _restartKeep ??= RawReceivePort(null, 'twk hot restart');
  _restartReplacing = true;
}

@pragma('vm:entry-point')
Future<void> _restartWith(Function main, List<String> args) async {
  final generation = ++_restartGeneration;
  final errors = RawReceivePort((Object? report) {
    final [error, stack] = report! as List<Object?>;
    stderr.writeln('Unhandled exception:\n$error\n$stack');
    exitCode = 255;
  });
  late final RawReceivePort exits;
  exits = RawReceivePort((Object? _) {
    exits.close();
    errors.close();
    if (generation == _restartGeneration && !_restartReplacing) {
      exit(exitCode);
    }
  });
  await Isolate.spawn(
    _restartMain,
    [main, args],
    onExit: exits.sendPort,
    onError: errors.sendPort,
    // apart from the root isolate's `main`, which a debugger lists too
    debugName: 'main, restart $generation',
  );
  _restartReplacing = false;
}

void _restartMain(List<Object?> message) {
  final main = message[0]! as Function;
  final args = (message[1]! as List<Object?>).cast<String>();
  if (main is void Function(List<String>)) {
    main(args);
  } else if (main is void Function()) {
    main();
  } else {
    Function.apply(main, [args, null]);
  }
}
