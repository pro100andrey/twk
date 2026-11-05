# `twk logs`

An app serves its log with `LogSink.serve()` (twk_core), until
`LogSink.close()`: `TwkApp.logs`, where `print`, `log()` and uncaught errors
go while the app owns the screen. A `TwkApp` does so itself while it runs when
`TWK_DEBUG` names `logs`, so an app needs no code for it:

```bash
TWK_DEBUG=logs dart run packages/twk_core/example/chat_demo.dart  # from the root
dart run twk_dev:twk logs -C ../..    # here, in another terminal
```

`twk logs` connects to the app the project's address file `logs` names (the
last one that started serving), sends the token, prints the records the sink
kept and then each one as it comes, `09:05:07.042 warning message: error` and
the stack below, on stdout; with colours (the time and the stack dim, the
level and the error dim, cyan, yellow or bold red by level) when stdout is a
terminal that takes escape sequences and `NO_COLOR` is not set, or as
`--[no-]color` says. While no app serves, and after one ends, it says so on
stderr and waits for the next.
