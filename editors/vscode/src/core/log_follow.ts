// Follows the log of the app of a project, one app after another, as
// `twk logs` does (twk_dev's lib/src/logs.dart): reads the project's
// address file, connects to the socket it names, sends the token and a line
// feed, and gets the records kept, then each one as it comes; when the app
// ends, waits for the file to name the next. The file and the socket are
// behind [LogEndpoints] (node's in core/log_socket.ts, a fake in the
// tests); the waiting is on a [Clock].
import { ShellAddress } from './address';
import { Clock, Disposable, Event } from './events';

/** A connection to the log of an app: lines, until it ends. */
export interface LogConnection {
  readonly onLine: Event<string>;
  /** The app went away, or the connection broke. */
  readonly onEnd: Event<void>;
  close(): void;
}

/** The files and sockets of the logs an app serves. */
export interface LogEndpoints {
  /** The address the project's apps serve their log at, or undefined for none (no file, or none valid). */
  address(project: string): ShellAddress | undefined;
  /** Connects to [address] and sends its token; rejects where no one listens (an address an app left behind). */
  connect(address: ShellAddress): Promise<LogConnection>;
}

/** What a [LogFollower] tells. */
export interface LogFollowing {
  /** An app's log was connected: the records it kept come next. */
  connected(): void;
  line(text: string): void;
  /** The connection ended: the app went away. */
  ended(): void;
}

export class LogFollower implements Disposable {
  /** How long it waits for an address, and for the next app, in milliseconds (`twk logs`'s own). */
  static readonly poll = 200;

  private timer: Disposable | undefined;
  private connection: LogConnection | undefined;
  private listening: Disposable[] = [];
  private stopped = false;
  /** The address whose connection ended last: tried again only once the file names another. */
  private spent: string | undefined;

  constructor(
    private readonly project: string,
    private readonly endpoints: LogEndpoints,
    private readonly clock: Clock,
    private readonly following: LogFollowing,
  ) {
    this.tick();
  }

  private later(): void {
    if (!this.stopped) {
      this.timer = this.clock.setTimeout(() => this.tick(), LogFollower.poll);
    }
  }

  private tick(): void {
    this.timer = undefined;
    if (this.stopped) {
      return;
    }
    const address = this.endpoints.address(this.project);
    if (!address || `${address.where}#${address.token}` === this.spent) {
      this.later();
      return;
    }
    const key = `${address.where}#${address.token}`;
    this.endpoints.connect(address).then(
      (connection) => {
        if (this.stopped) {
          connection.close();
          return;
        }
        this.connection = connection;
        this.following.connected();
        this.listening = [
          connection.onLine((line) => this.following.line(line)),
          connection.onEnd(() => {
            this.listening.forEach((d) => d.dispose());
            this.listening = [];
            this.connection = undefined;
            this.spent = key;
            this.following.ended();
            this.later();
          }),
        ];
      },
      () => this.later(),
    );
  }

  dispose(): void {
    this.stopped = true;
    this.timer?.dispose();
    this.timer = undefined;
    this.listening.forEach((d) => d.dispose());
    this.listening = [];
    this.connection?.close();
    this.connection = undefined;
  }
}
