// What the twk terminal is, switch by switch: the capabilities the person
// picks (a preset, or each switch), and what follows from them for the
// three that carry them to an app. twk_core decides an app's capabilities
// (Terminal._probe in packages/twk_core/lib/src/terminal/terminal.dart)
// from the link's environment and what the terminal declares, both in the
// shell's welcome (core/shell.ts), and from the answers to the queries the
// app writes first, which the webview gives (webview/answers.ts, by what
// [answersOf] says). Nothing here imports anything: the webview's bundle
// takes the types too.

/** How many colours the terminal shows, as its environment tells (twk's `colorModeFor`). */
export type ColorDepth = 'truecolor' | '256' | '16' | 'none';

/**
 * How the terminal shows images: what xterm.js's image addon (0.9, the one
 * for xterm.js 6.0) shows, sixel and iTerm2's inline images. kitty's
 * graphics protocol is only in its 0.10 betas, for xterm.js 6.1's.
 */
export type Graphics = 'none' | 'sixel' | 'iterm2';

/** A switch of the terminal's that is on or off. */
export type Toggle =
  | 'answers'
  | 'synchronizedOutput'
  | 'kittyKeyboard'
  | 'cellSize'
  | 'notifications'
  | 'progress'
  | 'pointerShapes'
  | 'repeatChar'
  | 'links'
  | 'clipboard';

/** What the terminal is: each of its switches. */
export interface Capabilities {
  readonly colors: ColorDepth;
  readonly graphics: Graphics;
  /** Whether it answers the queries of twk's probe at all; off, none (DA1 neither): the probe times out. */
  readonly answers: boolean;
  /** DECRQM 2026, which xterm.js has; off, the mode is not recognised. */
  readonly synchronizedOutput: boolean;
  /** kitty's keyboard protocol: the webview answers `CSI ? u` and encodes keys as the app pushed (disambiguation). */
  readonly kittyKeyboard: boolean;
  /** `CSI 16 t`, a cell's size in pixels, answered by the webview. */
  readonly cellSize: boolean;
  /** OSC 777 `notify`, shown as VS Code's notification; declared. */
  readonly notifications: boolean;
  /** OSC 9;4, shown in VS Code's status bar; declared. */
  readonly progress: boolean;
  /** OSC 22, the pointer's shape over the terminal; declared. */
  readonly pointerShapes: boolean;
  /** REP (`CSI n b`), which xterm.js does; declared. */
  readonly repeatChar: boolean;
  /** OSC 8 hyperlinks, opened through VS Code (http, https, mailto); off, shown as text only. */
  readonly links: boolean;
  /** OSC 52, put on VS Code's clipboard; off, dropped. */
  readonly clipboard: boolean;
}

/** Each switch that is on or off: its name for the person, and what it does. */
export const toggles: readonly { readonly toggle: Toggle; readonly label: string; readonly description: string }[] = [
  { toggle: 'answers', label: 'answers', description: "answers the probe's queries; off, none, and the probe times out" },
  { toggle: 'synchronizedOutput', label: 'synchronized output', description: 'DEC mode 2026: each frame drawn at once' },
  { toggle: 'kittyKeyboard', label: 'kitty keyboard', description: "kitty's keyboard protocol: Escape, Ctrl and Alt keys as CSI u" },
  { toggle: 'cellSize', label: 'cell size', description: "CSI 16 t answered: a cell's size in pixels, for images" },
  { toggle: 'notifications', label: 'notifications', description: 'OSC 777 shown as VS Code notifications' },
  { toggle: 'progress', label: 'progress', description: "OSC 9;4 shown in VS Code's status bar" },
  { toggle: 'pointerShapes', label: 'pointer shapes', description: "OSC 22: the mouse pointer's shape over the terminal" },
  { toggle: 'repeatChar', label: 'REP', description: 'CSI n b repeats the character before it' },
  { toggle: 'links', label: 'links', description: 'OSC 8 hyperlinks opened through VS Code' },
  { toggle: 'clipboard', label: 'clipboard', description: "OSC 52 put on VS Code's clipboard" },
];

export const colorDepths: readonly { readonly colors: ColorDepth; readonly label: string; readonly description: string }[] = [
  { colors: 'truecolor', label: '24-bit color', description: 'COLORTERM=truecolor' },
  { colors: '256', label: '256 colors', description: 'TERM=xterm-256color, no COLORTERM' },
  { colors: '16', label: '16 colors', description: 'TERM=xterm' },
  { colors: 'none', label: 'no color', description: 'NO_COLOR=1' },
];

export const graphicsKinds: readonly { readonly graphics: Graphics; readonly label: string; readonly description: string }[] = [
  { graphics: 'none', label: 'no images', description: 'the cells of an image stay blank' },
  { graphics: 'sixel', label: 'sixel images', description: "DEC sixel, by xterm.js's image addon" },
  { graphics: 'iterm2', label: 'iTerm2 images', description: "iTerm2's inline images (OSC 1337), by xterm.js's image addon" },
];

/** xterm.js and what the extension does beside it: the default. */
const xtermJs: Capabilities = {
  colors: 'truecolor',
  graphics: 'none',
  answers: true,
  synchronizedOutput: true,
  kittyKeyboard: false,
  cellSize: true,
  notifications: true,
  progress: true,
  pointerShapes: true,
  repeatChar: true,
  links: true,
  clipboard: true,
};

/** Of the toggles, none: a terminal that does the least while it answers. */
const bare: Capabilities = {
  ...xtermJs,
  synchronizedOutput: false,
  cellSize: false,
  notifications: false,
  progress: false,
  pointerShapes: false,
  repeatChar: false,
  links: false,
  clipboard: false,
};

export interface Preset {
  readonly name: string;
  readonly description: string;
  readonly capabilities: Capabilities;
}

export const presets: readonly Preset[] = [
  { name: 'xterm.js', description: '24-bit color, what xterm.js answers, notifications, progress, links and the clipboard through VS Code', capabilities: xtermJs },
  { name: 'everything', description: 'xterm.js, kitty keyboard and sixel images', capabilities: { ...xtermJs, kittyKeyboard: true, graphics: 'sixel' } },
  { name: '256 colors', description: 'xterm.js with TERM=xterm-256color, no COLORTERM', capabilities: { ...xtermJs, colors: '256' } },
  { name: '16 colors', description: 'xterm.js with TERM=xterm', capabilities: { ...xtermJs, colors: '16' } },
  { name: 'no color', description: 'xterm.js with NO_COLOR=1', capabilities: { ...xtermJs, colors: 'none' } },
  { name: 'no synchronized output', description: 'xterm.js, DEC mode 2026 not recognised', capabilities: { ...xtermJs, synchronizedOutput: false } },
  { name: 'bare', description: 'answers, declares nothing it does: none of the toggles', capabilities: bare },
  { name: 'no answers', description: 'a terminal that answers no query: the probe times out', capabilities: { ...bare, answers: false } },
];

/** The preset of [name]; the first (xterm.js) for any other. */
export function presetNamed(name: unknown): Preset {
  return presets.find((p) => p.name === name) ?? presets[0];
}

/** What the person chose: a preset and the switches changed from it. */
export interface Choice {
  readonly preset: Preset;
  readonly capabilities: Capabilities;
}

const isColors = (v: unknown): v is ColorDepth => colorDepths.some((c) => c.colors === v);
const isGraphics = (v: unknown): v is Graphics => graphicsKinds.some((g) => g.graphics === v);

/**
 * The capabilities of the settings' values, each checked: the preset
 * [preset] names (xterm.js for none), each switch of [changes] (an object
 * of the [Capabilities]' fields) of the right type over it, the rest of
 * it left out.
 */
export function choiceOf(preset: unknown, changes: unknown): Choice {
  const p = presetNamed(preset);
  const c: Record<string, unknown> = typeof changes === 'object' && changes !== null && !Array.isArray(changes) ? { ...changes } : {};
  let capabilities: Capabilities = {
    ...p.capabilities,
    ...(isColors(c.colors) ? { colors: c.colors } : {}),
    ...(isGraphics(c.graphics) ? { graphics: c.graphics } : {}),
  };
  for (const { toggle } of toggles) {
    const on = c[toggle];
    if (typeof on === 'boolean') {
      capabilities = withToggle(capabilities, toggle, on);
    }
  }
  return { preset: p, capabilities };
}

/** [capabilities] with [toggle] [on]. */
export function withToggle(capabilities: Capabilities, toggle: Toggle, on: boolean): Capabilities {
  return { ...capabilities, [toggle]: on };
}

/** The switches where [capabilities] differ from [preset]'s: what the settings keep beside the preset's name. */
export interface Changes {
  readonly colors?: ColorDepth;
  readonly graphics?: Graphics;
  readonly toggles: Partial<Record<Toggle, boolean>>;
}

export function changesFrom(preset: Preset, capabilities: Capabilities): Changes {
  const base = preset.capabilities;
  const changed: Partial<Record<Toggle, boolean>> = {};
  for (const { toggle } of toggles) {
    if (base[toggle] !== capabilities[toggle]) {
      changed[toggle] = capabilities[toggle];
    }
  }
  return {
    ...(base.colors !== capabilities.colors ? { colors: capabilities.colors } : {}),
    ...(base.graphics !== capabilities.graphics ? { graphics: capabilities.graphics } : {}),
    toggles: changed,
  };
}

/** [changes] as the setting `twk.terminal.capabilities` keeps them: one object of the switches changed. */
export function changesSetting(changes: Changes): Record<string, string | boolean> {
  return {
    ...(changes.colors !== undefined ? { colors: changes.colors } : {}),
    ...(changes.graphics !== undefined ? { graphics: changes.graphics } : {}),
    ...changes.toggles,
  };
}

/** What the title of a terminal says of [choice]: the preset, and each switch changed from it. */
export function describeChoice(choice: Choice): string {
  const changes = changesFrom(choice.preset, choice.capabilities);
  const said: string[] = [];
  if (changes.colors !== undefined) {
    said.push(colorDepths.find((c) => c.colors === changes.colors)?.label ?? changes.colors);
  }
  if (changes.graphics !== undefined) {
    said.push(graphicsKinds.find((g) => g.graphics === changes.graphics)?.label ?? changes.graphics);
  }
  for (const t of toggles) {
    const on = changes.toggles[t.toggle];
    if (on !== undefined) {
      said.push(on ? t.label : `no ${t.label}`);
    }
  }
  return [choice.preset.name, ...said].join(', ');
}

/** What twk_core reads of the terminal's environment: what xterm.js is, as twk_web's XtermLink says. */
export function environmentOf(capabilities: Capabilities): Record<string, string> {
  const program = { TERM_PROGRAM: 'twk-vscode' };
  switch (capabilities.colors) {
    case 'truecolor':
      return { TERM: 'xterm-256color', COLORTERM: 'truecolor', ...program };
    case '256':
      return { TERM: 'xterm-256color', ...program };
    case '16':
      return { TERM: 'xterm', ...program };
    case 'none':
      return { TERM: 'xterm-256color', COLORTERM: 'truecolor', ...program, NO_COLOR: '1' };
  }
}

/**
 * What the terminal declares it does in the shell's welcome (`declares`,
 * twk_core's `TerminalDeclaration`), each in place of twk's guess by the
 * terminal's name: all of them, as the terminal knows itself. In
 * twk_core's order of them, as the golden of the wire has it.
 */
export interface Declaration {
  readonly notifications?: 'none' | 'osc9' | 'osc777' | 'osc99';
  readonly progressReports?: boolean;
  readonly pointerShapes?: boolean;
  readonly repeatChar?: boolean;
  readonly graphics?: 'none' | 'kitty' | 'sixel' | 'iterm2';
}

export function declarationOf(capabilities: Capabilities): Declaration {
  return {
    notifications: capabilities.notifications ? 'osc777' : 'none',
    progressReports: capabilities.progress,
    pointerShapes: capabilities.pointerShapes,
    repeatChar: capabilities.repeatChar,
    graphics: capabilities.graphics,
  };
}

/** A query of twk's probe that the webview leaves unanswered where denied. */
export type Query =
  | 'synchronizedOutput' // DECRQM 2026: answered "not recognised"
  | 'graphemes' // DECRQM 2027
  | 'inBandResize' // DECRQM 2048
  | 'margins' // DECRQM 69
  | 'colorSchemeReports' // DECRQM 2031
  | 'colors' // OSC 10, 11, 4 queries: no answer
  | 'deviceAttributes'; // DA1, the probe's last: no answer

/**
 * What the webview answers and does: the queries it denies, and each of
 * what it emulates beside xterm.js. Sent to it (webview/protocol.ts) as
 * each app is taken.
 */
export interface Answers {
  readonly deny: readonly Query[];
  /** kitty's keyboard protocol: `CSI ? u` answered, keys encoded as the app pushed. */
  readonly kittyKeyboard: boolean;
  /** The name XTVERSION (`CSI > q`) is answered with; null, no answer. */
  readonly version: string | null;
  readonly cellSize: boolean;
  readonly graphics: Graphics;
  readonly notifications: boolean;
  readonly progress: boolean;
  readonly pointerShapes: boolean;
  readonly links: boolean;
  readonly clipboard: boolean;
}

/** The terminal's name as XTVERSION tells it: none of the names twk knows a terminal by. */
export const terminalVersion = 'twk-vscode(0.0.1)';

export function answersOf(capabilities: Capabilities): Answers {
  const answers = capabilities.answers;
  const deny: Query[] = answers
    ? capabilities.synchronizedOutput
      ? []
      : ['synchronizedOutput']
    : ['synchronizedOutput', 'graphemes', 'inBandResize', 'margins', 'colorSchemeReports', 'colors', 'deviceAttributes'];
  return {
    deny,
    kittyKeyboard: answers && capabilities.kittyKeyboard,
    version: answers ? terminalVersion : null,
    cellSize: answers && capabilities.cellSize,
    graphics: capabilities.graphics,
    notifications: capabilities.notifications,
    progress: capabilities.progress,
    pointerShapes: capabilities.pointerShapes,
    links: capabilities.links,
    clipboard: capabilities.clipboard,
  };
}

/** An item of the picks of the switches. */
export interface ChoiceItem {
  readonly label: string;
  readonly description: string;
  readonly picked: boolean;
}

/** The items of the pick of the toggles, those on in [capabilities] picked. */
export function toggleItems(capabilities: Capabilities): ChoiceItem[] {
  return toggles.map((t) => ({ label: t.label, description: t.description, picked: capabilities[t.toggle] }));
}

/** [capabilities] with the toggles the [labels] picked on and the others off. */
export function togglesPicked(capabilities: Capabilities, labels: readonly string[]): Capabilities {
  return toggles.reduce((c, t) => withToggle(c, t.toggle, labels.includes(t.label)), capabilities);
}
