// Whether a folder can run twk_dev from its own pubspec.
import * as fs from 'node:fs';
import * as path from 'node:path';

import { projectOf } from './project';

/**
 * Whether `dart run twk_dev:twk` can resolve twk_dev in [dir]: the facts of the
 * folder, not dart's words. False where there is no pubspec.yaml above it, or
 * the nearest one neither is resolved to twk_dev (`.dart_tool/package_config.json`
 * of its project or the workspace above) nor names it; undefined where
 * a file could not be read.
 */
export function dependsOnTwkDev(dir: string): boolean | undefined {
  const project = projectOf(path.join(dir, 'x'));
  if (project === undefined) {
    return false;
  }
  try {
    for (let d = project; ; d = path.dirname(d)) {
      const config = path.join(d, '.dart_tool', 'package_config.json');
      if (fs.existsSync(config)) {
        const packages = (JSON.parse(fs.readFileSync(config, 'utf8')) as { packages?: { name?: string }[] }).packages ?? [];
        if (packages.some((p) => p.name === 'twk_dev')) {
          return true;
        }
        break;
      }
      if (path.dirname(d) === d) {
        break;
      }
    }
    // not resolved (yet): dart run resolves a pubspec that names it
    return /^\s*twk_dev\s*:/m.test(fs.readFileSync(path.join(project, 'pubspec.yaml'), 'utf8'));
  } catch {
    return undefined;
  }
}

/** [text] as `twk create` derives the package's name from a folder's: lower case, other characters than letters, digits and `_` as `_`. */
export function packageNameOf(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9_]/g, '_');
}

const reserved = new Set(
  ('abstract as assert await break case catch class const continue covariant default deferred do else enum export extends external false final finally for hide if implements import in ' +
    'inline interface is late library mixin new null of on operator part required rethrow return sealed set super switch this throw true try type var void while with yield').split(' '),
);

/** The packages a new project depends on, which it cannot be named as. */
const taken = new Set(['pro_lints', 'test', 'twk', 'twk_core', 'twk_dev', 'twk_lints', 'twk_test']);

/** What makes [name] (a package name already) none for a project, as `twk create` refuses it; undefined when it is one. */
export function packageNameError(name: string): string | undefined {
  if (!/^[a-z][a-z0-9_]*$/.test(name)) {
    return `"${name}" is not a package name: a lower case letter first, then lower case letters, digits and _`;
  }
  if (reserved.has(name)) {
    return `"${name}" is a reserved word`;
  }
  if (taken.has(name)) {
    return `"${name}" is the name of a package the app depends on`;
  }
  return undefined;
}

/** Why a project folder called [folder] would be refused by `twk create` (which names its package after it), or undefined. */
export function folderNameError(folder: string): string | undefined {
  const name = packageNameOf(folder);
  const error = packageNameError(name);
  return error === undefined ? undefined : name === folder ? error : `${error} (the package is named after the folder: ${folder} is ${name})`;
}
