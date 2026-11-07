# `twk create`

```bash
dart run twk_dev:twk create ~/my_app --template=dashboard
cd ~/my_app && dart pub get && dart run bin/main.dart
```

`twk create <dir>` writes a package into `<dir>`, made if it is not there,
with the directories on the way to it: `pubspec.yaml`, `analysis_options.yaml`
(pro_lints' recommended rules, twk_lints' recommended set — the plugin with
all its rules on, [twk_lints](https://pub.dev/packages/twk_lints) — strict
casts, inference and raw types), `bin/main.dart`, which runs the app, the app
in `lib/<name>.dart`, its `testTwk` tests in `test/<name>_test.dart`, a
`README.md` that says how to run, hot reload, inspect and test it, and a
`.gitignore`. As written it gets its dependencies, analyzes with no issue,
passes its tests and is formatted. `--template` (`-t`) picks the app, `--list`
names them, and `--agents` writes the files for coding agents (below).

## What it asks

In a terminal (stdin and stdout both one), `twk create` asks, on twk's own
`Cli`, for what the flags did not say: which app (`--template`), and which
files for coding agents (`--agents`, both at first). `--agents=agents-md,skill`
says them and `--agents=none` says none, so with `--template` nothing is asked.
`skill` is the twk skill in `.agents/skills/twk` and `.claude/skills/twk`;
`agents-md` is the block of `AGENTS.md`; they are written by `twk agents`'
code (`agentsPlan`), after the package is made, and the run says what it
wrote. A bad value exits with 64. Ctrl+C at a question cancels: nothing is
written, the exit code is 130 (1 for Ctrl+D), the terminal as it was.

Without a terminal (an agent, CI, a pipe) it asks nothing, takes the `app`
template and writes no file for agents unless `--agents` says so, so that the
output of an existing run does not change. Under `CI` it asks nothing in a
terminal either.

## Templates

### `app` (the default)

full screen: notes in a `SelectionList` beside the one chosen, a `StatusBar`
above them and a `KeyHintsBar` below; Enter opens a note, Escape goes back,
Tab and a click move the focus between the panes, Ctrl+Q quits

### `inline`

inline, below the shell's prompt: each line sent goes to the scrollback
(`Static`) with the app's answer under it, a `Spinner` while it thinks; the
`TextField` and the keys alone stay in the app's rows

### `form`

full screen: a `Form` of a name, an email, an age (`NumberInput`) and a
`Checkbox`, each field's error under it; Enter goes to the next field and from
the last submits, as Ctrl+S and the button do

### `dashboard`

full screen: readings taken every second, the CPU in a `Chart` of the last
minute, the memory in a `LineGauge` and the requests to each service in a
`BarChart`; `p` pauses

## The package it writes

The package is named after `<dir>`, in lower case, other characters than
letters, digits and `_` as `_` (`My-App` gives `my_app`), or as
`--name=<package>` says: a lower case letter first, none of the words pub
refuses (Dart's reserved words, `inline`, `type`, …) and none of the packages
it depends on, or the command exits with 64. The pubspec takes twk, and
twk_test, twk_dev and twk_lints as dev dependencies (so that `dart run
twk_dev:twk run bin/main.dart` hot reloads the app, and its analysis options
include twk_lints' set), by path from the checkout of the twk repository
`--path-to-twk=<dir>` names, or else the one the command runs from: the
nearest directory from the command's package up that holds `packages/twk`,
`packages/twk_test`, `packages/twk_dev` and `packages/twk_lints`. Without
either, from pub at `^0.3.0`. A `--path-to-twk` that is no checkout exits with
1, as does a `<dir>` that is a file or under one, `--force` or not, and a
directory that is not empty unless `--force`, which writes the template's
files over those of the same paths and leaves the others: a file already as
the template has it is left alone, and named `(the same there)`, one it writes
over `(over the one there)`. `--dry-run` names the files it would write, so
marked, and writes none, nor any directory, after the same checks of `<dir>`
as the run. Both are mold's: `twk create` plans the unpack with mold's
`Unbundler.plan` (with `overwrite` for `--force`) and writes that plan with
`Unbundler.apply`, which checks the directory again, makes the directories not
there and undoes its writes, and those, when one fails. What mold refuses is
printed as mold says it, with `--force writes into it.` after a directory that
is not empty, which mold's library leaves to its caller.

Each template is a package of this repository, `templates/<name>/`, named
`<name>_template`, which runs, analyzes and passes its tests where it is,
taking twk, twk_test, twk_dev and twk_lints by path in the repository. Its
`mold.yaml` makes it a template of [mold](https://pub.dev/packages/mold): the
variable `package_name` replaces `<name>_template` in each casing mold derives
(`app_template`, `app-template`, `APP_TEMPLATE`, `AppTemplate`), in the paths
and the text, and leaves `pubspec.lock` and itself out.
`tool/pack_templates.dart` packs each with mold's library into
`lib/src/templates/<name>.g.dart`, the archive in base64 as `mold pack -f
base64` writes it, under a doc comment (`EmbedSource`'s `doc`), with mold's
`// ignore_for_file: type=lint` (so `dart analyze --fatal-infos` takes them as
they are), which `twk create` unpacks, so the command needs no checkout of the
repository. Packing them warns of nothing. After a template changed:

```bash
dart run tool/pack_templates.dart
```

The pubspec's dependencies on twk, twk_test, twk_dev and twk_lints are
rewritten as mold plans the unpack, by its `rewrite` hook (`withTwkFrom` in
`lib/src/templates/templates.dart`, `createPlan` in `lib/src/create.dart`), so
whether the pubspec there is the same is about the one written. Not by a mold
variable: whether they are taken by path or by version is a choice of the
command, each a YAML of another shape, while mold's substitutions put a value
in place of a literal; and the template's pubspec takes them by paths in the
repository, which a `{{ … }}` in their place would break, so a path is no
value of the template for mold's `yamlString` to quote, and `withTwkFrom`
quotes it.
