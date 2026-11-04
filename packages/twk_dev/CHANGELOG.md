# Changelog

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
