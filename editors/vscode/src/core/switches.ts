// What the twk terminal switches on in any app it serves, beside what it
// tells the app it is (capabilities.ts): the screen-reader mode and twk's
// debug aids. twk reads TWK_SCREEN_READER and TWK_DEBUG of the
// environment of a terminal of the app's process (`TerminalInfo.settings`
// in packages/twk_core/lib/src/terminal/terminal.dart), the shell's
// welcome here, in place of the process's values; the rest of the
// welcome's environment is only what the terminal is. So a switch reaches
// an app the extension started and one started anywhere with its
// TWK_SHELL alike, from the next app to connect on (a hot restart too).

/** A debug aid of twk's that TWK_DEBUG names. */
export type DebugAid = 'overlay' | 'console' | 'frames' | 'timeline' | 'logs' | 'rainbow' | 'relayout';

/** Each debug aid, and what it does. */
export const debugAids: readonly { readonly aid: DebugAid; readonly description: string }[] = [
  { aid: 'overlay', description: "the frame overlay: each frame's times, bytes and cells" },
  { aid: 'console', description: "the log console over the app's bottom rows, open on an error" },
  { aid: 'frames', description: 'each frame written in full below the last, as text' },
  { aid: 'timeline', description: "each frame's phases as Timeline events, for DevTools" },
  { aid: 'logs', description: "the app's log served to `twk logs`" },
  { aid: 'rainbow', description: 'the repaint rainbow: what repainted changes color' },
  { aid: 'relayout', description: 'what was laid out again, highlighted' },
];

/** What the terminal switches on. */
export interface Switches {
  readonly screenReader: boolean;
  /** In the order of [debugAids], each once. */
  readonly debug: readonly DebugAid[];
}

export const noSwitches: Switches = { screenReader: false, debug: [] };

function isAid(value: unknown): value is DebugAid {
  return debugAids.some((a) => a.aid === value);
}

/**
 * The switches of settings' values, each checked: a screen reader on only
 * for `true`, the aids among [debugAids] (in their order, each once), any
 * other value left out.
 */
export function switchesOf(screenReader: unknown, debug: unknown): Switches {
  const named = new Set(Array.isArray(debug) ? debug.filter(isAid) : []);
  return {
    screenReader: screenReader === true,
    debug: debugAids.map((a) => a.aid).filter((aid) => named.has(aid)),
  };
}

/**
 * The variables of the shell's welcome that [switches] set: only those it
 * turns on, so that an app's own environment decides the rest (a launch's
 * TWK_DEBUG). TWK_DEBUG, once set, takes the place of the app's, so it
 * names `keys` too: the app's own hot reload and restart keys (Ctrl+G h,
 * Ctrl+G H), which the extension's runs and launches ask for.
 */
export function switchEnvironment(switches: Switches): Record<string, string> {
  const env: Record<string, string> = {};
  if (switches.screenReader) {
    env.TWK_SCREEN_READER = '1';
  }
  if (switches.debug.length > 0) {
    env.TWK_DEBUG = ['keys', ...switches.debug].join(',');
  }
  return env;
}

/** The switches on, for a terminal's title: `screen reader, overlay`; empty for none. */
export function describeSwitches(switches: Switches): string {
  return [...(switches.screenReader ? ['screen reader'] : []), ...switches.debug].join(', ');
}

/** An item of the pick of switches. */
export interface SwitchItem {
  readonly label: string;
  readonly description: string;
  readonly picked: boolean;
}

const readerLabel = 'screen reader';

/** The items to pick the switches from, those of [current] picked. */
export function switchItems(current: Switches): SwitchItem[] {
  return [
    { label: readerLabel, description: 'TWK_SCREEN_READER=1: the app read out as lines of text', picked: current.screenReader },
    ...debugAids.map((a) => ({ label: a.aid, description: a.description, picked: current.debug.includes(a.aid) })),
  ];
}

/** The switches the labels of the items picked say. */
export function switchesPicked(labels: readonly string[]): Switches {
  return switchesOf(labels.includes(readerLabel), labels);
}
