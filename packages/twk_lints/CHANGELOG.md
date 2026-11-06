# Changelog

## Unreleased

- `key_names` reads the `shortcuts:` map of `Shortcuts`, which twk takes by
  name now.
- `wall_time_in_tests` reports a `Future.timeout` with no `onTimeout`, which
  fails saying `TimeoutException after 0:00:05` and nothing of what was awaited:
  twk_test's `waitFor` names it.

## 0.2.0

- Takes twk, twk_core and twk_test at 0.2.0, which have breaking
  changes; nothing of this package changed.

## 0.1.0

The first release.

- A plugin of the analysis server's plugin system, enabled by including
  `package:twk_lints/recommended.yaml`.
- Warnings: `set_state_after_dispose`, `context_after_await`,
  `dispose_controllers`, `key_names`.
- Lints: `missing_key_in_children`, `untyped_table`,
  `prefer_key_bindings`, `unnamed_control`, `wall_time_in_tests`.
- Fixes: a mounted check, a row type, a semantics label, a value key, a
  field disposed, a fake clock elapsed, key bindings for a listener.
- Assists: wrap a widget (in a widget, a builder, a row or a column),
  remove, move and swap widgets, extract a widget, convert between a
  stateless and a stateful widget.
