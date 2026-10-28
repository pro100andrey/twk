// Where in the app's code a widget was made, or a build method is, found
// through the VM service of the app ([AppService.vm]): the classes by
// name (getClassList), a class's `build` and its place in its script
// (getObject), the script's source as the VM runs it, and a package: URI
// as a file (lookupResolvedPackageUris). What it looks for in that source
// is source_find.ts's. All of it asked when a place is wanted, nothing
// while the app runs; what it read is kept until [SourceLocator.forget]
// (a hot reload changes the code). No vscode import.
import { AppService, InspectNode } from './inspect';
import { buildsIn, className, codeOnly, constructorCalls, creationOwners, lineColumnOf, offsetOf, pickCall, tokenLineColumn } from './source_find';

/** A place in a file of the app's code. */
export interface SourceSpot {
  /** The file's URI (file:). */
  readonly uri: string;
  /** From 1. */
  readonly line: number;
  /** From 1. */
  readonly column: number;
  /** Whether it is the one call that made the widget, or a guess among several of its type in that build. */
  readonly exact: boolean;
  /** The build method it is in, `_CounterState.build`. */
  readonly method: string;
}

type Json = Record<string, unknown>;

const isRecord = (v: unknown): v is Json => typeof v === 'object' && v !== null && !Array.isArray(v);
const text = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined);
const records = (v: unknown): Json[] => (Array.isArray(v) ? v.filter(isRecord) : []);

/** A class the VM has, by its id, name and library. */
interface ClassRef {
  readonly id: string;
  readonly name: string;
  readonly library: string | undefined;
}

/** The source of a build method: its script's text, URI, and where the method begins and ends in it. */
interface BuildSource {
  readonly uri: string;
  readonly source: string;
  readonly start: number;
  readonly end: number;
  readonly line: number;
  readonly column: number;
  readonly method: string;
}

/** How far up a class's supertypes a `build` is looked for. */
const superDepth = 6;

export class SourceLocator {
  private classes: Promise<ClassRef[]> | undefined;
  private readonly builds = new Map<string, Promise<BuildSource[]>>();
  private readonly files = new Map<string, Promise<string | undefined>>();
  private readonly scripts = new Map<string, Promise<Json>>();

  constructor(private readonly app: Pick<AppService, 'vm'>) {}

  /** Forgets what it read: the app's code changed (a hot reload). */
  forget(): void {
    this.classes = undefined;
    this.builds.clear();
    this.files.clear();
    this.scripts.clear();
  }

  /**
   * Where the widget of the element [id] names in the tree [root] was
   * made: in the nearest build above it whose source calls a constructor
   * of its type ([creationOwners]); undefined where none does.
   */
  async creation(root: InspectNode | null, id: number, type: string): Promise<SourceSpot | undefined> {
    const name = className(type);
    // which builds make widgets of that type, of all the tree's
    const builds = buildsIn(root);
    const making = new Map<string, boolean>();
    await Promise.all(
      builds.map(async (b) => {
        const sources = await this.buildsOf(b);
        // one not found: taken as making some, its elements its own
        making.set(b, sources.length === 0 || sources.some((s) => constructorCalls(s.source, s.start, s.end, name).length > 0));
      }),
    );
    for (const owner of creationOwners(root, id, (b) => making.get(b) ?? true)) {
      for (const b of await this.buildsOf(owner.build)) {
        const picked = pickCall(constructorCalls(b.source, b.start, b.end, name), owner.index, owner.count);
        if (picked) {
          const at = lineColumnOf(b.source, picked.offset);
          return { uri: await this.fileOf(b.uri), ...at, exact: picked.exact, method: b.method };
        }
      }
    }
    return undefined;
  }

  /** Where the `build` method of the type [build] (a widget's, a state's) begins; undefined for none found. */
  async buildMethod(build: string): Promise<SourceSpot | undefined> {
    const [b] = await this.buildsOf(build);
    return b && { uri: await this.fileOf(b.uri), line: b.line, column: b.column, exact: true, method: b.method };
  }

  /** The build methods of the classes named [type] (of the app's libraries first, dart: ones never). */
  private buildsOf(type: string): Promise<BuildSource[]> {
    const name = className(type);
    let found = this.builds.get(name);
    if (!found) {
      found = this.findBuilds(name).catch(() => []);
      this.builds.set(name, found);
    }
    return found;
  }

  private async findBuilds(name: string): Promise<BuildSource[]> {
    const classes = (await this.classList()).filter((c) => c.name === name && !c.library?.startsWith('dart:'));
    // the app's own (file:) before the packages'
    classes.sort((a, b) => Number(!a.library?.startsWith('file:')) - Number(!b.library?.startsWith('file:')));
    const builds: BuildSource[] = [];
    for (const c of classes) {
      const b = await this.buildOfClass(c.id, name);
      if (b) {
        builds.push(b);
      }
    }
    return builds;
  }

  private classList(): Promise<ClassRef[]> {
    this.classes ??= (async () => {
      const list = await this.app.vm('getClassList');
      return records(list.classes).flatMap((c) => {
        const id = text(c.id);
        const name = text(c.name);
        return id && name ? [{ id, name, library: isRecord(c.library) ? text(c.library.uri) : undefined }] : [];
      });
    })();
    // one that failed is asked again next time
    this.classes.catch(() => (this.classes = undefined));
    return this.classes;
  }

  /** The `build` of the class [id], or of the nearest of its superclasses with one. */
  private async buildOfClass(id: string, name: string): Promise<BuildSource | undefined> {
    let classId: string | undefined = id;
    for (let depth = 0; classId && depth < superDepth; depth++) {
      const c = await this.app.vm('getObject', { objectId: classId });
      const build = records(c.functions).find((f) => f.name === 'build');
      const buildId = build && text(build.id);
      if (buildId) {
        return this.sourceOf(buildId, `${name}.build`);
      }
      classId = isRecord(c.super) ? text(c.super.id) : undefined;
    }
    return undefined;
  }

  private async sourceOf(functionId: string, method: string): Promise<BuildSource | undefined> {
    const f = await this.app.vm('getObject', { objectId: functionId });
    const location = isRecord(f.location) ? f.location : undefined;
    const scriptId = location && isRecord(location.script) ? text(location.script.id) : undefined;
    if (!location || !scriptId) {
      return undefined;
    }
    let fetching = this.scripts.get(scriptId);
    if (!fetching) {
      fetching = this.app.vm('getObject', { objectId: scriptId });
      this.scripts.set(scriptId, fetching);
    }
    const script = await fetching;
    const source = text(script.source);
    const uri = text(script.uri);
    if (source === undefined || uri === undefined) {
      return undefined;
    }
    const table = Array.isArray(script.tokenPosTable)
      ? script.tokenPosTable.filter((r): r is number[] => Array.isArray(r) && r.every((n) => typeof n === 'number'))
      : [];
    const at = (pos: unknown) => (typeof pos === 'number' ? tokenLineColumn(table, pos) : undefined);
    const begin =
      at(location.tokenPos) ??
      (typeof location.line === 'number' && typeof location.column === 'number' ? { line: location.line, column: location.column } : undefined);
    if (!begin) {
      return undefined;
    }
    const finish = at(location.endTokenPos);
    const start = offsetOf(source, begin.line, begin.column);
    const end = finish ? offsetOf(source, finish.line, finish.column) + 1 : source.length;
    // the method's name, after its metadata (@override), where it begins
    const name = /\bbuild\s*\(/g;
    name.lastIndex = start;
    const found = name.exec(codeOnly(source));
    const shown = found && found.index < end ? lineColumnOf(source, found.index) : begin;
    return { uri, source, start, end, line: shown.line, column: shown.column, method };
  }

  /** The file: URI of the script [uri]: a package: one as the app's package config resolves it. */
  private fileOf(uri: string): Promise<string> {
    if (!uri.startsWith('package:')) {
      return Promise.resolve(uri);
    }
    let file = this.files.get(uri);
    if (!file) {
      file = this.app
        .vm('lookupResolvedPackageUris', { uris: [uri] })
        .then((r) => (Array.isArray(r.uris) ? text(r.uris[0]) : undefined))
        .catch(() => undefined);
      this.files.set(uri, file);
    }
    return file.then((f) => f ?? uri);
  }
}
