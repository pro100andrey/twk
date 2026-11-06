# Changelog

## Unreleased

Added:

- `twk create` asks, in a terminal, for what its flags did not say: the
  template and the files for coding agents (the twk skill in
  `.agents/skills/twk` and `.claude/skills/twk`, and the block of
  `AGENTS.md`, written as `twk agents` writes them, after the package).
  `--agents=agents-md,skill` says them, `--agents=none` says none; with
  `--template` they ask nothing. Without a terminal it asks nothing and takes
  the defaults as before (the `app` template, no files for agents). Ctrl+C
  at a question writes nothing and exits with 130. `createApp`, `askCreate`
  and `canAsk` are the writing, the asking and the check apart.
- `twk agents`: writes the twk skill, the one that comes with this twk_dev
  (`SKILL.md` and its `references/`), into a project's `.agents/skills/twk`
  and `.claude/skills/twk`, and a block of twk's own between two markers
  into its `AGENTS.md`, for a coding agent to learn twk from rather than
  from what it remembers of Flutter. Run again, it writes over what a newer
  twk_dev changed and says so, or says there is nothing to do and changes
  no file; what the project's `AGENTS.md` has outside the markers, and files
  of its own in the skills' directories, it leaves. Each skill directory
  holds a manifest, `.twk-agents.json`, of the files `twk agents` wrote with
  their hashes: a file a newer twk_dev dropped is removed (with a directory
  it empties) where it is still as written, and stays, named, where the
  project changed it, as does a file the skill still has that the project
  changed; with no manifest yet, nothing is removed. `--directory` names the
  project, `--dry-run` writes nothing. `agentsPlan` is the same as a
  function, for a caller that chooses which of the three to write.

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
