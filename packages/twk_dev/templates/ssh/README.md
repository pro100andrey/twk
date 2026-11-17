# ssh_template

An app served over SSH: each client that logs in gets a counter of its own,
greeted by name, on its own terminal, with the size of that terminal. Up
counts, q quits. Made by `twk create --template=ssh`, on the widgets of twk
and [twk_ssh](https://pub.dev/packages/twk_ssh).

## Run

```bash
dart pub get
dart run bin/main.dart [port]
ssh -t -p 2222 localhost
```

The server listens on `127.0.0.1` (port 2222 unless one is given), so only
this machine reaches it; `serveSsh`'s `address` opens it to others.

- Who may log in: a public key listed in `~/.ssh/authorized_keys`, as any
  user, and no password. The file is read at each attempt. A file that
  others than its owner can write, or none, lets nobody in.
  `serveCounter(authenticate: SshAuth(...))` says it otherwise.
- The server's identity is the key in `host_ed25519`, made there the first
  time and kept (it is in `.gitignore`: it is this machine's, not the
  code's). A client that has seen it before warns if it changes.

## Test

```bash
dart test
dart analyze
dart format --output=none --set-exit-if-changed .
```

`testTwk` (twk_test) runs the app on a terminal in memory under a fake
clock: keys go in as a terminal sends them, the screen is read back.

## Files

- `bin/main.dart` runs the server.
- `lib/ssh_template.dart` is the app and `serveCounter`, which serves it.
- `test/ssh_template_test.dart` tests them.
