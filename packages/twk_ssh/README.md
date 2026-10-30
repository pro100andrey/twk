# twk_ssh — serve twk apps over SSH

A minimal SSH server for apps of [twk](../twk/README.md): each client
that logs in gets a session of its own, on a terminal fed by the
session's channel, as `ssh host` gets a shell. It is a package of its
own so that apps which serve nothing over SSH do not carry it. The
cryptography is
[pinenacl](https://pub.dev/packages/pinenacl),
[pointycastle](https://pub.dev/packages/pointycastle) and, for ML-KEM,
[cipherlib](https://pub.dev/packages/cipherlib), and
[dartssh2](https://pub.dev/packages/dartssh2) reads and writes the key
files and is the client of the tests.

**This is a minimal server, and it has not been audited.** It speaks
the few algorithms below, does one thing (a session per connection),
and has been tested against dartssh2 and OpenSSH's `ssh`; it is not a
replacement for OpenSSH's `sshd`. Put it where a mistake in it costs
little.

## Quick start

```dart
import 'package:twk/twk.dart';
import 'package:twk_ssh/twk_ssh.dart';

Future<void> main() async {
  final server = await serveSsh(
    port: 2222,
    hostKeys: [await SshHostKey.loadOrGenerate('host_ed25519')],
    authenticate: SshAuth.authorizedKeys('authorized_keys'),
    app: (session) => Text('hello ${session.user}'),
  );
  print('ssh -p ${server.port} localhost');
}
```

`serveSsh` runs an app per session that a client opens on a terminal,
full screen, built by `app(session)`: who logged in, what the client
sent (`session.user`, `environment`, `command`) reach the app through
`session`, and nothing else does — the app's own twk settings
(`TWK_DEBUG`, `TWK_LOG`, `TWK_EDITOR`) are read from an empty
environment, neither the server's nor the client's. The terminal is the
client's (`SshTerminalLink`, which `Terminal.overLink` opens a
`Terminal` over): its `TERM`, size (80 by 24 where the client sent none,
as `ssh -tt` without a terminal of its own does) and Backspace byte, its
window's changes as resizes, what it types as input. The app quits as
any does (`AppBinding.quit`, Ctrl+C): the terminal is restored and the
client gets exit status 0; an app that ends with an error exits with 1,
the error going to `onError`. A client that goes away quits its app. A
session without a terminal (`ssh -T`, a command without `-t`) is told
so and exits with 1. The server listens on the loopback interface
unless `address` says otherwise. `example/serve.dart` serves a counter:

```sh
dart run example/serve.dart        # ssh -p 2222 localhost
```

## Sessions by hand

`SshServer.bind` runs a handler of its own per session instead, which
reads and writes the channel itself:

```dart
import 'dart:convert';

import 'package:twk_ssh/twk_ssh.dart';

Future<void> main() async {
  final server = await SshServer.bind(
    'localhost',
    2222,
    hostKeys: [await SshHostKey.loadOrGenerate('host_ed25519')],
    auth: SshAuth.authorizedKeys('authorized_keys'),
    onSession: (session) async {
      session.add(utf8.encode('hello ${session.user}\r\n'));
      await session.flush();
    },
  );
  print('ssh -p ${server.port} localhost');
}
```

A session starts when the client asks for a shell or a command and ends
when `onSession`'s future completes: the client gets exit status 0, or
what `SshSession.exit` gave, or 1 when the handler threw (that error
goes to `onError`). The session has

- `user`, and `publicKey`, the key they logged in with (null for a
  password); `remoteAddress` and `remotePort`;
- `pty`, the terminal the client asked for (`TERM`, columns and rows,
  at most 2048 by 1024, pixel sizes, the terminal modes with the
  Backspace byte), null for `ssh -T` or a command without `-t`, and
  `resizes`, the terminal after each change of the client's window;
- `environment`, what the client sent (`SendEnv`, `SetEnv`), at most 64
  variables of 4 KiB; `command`, the command of `ssh host command`, null
  for a shell; `signals`, by name (`INT`, `TERM`);
- `input`, what the client types, and `add`, which writes to it: output
  goes no faster than the client's window grants and the rest waits, so
  `flush` completes once everything is sent; input the app doesn't read
  is held for at most the server's window (1 MiB), and the client is
  granted more only as the app reads;
- `exit(status)`, which sends what is pending (for at most 5 seconds
  while the client grants nothing), the status, EOF and close; `done`
  completes once the channel is closed by either end or the connection
  is gone.

One session channel is served per connection: a second one is refused,
and so are port forwarding, X11, agent forwarding and subsystems
(`sftp`). The connection ends a second after the session, when the
client doesn't end it itself.

## Logging in

`SshAuth(publicKey:, password:)` takes callbacks that say who may log in
with which key or password; `SshAuth.authorizedKeys(path)` reads an
authorized_keys file at each attempt, any user name accepted (so
`session.user` is then only the name the client gave; who proved to be
there is `session.publicKey`). Lines with
options (`from=`, `command=`, `restrict`) are skipped, since the server
does not apply them: their keys are refused. There is no `none` method
and no keyboard-interactive or host-based login. A connection gets
`maxAttempts` failures (6), then it is ended, and `loginTimeout` (2
minutes) to log in. At most `maxUnauthenticated` connections (10) may
be at it at once: one that comes while that many have not logged in is
closed before a byte is sent or read, as OpenSSH's `MaxStartups` starts
to do at 10. That keeps a flood of half-open logins from costing more
than ten key exchanges at a time; it also means ten clients that never
log in hold the door for `loginTimeout`, so a server facing the open
internet wants a shorter one, and a firewall's per-address limit. An
address whose connection ends without a login after a failed attempt is
refused for 5 seconds more for each, up to 10 minutes, as OpenSSH's
`PerSourcePenalties`: guessing passwords costs time, not only
connections.

The host key is an OpenSSH, PKCS#1 or SEC1 private key file, encrypted
or not (`SshHostKey.load`), or a new ssh-ed25519 key generated into a
file readable by its owner only, mode 0600 (`SshHostKey.loadOrGenerate`;
on Windows the directory's permissions apply). `fingerprint` and
`publicKeyLine` are what clients see and put in `known_hosts`.

## What it speaks

| | |
|---|---|
| key exchange | `mlkem768x25519-sha256` (post-quantum hybrid, RFC 10042), `curve25519-sha256` (also as `@libssh.org`); strict key exchange (`kex-strict-s-v00@openssh.com`, the Terrapin countermeasure) |
| host keys | `ssh-ed25519`, `rsa-sha2-256`, `ecdsa-sha2-nistp256`, `-nistp384`, `-nistp521` |
| ciphers | `aes128-ctr`, `aes192-ctr`, `aes256-ctr` |
| MACs | `hmac-sha2-256-etm@openssh.com`, `hmac-sha2-512-etm@openssh.com`, `hmac-sha2-256`, `hmac-sha2-512` |
| compression | `none` |
| user keys | `ssh-ed25519`; `ssh-rsa` of 2048 bits or more, signed with `rsa-sha2-256` or `rsa-sha2-512`; ECDSA on the three NIST curves |

A client that shares none of these in a category is disconnected with
KEY_EXCHANGE_FAILED. Every OpenSSH since 7.x shares them; OpenSSH 10
agrees on `mlkem768x25519-sha256` by itself (it is its default) and so
gives no "not post-quantum" warning (tested with 10.6); clients without
it (dartssh2 4.1) get `curve25519-sha256`.

| limit | | |
|---|---|---|
| rekey | `rekeyLimit: SshRekeyLimit(bytes:, time:)` | 1 GiB either way or 1 hour, whichever first (RFC 4253 §9); and before 2^31 packets either way |
| logging in | `loginTimeout`, `maxAttempts` | 2 minutes, 6 failures |
| at once, not logged in | `maxUnauthenticated` | 10; more are closed at once |
| sessions | | one session channel a connection |
| packet | | 256 KiB from the client |
| channel window | | 1 MiB of input held for the app |
| environment | | 64 variables of 4 KiB |

The server starts a key exchange itself once the keys in effect pass
`rekeyLimit`, and takes the ones the client starts (OpenSSH does one
after its `RekeyLimit`). The limits are checked as packets go, before
one is sent and after one is read: what the app sends past the limit
waits for the new keys and goes under them, and a connection with no
traffic keeps its keys, which then protect nothing new. Time is read on
the server's `clock`, a stopwatch per connection by default, and the
deadlines (`loginTimeout`, the second a connection waits for the client
after its session) run on its `timers`, `Timer.new` by default: a test
gives it a fake clock's (`clock: fake.stopwatch, timers: (d, f) =>
fake.run(() => Timer(d, f))`), whose time moves only when the test says.

### The post-quantum key exchange

`mlkem768x25519-sha256` combines ML-KEM-768 (FIPS 203) with X25519:
the shared secret is SHA-256 of both, so it holds while either does,
and a mistake in the ML-KEM half costs no more than the exchange would
have without it. The server's half of ML-KEM is the encapsulation, and
it comes from [cipherlib](https://pub.dev/packages/cipherlib) 0.7
(pure Dart, BSD-3-Clause, by the author of
[hashlib](https://pub.dev/packages/hashlib), which it uses for SHA-3):
a port of the reference implementation (pq-crystals), its compression
without division (no KyberSlash), its decapsulation's comparison and
selection without branches. `test/mlkem_test.dart` holds the server's
very call to NIST's ACVP vectors for FIPS 203 (`test/data/`, the
ML-KEM-768 encapsulation and key-check groups, with the commit they are
from), and the server checks the client's key itself (its length, and
every coefficient below q) before encapsulating.

What was looked at, in October 2026:

- [cipherlib](https://pub.dev/packages/cipherlib) 0.7.2: passes every
  ACVP keyGen, encapsulation, decapsulation and encapsulation-key-check
  vector of all three parameter sets; its decapsulation skips the key
  check of FIPS 203 §7.1 on imported keys (a TODO it states), which
  the server, which never decapsulates, doesn't need. Chosen.
- [pqcrypto](https://pub.dev/packages/pqcrypto) 0.4.3: passes the same
  vectors, but compresses with integer division of secret-dependent
  values (`~/`, the KyberSlash pattern), reduces with a branch on the
  value, and samples the matrix from a fixed 672 bytes of SHAKE128,
  leaving the rest of the polynomial zero if they run out (not as FIPS
  203 says). Not chosen.
- FFI wrappers (`oqs`, `liboqs`, `mlkem_native`, `pqforge_ffi`): native
  code, which this package does without.
- `sntrup761x25519-sha512`: no Dart implementation of sntrup761 was
  found, and OpenSSH prefers the ML-KEM hybrid since 10.0.

No Dart runtime promises constant time (the JIT, AOT and dart2js may
compile the same code with or without branches), and cipherlib has not
been audited: the ML-KEM half is held to NIST's vectors, not proven free
of timing leaks, which the hybrid's X25519 half is there for.

What the transport checks: a packet's length against 256 KiB and the
cipher's block as soon as it is read, before anything is allocated for
it; the MAC in constant time, before the padding is read (with
encrypt-then-MAC, before anything is decrypted); the padding; sequence
numbers wrapping at 2^32 and, under strict key exchange, starting again
after each NEWKEYS, the client's KEXINIT its first packet and nothing
but the exchange's messages before its NEWKEYS (without strict key
exchange, IGNORE and DEBUG too); a curve25519 key of the right length
and not of small order; channel windows both ways.

## Tests

`dart test` runs a real dartssh2 client against a server on the loopback
interface, at a port the system picks: key and password logins, refused
keys, the attempt limit, terminals and their size, input, resizes, exit
statuses, two sessions at once, windows, rekeys either side starts; a
raw client for what real clients never send (messages out of order,
unknown algorithms, oversized packets, keys that fail their checks) and
for the hybrid exchange, on a fake clock for the rekey's time; NIST's
ACVP vectors for ML-KEM-768; OpenSSH's `ssh` where it is installed
(skipped with a reason where not), with `StrictHostKeyChecking=no` and
no known_hosts, agreeing on `mlkem768x25519-sha256` unwarned.
`serve_test.dart` runs apps under `serveSsh` against a client terminal
that feeds what it is sent to twk_test's emulator and answers the
probe's DA1: the user, size and `TERM` reaching the app, keys, resizes,
quitting with 0, an error with 1, two apps at once, a client that goes
away, a session without a terminal, and `ssh -tt`.
