// Prints a line with the web's printError inside a zone that catches
// what is printed in it, for web_test.dart: says on stdout how many lines
// the zone caught.
// ignore_for_file: avoid_print
import 'dart:async';

import 'package:twk_core/src/platform/web.dart' as web;

void main() {
  final caught = <String>[];
  runZoned(
    () => web.printError('to the console'),
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => caught.add(line),
    ),
  );
  print('the zone caught ${caught.length}');
}
