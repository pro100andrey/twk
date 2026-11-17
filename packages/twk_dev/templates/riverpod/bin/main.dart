import 'package:riverpod_template/riverpod_template.dart';
import 'package:twk/twk.dart';
import 'package:twk_riverpod/twk_riverpod.dart';

// riverpod: the state in providers, which the ProviderScope keeps
Future<void> main() => runApp(const ProviderScope(child: Counter()));
