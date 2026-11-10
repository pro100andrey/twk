// The main of a twk app, found in the text of a Dart file.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

import { findTwkMain } from '../../../core/main_find';

const head = "import 'package:twk/twk.dart';\n\n";

describe('the main of a twk app', () => {
  it('is found over runApp, with its line', () => {
    assert.deepEqual(findTwkMain(`${head}void main() {\n  runApp(const Text('x'));\n}\n`), { line: 2, column: 0 });
  });

  it('is found for an async main and a TwkApp', () => {
    const src = `import "package:twk_core/twk_core.dart";\nFuture<void> main(List<String> args) async {\n  final app = TwkApp(await Terminal.open());\n}\n`;
    assert.deepEqual(findTwkMain(src), { line: 1, column: 0 });
  });

  it('is not found without a twk import', () => {
    assert.equal(findTwkMain('void main() {\n  runApp(x);\n}\n'), null);
  });

  it('is not found without a main, or when main starts nothing', () => {
    assert.equal(findTwkMain(`${head}void run() { runApp(x); }\n`), null);
    assert.equal(findTwkMain(`${head}void main() { print(1); }\n`), null);
  });

  it('ignores runApp in comments and strings, and other names ending so', () => {
    assert.equal(findTwkMain(`${head}void main() {\n  // runApp(x);\n  print('runApp(x) TwkApp');\n  myrunApp(x);\n  a.runApp(x);\n}\n`), null);
  });

  it('ignores a main that is indented (not top level) or commented out', () => {
    assert.equal(findTwkMain(`${head}class A { void main() { runApp(x); } }\n// void main() {}\n`), null);
  });

  it('ignores an import in a comment', () => {
    assert.equal(findTwkMain("// import 'package:twk/twk.dart';\nvoid main() { runApp(x); }\n"), null);
  });

  it('is not found in a test file or under the package test/, wherever the package is', () => {
    const src = `${head}void main() {\n  runApp(x);\n}\n`;
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'twk_main_find_'));
    try {
      // the package itself sits under a directory named test
      const pkg = path.join(dir, 'test', 'app');
      fs.mkdirSync(path.join(pkg, 'test', 'sub'), { recursive: true });
      fs.mkdirSync(path.join(pkg, 'bin'));
      fs.mkdirSync(path.join(pkg, 'latest'));
      fs.writeFileSync(path.join(pkg, 'pubspec.yaml'), 'name: app\n');
      assert.deepEqual(findTwkMain(src, path.join(pkg, 'bin', 'main.dart')), { line: 2, column: 0 });
      assert.deepEqual(findTwkMain(src, path.join(pkg, 'latest', 'a.dart')), { line: 2, column: 0 });
      assert.equal(findTwkMain(src, path.join(pkg, 'bin', 'a_test.dart')), null);
      assert.equal(findTwkMain(src, path.join(pkg, 'test', 'a.dart')), null);
      assert.equal(findTwkMain(src, path.join(pkg, 'test', 'sub', 'a.dart')), null);
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});
