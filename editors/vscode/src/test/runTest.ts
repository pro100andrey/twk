// Runs the extension's tests in VS Code (@vscode/test-electron): the VS Code
// at VSCODE_EXECUTABLE (e.g. /opt/visual-studio-code/code), else one it
// downloads to .vscode-test; profile and extensions in a directory of
// their own (TWK_VSCODE_TEST_DIR, else the system's temporary one), never
// the user's. The workspace is packages/twk of this repository. With
// TWK_VSCODE_DART=1 the extensions of that directory are on: Dart-Code
// installed there (`code --extensions-dir <dir>/extensions
// --install-extension Dart-Code.dart-code`) runs the debugging test.
import * as os from 'node:os';
import * as path from 'node:path';

import { runTests } from '@vscode/test-electron';

async function main(): Promise<void> {
  const extensionDevelopmentPath = path.resolve(__dirname, '../..');
  const scratch = process.env.TWK_VSCODE_TEST_DIR ?? path.join(os.tmpdir(), 'twk-vscode-test');
  const workspace = path.resolve(extensionDevelopmentPath, '../../packages/twk');
  await runTests({
    vscodeExecutablePath: process.env.VSCODE_EXECUTABLE || undefined,
    extensionDevelopmentPath,
    extensionTestsPath: path.resolve(__dirname, './suite/index'),
    launchArgs: [
      workspace,
      ...(process.env.TWK_VSCODE_DART === '1' ? [] : ['--disable-extensions']),
      '--disable-workspace-trust',
      '--skip-welcome',
      '--skip-release-notes',
      `--user-data-dir=${path.join(scratch, 'user-data')}`,
      `--extensions-dir=${path.join(scratch, 'extensions')}`,
    ],
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
