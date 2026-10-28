import 'package:gallery/gallery.dart';
import 'package:test/test.dart';

void main() {
  group('GalleryRoute.parse', () {
    test('reads the page, theme, tab, options and time', () {
      final r = GalleryRoute.parse(
        '#/controls/button?theme=light&tab=code&o=wrap:none;width:40&t=2000',
      );
      expect(r.group, 'controls');
      expect(r.page, 'button');
      expect(r.theme, 'light');
      expect(r.tab, 'code');
      expect(r.options, {'wrap': 'none', 'width': '40'});
      expect(r.t, const Duration(seconds: 2));
    });

    test('takes the route with or without the leading # and /', () {
      for (final s in [
        '#/text/text',
        '/text/text',
        'text/text',
        '#text/text',
      ]) {
        final r = GalleryRoute.parse(s);
        expect((r.group, r.page), ('text', 'text'), reason: s);
      }
    });

    test('reads keys, comma among them, and what is typed', () {
      final r = GalleryRoute.parse(
        '#/data/table?keys=tab,shift+tab,ctrl+p,comma&type=spark line',
      );
      expect(r.keys, ['tab', 'shift+tab', 'ctrl+p', ',']);
      expect(r.type, 'spark line');
    });

    test('decodes escapes, keeping a plus', () {
      final r = GalleryRoute.parse('#/text/text?o=rows:10%20000&keys=ctrl+k');
      expect(r.options, {'rows': '10 000'});
      expect(r.keys, ['ctrl+k']);
    });

    test('a value keeps what follows its first colon', () {
      final r = GalleryRoute.parse('#/a/b?o=time:10:30');
      expect(r.options, {'time': '10:30'});
    });

    test('keeps focus, filter, palette, toast, kind, size and bare', () {
      final r = GalleryRoute.parse(
        '#/text?focus=o:wrap&filter=box&palette=dark&toast=Hi&kind=success'
        '&size=80x24&bare=1',
      );
      expect(r.group, 'text');
      expect(r.page, isNull);
      expect(r.focus, 'o:wrap');
      expect(r.filter, 'box');
      expect(r.palette, 'dark');
      expect(r.toast, 'Hi');
      expect(r.kind, 'success');
      expect(r.size, '80x24');
      expect(r.bare, isTrue);
    });

    test('never throws, whatever it is given', () {
      for (final s in [
        '',
        '#',
        '?',
        '#/?&&=&',
        '#/x/y?t=abc&o=;;:&keys=,,',
        '#/%zz/%',
      ]) {
        expect(() => GalleryRoute.parse(s), returnsNormally, reason: s);
      }
      expect(GalleryRoute.parse('#/a?t=abc').t, Duration.zero);
    });

    test('writes itself back as it reads', () {
      const s =
          '#/controls/button?theme=light&tab=code&t=2000&o=color:accent'
          '&focus=page&keys=tab,comma&type=hi%20there';
      final r = GalleryRoute.parse(s);
      expect(r.toString(), s);
      expect(GalleryRoute.parse(r.toString()), r);
    });
  });

  test('slug names a title as a route does', () {
    expect(slug('Checkbox, Switch'), 'checkbox-switch');
    expect(slug('Align, Center'), 'align-center');
    expect(slug('IntrinsicWidth/Height'), 'intrinsicwidth-height');
    expect(slug('Rich (`twk_rich`)'), 'rich-twk-rich');
  });
}
