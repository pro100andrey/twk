@Tags(['process'])
library;

import 'package:test/test.dart';

import 'create_cycle.dart';

void main() => templateCycle(
  'app',
  extraFiles: ['dart_test.yaml', 'test/app_app_driver_test.dart'],
);
