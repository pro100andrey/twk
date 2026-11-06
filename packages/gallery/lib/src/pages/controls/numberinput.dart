// The NumberInput page.
part of 'controls.dart';

final _numberinputPage = GalleryPage(
  group: _group,
  title: 'NumberInput',
  build: (context, o) => const _Numbers(),
  code: (o) => [
    'var _copies = 1.0;',
    'var _price = 9.5;',
    '',
    '@override',
    'Widget build(BuildContext context) => Column(',
    '  mainAxisSize: .min,',
    '  crossAxisAlignment: .start,',
    '  spacing: 1,',
    '  children: [',
    '    Row(',
    '      mainAxisSize: .min,',
    '      children: [',
    "        const SizedBox(width: 16, child: Text('copies, 1 to 99')),",
    '        SizedBox(',
    '          width: 10,',
    '          child: NumberInput(',
    '            value: _copies,',
    '            min: 1,',
    '            max: 99,',
    '            onChanged: (value) => setState(() => _copies = value),',
    '          ),',
    '        ),',
    '      ],',
    '    ),',
    '    Row(',
    '      mainAxisSize: .min,',
    '      children: [',
    "        const SizedBox(width: 16, child: Text('price, by 0.25')),",
    '        SizedBox(',
    '          width: 10,',
    '          child: NumberInput(',
    '            value: _price,',
    '            min: 0,',
    '            step: 0.25,',
    '            decimals: 2,',
    '            onChanged: (value) => setState(() => _price = value),',
    '          ),',
    '        ),',
    '      ],',
    '    ),',
    '    Text(',
    r"      '${_copies.round()} × ${_price.toStringAsFixed(2)} = '",
    r"      '${(_copies * _price).toStringAsFixed(2)}',",
    '    ),',
    '  ],',
    ');',
  ].join('\n'),
);

/// Copies and a price, typed or stepped, and what they come to.
final class _Numbers extends StatefulWidget {
  const _Numbers();

  @override
  State<_Numbers> createState() => _NumbersState();
}

final class _NumbersState extends State<_Numbers> with KeptState {
  @override
  Widget build(BuildContext context) {
    final copies = keptOr<double>('copies', 1);
    final price = keptOr('price', 9.5);
    Widget row(String label, Widget input) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 16, child: Text(label)),
        SizedBox(width: 10, child: input),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        row(
          'copies, 1 to 99',
          NumberInput(
            value: copies,
            min: 1,
            max: 99,
            onChanged: (value) => keep('copies', value),
          ),
        ),
        row(
          'price, by 0.25',
          NumberInput(
            value: price,
            min: 0,
            step: 0.25,
            decimals: 2,
            onChanged: (value) => keep('price', value),
          ),
        ),
        LitLine([
          (
            '${copies.round()} × ${price.toStringAsFixed(2)} = '
                '${(copies * price).toStringAsFixed(2)}',
            false,
          ),
        ], serial: serial),
      ],
    );
  }
}
