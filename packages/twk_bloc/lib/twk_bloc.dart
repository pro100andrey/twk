/// Bloc for widgets of the twk package: `BlocProvider` provides a bloc or a
/// cubit to a subtree, `RepositoryProvider` any other object, found by
/// their type (`context.read`, `context.watch`, `context.select`);
/// `BlocBuilder`, `BlocSelector`, `BlocListener` and `BlocConsumer` build
/// and act on the states a bloc emits.
///
/// It builds on twk's provider library, `package:twk/provider.dart`, as
/// flutter_bloc does on provider: its providers are that library's,
/// nested by its `MultiProvider` as well, and found by its context
/// extensions, which it exports with `SingleChildWidget` and
/// `ProviderNotFoundException`, so that a file may import both. It
/// exports package:bloc too.
library;

export 'package:bloc/bloc.dart';
export 'package:twk/provider.dart'
    show
        ProviderNotFoundException,
        ReadContext,
        SelectContext,
        SingleChildWidget,
        WatchContext;

export 'src/provider.dart' hide findProvided;
export 'src/widgets.dart';
