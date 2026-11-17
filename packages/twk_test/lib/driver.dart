// Examples can assume:
// import 'package:test/test.dart';

/// Tests of a twk app as a real process in a pseudo-terminal: [driverTest]
/// starts it ([DriverTester.start]), drives it as a user does ([DriverApp]),
/// and reads its screen with the matchers and its widgets with the finders
/// of `package:twk_test/twk_test.dart`. A library of its own, so that tests
/// of the widgets in the test's process ([testTwk]) do not load the driver.
///
/// ```dart
/// driverTest('saving shows it', (d) async {
///   final app = await d.start('bin/main.dart', size: (60, 12));
///   await app.press('ctrl+n');
///   await app.tap(find.text('Save'));
///   expect(app.screen, containsLine('Saved'));
/// }, tags: 'process');
/// ```
///
/// @docImport 'src/driver.dart';
/// @docImport 'src/tester.dart';
/// @docImport 'twk_test.dart';
library;

export 'package:twk_driver/twk_driver.dart'
    show DriverError, ExitResult, Found, Step;

export 'src/driver.dart'
    show
        DriverApp,
        DriverTester,
        driverTest,
        profileEnvironment,
        terminalProfiles;
export 'src/driver_screen.dart' show DriverScreen;
