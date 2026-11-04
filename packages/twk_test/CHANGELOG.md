# Changelog

## 0.2.0

- `FakeCliTerminal.openInline` opens the inline terminal again once the
  last one is closed (a session ended by a Ctrl+C, then another), as the
  process's own terminal now does, and throws only while one is open; it
  threw on any second open ("stdin is closed"). `opened` counts each. A
  test that relied on the second open throwing gets a new terminal.

Breaking:

- `describeScreen` prints the screen as plain text unless `styles: true`;
  it marked styles always before. `describeApp` lost its `styles`.
- `containsLine` and `hasTextAt` take `within` as a `Finder` only; a
  rectangle goes in `withinRect`, a `CellRect` (the one `rect` gives and
  `linesIn` takes, now a public typedef). Both together is an
  `ArgumentError`.
- `TwkTester.pointerShape` throws a `StateError` unless
  `pumpWidget(pointerShapes: true)`; it read null there, so an `isNull`
  could pass for the wrong reason.

## 0.1.0

The first release.

- `testTwk` and `TwkTester`: an app on a terminal in memory under a
  `FakeClock`; `pumpWidget`, `pump`, `pumpUntilIdle`; keys, text, the
  mouse, paste, focus and resizes as the bytes a terminal sends; the
  fullscreen and the inline modes and a fixed viewport.
- The screen read back through `Vt`, a strict emulator (kitty graphics,
  sixel and iTerm2 images among what it takes): `lines`, `cell`, and
  matchers such as `containsLine`, `matchesScreen`, `matchesScreenFile`
  (golden files, `TWK_UPDATE_GOLDENS=1`) and `styleAt`.
- Finders (`find.text`, `find.byType`, `find.byKey`, …) and taps on what
  they find (`clickOn`).
- The frames an app wrote (`RecordedFrame`), printed when a test fails
  and written as a trace (`writeTrace`).
- `Shot`: a widget tree or a render object drawn without an app.
- `VtTerminal`, a terminal backend in the inline mode over the emulator.
- `waitFor` and `waitUntil` for what only real time brings;
  `compiledProgram`, `startProcess` and `runProcess` for a program a test
  runs in a process of its own, ended with the test.
