# The `twk` command

The [README](../README.md) says how to install twk_dev. Paths here are relative
to the package's directory, `packages/twk_dev`, unless they say otherwise.

The app takes twk_dev as a dev dependency, so `dart run twk_dev:twk` runs the
version its lock file names. In a checkout of the twk repository, from this
directory, as the rest of these guides do:

```bash
dart run twk_dev:twk --help
```

`--help`, `help <command>` and no arguments print the usage and exit with 0;
an unknown subcommand or option exits with 64.

## Subcommands

### `twk create <dir> [-t <template>] [--agents=<files>]`

writes a new app into `<dir>` from a template (`app`, `inline`, `form`,
`dashboard`): a package that runs, analyzes and passes its tests as it is.
`--agents=agents-md,skill` also writes the files for coding agents, as
`twk agents` does. In a terminal it asks for the template and the files
that the flags did not say; without one (an agent, CI, a pipe) it asks
nothing and takes the `app` template and no files for agents, and its next
steps name `twk agents` for the skill

### `twk agents [-C <dir>] [--dry-run]`

writes the twk skill and a short block of `AGENTS.md` into the project, for a
coding agent: [the section for agents](../README.md#for-coding-agents)

Each skill directory gets a manifest, `.twk-agents.json`, of the files it
wrote with their hashes. Run again after an upgrade, it removes the files the
new skill no longer has that are still as it wrote them; one the project
changed stays and is named, as does a file that is in no manifest (the
project's own) and a link where the manifest lists a file. A file the new
skill still has that is not as a run wrote it (its hash is not the one the
manifest lists, or it lists none) stays too, and is named: delete it to have
the skill's again. The manifest keeps the hash of what was written, so that
such a file stays one until it is deleted or as the skill has it. With no
manifest yet it writes one, removes nothing and leaves what differs from the
skill, naming it. `--dry-run` says what it would remove.

### `twk shell [-C <dir>]`

owns this terminal and serves it over a local socket to an app of the project
started without a terminal (from the IDE, under the debugger)

### `twk logs [-C <dir>] [--[no-]color]`

tails the log an app of the project serves over a local socket, with levels
and colours

### `twk run [--no-asserts] [--debug=<aids>] [--screen-reader] [--plain] <file> [<arguments>...]`

runs the app in `<file>` in this terminal with hot reload: watches the
package's `lib/` and `<file>` and reloads them as they change, each State
kept; Ctrl+G h in the app reloads, Ctrl+G H restarts. `--debug`, `--screen-reader` and `--plain` set
`TWK_DEBUG`, `TWK_SCREEN_READER` and `TWK_PLAIN` for the app; an unknown
aid is refused with 64

### `twk inspect [<vm-service-uri>] [-C <dir>]`

shows a running app's widget tree, or its render tree, the selected node's
properties and layout, the node outlined on the app's screen, and selects the
node under a cell clicked on the app's screen; the app at the address given,
or the one `twk run` runs from the project

### `twk record [--out=<file>] [--idle-limit=<s>] [--title=<text>] [--keys] -- <command>`

runs `<command>` in a pseudo-terminal of this terminal's size, this terminal
passed through in raw mode, and records the session as asciicast v2

### `twk play [--speed=<factor>] [--idle-limit=<s>] <file>`

plays a recording back in this terminal

### `twk tape <file.tape>`

runs a tape, a script of what to type into a program and when, in a
pseudo-terminal, and writes the session as asciicast v2, as an animated SVG
and as still SVGs of the screens it names

## Projects

`shell`, `logs` and `inspect` work for the project of the current directory,
or of `-C <dir>`: the nearest directory from there up that holds a
`pubspec.yaml`. `<dir>` is made absolute and normalised first, so `-C a/b/..`
goes up to `a`, and the project's path they print has no `.` or `..` in it.
They find each other's ends by address files in its `.dart_tool/twk/`
(`LocalAddress` in twk_core): `shell` and `logs`, each the socket's address
(`unix:<path>`, or `tcp:127.0.0.1:<port>` on Windows, which has no Unix domain
sockets) and a token on a line of its own, which a client sends first; `run`,
the WebSocket address of the VM service of the app `twk run` runs, a line. A
Unix domain socket lives beside its address file (`shell.sock`,
`logs-<pid>-<n>.sock`), or in a new temporary directory when that path is
longer than a socket's path may be (103 bytes).
