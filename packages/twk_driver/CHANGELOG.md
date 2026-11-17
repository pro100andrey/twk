# Changelog

## Unreleased

Added:

- The package: `Session`, a twk app run as a process in a pseudo-terminal
  and driven from outside (`press`, `type`, `paste`, `resize`, `tap`,
  `find`, `waitForScreen`), each action returning at the frame that took the
  input in; the ports `TerminalPort`, `ScreenPort`, `AppServicePort` and
  `ProcessPort` with their adapters; `ByteLog`, the app's count of what it
  wrote against what the terminal gave.
- `VmAppClient` and `AppClient`, moved from twk_dev, and `compiledProgram`,
  moved from twk_test.
