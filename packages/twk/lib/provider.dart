/// Provider for widgets of the twk package, as package:provider is for
/// Flutter's: values provided to a subtree and found by their type
/// (`context.read`, `context.watch`, `context.select`), the widgets that
/// depend on them rebuilt when they change.
///
/// `Provider` provides a value, `ChangeNotifierProvider` and
/// `ListenableProvider` a listenable, `ValueListenableProvider` the value
/// of one, `FutureProvider` and `StreamProvider` what a future or a stream
/// gives, `ProxyProvider` and `ProxyProvider2` one made from others;
/// `MultiProvider` nests them. `Consumer`, `Consumer2` and `Selector`
/// build with what they provide.
library;

export 'src/provider/async_provider.dart';
export 'src/provider/consumer.dart';
export 'src/provider/inherited_provider.dart' hide deepEquals;
export 'src/provider/listenable_provider.dart';
export 'src/provider/proxy_provider.dart';
export 'src/provider/single_child.dart' hide nestedChild;
