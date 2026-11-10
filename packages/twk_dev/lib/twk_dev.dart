/// The `twk` command: developer tools for apps built on twk. As a library,
/// what its commands are made of: `runTwk`, which runs it on a command
/// line; `Cast`, `CastHeader`, `CastEvent` and `CastWriter`, the asciicast
/// v2 recordings `twk record` writes and `twk play` plays; `formatLine` and
/// `formatRecord`, a record of an app's log as `twk logs` shows it.
///
/// A recording's `Cast.writes` are what twk_test's `screenFrames` plays
/// through its emulator, a screen a frame, for a test.
///
/// `agentsPlan` and its `AgentsPlan`: what `twk agents` writes into a
/// project, for a caller that chooses the files.
library;

export 'src/agents.dart'
    show
        AgentsAction,
        AgentsChange,
        AgentsException,
        AgentsFile,
        AgentsPlan,
        agentsPlan,
        agentsProblem,
        dependsOnTwk,
        mergeAgentsBlock;
export 'src/cast.dart' show Cast, CastEvent, CastHeader, CastWriter;
export 'src/cast_test_gen.dart' show castTestSource;
export 'src/cli.dart' show runTwk, usageExitCode;
export 'src/logs.dart' show formatLine, formatRecord;
