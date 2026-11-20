import 'package:bloc_template/bloc_template.dart';
import 'package:twk/twk.dart';
import 'package:twk_bloc/twk_bloc.dart';

// bloc: the state in a cubit, which the BlocProvider creates and closes
Future<void> main() => runApp(
  BlocProvider(create: (_) => CounterCubit(), child: const Counter()),
);
