/// What the gallery's tests and tools use of it besides
/// `package:gallery/gallery.dart`, which this exports too: the catalog's
/// pages as routes, a route shown in twk's tester as the golden screens
/// show it, and the parts of the shell and the pages they look into. They
/// import this rather than `package:gallery/src/…`, so that the gallery's
/// files can move without them.
library;

export 'gallery.dart';
export 'src/catalog_routes.dart';
export 'src/pages/cli_code.dart' show cliCode;
export 'src/pages/pictures.dart' show pictureBytes;
export 'src/pages/rich.dart' show qrEncodes;
export 'src/paint.dart' show cut;
export 'src/shell/code_select.dart';
export 'src/shell/stage.dart' show RenderStage, Stage;
export 'src/shell/tokens.dart' show sidebarWidth;
export 'src/testing/show_route.dart';
