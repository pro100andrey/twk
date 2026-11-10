// The main of a twk app, found in the text of a Dart file.
import * as assert from 'node:assert/strict';

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
});
