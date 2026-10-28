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
