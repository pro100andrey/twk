/// The Model Context Protocol over JSON-RPC 2.0, as `twk mcp` serves it:
/// [McpServer], the [McpTool]s it offers, and what a tool answers,
/// [McpResult].
///
/// This file is the whole of the protocol and its transport (a line of
/// JSON per message, on a pair of streams): the tools know nothing of
/// JSON-RPC, so the transport can change without them.
library;

import 'dart:async';
import 'dart:convert';

/// A JSON object.
typedef JsonMap = Map<String, Object?>;

/// What a tool answers: [text], and whether it [isError]. A failure of a
/// tool is a result that says why, not a protocol error, so the model that
/// called it reads the reason.
final class McpResult {
  /// An answer of [text].
  const McpResult(this.text, {this.isError = false});

  /// A failure whose reason is [text].
  const McpResult.error(this.text) : isError = true;

  /// What the model reads.
  final String text;

  /// Whether the tool failed.
  final bool isError;

  /// As the protocol writes a tool's result.
  JsonMap toJson() => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': isError,
  };
}

/// A tool the server offers: its [name], what it does, the JSON Schema of
/// its arguments, and [call].
abstract class McpTool {
  /// The name a client calls it by.
  String get name;

  /// What it does, for the model to choose it by.
  String get description;

  /// The JSON Schema of its arguments, an object.
  JsonMap get inputSchema;

  /// Runs it with [arguments], an object that is the schema's. Anything it
  /// throws is the tool's failure.
  Future<McpResult> call(JsonMap arguments);

  /// Called when the server ends (its input did): a tool that holds
  /// something running lets go of it. Nothing by default.
  Future<void> end() async {}
}

/// The JSON-RPC error codes of the protocol.
abstract final class RpcCode {
  /// Not JSON.
  static const parseError = -32700;

  /// JSON, but not a request.
  static const invalidRequest = -32600;

  /// No such method.
  static const methodNotFound = -32601;

  /// Arguments that are not the method's, an unknown tool.
  static const invalidParams = -32602;

  /// The server's own failure.
  static const internalError = -32603;
}

/// A server of tools, one client at a time.
class McpServer {
  /// A server that names itself [name] and [version] and tells the client
  /// [instructions].
  McpServer({
    required this.name,
    required this.version,
    required this.instructions,
    required List<McpTool> tools,
  }) : _tools = {for (final t in tools) t.name: t};

  /// The versions of the protocol this speaks, the newest first. A client
  /// that asks for one of them gets it; any other asks for the first.
  static const protocolVersions = ['2025-06-18', '2025-03-26', '2024-11-05'];

  /// What it calls itself.
  final String name;

  /// Its version.
  final String version;

  /// What it tells the client about using it.
  final String instructions;

  final Map<String, McpTool> _tools;

  /// The answer to one message [line], null where none is due (a
  /// notification).
  Future<String?> handleLine(String line) async {
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException catch (e) {
      return _error(null, RpcCode.parseError, 'not JSON: ${e.message}');
    }
    final reply = await handle(message);
    return reply == null ? null : jsonEncode(reply);
  }

  /// The answer to one decoded [message], null for a notification.
  Future<JsonMap?> handle(Object? message) async {
    if (message is! Map<String, Object?>) {
      return _errorOf(
        null,
        RpcCode.invalidRequest,
        message is List
            ? 'a batch is not supported: send one request per line'
            : 'a request is a JSON object',
      );
    }
    final id = message['id'];
    final method = message['method'];
    if (message['jsonrpc'] != '2.0' ||
        method is! String ||
        (id != null && id is! int && id is! String)) {
      // a response of a client (it asked for nothing of ours) is not one
      if (method == null &&
          (message.containsKey('result') || message.containsKey('error'))) {
        return null;
      }
      return _errorOf(
        id is int || id is String ? id : null,
        RpcCode.invalidRequest,
        'not a JSON-RPC 2.0 request: it needs "jsonrpc": "2.0", a string '
        '"method" and an integer or string "id"',
      );
    }
    final notification = !message.containsKey('id');
    final params = message['params'];
    if (params != null && params is! Map<String, Object?>) {
      return notification
          ? null
          : _errorOf(id, RpcCode.invalidParams, '"params" is an object');
    }
    final args = (params as JsonMap?) ?? const {};
    try {
      final JsonMap result;
      switch (method) {
        case 'initialize':
          result = _initialize(args);
        case 'ping':
          result = {};
        case 'tools/list':
          result = {
            'tools': [
              for (final t in _tools.values)
                {
                  'name': t.name,
                  'description': t.description,
                  'inputSchema': t.inputSchema,
                },
            ],
          };
        case 'tools/call':
          result = await _call(args);
        default:
          if (notification) {
            // `notifications/initialized` and its like: nothing to answer
            return null;
          }
          return _errorOf(
            id,
            RpcCode.methodNotFound,
            'no method "$method"',
          );
      }
      return notification
          ? null
          : {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on _Rpc catch (e) {
      return notification ? null : _errorOf(id, e.code, e.message);
    }
  }

  JsonMap _initialize(JsonMap params) {
    final asked = params['protocolVersion'];
    if (asked is! String) {
      throw const _Rpc(
        RpcCode.invalidParams,
        'initialize needs a string "protocolVersion"',
      );
    }
    return {
      'protocolVersion': protocolVersions.contains(asked)
          ? asked
          : protocolVersions.first,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': name, 'version': version},
      'instructions': instructions,
    };
  }

  Future<JsonMap> _call(JsonMap params) async {
    final name = params['name'];
    if (name is! String) {
      throw const _Rpc(RpcCode.invalidParams, 'tools/call needs a "name"');
    }
    final tool = _tools[name];
    if (tool == null) {
      throw _Rpc(RpcCode.invalidParams, 'unknown tool "$name"');
    }
    final arguments = params['arguments'];
    if (arguments != null && arguments is! Map<String, Object?>) {
      throw const _Rpc(RpcCode.invalidParams, '"arguments" is an object');
    }
    try {
      return (await tool.call((arguments as JsonMap?) ?? {})).toJson();
    } on Object catch (e) {
      return McpResult.error('$name failed: $e').toJson();
    }
  }

  /// Serves [input], a message a line, answering on [output], until
  /// [input] ends. A request is answered when its tool is done, the next
  /// one read meanwhile is not waited for out of order: they are run one
  /// at a time, in order, as an app is driven by one step at a time.
  Future<void> serve(
    Stream<List<int>> input,
    void Function(String line) output,
  ) async {
    var chain = Future<void>.value();
    try {
      await for (final line
          in utf8.decoder.bind(input).transform(const LineSplitter())) {
        if (line.trim().isEmpty) {
          continue;
        }
        chain = chain.then((_) async {
          String? reply;
          try {
            reply = await handleLine(line);
          } on Object catch (e) {
            // one request that breaks does not silence the ones after it
            reply = _internalError(line, e);
          }
          if (reply != null) {
            output(reply);
          }
        });
      }
      await chain;
    } finally {
      for (final tool in _tools.values) {
        try {
          await tool.end();
        } on Object {
          // the others are let go all the same
        }
      }
    }
  }

  /// The answer to a request [line] that [error] escaped from: an internal
  /// error where it had an id, nothing where it was a notification.
  static String? _internalError(String line, Object error) {
    try {
      final message = jsonDecode(line);
      if (message is Map<String, Object?> &&
          message.containsKey('id') &&
          (message['id'] is int || message['id'] is String)) {
        return _error(message['id'], RpcCode.internalError, '$error');
      }
    } on Object {
      // not even JSON: nobody to answer
    }
    return null;
  }

  static String _error(Object? id, int code, String message) =>
      jsonEncode(_errorOf(id, code, message));

  static JsonMap _errorOf(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

final class _Rpc implements Exception {
  const _Rpc(this.code, this.message);

  final int code;
  final String message;
}
