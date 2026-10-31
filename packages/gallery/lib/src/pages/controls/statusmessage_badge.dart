// The StatusMessage, Badge page.
part of 'controls.dart';

/// The StatusMessage, Badge page's `kind` option.
const _statusmessageBadgeKind = ChoiceOption<String>(
  'kind',
  'kind',
  values: ['info', 'success', 'warning', 'error'],
);

final _statusmessageBadgePage = GalleryPage(
  group: _group,
  title: 'StatusMessage, Badge',
  options: const [
    _statusmessageBadgeKind,
  ],
  build: (context, o) {
    final kind = StatusKind.values.byName(o(_statusmessageBadgeKind));
    final (said, disk) = _says[kind]!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        StatusMessage(said, kind: kind),
        StatusMessage(disk, kind: kind, title: 'Disk'),
        Row(
          mainAxisSize: MainAxisSize.min,
          gap: 1,
          children: [
            for (final kind in StatusKind.values) Badge(kind.name, kind: kind),
            const Badge('3'),
          ],
        ),
      ],
    );
  },
  code: (o) {
    final k = o.nameOf(_statusmessageBadgeKind);
    final (said, disk) = _says[StatusKind.values.byName(k)]!;
    return [
      'return Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      "    const StatusMessage('$said', kind: .$k),",
      '    const StatusMessage(',
      "      '$disk',",
      '      kind: .$k,',
      "      title: 'Disk',",
      '    ),',
      '    Row(',
      '      mainAxisSize: .min,',
      '      gap: 1,',
      '      children: [',
      _badgesLine,
      "        const Badge('3'),",
      '      ],',
      '    ),',
      '  ],',
      ');',
    ].join('\n');
  },
);

/// What each kind of StatusMessage says: a message, and one under the
/// title Disk.
const Map<StatusKind, (String, String)> _says = {
  StatusKind.info: (
    'Saving runs in the background.',
    'The disk has 120 GB free.',
  ),
  StatusKind.success: ('Saved 3 files to disk.', 'Backed up: 3 files, 12 MB.'),
  StatusKind.warning: (
    'Saved 3 files; 1 was skipped.',
    'The disk is nearly full: 95% of it is used.',
  ),
  StatusKind.error: (
    'Could not save 3 files.',
    'The disk is full: nothing more can be written.',
  ),
};

const _badgesLine =
    '        for (final kind in StatusKind.values) '
    'Badge(kind.name, kind: kind),';
