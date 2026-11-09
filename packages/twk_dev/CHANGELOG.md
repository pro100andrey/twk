# Changelog

## Unreleased

Fixed:

- `twk logs` and `twk create` take a pseudo-terminal of no size for a
  terminal: colours in the log, questions asked.

## 0.3.0

Added:

- `twk create` asks, in a terminal, for what its flags did not say: the template
  and the files for coding agents. `--agents=agents-md,skill` says them,
  `--agents=none` says none. Without a terminal it asks nothing and takes the
  defaults. `createApp`, `askCreate` and `canAsk` are the steps apart.
- `twk agents` writes the twk skill into a project's `.agents/skills/twk` and
  `.claude/skills/twk`, and a block between two markers into its `AGENTS.md`. Run
  again, it updates what a newer twk_dev changed. A manifest, `.twk-agents.json`,
  lists what it wrote: files not as it wrote them, and links, stay and are named.
  `--directory` names the project, `--dry-run` writes nothing. `agentsPlan` is the
  same as a function.

Changed:

- `twk create` makes a project take twk, twk_dev, twk_lints and twk_test at
  `^0.3.0`.

## 0.2.0

- Takes twk, twk_core and twk_term at 0.2.0, which have breaking
  changes, and `twk create` makes a project take twk, twk_dev, twk_lints
  and twk_test from pub at `^0.2.0`.

## 0.1.0

The first release.

- `twk create`: an app from a template (`app`, `dashboard`, `form`,
  `inline`), depending on twk, with twk_test and twk_lints.
- `twk run`: the app hot reloaded on save, its terminal kept.
- `twk inspect` and `twk logs`: the widget tree of a running app, and its
  log, over the VM service.
- `twk shell`: the terminal a twk app's editor extension talks to.
- `twk record`, `twk play` and `twk tape`: a session recorded as an
  asciicast, played back, or scripted and drawn as SVG; and
  `Cast.writes`, what a recording did to its terminal, which twk_test's
  `screenFrames` plays into the screens it showed, for a test.
