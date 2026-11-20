/// `twk mcp`: [McpCommand], an MCP server on stdio that lets a coding
/// agent start, drive and look at a twk app.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'completion.dart';
import 'mcp/app_tools.dart';
import 'mcp/jsonrpc.dart';

/// What the server tells a client about using it.
const mcpInstructions =
    'Drives one twk app (a terminal UI built on the twk package) in a '
    'pseudo-terminal. start_app first; every action answers with the '
    'screen after it and a line with the frame, the input the app has '
    'read and whether it is quiet. The app runs on time you move: '
    'wait_for and elapse move it, so there is nothing to sleep for. A '
    'failure says why (what covers a node, "never" for an app that is '
    'quiet, "not within" the budget, the app exited): read it rather than '
    'wait longer. stop_app when done.';

/// The server `twk mcp` runs, with its tools; [launcher] starts the apps.
McpServer twkMcpServer({AppLauncher? launcher}) => McpServer(
  name: 'twk',
  version: '0.3.0',
  instructions: mcpInstructions,
  tools: appTools(launcher: launcher),
);

/// `twk mcp`: serves the Model Context Protocol on stdin and stdout, until
/// stdin ends.
final class McpCommand extends Command<int> with Completes {
  @override
  Positionals get positionals => const Positionals.none();

  @override
  String get name => 'mcp';

  @override
  String get invocation => 'twk mcp';

  @override
  String get description =>
      'Serve an MCP server on stdio that drives a twk app.\n\n'
      'A coding agent registers it as a command (`twk mcp`) and gets the '
      'tools start_app, screen, tree, find, press, type, tap, wait_for, '
      'elapse, hot_reload, logs and stop_app. The app runs on time the '
      'server moves, and each tool answers with the screen after it. '
      'Nothing but protocol goes to stdout.';

  @override
  Future<int> run() async {
    final server = twkMcpServer();
    await server.serve(stdin, stdout.writeln);
    return 0;
  }
}
