/// Riverpod for widgets of the twk package: a `ProviderScope` keeps the
/// state of providers, and the widgets that use them (`ConsumerWidget`,
/// `ConsumerStatefulWidget`, `Consumer`) watch them through a `WidgetRef`,
/// rebuilt when what they watch changes.
///
/// It exports package:riverpod's own library too; its `misc.dart` and
/// `legacy.dart` are this package's.
library;

export 'package:riverpod/riverpod.dart';

export 'src/consumer.dart';
export 'src/provider_scope.dart';
