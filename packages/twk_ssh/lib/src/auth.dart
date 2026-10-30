/// Who may log in to the server, and how.
library;

import 'dart:async';
import 'dart:io';

import 'keys.dart';

/// Who may log in: by a public key [publicKey] accepts, or by a password
/// [password] accepts. There is no `none` method, keyboard-interactive or
/// host-based login; with neither callback nobody gets in.
///
/// A connection gets [maxAttempts] failed attempts, then it is ended. The
/// client's first `none` request (which asks what the methods are) and a
/// query for a key that is accepted don't count.
final class SshAuth {
  /// Logins by [publicKey] and [password], [maxAttempts] failures allowed.
  const SshAuth({this.publicKey, this.password, this.maxAttempts = 6});

  /// Keys the authorized_keys file at [path] lists may log in, as any
  /// user (see [AuthorizedKeys] for the lines taken). The file is read at
  /// each attempt: a key added or removed counts at once, and a file that
  /// can't be read, or that others than its owner may write
  /// ([AuthorizedKeys.load]), lets no key in.
  factory SshAuth.authorizedKeys(
    String path, {
    FutureOr<bool> Function(String user, String password)? password,
    int maxAttempts = 6,
  }) => SshAuth(
    publicKey: (user, key) async {
      try {
        return (await AuthorizedKeys.load(path)).contains(key);
      } on FileSystemException {
        return false;
      }
    },
    password: password,
    maxAttempts: maxAttempts,
  );

  /// Whether `user` may log in with `key`; asked before the client proves
  /// it holds the private key, and again once it has.
  final FutureOr<bool> Function(String user, SshPublicKey key)? publicKey;

  /// Whether `user` may log in with `password`.
  final FutureOr<bool> Function(String user, String password)? password;

  /// How many failed attempts a connection gets before it is ended.
  final int maxAttempts;

  /// The methods offered, as a failure lists them.
  List<String> get methods => [
    if (publicKey != null) 'publickey',
    if (password != null) 'password',
  ];
}
