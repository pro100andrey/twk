// The terminal report: what an app is told by the twk terminal as the
// settings have it (the environment, what the welcome declares, which of the
// probe's queries are answered and what the webview emulates), and the
// project's part, which `twk doctor --json` says. All computed from
// core/capabilities.ts and core/switches.ts, the same functions the terminal
// takes an app with, so the report cannot say otherwise; the HTML for the
// webview is pure too.
import { Choice, Declaration, answersOf, declarationOf, environmentOf, describeChoice } from './capabilities';
import { escapeHtml } from './html';
import { Switches, switchEnvironment, describeSwitches } from './switches';

/** How a query of twk's probe ends. */
export type Outcome = 'answered' | 'not recognised' | 'no answer';

/** A query of the probe, and what the twk terminal does with it. */
export interface QueryRow {
  readonly query: string;
  readonly sequence: string;
  readonly outcome: Outcome;
  readonly detail: string;
}

/** A thing an app asks the terminal for beside the queries, and whether it is done. */
export interface HandledRow {
  readonly name: string;
  readonly on: boolean;
  readonly detail: string;
}

/** What the twk terminal is to an app, for one choice of preset and switches. */
export interface TerminalReport {
  /** The preset and the switches changed from it, as a terminal's title says them. */
  readonly profile: string;
  readonly switches: string;
  /** TERM, COLORTERM, NO_COLOR, TERM_PROGRAM and the switches' variables: what the app is started with. */
  readonly environment: Readonly<Record<string, string>>;
  readonly declares: Declaration;
  readonly queries: readonly QueryRow[];
  readonly handled: readonly HandledRow[];
}

export function terminalReportOf(choice: Choice, switches: Switches): TerminalReport {
  const capabilities = choice.capabilities;
  const answers = answersOf(capabilities);
  const denied = (q: (typeof answers.deny)[number]) => answers.deny.includes(q);
  const mode = (query: string, sequence: string, q: (typeof answers.deny)[number]): QueryRow =>
    denied(q)
      ? { query, sequence, outcome: 'not recognised', detail: 'the extension answers the mode as 0, not recognised' }
      : { query, sequence, outcome: 'answered', detail: "xterm.js's own answer" };
  const queries: QueryRow[] = [
    mode('synchronized output', 'CSI ? 2026 $ p', 'synchronizedOutput'),
    mode('grapheme clusters', 'CSI ? 2027 $ p', 'graphemes'),
    mode('in-band resize', 'CSI ? 2048 $ p', 'inBandResize'),
    mode('left and right margins', 'CSI ? 69 $ p', 'margins'),
    mode('color scheme reports', 'CSI ? 2031 $ p', 'colorSchemeReports'),
    denied('colors')
      ? { query: 'colors', sequence: 'OSC 10, 11, 4 ; ?', outcome: 'no answer', detail: 'dropped by the extension' }
      : { query: 'colors', sequence: 'OSC 10, 11, 4 ; ?', outcome: 'answered', detail: "xterm.js's own answer" },
    answers.version === null
      ? { query: 'terminal name and version', sequence: 'CSI > q', outcome: 'no answer', detail: 'the extension adds none; xterm.js has no answer of its own to it' }
      : { query: 'terminal name and version', sequence: 'CSI > q', outcome: 'answered', detail: answers.version },
    answers.kittyKeyboard
      ? { query: 'kitty keyboard flags', sequence: 'CSI ? u', outcome: 'answered', detail: 'the flags the app pushed (disambiguation); keys are encoded as CSI u' }
      : { query: 'kitty keyboard flags', sequence: 'CSI ? u', outcome: 'no answer', detail: 'keys are those of xterm.js' },
    answers.cellSize
      ? { query: 'cell size in pixels', sequence: 'CSI 16 t', outcome: 'answered', detail: 'once the terminal has measured a cell' }
      : { query: 'cell size in pixels', sequence: 'CSI 16 t', outcome: 'no answer', detail: 'xterm.js drops the report' },
    denied('deviceAttributes')
      ? { query: 'device attributes (the probe\'s last query)', sequence: 'CSI c', outcome: 'no answer', detail: 'the probe times out' }
      : { query: 'device attributes (the probe\'s last query)', sequence: 'CSI c', outcome: 'answered', detail: "xterm.js's own answer" },
  ];
  const on = (flag: boolean, yes: string, no: string) => (flag ? yes : no);
  const handled: HandledRow[] = [
    { name: 'images', on: answers.graphics !== 'none', detail: answers.graphics === 'none' ? 'the cells of an image stay blank' : answers.graphics === 'sixel' ? 'DEC sixel' : "iTerm2's inline images (OSC 1337)" },
    { name: 'notifications', on: answers.notifications, detail: on(answers.notifications, 'OSC 777 shown as VS Code notifications', 'OSC 777 dropped') },
    { name: 'progress', on: answers.progress, detail: on(answers.progress, "OSC 9;4 shown in VS Code's status bar", 'OSC 9;4 dropped') },
    { name: 'pointer shapes', on: answers.pointerShapes, detail: on(answers.pointerShapes, 'OSC 22 sets the pointer over the terminal', 'OSC 22 ignored') },
    { name: 'links', on: answers.links, detail: on(answers.links, 'OSC 8 hyperlinks opened through VS Code', 'OSC 8 shown as text only') },
    { name: 'clipboard', on: answers.clipboard, detail: on(answers.clipboard, "OSC 52 put on VS Code's clipboard", 'OSC 52 dropped') },
    { name: 'repeat character', on: capabilities.repeatChar, detail: on(capabilities.repeatChar, 'CSI n b, declared', 'declared as not done') },
  ];
  return {
    profile: describeChoice(choice),
    switches: describeSwitches(switches),
    environment: { ...environmentOf(capabilities), ...switchEnvironment(switches) },
    declares: declarationOf(capabilities),
    queries,
    handled,
  };
}

/** A file of `.dart_tool/twk` and what it names. */
export interface ServiceState {
  readonly address: string;
  readonly listens: boolean;
}

/** `twk doctor --json`, the project's part of it. */
export interface ProjectReport {
  readonly project: string;
  readonly dart: string;
  readonly lock: string | null;
  readonly versions: Readonly<Record<string, string>>;
  readonly agree: boolean;
  readonly state: Readonly<Record<string, ServiceState>>;
  readonly agents: { readonly stale: readonly string[]; readonly edited: readonly string[]; readonly missing: boolean } | null;
}

/** What asking `twk doctor` came to. */
export type ProjectResult =
  | { readonly kind: 'ok'; readonly report: ProjectReport }
  | { readonly kind: 'none' }
  | { readonly kind: 'failed'; readonly message: string };

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((s): s is string => typeof s === 'string') : []);

/**
 * The report of [stdout], the output of `twk doctor --json`: its one
 * object, after whatever `dart run` wrote before it (a build line). Each
 * field checked; an output that is no such object is `failed`, saying so.
 */
export function parseDoctor(stdout: string): ProjectResult {
  const start = stdout.startsWith('{') ? 0 : stdout.indexOf('\n{') + 1;
  if (start === 0 && !stdout.startsWith('{')) {
    return { kind: 'failed', message: `no JSON in the output of twk doctor: ${stdout.trim().split('\n')[0] || '(empty)'}` };
  }
  let json: unknown;
  try {
    json = JSON.parse(stdout.slice(start));
  } catch {
    return { kind: 'failed', message: 'the output of twk doctor is not JSON' };
  }
  if (!isRecord(json) || typeof json.project !== 'string') {
    return { kind: 'failed', message: 'the output of twk doctor is not its report' };
  }
  const versions: Record<string, string> = {};
  if (isRecord(json.versions)) {
    for (const [name, v] of Object.entries(json.versions)) {
      if (typeof v === 'string') {
        versions[name] = v;
      }
    }
  }
  const state: Record<string, ServiceState> = {};
  if (isRecord(json.state)) {
    for (const [name, s] of Object.entries(json.state)) {
      if (isRecord(s) && typeof s.address === 'string') {
        state[name] = { address: s.address, listens: s.listens === true };
      }
    }
  }
  const a = json.agents;
  return {
    kind: 'ok',
    report: {
      project: json.project,
      dart: typeof json.dart === 'string' ? json.dart : '',
      lock: typeof json.lock === 'string' ? json.lock : null,
      versions,
      agree: json.agree === true,
      state,
      agents: isRecord(a) ? { stale: strings(a.stale), edited: strings(a.edited), missing: a.missing === true } : null,
    },
  };
}


/** The packages `twk doctor` compares, in its order. */
export const doctorPackages = ['twk', 'twk_core', 'twk_dev', 'twk_test'] as const;

function projectHtml(result: ProjectResult): string {
  if (result.kind === 'none') {
    return '<p class="muted">No Dart project: open a file of one, or a folder, for the project part.</p>';
  }
  if (result.kind === 'failed') {
    return `<p class="bad">${escapeHtml(result.message)}</p>`;
  }
  const r = result.report;
  const rows: string[] = [
    `<tr><th>project</th><td>${escapeHtml(r.project)}</td></tr>`,
    `<tr><th>Dart</th><td>${escapeHtml(r.dart)}</td></tr>`,
    `<tr><th>pubspec.lock</th><td>${r.lock === null ? 'none found' : escapeHtml(r.lock)}</td></tr>`,
    ...doctorPackages.map((p) => `<tr><th>${p}</th><td>${r.versions[p] === undefined ? '<span class="muted">not in the lock</span>' : escapeHtml(r.versions[p])}</td></tr>`),
    `<tr><th>versions</th><td class="${r.agree ? 'ok' : 'bad'}">${r.lock === null ? 'no lock to compare' : r.agree ? 'agree' : 'DISAGREE: pub upgrade them together'}</td></tr>`,
  ];
  const services = Object.entries(r.state);
  rows.push(
    services.length === 0
      ? '<tr><th>.dart_tool/twk</th><td class="muted">nothing: no app running</td></tr>'
      : services.map(([name, s]) => `<tr><th>${escapeHtml(name)}</th><td>${escapeHtml(s.address)} <span class="${s.listens ? 'ok' : 'bad'}">${s.listens ? 'listening' : 'left behind'}</span></td></tr>`).join(''),
  );
  if (r.agents !== null) {
    const parts = [
      ...(r.agents.missing ? ['missing: twk agents writes it'] : []),
      ...(r.agents.stale.length > 0 ? [`older than this twk_dev: ${r.agents.stale.map(escapeHtml).join(', ')} (twk agents rewrites them)`] : []),
      ...(r.agents.edited.length > 0 ? [`changed by the project, kept: ${r.agents.edited.map(escapeHtml).join(', ')}`] : []),
    ];
    rows.push(`<tr><th>skill for agents</th><td class="${parts.length === 0 ? 'ok' : 'bad'}">${parts.length === 0 ? 'current' : parts.join('; ')}</td></tr>`);
  }
  return `<table>${rows.join('')}</table>`;
}

/** The page: the terminal's part and the project's, under a CSP allowing the one script, [nonce]'s (the Refresh button). */
export function reportHtml(terminal: TerminalReport, project: ProjectResult, nonce: string): string {
  const env = Object.entries(terminal.environment)
    .map(([k, v]) => `<tr><th>${escapeHtml(k)}</th><td>${escapeHtml(v)}</td></tr>`)
    .join('');
  const declares = Object.entries(terminal.declares)
    .map(([k, v]) => `<tr><th>${escapeHtml(k)}</th><td>${escapeHtml(String(v))}</td></tr>`)
    .join('');
  const queries = terminal.queries
    .map((q) => `<tr><td>${escapeHtml(q.query)}</td><td><code>${escapeHtml(q.sequence)}</code></td><td class="${q.outcome === 'answered' ? 'ok' : 'bad'}">${q.outcome}</td><td>${escapeHtml(q.detail)}</td></tr>`)
    .join('');
  const handled = terminal.handled
    .map((h) => `<tr><td>${escapeHtml(h.name)}</td><td class="${h.on ? 'ok' : 'muted'}">${h.on ? 'on' : 'off'}</td><td>${escapeHtml(h.detail)}</td></tr>`)
    .join('');
  return `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'">
<title>twk terminal report</title>
<style>body{font-family:var(--vscode-font-family);color:var(--vscode-foreground);padding:8px 16px}
table{border-collapse:collapse;margin:4px 0 16px}th{text-align:left;padding:2px 16px 2px 0;font-weight:normal;color:var(--vscode-descriptionForeground)}
td{padding:2px 16px 2px 0}.ok{color:var(--vscode-testing-iconPassed)}.bad{color:var(--vscode-errorForeground)}.muted{color:var(--vscode-descriptionForeground)}
code{font-family:var(--vscode-editor-font-family)}h2{font-size:1.1em;margin:16px 0 4px}</style></head>
<body><h1>The twk terminal</h1>
<p>Profile <b>${escapeHtml(terminal.profile)}</b>${terminal.switches === '' ? '' : `, switches on: ${escapeHtml(terminal.switches)}`}. <button id="refresh">Refresh</button></p>
<h2>An app is started with</h2><table>${env}</table>
<h2>The welcome declares</h2><table>${declares}</table>
<h2>The probe's queries</h2><table>${queries}</table>
<h2>What the terminal does for the app</h2><table>${handled}</table>
<h1>The project</h1>${projectHtml(project)}
<script nonce="${nonce}">const vscode=acquireVsCodeApi();document.getElementById('refresh').addEventListener('click',()=>vscode.postMessage({refresh:true}));</script>
</body></html>`;
}

/** Whether a message from the page is its Refresh button. */
export function isRefresh(message: unknown): boolean {
  return typeof message === 'object' && message !== null && 'refresh' in message && message.refresh === true;
}
