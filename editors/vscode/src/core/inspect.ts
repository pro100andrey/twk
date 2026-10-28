// What twk's service extensions (`ext.twk.*`, AppBinding.callServiceExtension
// in packages/twk/lib/src/binding/app_binding.dart) answer about an app, as
// typed values: the element tree, the node at a cell, the debug aids; each
// answer checked before it is taken (its `version` among it), as it comes
// from another process. And what an inspector asks of one app
// ([AppService]): HotApp is it. No vscode import: its tests run under
// plain node.
import { Event } from './events';

/** The shape of the answers read here (`AppBinding.serviceExtensionsVersion`). */
export const inspectorVersion = 1;

/** A property of a node: a value, after its name if it has one. */
export interface InspectProperty {
  readonly name?: string;
  readonly value: string;
}

/** An element of the app's tree, as `ext.twk.tree` describes it. */
export interface InspectNode {
  readonly id: number;
  /** The type of its widget. */
  readonly name: string;
  readonly key?: string;
  readonly properties: readonly InspectProperty[];
  readonly size?: { readonly width: number; readonly height: number };
  readonly flags: readonly string[];
  /** The id of its render object, or of the nearest below it. */
  readonly render?: number;
  /** The type whose `build` makes its child: a stateless widget's, a state's. */
  readonly build?: string;
  readonly children: readonly InspectNode[];
}

/** The element tree: its root, and the id of the app's own element, below the binding's. */
export interface InspectTree {
  readonly root: InspectNode | null;
  readonly app: number | null;
}

/** The debug aids `ext.twk.flags` gives and sets. */
export interface Flags {
  readonly overlay: boolean;
  readonly console: boolean;
  readonly rainbow: boolean;
  readonly relayout: boolean;
  readonly keys: boolean;
  readonly select: boolean;
  /** Whether a pick goes on after a cell picked (a twk of before it: never). */
  readonly selectMany: boolean;
  readonly treeEvents: boolean;
}

export type FlagName = keyof Flags;

export const flagNames: readonly FlagName[] = ['overlay', 'console', 'rainbow', 'relayout', 'keys', 'select', 'selectMany', 'treeEvents'];

/** What an inspector hears from the app: what it posted, a hot reload done, or its binding there (its service extensions registered), which may be after its VM service connected. */
export type AppEvent =
  | { readonly kind: 'extension'; readonly name: string; readonly data: unknown }
  | { readonly kind: 'reloaded' }
  | { readonly kind: 'bound' };

/** One app, as an inspector asks of it: HotApp, or a fake in a test. */
export interface AppService {
  /** Calls the binding's service extension [method] (`ext.twk.tree`...), the parameters strings as the VM service passes them. */
  extension(method: string, params?: Readonly<Record<string, string>>): Promise<Record<string, unknown>>;
  /** Calls the VM service's [method] in the binding's isolate (`isolateId` added): getClassList, getObject... */
  vm(method: string, params?: Readonly<Record<string, unknown>>): Promise<Record<string, unknown>>;
  /** What the app posted on the `Extension` stream, each hot reload done, its binding there. */
  readonly onEvent: Event<AppEvent>;
  /** Whether its binding is there: its service extensions answer. */
  readonly bound: boolean;
  /** Settles once the app is gone. */
  readonly closed: Promise<void>;
}

const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const isId = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v > 0;
const isCount = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0;

/** An answer of a version this reads: the version checked. */
function versioned(answer: unknown): Record<string, unknown> {
  if (!isRecord(answer)) {
    throw new Error('the app answered no JSON object');
  }
  if (answer.version !== inspectorVersion) {
    throw new Error(`the app answers twk's inspector in version ${String(answer.version)}; this extension reads ${inspectorVersion}`);
  }
  return answer;
}

/** A node of `ext.twk.tree`'s answer and those below it; undefined for anything else. */
export function parseNode(v: unknown): InspectNode | undefined {
  if (!isRecord(v) || !isId(v.id) || typeof v.name !== 'string' || !Array.isArray(v.children)) {
    return undefined;
  }
  const properties: InspectProperty[] = [];
  for (const p of Array.isArray(v.properties) ? v.properties : []) {
    if (isRecord(p) && typeof p.value === 'string') {
      properties.push(typeof p.name === 'string' ? { name: p.name, value: p.value } : { value: p.value });
    }
  }
  const children: InspectNode[] = [];
  for (const c of v.children) {
    const child = parseNode(c);
    if (!child) {
      return undefined;
    }
    children.push(child);
  }
  const size = isRecord(v.size) && isCount(v.size.width) && isCount(v.size.height) ? { width: v.size.width, height: v.size.height } : undefined;
  return {
    id: v.id,
    name: v.name,
    ...(typeof v.key === 'string' ? { key: v.key } : {}),
    properties,
    ...(size ? { size } : {}),
    flags: Array.isArray(v.flags) ? v.flags.filter((f): f is string => typeof f === 'string') : [],
    ...(isId(v.render) ? { render: v.render } : {}),
    ...(typeof v.build === 'string' ? { build: v.build } : {}),
    children,
  };
}

/** `ext.twk.tree`'s answer (the element tree); throws on one this doesn't read. */
export function parseTree(answer: unknown): InspectTree {
  const a = versioned(answer);
  if (a.tree !== 'element') {
    throw new Error(`not the element tree: ${String(a.tree)}`);
  }
  const root = a.root === null ? null : parseNode(a.root);
  if (root === undefined) {
    throw new Error('the app answered a tree this does not read');
  }
  return { root, app: isId(a.app) ? a.app : null };
}

/** `ext.twk.select`'s answer: the element at the cell, null for none, and the ids from the root down to it. */
export function parseSelect(answer: unknown): { readonly id: number | null; readonly path: readonly number[] } {
  const a = versioned(answer);
  const path = Array.isArray(a.path) ? a.path.filter(isId) : [];
  return { id: isId(a.id) ? a.id : null, path };
}

/** `ext.twk.flags`' answer; a flag it does not give is off. */
export function parseFlags(answer: unknown): Flags {
  const a = versioned(answer);
  const on = (name: FlagName) => a[name] === true;
  return {
    overlay: on('overlay'),
    console: on('console'),
    rainbow: on('rainbow'),
    relayout: on('relayout'),
    keys: on('keys'),
    select: on('select'),
    selectMany: on('selectMany'),
    treeEvents: on('treeEvents'),
  };
}

/** The cell of `twk.select`, the event of a pick on the app's screen; null for a pick ended with none (Escape); undefined for no such event. */
export function parsePicked(data: unknown): { readonly x: number; readonly y: number } | null | undefined {
  if (!isRecord(data) || data.version !== inspectorVersion) {
    return undefined;
  }
  if (data.x === null && data.y === null) {
    return null;
  }
  return isCount(data.x) && isCount(data.y) ? { x: data.x, y: data.y } : undefined;
}

/** The nodes from [root] down to the one [id] names, root first; undefined where none is. */
export function pathTo(root: InspectNode | null, id: number): InspectNode[] | undefined {
  if (!root) {
    return undefined;
  }
  if (root.id === id) {
    return [root];
  }
  for (const c of root.children) {
    const below = pathTo(c, id);
    if (below) {
      return [root, ...below];
    }
  }
  return undefined;
}

/** The node [id] names in [tree]. */
export function nodeOf(tree: InspectTree, id: number): InspectNode | undefined {
  return pathTo(tree.root, id)?.at(-1);
}

/** The node the tree is shown from: the app's own, or the root. */
export function shownRoot(tree: InspectTree): InspectNode | null {
  return (tree.app === null ? undefined : nodeOf(tree, tree.app)) ?? tree.root;
}

/** What a tree item says of [node] beside its name: its key, its first property, its size. */
export function describeNode(node: InspectNode): string {
  const parts: string[] = [];
  if (node.key) {
    parts.push(node.key);
  }
  const first = node.properties[0];
  if (first) {
    const text = first.name ? `${first.name}: ${first.value}` : first.value;
    parts.push(text.length > 40 ? `${text.substring(0, 39)}…` : text);
  }
  if (node.size) {
    parts.push(`${node.size.width}×${node.size.height}`);
  }
  return parts.join(' · ');
}

/** The lines of a tree item's tooltip: every property, the size, the flags, what builds it. */
export function detailsOf(node: InspectNode): string[] {
  return [
    node.key ? `${node.name} ${node.key}` : node.name,
    ...node.properties.map((p) => (p.name ? `${p.name}: ${p.value}` : p.value)),
    ...(node.size ? [`size ${node.size.width}×${node.size.height}`] : []),
    ...(node.flags.length ? [node.flags.join(', ')] : []),
    ...(node.build ? [`built by ${node.build}.build`] : []),
  ];
}

/** The debug aids an inspector switches: the panels and highlights twk draws over the app. */
export type Toggle = 'overlay' | 'rainbow' | 'relayout' | 'console';

const toggles: readonly { readonly flag: Toggle; readonly label: string; readonly detail: string }[] = [
  { flag: 'overlay', label: 'Frame overlay', detail: "the frames' times, bytes and builds, at the top right" },
  { flag: 'rainbow', label: 'Repaint rainbow', detail: 'each repaint of a repaint boundary tinted with the next colour' },
  { flag: 'relayout', label: 'Relayout highlight', detail: 'what was laid out since the last frame, outlined' },
  { flag: 'console', label: 'Log console', detail: "the app's log over its bottom rows" },
];

/** The items of a pick of the toggles, each picked as [flags] has it. */
export function toggleItems(flags: Flags): { readonly label: string; readonly detail: string; readonly picked: boolean }[] {
  return toggles.map((t) => ({ label: t.label, detail: t.detail, picked: flags[t.flag] }));
}

/** Each toggle on or off, as the items [labels] were picked of [toggleItems]'. */
export function togglesPicked(labels: readonly string[]): Record<Toggle, boolean> {
  const on = (flag: Toggle) => labels.includes(toggles.find((t) => t.flag === flag)?.label ?? '');
  return { overlay: on('overlay'), rainbow: on('rainbow'), relayout: on('relayout'), console: on('console') };
}

/** `ext.twk.flags`' parameters that set [changes]. */
export function flagParams(changes: Readonly<Partial<Record<FlagName, boolean>>>): Record<string, string> {
  return Object.fromEntries(Object.entries(changes).map(([k, v]) => [k, v ? 'true' : 'false']));
}
