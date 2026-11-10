// The `main` of a twk app in a Dart file, told from its text alone (no
// analysis server, so it is cheap enough to run on each edit): a top-level
// `main` in a file that imports a twk package (`package:twk/...`,
// `package:twk_core/...`) and, in code (not in a comment or string), calls
// `runApp(` or names `TwkApp`. A `main` that hands over to another file's
// function is not found; the commands Run and Debug in twk Terminal are
// there for it.
import * as path from 'node:path';

import { projectOf } from './project';
import { codeOnly } from './source_find';

/** Where the `main` declaration begins. */
export interface TwkMain {
  readonly line: number;
  readonly column: number;
}

const twkImport = /^[ \t]*(?:import|export)[ \t]+(['"])package:twk(?:_[a-z0-9_]+)?\//m;
const mainDeclaration = /^(?:(?:void|Future<void>|FutureOr<void>)[ \t]+)?main[ \t]*\(/m;
const startsApp = /(?<![\w$.])runApp[ \t]*\(|(?<![\w$])TwkApp\b/;

// a test file or a file under the package's test/ (either separator) is no app to run
const testFile = /(?:_test\.dart|^test[\\/][^]*)$/;

// [filePath] judged from its package root (the nearest pubspec.yaml above it),
// so that a directory named test further up does not make it a test file
function isTestFile(filePath: string): boolean {
  const root = projectOf(filePath);
  return testFile.test(root === undefined ? path.basename(filePath) : path.relative(root, filePath));
}

/**
 * The `main` of a twk app in [source], or null when it is none. [filePath],
 * where given, leaves out the test files (`*_test.dart`, under the package's `test/`):
 * they import twk packages and call `runApp`, but are run by `dart test`.
 */
export function findTwkMain(source: string, filePath?: string): TwkMain | null {
  if (filePath !== undefined && isTestFile(filePath)) {
    return null;
  }
  if (!twkImport.test(source)) {
    return null;
  }
  const code = codeOnly(source);
  const main = mainDeclaration.exec(code);
  if (!main || !startsApp.test(code)) {
    return null;
  }
  const before = code.substring(0, main.index);
  const line = before.split('\n').length - 1;
  return { line, column: 0 };
}
