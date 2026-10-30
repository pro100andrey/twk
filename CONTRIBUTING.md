# Contributing to twk

## The repository

One pub workspace: the root's `pubspec.yaml` (`twk_workspace`, no package
of its own to publish) lists every package under `packages/` — the core
is `packages/twk_core` — and every tool's package under `tool/`,
resolved together by one `dart pub get` at the root into one
`pubspec.lock`. The templates under `packages/twk_dev/templates/` stay
out: scaffolds of apps of their own that `twk create` copies out of the
repository, each with its own `dart pub get` and lock.

The conventions code, docs and tests are written to are in
[doc/internals/quality/README.md](doc/internals/quality/README.md).

## Checks

The checks are tasks in `xtask.yaml`, run by
[xtask](https://pub.dev/packages/xtask), a dev dependency (nothing to
install): `dart run tool/xtask.dart <gate or task>`, or `xtask <gate or
task>` with xtask activated (`dart pub global activate xtask`), which
hands the run to `tool/xtask.dart`. `--list` prints them by gate,
`--graph <gate>` what a gate pulls in, `--dry-run <name>` the commands it
would run, `--why <task>` what reaches a task.

```bash
dart run tool/xtask.dart quick              # while working: pub get, analyze, format
dart run tool/xtask.dart handover -j auto   # before a pull request: must pass
dart run tool/xtask.dart bench              # when the frame path changed (below)
```

- `-j auto` runs the checks that don't depend on each other at once; it
  prints each task's output whole when it ends. Without `-j` they run one
  at a time.
- `handover` is: `xtask.yaml` valid; `dart format` changing nothing; the
  workspace's `dart pub get` and each template's; in every package
  `dart analyze --fatal-infos` and, where it has `test/`, `dart test`;
  the root's analyze (`pro_lints/recommended`, strict casts, inference
  and raw types, and twk_lints' plugin) and its tests (`test/tool/`, the
  tools' tests);
  every ```` ```dart ```` example of a `///` comment in `lib/` analyzed
  in its package (`doc-snippets`); each page of the gallery's Code tab
  run in twk's tester and held to what its stage shows (`gallery-code`),
  the gallery's golden screens being its `dart test`, drawn as the SVGs of
  `packages/gallery/doc/shots/` and failed where those are stale
  (`gallery-shots`), and written into the widget catalog, `doc/widgets/`,
  failed where it is stale (`catalog`); and the chat demo
  end to end in a pseudo-terminal, fullscreen and inline, its output
  then through the test emulator (`e2e-fullscreen`, `e2e-inline`). The
  end to end is what a change to anything that reads from or writes to
  the terminal has to pass.
- The VS Code extension (`editors/vscode`) is in `handover` too: its
  `npm ci`, its compile (tsc) and its unit tests, run in a copy of their
  own under `.dart_tool/vscode/`. They need node and npm on the `PATH`
  and are skipped, saying so, without them.
- No test waits on the wall clock: apps and timers run on a fake clock
  the test moves (`t.pump`, `clock.elapse`, `clock.elapseUntil`), real
  events are awaited with twk_test's `waitFor`/`waitUntil`. twk_lints'
  `wall_time_in_tests` fails the analysis on a `Future.delayed`, `sleep`,
  `Timer` or `Stream.periodic` under `test/`; an
  `// ignore: twk_lints/wall_time_in_tests` takes its reason on the
  comment above it, and only where real time is what is measured.
- `--keep-going` reports every failure instead of stopping at the first.
  `--only` runs the per-package steps in some packages only:
  `dart run tool/xtask.dart handover -j auto --only 'packages=packages/twk/*,packages/twk_core/*'`.
  A single task runs by its name (`dart run tool/xtask.dart pkg-test`),
  and what follows `--` goes to its command.
- When the frame path changed, the code a frame or input runs through
  (the core's `canvas.dart`, `surface.dart`, `presenter.dart`, `style.dart`,
  `fill.dart`, `byte_sink.dart`, `screen.dart`, `app.dart`, `render/`,
  `unicode/`, `input/parser.dart`, `terminal/outbox.dart`): `bench`, the
  frame benchmark, against the commit the work started from
  (`BENCH_BASELINE=<rev>`), with its report in the pull request. It fails
  when a scenario writes more bytes per frame, or is slower by more than
  5 %. It pins itself to one CPU (`BENCH_CPU`) and keeps the other heavy
  steps off it where `taskset` is there, under a lock (`BENCH_LOCK`,
  `/tmp/twk/bench.lock`) two benchmarks on one machine never share; run
  it on a quiet machine. Not pinned, its times are reported, not failed.
- `ci` is all of it, the benchmark last and alone, and two more:
  `browser-test`, twk_web's tests in Chrome (`CHROME_EXECUTABLE`, else the
  first of `google-chrome-stable`, `google-chrome`, `chromium` on the
  `PATH`; skipped without one), which needs the network. Its packages'
  tests are all but the slowest's: those of `twk_ssh`, `twk_dev` and `twk`
  are `ci-tests`, which CI runs in a second Linux job beside it.
- CI (`.github/workflows/ci.yml`) runs `ci` and `ci-tests` on Linux, side
  by side, and `ci-os` on macOS and Windows: on macOS every package's
  tests and the end to end runs, on Windows the tests of `twk_core`,
  `twk` and `twk_test`; the
  benchmark is Linux's (`platforms:` in `xtask.yaml`). Each step of a workflow
  runs one gate: `workflows-check` (`--check-ci`), in `handover`, refuses
  anything else, so a check is added to `xtask.yaml`, never to the
  workflow.
- On demand, not in a gate: `undocumented` and `coverage` write reports
  to `doc/internals/quality/` (not committed); `-- <package>...` makes
  those packages' only. `pub-check` says whether the seven packages of a
  release are ready for pub.dev: `publish_to`, the errors of `dart pub
  publish --dry-run`, every file git tracks in `lib/` and `bin/` in the
  archive it lists, and pana's score with what lost points (pana
  activated with `dart pub global activate pana`; skipped without it;
  a package with `screenshots:`, twk, failed without libwebp's `cwebp`,
  `webpinfo` and `gif2webp` on the `PATH`, which pana converts them with; a
  package that depends on one of this repository's not on pub.dev yet is
  not scored). `publish-core`, `publish-twk`, `publish-test`,
  `publish-lints`, `publish-term`, `publish-rich` and `publish-dev`
  publish them, each after those it depends on and its own package's
  `check-<name>`, which pana scores there, once they are on pub.dev (a
  package it cannot score fails it), `publish-dev` all seven in order,
  once `dart pub login` has: the version named in the changelog, the
  package as HEAD has it, then the upload, waited for until pub.dev
  serves it. A version pub.dev serves already is skipped, so a run again
  after one failed takes up where it stopped.
- A package that depends on riverpod, bloc, analyzer or dartssh2 needs
  the network on its first `dart pub get`. `packages/twk_ssh`'s tests run
  OpenSSH's `ssh` and `ssh-keygen` where they are on the `PATH`.
