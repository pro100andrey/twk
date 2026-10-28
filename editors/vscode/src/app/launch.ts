// The debug configurations of apps debugged in a twk terminal, as plain
// data: what a `"type": "twk"` launch (F5, launch.json) becomes for
// Dart-Code, what the person's configuration asks for, and the launch the
// extension made read back from a session's configuration. vscode/launch.ts
// and vscode/debugger.ts are the adapters that hand VS Code's
// configurations to these.
import { DartLaunch } from './ports';

/** A configuration as VS Code holds it: JSON-like, checked before it is taken for anything. */
export type Configuration = Readonly<Record<string, unknown>>;

/** What a person's configuration asks for: an app to debug in a twk terminal of its own. */
export interface DebugRequest {
  readonly program: string;
  readonly cwd?: string;
  readonly name?: string;
  readonly env: Readonly<Record<string, string>>;
  /** The rest (args, toolArgs, vmAdditionalArgs...), passed on to Dart-Code as it is. */
  readonly others: Configuration;
}

/** The field of a Dart configuration that asks for a twk terminal. */
export const twkTerminalField = 'twkTerminal';

/** The fields a [DartLaunch] sets: none of them is passed on from [DebugRequest.others]. */
const launchFields = new Set(['type', 'request', 'name', 'program', 'cwd', 'console', 'env', 'twkSession', twkTerminalField]);

function othersOf(c: Configuration): Configuration {
  return Object.fromEntries(Object.entries(c).filter(([k]) => !launchFields.has(k)));
}

const isStrings = (v: unknown): v is Record<string, string> =>
  typeof v === 'object' && v !== null && !Array.isArray(v) && Object.values(v).every((s) => typeof s === 'string');

/**
 * A `"type": "twk"` configuration as the Dart one it stands for, before
 * VS Code substitutes its variables: Dart-Code's launch in the Debug
 * Console, marked [twkTerminalField], the current file when it names no
 * program. A string says why it can't be.
 */
export function asDartConfiguration(c: Configuration): Configuration | string {
  if (c.request !== undefined && c.request !== 'launch') {
    return 'a twk configuration launches ("request": "launch"); attach with Dart-Code\'s own';
  }
  return {
    ...c,
    type: 'dart',
    request: 'launch',
    console: 'debugConsole',
    [twkTerminalField]: true,
    program: c.program ?? '${file}',
  };
}

/** Whether [c] is a Dart configuration that asks for a twk terminal and has none yet. */
export function wantsTerminal(c: Configuration): boolean {
  return c.type === 'dart' && c[twkTerminalField] === true && c.twkSession === undefined;
}

/** What [c], its variables substituted, asks for; a string says what is wrong with it. */
export function debugRequest(c: Configuration): DebugRequest | string {
  if (c.request !== undefined && c.request !== 'launch') {
    return 'a twk terminal is for a launch ("request": "launch")';
  }
  if (typeof c.program !== 'string' || !c.program) {
    return 'the configuration names no program (a Dart file)';
  }
  if (c.cwd !== undefined && typeof c.cwd !== 'string') {
    return '"cwd" is not a path';
  }
  if (c.env !== undefined && !isStrings(c.env)) {
    return '"env" is not an object of strings';
  }
  return {
    program: c.program,
    ...(typeof c.cwd === 'string' ? { cwd: c.cwd } : {}),
    ...(typeof c.name === 'string' ? { name: c.name } : {}),
    env: c.env ?? {},
    others: othersOf(c),
  };
}

/** [launch] as the configuration VS Code starts: its [DartLaunch.others] around it. */
export function toConfiguration(launch: DartLaunch): Configuration {
  const { others, ...fields } = launch;
  return { ...others, ...fields };
}

/** The launch [c] is, when the extension made it (it has `twkSession`); else undefined. */
export function fromConfiguration(c: Configuration): DartLaunch | undefined {
  const { type, request, name, program, cwd, env, twkSession } = c;
  if (
    type !== 'dart' ||
    request !== 'launch' ||
    typeof program !== 'string' ||
    typeof cwd !== 'string' ||
    typeof twkSession !== 'string' ||
    !isStrings(env)
  ) {
    return undefined;
  }
  return {
    type,
    request,
    name: typeof name === 'string' ? name : program,
    program,
    cwd,
    console: 'debugConsole',
    env,
    twkSession,
    others: othersOf(c),
  };
}
