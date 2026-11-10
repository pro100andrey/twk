// Runs the PACKAGED extension in VS Code: the .vsix (TWK_VSIX, else the
// xtask task vscode-package's, .dart_tool/vscode/twk-vscode.vsix at the
// repository's root) installed with VS Code's own `--install-extension` into
// an extensions directory of its own (TWK_VSCODE_TEST_DIR/installed/
// extensions, emptied first), then VS Code started on packages/twk with only
// that directory's extensions and the tests of suite/installed.test.ts
// run against the installed copy: the files the .vsix ships (out/ and four
// xterm files) are all it has. No extensionDevelopmentPath of the
// extension's: the one given is an inert directory, which VS Code needs a
// path for.
import * as childProcess from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { downloadAndUnzipVSCode, resolveCliArgsFromVSCodeExecutablePath, runTests } from '@vscode/test-electron';

async function main(): Promise<void> {
  const root = path.resolve(__dirname, '../..');
  const vsix = process.env.TWK_VSIX ?? path.resolve(root, '../../.dart_tool/vscode/twk-vscode.vsix');
  if (!fs.existsSync(vsix)) {
    throw new Error(`no .vsix at ${vsix}: dart run tool/xtask.dart vscode-package at the repository's root writes one (or set TWK_VSIX)`);
  }
  const scratch = path.join(process.env.TWK_VSCODE_TEST_DIR ?? path.join(os.tmpdir(), 'twk-vscode-test'), 'installed');
  fs.rmSync(scratch, { recursive: true, force: true });
  const extensions = path.join(scratch, 'extensions');
  const userData = path.join(scratch, 'user-data');
  const probe = path.join(scratch, 'probe');
  fs.mkdirSync(probe, { recursive: true });
  fs.writeFileSync(path.join(probe, 'package.json'), JSON.stringify({ name: 'probe', publisher: 'probe', version: '0.0.0', engines: { vscode: '^1.95.0' } }));

  const vscodeExecutablePath = process.env.VSCODE_EXECUTABLE || (await downloadAndUnzipVSCode());
  const [cli, ...cliArgs] = resolveCliArgsFromVSCodeExecutablePath(vscodeExecutablePath);
  const installed = childProcess.spawnSync(cli, [...cliArgs, '--install-extension', vsix, `--extensions-dir=${extensions}`, `--user-data-dir=${userData}`], {
    encoding: 'utf8',
    stdio: 'pipe',
  });
  process.stdout.write(`${installed.stdout}${installed.stderr}`);
  if (installed.status !== 0) {
    throw new Error(`--install-extension failed (${installed.status})`);
  }
  if (!fs.readdirSync(extensions).some((d) => d.startsWith('twk.twk-vscode-'))) {
    throw new Error(`the .vsix is not in ${extensions}: ${fs.readdirSync(extensions).join(' ')}`);
  }
  await runTests({
    vscodeExecutablePath,
    extensionDevelopmentPath: probe,
    extensionTestsPath: path.resolve(__dirname, './suite/installed'),
    extensionTestsEnv: { TWK_EXTENSIONS_DIR: extensions },
    launchArgs: [
      path.resolve(root, '../../packages/twk'),
      '--disable-workspace-trust',
      '--skip-welcome',
      '--skip-release-notes',
      `--user-data-dir=${userData}`,
      `--extensions-dir=${extensions}`,
    ],
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
