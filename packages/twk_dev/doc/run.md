# `twk run`

```bash
# from the repository's root: packages/twk's counter, hot reloaded
dart run packages/twk_dev/bin/twk.dart run packages/twk/example/counter.dart
```

The app in `<file>` has this terminal to itself: `twk run` starts it with
`dart run` and the VM service on (on a port the OS picks, with
`-DSILENT_VM_SERVICE=true`, so that the VM says nothing of it on the app's
screen), gives it its own stdin, stdout and stderr, and writes nothing to them
while the app runs. The arguments after `<file>` are the app's (`twk run
bin/main.dart --inline`). The app's debug keys are on: `keys` is added to the
`TWK_DEBUG` it gets.

`twk run` connects to the VM service (`package:vm_service`) and watches the
`lib/` of the package `<file>` is in, the nearest directory from it up that
holds a `pubspec.yaml`, and `<file>`. When a `.dart` file there changes, or is
moved there as editors that save safely do, it reloads the sources 100 ms
after the last change (`reloadSources`) and calls the binding's
`ext.twk.reassemble` (twk's `AppBinding.reassemble`): every element is
rebuilt, each State kept, every render object laid out and painted again and
the whole screen written again, so the code changed shows. A file elsewhere, a
sibling of `<file>` or one of another package, is reloaded by hand: Ctrl+G h
in the app. What `main` built, and code that ran already, a reload leaves as
it was: Ctrl+G H restarts the app — SIGTERM, on which the app puts the
terminal back and exits, SIGKILL if it has not after 5 s — and starts it
again, its state new. The app is reloaded once its binding runs (its first
`runApp`), which registers the extensions: a change seen before is reloaded
then, newer as it may be than the sources the app was compiled from.

What `twk run` says goes to the app's log (`ext.twk.log`), which the app's
console lists (Ctrl+G c) and `twk logs` tails (with `TWK_DEBUG=logs`): what it
watches, each reload (`hot reload: 2 libraries in 61 ms`), and why one failed
— the compiler's errors, at the error level, which opens the console. The app
goes on with the code it had.

The keys are the app's because the app has stdin: `twk run` reads no keys of
its own. Ctrl+G h and Ctrl+G H are debug keys of the binding, which post an
event, `twk.reload` or `twk.restart`, on the VM service's `Extension` stream
(`dart:developer`'s `postEvent`) that `twk run` listens to: they work in the
terminal the app is in, the same on every platform, with nothing to type
elsewhere and no process to find; an app run without `twk run` says in its log
that no tool listens.

While the app runs, the WebSocket address of its VM service is in
`.dart_tool/twk/run` of the project of the current directory, where `twk
inspect` finds it: written whole once the VM says where it listens, again for
an app restarted, and removed as `twk run` ends, unless another `twk run` of
the project wrote it since.

`twk run` ends when the app does, with its exit code, or 128 and the signal's
number when a signal ended it, as a shell gives it. SIGINT, SIGTERM and SIGHUP
end the app as a restart does, then `twk run`, with 128 and the signal's
number; Ctrl+C reaches `twk run` only while no app has the terminal in raw
mode, as while one starts. On Windows, which has no SIGTERM, a restart kills
the app without the terminal put back; `twk run` has not been run on Windows;
on macOS its tests run it.
