// The address of a twk shell on one line, as the environment variable
// TWK_SHELL holds it: what twk_core's `LocalAddress.toVariable` writes and
// `LocalAddress.fromVariable` reads (packages/twk_core/lib/src/terminal/
// address.dart). This file must say what that one says.

/** The variable an app with no terminal of its own finds its shell by. */
export const shellVariable = 'TWK_SHELL';

/** Where a shell listens, and the token an app opens with. */
export interface ShellAddress {
  /** `unix:<path>` or `tcp:<host>:<port>`. */
  readonly where: string;
  readonly token: string;
}

/** [address] as TWK_SHELL holds it: `<where>#<token>`. */
export function toVariable(address: ShellAddress): string {
  return `${address.where}#${address.token}`;
}

/** What [toVariable] made; undefined for anything else. */
export function fromVariable(value: string): ShellAddress | undefined {
  const hash = value.lastIndexOf('#');
  if (hash < 0 || /[\r\n]/.test(value)) {
    return undefined;
  }
  const where = value.substring(0, hash);
  const token = value.substring(hash + 1);
  if (!token) {
    return undefined;
  }
  if (where.startsWith('unix:') && where.length > 5) {
    return { where, token };
  }
  const colon = where.lastIndexOf(':');
  if (where.startsWith('tcp:') && colon > 4 && /^\d+$/.test(where.substring(colon + 1)) && isIp(where.substring(4, colon))) {
    return { where, token };
  }
  return undefined;
}

/** What `net.connect` takes for [where] ([ShellAddress.where]): the path of `unix:<path>`, the host and port of `tcp:<host>:<port>`. */
export function connectionOf(where: string): { path: string } | { host: string; port: number } {
  if (where.startsWith('tcp:')) {
    const colon = where.lastIndexOf(':');
    return { host: where.substring(4, colon), port: Number(where.substring(colon + 1)) };
  }
  return { path: where.substring('unix:'.length) };
}

function isIp(host: string): boolean {
  return /^\d{1,3}(\.\d{1,3}){3}$/.test(host) || (host.includes(':') && /^[0-9a-fA-F:.]+$/.test(host));
}
