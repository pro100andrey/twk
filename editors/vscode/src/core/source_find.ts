// Where a widget was made, found in the app's code: twk keeps no creation
// locations (its widgets' constructors are `const` and run no code, and
// `dart run` has no kernel transformer such as Flutter's
// track-widget-creation), so an element's widget is looked for in the
// `build` methods above it ([creationOwners]), the nearest first, as a
// call of its type's constructor in that method's source ([constructorCalls]);
// among several, the one in the place the element has among those of its
// type that build made ([CreationOwner.index]). Pure functions over the
// tree and source text; VM service lookups are locator.ts's.
import { InspectNode, pathTo } from './inspect';

/** A build method that may have made the widget: the component element whose build it is, and what it made of that type. */
export interface CreationOwner {
  /** The element whose child its `build` makes. */
  readonly node: InspectNode;
  /** The type of that `build` (the widget's, the state's). */
  readonly build: string;
  /** Where the widget is among the elements of its type this build made, in the tree's order. */
  readonly index: number;
  /** How many elements of its type this build made. */
  readonly count: number;
}

/** The type [name] (a runtimeType's text) is a class of: `Foo<int>` is `Foo`. */
export function className(name: string): string {
  const lt = name.indexOf('<');
  return lt < 0 ? name : name.substring(0, lt);
}

/**
 * The builds that may have made the widget of the element [id] names, the
 * nearest first: each element above it that builds (a stateless widget's,
 * a stateful one's), with where the element is among those of its type it
 * made. What one build made: the elements below it, but those below
 * another build that [makes] widgets of that type, which that one made;
 * below one that makes none, they were passed to it (a `child`), and so
 * are counted; the builds on the way to [id] are looked into, as the
 * widget may have been passed through them (a `child`, a builder's
 * closure).
 */
export function creationOwners(root: InspectNode | null, id: number, makes: (build: string) => boolean = () => true): CreationOwner[] {
  const path = pathTo(root, id);
  if (!path) {
    return [];
  }
  const target = path[path.length - 1];
  const onPath = new Set(path.map((n) => n.id));
  const type = className(target.name);
  const owners: CreationOwner[] = [];
  for (let i = path.length - 2; i >= 0; i--) {
    const node = path[i];
    if (node.build === undefined) {
      continue;
    }
    const made: InspectNode[] = [];
    const visit = (n: InspectNode) => {
      if (className(n.name) === type) {
        made.push(n);
      }
      // another build's elements are its own, but on the way to the target
      // or where it makes none of the type
      if (n.build === undefined || onPath.has(n.id) || !makes(n.build)) {
        n.children.forEach(visit);
      }
    };
    node.children.forEach(visit);
    owners.push({ node, build: node.build, index: Math.max(0, made.indexOf(target)), count: made.length });
  }
  return owners;
}

/** [source] with its comments and string literals blanked out, each character's offset kept. */
export function codeOnly(source: string): string {
  const out = source.split('');
  const blank = (from: number, to: number) => {
    for (let k = from; k < to; k++) {
      if (out[k] !== '\n') {
        out[k] = ' ';
      }
    }
  };
  let i = 0;
  while (i < source.length) {
    const c = source[i];
    const next = source[i + 1];
    if (c === '/' && next === '/') {
      const end = source.indexOf('\n', i);
      const to = end < 0 ? source.length : end;
      blank(i, to);
      i = to;
    } else if (c === '/' && next === '*') {
      // Dart's block comments nest
      let depth = 1;
      let k = i + 2;
      while (k < source.length && depth > 0) {
        if (source[k] === '/' && source[k + 1] === '*') {
          depth++;
          k += 2;
        } else if (source[k] === '*' && source[k + 1] === '/') {
          depth--;
          k += 2;
        } else {
          k++;
        }
      }
      blank(i, k);
      i = k;
    } else if (c === "'" || c === '"') {
      const raw = i > 0 && source[i - 1] === 'r';
      const triple = source.startsWith(c.repeat(3), i);
      const quote = triple ? c.repeat(3) : c;
      let k = i + quote.length;
      while (k < source.length && !source.startsWith(quote, k) && (triple || source[k] !== '\n')) {
        k += !raw && source[k] === '\\' ? 2 : 1;
      }
      const to = Math.min(source.length, k + quote.length);
      blank(i, to);
      i = to;
    } else {
      i++;
    }
  }
  return out.join('');
}

/**
 * The offsets in [source] between [from] and [to] where a constructor of
 * [type] is called: `Text(`, `const Text(`, `Text.rich(`, `Foo<int>(`,
 * `w.Text(` with an import prefix; in code only, not in a comment or a
 * string.
 */
export function constructorCalls(source: string, from: number, to: number, type: string): number[] {
  const code = codeOnly(source);
  const name = type.replace(/[$]/g, '\\$');
  const call = new RegExp(`(?<![\\w$])(?:[a-z_][\\w$]*\\.)?(${name})\\s*(?:<[^()]*?>)?\\s*(?:\\.[A-Za-z_$][\\w$]*)?\\s*\\(`, 'g');
  const found: number[] = [];
  call.lastIndex = from;
  for (let m = call.exec(code); m !== null && m.index < to; m = call.exec(code)) {
    // where the type's name is, after any prefix
    found.push(m.index + m[0].indexOf(m[1]));
  }
  return found;
}

/** The line and column, both from 1, of [offset] in [source]. */
export function lineColumnOf(source: string, offset: number): { readonly line: number; readonly column: number } {
  let line = 1;
  let start = 0;
  for (let i = source.indexOf('\n'); i >= 0 && i < offset; i = source.indexOf('\n', i + 1)) {
    line++;
    start = i + 1;
  }
  return { line, column: offset - start + 1 };
}

/** The offset in [source] of [line] and [column], both from 1. */
export function offsetOf(source: string, line: number, column: number): number {
  let start = 0;
  for (let l = 1; l < line; l++) {
    const nl = source.indexOf('\n', start);
    if (nl < 0) {
      return source.length;
    }
    start = nl + 1;
  }
  return Math.min(source.length, start + column - 1);
}

/**
 * The line and column of [tokenPos] in a script's `tokenPosTable` (the VM
 * service's: rows of a line, then pairs of a token position and its
 * column); undefined where the table has none.
 */
export function tokenLineColumn(table: readonly (readonly number[])[], tokenPos: number): { readonly line: number; readonly column: number } | undefined {
  for (const row of table) {
    for (let k = 1; k + 1 < row.length; k += 2) {
      if (row[k] === tokenPos) {
        return { line: row[0], column: row[k + 1] };
      }
    }
  }
  return undefined;
}

/**
 * Which of [calls] (of the widget's type, in a build's source) made the
 * widget: the only one, or the one at its [index] among the [count] the
 * build made when there are as many calls; else the one nearest that
 * place, the guess said not to be exact. Undefined for no calls.
 */
export function pickCall(calls: readonly number[], index: number, count: number): { readonly offset: number; readonly exact: boolean } | undefined {
  if (calls.length === 0) {
    return undefined;
  }
  // one call makes every element of its type the build made
  const exact = calls.length === 1 || calls.length === count;
  return { offset: calls[Math.min(index, calls.length - 1)], exact };
}

/** The types whose builds make the elements of the tree [root], by name, each once: what [creationOwners]' `makes` is asked of. */
export function buildsIn(root: InspectNode | null): string[] {
  const builds = new Set<string>();
  const visit = (n: InspectNode) => {
    if (n.build !== undefined) {
      builds.add(n.build);
    }
    n.children.forEach(visit);
  };
  if (root) {
    visit(root);
  }
  return [...builds];
}
