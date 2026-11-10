/// `twk doctor`: [DoctorCommand], and the report it prints ([Doctor]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:twk/cli.dart' show CliTerminal;
import 'package:twk_core/twk_core.dart';
import 'package:yaml/yaml.dart';

import 'agents.dart';
import 'create.dart' show askTerminal;
import 'project.dart';
import 'run.dart' show serviceFileOf;

/// The packages whose versions in the lock have to agree.
const doctorPackages = ['twk', 'twk_core', 'twk_dev', 'twk_test'];

/// How long `twk doctor` waits for a socket of `.dart_tool/twk` to take a
/// connection before it calls the file left behind.
const doctorConnectTimeout = Duration(seconds: 1);

/// `twk doctor`: what this terminal does, and whether the project's twk
/// packages agree.
final class DoctorCommand extends Command<int> {
  /// Sets up `twk doctor`'s options: `--directory` and `--json`. [terminal]
  /// gives the terminal to probe, null where there is none; [environment]
  /// the environment to report, the process's by default.
  DoctorCommand({
    CliTerminal? Function() terminal = askTerminal,
    Map<String, String>? environment,
    StringSink? out,
  }) : this._(terminal, environment, out);

  DoctorCommand._(this._terminal, this._environment, this._out) {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        valueHelp: 'path',
        help:
            'A directory of the project to report on (default: the '
            'current one).',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the report as one JSON object, for tools.',
      );
  }

  final CliTerminal? Function() _terminal;
  final Map<String, String>? _environment;
  final StringSink? _out;

  @override
  String get name => 'doctor';

  @override
  String get invocation => 'twk doctor [-C <dir>] [--json]';

  @override
  String get description =>
      'Report what this terminal does and whether the project agrees.\n\n'
      'The terminal as twk probes it (TERM, its name and version, colors, '
      'synchronized output, kitty keyboard, graphics, links, the size of a '
      'cell, how long it took to answer), the twk, twk_core, twk_dev and '
      "twk_test versions of the project's pubspec.lock and whether they "
      "agree, the Dart SDK, an app running in the project's "
      '.dart_tool/twk, and the skill for agents when it is older than this '
      'twk_dev. Without a terminal (a pipe, an agent) only the project part '
      'is reported. Exits 1 where the versions disagree.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final report = await Doctor.collect(
      project: projectOf(args.option('directory')),
      terminal: _terminal(),
      environment: _environment ?? Platform.environment,
    );
    final out = _out ?? stdout;
    if (args.flag('json')) {
      out.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    } else {
      out.write(report.render());
    }
    return report.agree ? 0 : 1;
  }
}

/// What `twk doctor` found.
final class Doctor {
  /// A report of its parts.
  Doctor({
    required this.project,
    required this.dart,
    required this.environment,
    required this.versions,
    required this.state,
    this.terminal,
    this.agents,
    this.lock,
  });

  /// Looks at the terminal ([terminal], null for none), and at [project].
  static Future<Doctor> collect({
    required String project,
    required CliTerminal? terminal,
    required Map<String, String> environment,
  }) async {
    final lockFile = _lockOf(project);
    return Doctor(
      project: project,
      dart: Platform.version.split(' ').first,
      environment: {
        for (final name in const ['TERM', 'TERM_PROGRAM', 'COLORTERM'])
          name: ?environment[name],
      },
      terminal: terminal == null ? null : await _probe(terminal),
      lock: lockFile?.path,
      versions: lockFile == null ? const {} : _versions(lockFile),
      state: await _state(project),
      agents: _agents(project),
    );
  }

  /// The project's directory.
  final String project;

  /// The Dart SDK's version.
  final String dart;

  /// `TERM`, `TERM_PROGRAM` and `COLORTERM` as set.
  final Map<String, String> environment;

  /// The terminal's probe; null where there was no terminal to probe.
  final TerminalReport? terminal;

  /// The `pubspec.lock` the versions are from; null where there is none.
  final String? lock;

  /// The locked version of each of [doctorPackages] the lock has.
  final Map<String, String> versions;

  /// The files of the project's `.dart_tool/twk`, by service: `run`,
  /// `shell` and `logs`; those there are.
  final Map<String, StateReport> state;

  /// The skill for agents; null where the project does not depend on twk.
  final AgentsReport? agents;

  /// Whether the locked versions are one ([versions] being one or none).
  bool get agree => versions.values.toSet().length <= 1;

  /// The report as JSON, for tools.
  Map<String, Object?> toJson() => {
    'project': project,
    'dart': dart,
    'environment': environment,
    'terminal': terminal?.toJson(),
    'lock': lock,
    'versions': versions,
    'agree': agree,
    'state': {for (final e in state.entries) e.key: e.value.toJson()},
    'agents': agents?.toJson(),
  };

  /// The report as text for a person.
  String render() {
    final b = StringBuffer();
    void line([String text = '']) => b.writeln(text);
    final t = terminal;
    line('Terminal');
    if (t == null) {
      line('  none: stdin and stdout are not a terminal');
    } else {
      line('  TERM            ${environment['TERM'] ?? '(not set)'}');
      if (environment['TERM_PROGRAM'] case final program?) {
        line('  TERM_PROGRAM    $program');
      }
      line(
        '  name, version   '
        '${t.version.isEmpty ? '(not told)' : t.version}',
      );
      line('  colors          ${t.colors}');
      line('  DEC 2026        ${_yes(t.synchronizedOutput)}');
      line(
        '  kitty keyboard  '
        '${t.kittyKeyboard ? 'yes, flags ${t.kittyKeyboardFlags}' : 'no'}',
      );
      line('  graphics        ${t.graphics}');
      line('  links (OSC 8)   ${_yes(t.hyperlinks)}');
      line(
        '  cell size       '
        '${t.cellWidth == 0 ? 'not told' : _cell(t)}',
      );
      line(
        '  answers         ${t.answered ? 'all' : 'not all (swallowed?)'}'
        ' in ${t.probeMilliseconds} ms',
      );
    }
    line();
    line('Project  $project');
    line('  Dart            $dart');
    if (lock == null) {
      line('  pubspec.lock    none found');
    } else {
      for (final name in doctorPackages) {
        line(
          '  $name'.padRight(18) + (versions[name] ?? 'not in the lock'),
        );
      }
      line(
        agree
            ? '  the versions agree'
            : '  the versions DISAGREE: pub upgrade them together',
      );
    }
    if (state.isEmpty) {
      line('  .dart_tool/twk  nothing: no app running');
    }
    for (final MapEntry(:key, :value) in state.entries) {
      line('  $key'.padRight(18) + value.render());
    }
    final a = agents;
    if (a != null) {
      line('  agents skill    ${_skill(a)}');
      if (a.edited.isNotEmpty) {
        line(
          '                  changed by the project, kept: '
          '${a.edited.join(', ')}',
        );
      }
    }
    return b.toString();
  }
}

String _cell(TerminalReport t) => '${t.cellWidth}x${t.cellHeight} px';

String _skill(AgentsReport a) {
  if (a.stale.isNotEmpty) {
    return 'older than this twk_dev: ${a.stale.length} file(s), '
        'twk agents rewrites them';
  }
  return a.missing ? 'not installed (twk agents)' : 'current';
}

String _yes(bool value) => value ? 'yes' : 'no';

/// What a terminal's probe found.
final class TerminalReport {
  /// A probe's result.
  const TerminalReport({
    required this.version,
    required this.colors,
    required this.synchronizedOutput,
    required this.kittyKeyboard,
    required this.kittyKeyboardFlags,
    required this.graphics,
    required this.hyperlinks,
    required this.cellWidth,
    required this.cellHeight,
    required this.answered,
    required this.probeMilliseconds,
  });

  /// XTVERSION, empty where not told.
  final String version;

  /// The color mode's name.
  final String colors;

  /// DEC 2026.
  final bool synchronizedOutput;

  /// The kitty keyboard protocol, and the flags pushed.
  final bool kittyKeyboard;

  /// The flags of [kittyKeyboard].
  final int kittyKeyboardFlags;

  /// The graphics protocol's name.
  final String graphics;

  /// Whether links are written as OSC 8.
  final bool hyperlinks;

  /// A cell's size in pixels, 0 where not told.
  final int cellWidth;

  /// A cell's height in pixels, 0 where not told.
  final int cellHeight;

  /// Whether the last query was answered in time.
  final bool answered;

  /// How long opening the terminal took.
  final int probeMilliseconds;

  /// As JSON.
  Map<String, Object?> toJson() => {
    'version': version,
    'colors': colors,
    'synchronizedOutput': synchronizedOutput,
    'kittyKeyboard': kittyKeyboard,
    'kittyKeyboardFlags': kittyKeyboardFlags,
    'graphics': graphics,
    'hyperlinks': hyperlinks,
    'cellWidth': cellWidth,
    'cellHeight': cellHeight,
    'answered': answered,
    'probeMilliseconds': probeMilliseconds,
  };
}

Future<TerminalReport> _probe(CliTerminal terminal) async {
  final watch = terminal.clock.stopwatch();
  final backend = await terminal.openInline();
  watch.stop();
  try {
    final info = backend.info;
    return TerminalReport(
      version: info.terminalVersion,
      colors: info.colorMode.name,
      synchronizedOutput: info.caps.synchronizedOutput,
      kittyKeyboard: info.kittyKeyboard,
      kittyKeyboardFlags: info.kittyKeyboardFlags,
      graphics: info.caps.graphics.name,
      hyperlinks: terminal.capabilities.hyperlinks,
      cellWidth: info.caps.cellPixelWidth,
      cellHeight: info.caps.cellPixelHeight,
      answered: info.answeredQueries,
      probeMilliseconds: watch.elapsedMilliseconds,
    );
  } finally {
    await backend.close();
  }
}

/// The nearest `pubspec.lock` from [project] up (a workspace's is in its
/// root), null where there is none.
File? _lockOf(String project) {
  for (var dir = project; ; dir = p.dirname(dir)) {
    final file = File(p.join(dir, 'pubspec.lock'));
    if (file.existsSync()) {
      return file;
    }
    if (p.dirname(dir) == dir) {
      return null;
    }
  }
}

Map<String, String> _versions(File lock) {
  try {
    final yaml = loadYaml(lock.readAsStringSync());
    final packages = yaml is YamlMap ? yaml['packages'] : null;
    if (packages is! YamlMap) {
      return const {};
    }
    return {
      for (final name in doctorPackages)
        if (packages[name] case final YamlMap entry
            when entry['version'] is String)
          name: entry['version'] as String,
    };
  } on YamlException {
    return const {};
  }
}

/// One file of `.dart_tool/twk`.
final class StateReport {
  /// A file's [address] (what it names), and whether anything [listens].
  const StateReport(this.address, {required this.listens});

  /// What the file names.
  final String address;

  /// Whether a connection to it was taken; false for a file left behind.
  final bool listens;

  /// As JSON.
  Map<String, Object?> toJson() => {'address': address, 'listens': listens};

  /// As the report shows it.
  String render() => '$address (${listens ? 'listening' : 'left behind'})';
}

Future<Map<String, StateReport>> _state(String project) async {
  final state = <String, StateReport>{};
  final run = File(serviceFileOf(project));
  if (run.existsSync()) {
    final line = run.readAsLinesSync().firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '',
    );
    final uri = Uri.tryParse(line.trim());
    state['run'] = StateReport(
      line.trim(),
      listens:
          uri != null &&
          uri.hasPort &&
          await connects(
            () => Socket.connect(uri.host, uri.port),
          ),
    );
  }
  for (final service in const ['shell', 'logs']) {
    final address = LocalAddress.read(LocalAddress.fileOf(service, project));
    if (address != null) {
      state[service] = StateReport(
        address.toString(),
        listens: await connects(address.connect),
      );
    }
  }
  return state;
}

/// Whether [connect] opens a socket within [timeout]; the socket is closed.
/// One that opens after the timeout is closed too, not left holding a slot
/// of the server.
Future<bool> connects(
  Future<Socket> Function() connect, {
  Duration timeout = doctorConnectTimeout,
}) async {
  try {
    final attempt = connect();
    try {
      final socket = await attempt.timeout(timeout);
      socket.destroy();
      return true;
    } on TimeoutException {
      // the connect goes on: a socket it opens late is not left holding a
      // slot of the server
      unawaited(attempt.then((s) => s.destroy(), onError: (Object _) {}));
      return false;
    }
  } on Object {
    return false;
  }
}

/// The skill for agents in a project.
final class AgentsReport {
  /// A report of the skill's files.
  const AgentsReport({
    required this.stale,
    required this.edited,
    required this.missing,
  });

  /// The files `twk agents` wrote that this twk_dev has another version of.
  final List<String> stale;

  /// The files the project changed after `twk agents` wrote them.
  final List<String> edited;

  /// Whether none of the skill is in the project.
  final bool missing;

  /// As JSON.
  Map<String, Object?> toJson() => {
    'stale': stale,
    'edited': edited,
    'missing': missing,
  };
}

AgentsReport? _agents(String project) {
  if (agentsProblem(project) != null || !dependsOnTwk(project)) {
    return null;
  }
  try {
    final plan = agentsPlan(project);
    final skill = plan.changes.where((c) => c.file.isSkill).toList();
    return AgentsReport(
      stale: [
        for (final c in skill)
          if (c.action == AgentsAction.changed) c.path,
      ],
      edited: [
        for (final c in skill)
          if (c.action == AgentsAction.edited) c.path,
      ],
      missing: skill.every((c) => c.action == AgentsAction.wrote),
    );
  } on AgentsException {
    return null;
  }
}
