// The resident frontend compiler the runs compile their apps with
// (`dart run --resident`): kept between runs, it compiles a restarted app
// incrementally, where a plain `dart run` compiles all of it from source
// each time (3.7 s for a script importing package:twk, against 0.3 to
// 0.5 s once the compiler is warm). The extension's own, by an info file in
// a directory of its own, not the machine's default one, which other tools
// share and which ending here would end under them. `dart run` starts it
// with the first run that names the file, and starts it again where the
// file names a compiler that is gone; [shutdown] ends it, when the
// extension does. No vscode import: its tests run under plain node.
import * as fs from 'node:fs';
import * as path from 'node:path';

import { Clock } from './events';
import { ProcessStarter } from './process';

/** How long `dart compilation-server shutdown` is given before it is killed. */
export const shutdownPatience = 5000;

export interface ResidentCompilerDeps {
  readonly startProcess: ProcessStarter;
  readonly env: Readonly<Record<string, string | undefined>>;
  readonly clock: Clock;
  /** The `dart` command; `dart` on the PATH by default. */
  readonly dart?: string;
}

export class ResidentCompiler {
  /** The file `--resident-compiler-info-file` names: where the compiler says its address, once started. */
  readonly infoFile: string;

  private constructor(
    private readonly dir: string,
    private readonly deps: ResidentCompilerDeps,
  ) {
    this.infoFile = path.join(dir, 'resident_compiler.info');
  }

  /** A compiler whose info file is in a new directory under [temporaryRoot]; nothing is started yet. */
  static create(temporaryRoot: string, deps: ResidentCompilerDeps): ResidentCompiler {
    return new ResidentCompiler(fs.mkdtempSync(path.join(temporaryRoot, 'twk_vscode_compiler_')), deps);
  }

  /** The arguments of `dart run` that compile through it. */
  get runArgs(): string[] {
    return ['--resident', '--quiet', `--resident-compiler-info-file=${this.infoFile}`];
  }

  /**
   * Ends the compiler, where one was started (the info file is there), and
   * removes its directory. A shutdown that does not end in
   * [shutdownPatience] is killed: the window is closing.
   */
  async shutdown(): Promise<void> {
    if (fs.existsSync(this.infoFile)) {
      const p = this.deps.startProcess(
        this.deps.dart ?? 'dart',
        ['compilation-server', 'shutdown', `--resident-compiler-info-file=${this.infoFile}`],
        { cwd: this.dir, env: this.deps.env },
      );
      const timer = this.deps.clock.setTimeout(() => p.signal('SIGKILL'), shutdownPatience);
      await p.exited;
      timer.dispose();
    }
    fs.rmSync(this.dir, { recursive: true, force: true });
  }
}
