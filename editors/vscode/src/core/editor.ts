// The command that opens a file in the editor the extension runs in, for the
// apps it starts: their TWK_EDITOR (twk's `editorCommand`: `{file}`, `{line}`
// and `{column}` put in, words in quotes keep their blanks), so the app's
// console opens a frame of its stack here. The editor's own command line
// (found from `vscode.env.appRoot` by platform), by its path: `code` need not be on the PATH. No
// message over the twk terminal's wire: the terminal does not name a command
// for the app to run (twk_core's `Terminal.settingNames`), and a path to a
// program of this machine, set in the environment of the app the extension
// starts, is the user's own editor and nothing a remote end can change.
import * as path from 'node:path';

/** The names of the editors' command lines, VS Code's first. */
const binaries = ['code', 'code-insiders', 'codium', 'cursor'];

/** What follows the program in TWK_EDITOR: reuse the window the project is open in, go to the line. */
const arguments_ = '-r -g {file}:{line}:{column}';

/**
 * TWK_EDITOR for the editor installed at [appRoot] (`vscode.env.appRoot`),
 * whose command line [exists] finds as the first of [binaries] where the
 * platform keeps it: `<install>/bin/code` on Linux and `<install>\\bin\\code.cmd`
 * on Windows, two directories above the `resources/app` that appRoot is
 * there; `<appRoot>/bin/code` on macOS (`Contents/Resources/app/bin/code`).
 * The `bin` of appRoot itself is tried last, for an install that has its
 * command line there. Where none is found, `code`, for the PATH to resolve.
 */
export function editorCommandOf(appRoot: string, platform: string, exists: (file: string) => boolean): string {
  const p = platform === 'win32' ? path.win32 : path.posix;
  const own = p.join(appRoot, 'bin');
  const dirs = platform === 'darwin' ? [own] : [p.join(appRoot, '..', '..', 'bin'), own];
  for (const dir of dirs) {
    for (const name of binaries) {
      const file = p.join(dir, platform === 'win32' ? `${name}.cmd` : name);
      if (exists(file) && !file.includes('"')) {
        return `"${file}" ${arguments_}`;
      }
    }
  }
  return `code ${arguments_}`;
}
