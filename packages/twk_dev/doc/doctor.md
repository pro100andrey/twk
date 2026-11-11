# `twk doctor`

```bash
dart run twk_dev:twk doctor [-C <dir>] [--json]
```

A report for a person, or for a tool with `--json`.

## The terminal

Where stdin and stdout are a terminal, twk opens it as an inline app does
(`Terminal.open`, probe and all), reads what it found
(`TerminalInfo`), and puts it back. `answers` says whether the last query was
answered in time, with how long opening took: a terminal that swallows
queries (a multiplexer, a slow ssh) shows there. The name and version are
what XTVERSION told (`TerminalInfo.terminalVersion`); a multiplexer or a
graphics protocol given leaves it empty. Without a terminal (a pipe, an
agent) the section says so and nothing is probed.

## The project

* the versions of `twk`, `twk_core`, `twk_dev` and `twk_test` as the project
  resolves them, each with its source: `locked` (hosted or git, from the
  nearest `pubspec.lock`; a workspace's is in its root), `path` (a path
  dependency), or, for what the lock lacks, `workspace` (a member of the pub
  workspace) or `path`, read from the `pubspec.yaml` that
  `.dart_tool/package_config.json` names (a workspace's members and a
  package itself are not locked). Those found must be one version; else the
  report says so and the exit code is 1. Where none is found it says so.
* the Dart SDK that runs `twk`.
* the files `run`, `shell` and `logs` of `.dart_tool/twk` there are, each
  with what it names and whether a connection to it is taken (`listening`)
  or not (`left behind`, by an app that did not stop).
* the skill for agents, where the project depends on twk: `older than this
  twk_dev` where files `twk agents` wrote differ from the ones in this
  twk_dev (`twk agents` rewrites them); files the project changed are named
  and kept.

## `--json`

One object: `project`, `dart`, `environment`, `terminal` (null without one),
`lock`, `versions`, `sources` (the same keys: `locked`, `path` or
`workspace`), `agree`, `state` and `agents` (null where the project
does not depend on twk).
