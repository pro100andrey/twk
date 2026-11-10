// The Dart project a file is in, as twk finds it.
import * as fs from 'node:fs';
import * as path from 'node:path';

/** The nearest directory from [file]'s up holding a pubspec.yaml: what twk's LocalAddress.projectOf finds. */
export function projectOf(file: string): string | undefined {
  for (let dir = path.dirname(file); ; dir = path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) {
      return dir;
    }
    if (path.dirname(dir) === dir) {
      return undefined;
    }
  }
}

/** Whether [file] is [root] or below it (a name that merely starts with `..` is below). */
export function isInside(root: string, file: string): boolean {
  const rel = path.relative(root, file);
  return !(rel === '..' || rel.startsWith('..' + path.sep) || path.isAbsolute(rel));
}
