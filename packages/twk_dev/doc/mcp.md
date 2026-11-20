# twk mcp

`twk mcp` is a [Model Context Protocol](https://modelcontextprotocol.io)
server for coding agents. It starts a twk app in a pseudo-terminal and drives
it with `twk_driver`: the agent looks at the screen, presses keys, taps a
widget, moves the app's time and reloads its code, and each answer says what
the app looks like after.

## Register it

The server speaks on stdin and stdout, one JSON message a line; run it in the
project whose app it is to drive.

```sh
# Claude Code
claude mcp add twk -- dart run twk_dev:twk mcp
```

Any other client takes the same command: `dart run twk_dev:twk mcp` (or
`twk mcp` where the package is activated), no arguments. Protocol versions
2025-06-18, 2025-03-26 and 2024-11-05 are spoken: a client that asks for one
gets it, any other gets the newest. `twk agents` puts this into the
project's `AGENTS.md` and the skill.

## The tools

One app at a time.

| Tool | Does |
| --- | --- |
| `start_app` | `program` (the app's main file), `arguments`, `width`, `height`. Starts it and answers its first screen. |
| `screen` | The screen of the last frame. |
| `tree` | The widget tree as indented text (type, `#id`, `[key]`, size, properties); `depth` limits the levels. |
| `find` | `finder`: the nodes it matches, their ids and cells. |
| `press` | `keys`, as key bindings name them (`ctrl+s`, `shift+tab`, `g g`). |
| `type` | `text`, as the characters in one write. |
| `tap` | `finder`: clicks the one node it matches, after checking that a click there reaches it. |
| `wait_for` | `text` (or `absent`), `budget_ms` (10000), `io_ms`: moves the app's time until the screen has it. |
| `elapse` | `ms`: moves the app's time on. |
| `hot_reload` | Reloads the sources and has the app rebuild, each State kept. |
| `logs` | The log records since the last call (counted, so identical lines are each new). |
| `stop_app` | Ends the app; says what a finished app left behind (the tty, the alternate screen, the cursor). |

A finder is JSON: `{"text": "Save"}`, `{"textContaining": "ave"}`,
`{"textMatches": {"source": "Sa.e"}}`, `{"type": "Button"}`,
`{"key": {"value": "ok"}}`, `{"node": 42}`, `{"descendant": F, "of": F}`,
`{"ancestor": F, "of": F}`, `{"first": F}`, `{"last": F}`,
`{"at": 2, "of": F}`. One that matches none or more than one node fails, with
the first matches: pick on purpose.

## What an answer is

Each action answers the screen, then a line:

```text
Count: 2
Saved: 1
--
frame 5, input read 636 bytes, not quiet (next timer in 0.017 s)
```

The frame is how many the app has run, the input is what it has read of the
bytes the server wrote, and quiet says whether anything waits for time: a
timer, a frame asked for, input held back in the parser.

## Time

The app runs on the server's time (`TWK_DRIVEN`, part 4 of
`packages/twk_driver/DESIGN.md`): its timers fire when a tool moves the
clock. `press`, `type` and `tap` move it only to the frame the input asked
for; `wait_for` moves it from timer to timer until the screen is what it
waits for, up to `budget_ms` of the app's time; `elapse` moves it by a span.
Nothing is slept, so a wait for a one-minute timer takes no time.

Real input and output, a socket, a file or a child process, is outside that
clock. A `wait_for` on a screen that depends on one passes `io_ms`: a quiet
app is then waited for in real time, up to that.

## Failures

A tool that fails answers a result with `isError` and its reason, never a
timeout:

- `never: no screen with "..." ... and nothing will change it`: the app is
  quiet. More waiting does not help; the screen, and the closest line to the
  text, are in the answer.
- `no screen with "..." within 10 s of app time`: the budget went by, with
  the timers that wait.
- `... is covered by Box (node 12)`, `... nothing there takes a click`: a
  tap that would not reach its target.
- `the finder matches nothing` / `matches 3 nodes`: a finder that is not
  strict.
- `the app exited (1)`: the app ended without having said it was quitting;
  its last screen is in the answer. After a `press` of the key that quits
  the answer says `the app exited (0)`, and `stop_app` closes the session.
- `hot reload failed: ...`: the compiler's reasons.
