// The gallery's look, held screen by screen: every page in the dark and
// the light theme at 120x36 and in the dark at 80x24, and the routes that
// go past a page's first frame (themes, sizes, the palette, the code,
// keys), each against its file in test/goldens/. The files were first
// written when the gallery matched its design, then the prototype in
// design/gallery (since retired), cell for cell at each of these routes;
// TWK_UPDATE_GOLDENS=1 writes them again from the gallery.
import 'package:gallery/testing.dart';
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

/// The variants every page is shown in, by the name its file ends in: the
/// parameters added to its route.
const _variants = {'dark': '', 'light': 'theme=light', '80x24': 'size=80x24'};

/// The routes past a page's first frame, by the name of their file under
/// test/goldens/.
const _extra = {
  'text/text.160x48': '#/text/text?size=160x48',
  'text/rich-text.nord': '#/text/rich-text?theme=nord',
  'text/rich-text.mocha': '#/text/rich-text?theme=mocha',
  'text/text.latte': '#/text/text?theme=latte',
  'text/text.palette': '#/text/text?palette=spin',
  'text/text.code': '#/text/text?tab=code&focus=code',
  'text/text.filter': '#/text/text?focus=filter&filter=tab',
  'text/text.keys': '#/text/text?keys=tab,right,tab,down,space,t,c,y',
  'text/text.palette-run': '#/text/text?keys=ctrl+p,s,p,i,n,enter',
  'controls/button.keys': '#/controls/button?keys=tab,enter,tab,space,tab',
  'controls/checkbox-switch.keys':
      '#/controls/checkbox-switch?keys=tab,space,tab,space,tab,tab',
  'animation/spinner.keys': '#/animation/spinner?keys=tab,right,tab,left',
  'animation/progressbar.keys':
      '#/animation/progressbar?keys=tab,space,tab,right,right,end',
  'data/sparkline.keys': '#/data/sparkline?keys=tab,right,tab,right,tab,space',
  'data/table.keys': '#/data/table?keys=tab,down,down,s,s,right,tab,right',
  'overlays/dialog.open': '#/overlays/dialog?keys=tab,enter',
  'overlays/dialog.keys-close':
      '#/overlays/dialog?keys=tab,enter,tab,tab,escape',
  'overlays/dialog.keys-confirm': '#/overlays/dialog?keys=tab,enter,enter',
  'editing/textfield.keys':
      '#/editing/textfield?keys=tab,shift+left,backspace,ctrl+z,enter'
      '&type=hello',
  'editing/textfield.obscure':
      '#/editing/textfield?o=obscure:true;maxLength:8&keys=tab'
      '&type=secret words',
  'editing/inputdecoration.keys':
      '#/editing/inputdecoration?keys=tab,tab,tab,tab&type=hunter',
  'editing/inputdecoration.open': '#/editing/inputdecoration?keys=tab,enter',
  'editing/inputdecoration.underline':
      '#/editing/inputdecoration?o=border:underline;filled:true'
      '&keys=tab,tab&type=docs',
  // a low screen: the options under the stage scroll to the focused one
  'layout/wrap.80x24-keys':
      '#/layout/wrap?size=80x24&keys=tab,tab,tab,tab,'
      'tab,tab',
  'screen-readers/semantics.80x24-keys':
      '#/screen-readers/semantics?size=80x24&keys=tab,space,tab,tab,enter',
  // the console's other programs, and the end of the first
  'app/cli.install': '#/app/cli?o=program:install',
  'app/cli.check': '#/app/cli?o=program:check',
  'app/cli.create-done': '#/app/cli?t=4500',
};

void main() {
  final routes = {
    for (final place in pagePlaces)
      for (final MapEntry(key: name, value: params) in _variants.entries)
        '${place.path}.$name':
            '#/${place.path}${params.isEmpty ? '' : '?$params'}',
    ..._extra,
  };
  for (final MapEntry(key: name, value: route) in routes.entries) {
    testTwk('$name: $route', (t) async {
      await showRoute(t, route);
      expect(t, matchesScreenFile('test/goldens/$name.txt'));
    });
  }
}
