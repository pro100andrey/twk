# twk_driver

Drives a [twk](https://pub.dev/packages/twk) app as a real process in a
real pseudo-terminal, from outside: the keys are real bytes, the screen is
read through a terminal emulator, and the widget tree through the app's VM
service.

Every action returns once the app has drawn the frame that took the input
in: the app says so itself (`twk.frame` and `twk.input` events), so the
driver never waits for "idle" and never polls.

```dart
final app = await Session.start(
  ProcessSpec(await compiledProgram('example/counter.dart', ...)),
);
await app.press('up');
print(app.screenText);
await app.tap(const ElementFinder.text('Save'));
final report = await app.close();
```

`twk_test` (`package:twk_test/driver.dart`) and `twk mcp` are front ends of
this package. Linux and macOS only. `DESIGN.md` is the design.
