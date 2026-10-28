part of '../sample_app.dart';

extension on _SampleAppState {
  /// [child] in white text.
  Widget _styled(Widget child) => DefaultTextStyle(
    style: const Style(fg: Color.white),
    child: child,
  );

  List<Widget> _text() => [
    SizedBox(
      height: 2,
      child: Row(
        gap: 1,
        children: [
          const Text(
            'plain',
            style: Style(fg: Color.rgb(200, 120, 40), attrs: Attr.italic),
            wrap: TextWrap.grapheme,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            align: TextAlign.right,
          ),
          Text.rich([const Span('rich '), 'bold'.bold.fg(Color.red)]),
          const Spacer(),
          Builder(
            builder: (context) =>
                Text('${TerminalBrightness.of(context).name} terminal'),
          ),
        ],
      ),
    ),
  ];
}
