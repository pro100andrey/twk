// Node's [LogEndpoints]: the address file of a project read from the disk,
// and the log's socket (a Unix domain socket, TCP on the loopback
// interface on Windows) opened with net, the token sent first.
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as path from 'node:path';

import { ShellAddress } from './address';
import { addressFile, parseAddressFile } from './app_log';
import { Emitter } from './events';
import { LogConnection, LogEndpoints } from './log_follow';

/** Splits what comes into lines (UTF-8, a character cut between reads put together). */
export class Lines {
  private pending = '';
  private readonly decoder = new TextDecoder('utf-8');

  /** The complete lines [bytes] ends; a partial one waits for the next read. */
  push(bytes: Uint8Array): string[] {
    this.pending += this.decoder.decode(bytes, { stream: true });
    const lines = this.pending.split('\n');
    this.pending = lines.pop() ?? '';
    return lines.map((l) => l.replace(/\r$/, ''));
  }
}

export const nodeLogEndpoints: LogEndpoints = {
  address(project: string): ShellAddress | undefined {
    try {
      return parseAddressFile(fs.readFileSync(path.join(project, ...addressFile), 'utf8'));
    } catch {
      return undefined;
    }
  },

  connect(address: ShellAddress): Promise<LogConnection> {
    return new Promise((resolve, reject) => {
      const tcp = address.where.startsWith('tcp:');
      const colon = address.where.lastIndexOf(':');
      const socket = tcp ? net.connect({ host: address.where.substring(4, colon), port: Number(address.where.substring(colon + 1)) }) : net.connect(address.where.substring(5));
      const lines = new Emitter<string>();
      const ends = new Emitter<void>();
      const reader = new Lines();
      let ended = false;
      const end = () => {
        if (!ended) {
          ended = true;
          ends.fire();
          lines.dispose();
          ends.dispose();
        }
      };
      socket.once('connect', () => {
        socket.write(`${address.token}\n`);
        resolve({
          onLine: lines.event,
          onEnd: ends.event,
          close: () => {
            socket.destroy();
            end();
          },
        });
      });
      socket.on('data', (b: Buffer) => reader.push(b).forEach((l) => lines.fire(l)));
      socket.on('error', (e) => {
        reject(e);
        end();
      });
      socket.on('close', end);
    });
  },
};
