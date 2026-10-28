// A search written with hooks: the packages load while a spinner turns,
// then what is typed filters them, once the typing has paused for 300 ms;
// the part of each name that matches is highlighted. Escape clears the
// field, Ctrl+Q quits.
//
//   dart run example/hooks/search.dart
import 'dart:async';

import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';

Future<void> main() => runApp(const Search());

/// A package of the list: its name and what it is for.
typedef Package = ({String name, String about});

/// How long loading the packages takes.
const loadingTime = Duration(milliseconds: 600);

/// How long the typing pauses before the list is filtered.
const pause = Duration(milliseconds: 300);

/// The packages, after [loadingTime], as a request to a server gives them.
Future<List<Package>> loadPackages() => Future.delayed(
  loadingTime,
  () => [
    (name: 'args', about: 'parses command-line arguments'),
    (name: 'async', about: 'utilities for streams and futures'),
    (name: 'collection', about: 'collections and what to do with them'),
    (name: 'crypto', about: 'hashes: SHA-1, SHA-256, MD5'),
    (name: 'http', about: 'makes HTTP requests'),
    (name: 'intl', about: 'messages, dates and numbers by locale'),
    (name: 'json_annotation', about: 'annotations for JSON code'),
    (name: 'logging', about: 'hierarchical loggers'),
    (name: 'markdown', about: 'Markdown to HTML'),
    (name: 'meta', about: 'annotations for static analysis'),
    (name: 'path', about: 'joins and splits paths on any platform'),
    (name: 'shelf', about: 'web servers made of middleware'),
    (name: 'stream_channel', about: 'two-way streams'),
    (name: 'test', about: 'writes and runs tests'),
    (name: 'yaml', about: 'parses YAML'),
  ],
);

/// [value] once it has stayed the same for [delay]: a hook of its own,
/// made of two others. Each new [value] cancels the timer the last one
/// started (the effect's cleanup) and starts its own.
T useDebounced<T>(T value, Duration delay) {
  final settled = useState(value);
  useEffect(() {
    final timer = Timer(delay, () => settled.value = value);
    return timer.cancel;
  }, [value]);
  return settled.value;
}

final class Search extends HookWidget {
  const Search({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // made in the first build, disposed with the widget
    final field = useTextEditingController();
    // rebuilt on each key typed
    final query = useValueListenable(field).text.trim().toLowerCase();
    final settled = useDebounced(query, pause);
    // one request, not one a build
    final packages = useFuture(useMemoized(loadPackages));
    final all = packages.data ?? const <Package>[];
    // filtered again only when the settled query or the list changes
    final matches = useMemoized(
      () => [
        for (final package in all)
          if (package.name.contains(settled) ||
              package.about.toLowerCase().contains(settled))
            package,
      ],
      [settled, all],
    );

    return KeyBindings(
      // not 'q': the field takes the characters typed
      {'escape': field.clear, 'ctrl+q': () => AppBinding.of(context).quit()},
      child: Box(
        style: theme.background.merge(theme.text),
        border: .all(type: .rounded, style: theme.border),
        titles: [
          BorderTitle(' Packages ', style: theme.primary),
          BorderTitle(
            ' esc clear  ctrl+q quit ',
            style: theme.muted,
            alignment: .bottomRight,
          ),
        ],
        padding: const .x(1),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Row(
              gap: 1,
              children: [
                Text('⌕', style: theme.primary),
                Expanded(
                  child: TextField(
                    controller: field,
                    placeholder: 'search',
                    autofocus: true,
                  ),
                ),
              ],
            ),
            if (packages.hasData)
              Text(
                query != settled
                    ? 'searching…'
                    : '${matches.length} of ${all.length}',
                style: theme.muted,
              )
            else
              Row(
                gap: 1,
                children: [
                  Spinner(style: theme.primary),
                  Text('loading the packages', style: theme.muted),
                ],
              ),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, i) =>
                    _Match(package: matches[i], query: settled),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [package]'s name, the part of it that is [query] highlighted, and what
/// it is for.
final class _Match extends StatelessWidget {
  const _Match({required this.package, required this.query});

  final Package package;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = package.name;
    final at = query.isEmpty ? -1 : name.indexOf(query);
    return Text.rich(
      [
        if (at < 0)
          Span(name).bold
        else ...[
          Span(name.substring(0, at)).bold,
          Span(name.substring(at, at + query.length), theme.primary).bold,
          Span(name.substring(at + query.length)).bold,
        ],
        Span(' ' * (16 - name.length).clamp(1, 16)),
        Span(package.about, theme.muted),
      ],
      wrap: .none,
      overflow: .ellipsis,
    );
  }
}
