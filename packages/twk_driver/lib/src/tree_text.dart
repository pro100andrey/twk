/// [treeText], the widget tree `ext.twk.tree` answers, as indented text.
library;

import 'app_client.dart' show Json;

/// The widget tree of an `ext.twk.tree` [answer], one node to a line,
/// indented by level: `Column #12 [key] 40x3  mainAxisSize=max`. From the
/// app's own widget down (not the framework's root above it), to [depth]
/// levels when given, the nodes cut off counted. `the app has drawn no
/// frame: no tree yet` before its first.
String treeText(Json answer, {int? depth}) {
  final root = answer['root'];
  if (root is! Json) {
    return 'the app has drawn no frame: no tree yet';
  }
  final app = answer['app'];
  final start = (app is int ? _byId(root, app) : null) ?? root;
  final out = StringBuffer();
  _write(out, start, 0, depth);
  return out.toString().trimRight();
}

Json? _byId(Json node, int id) {
  if (node['id'] == id) {
    return node;
  }
  for (final c in node['children'] as List<Object?>? ?? const []) {
    if (c is Json) {
      final found = _byId(c, id);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}

void _write(StringBuffer out, Json node, int level, int? depth) {
  final key = node['key'];
  final size = node['size'];
  final props = [
    for (final prop in node['properties'] as List<Object?>? ?? const [])
      if (prop is Map && prop['name'] != null)
        '${prop['name']}${prop['value'] == null ? '' : '=${prop['value']}'}',
  ];
  out
    ..write('  ' * level)
    ..write('${node['name']} #${node['id']}')
    ..write(key == null ? '' : ' [$key]')
    ..write(size is Map ? ' ${size['width']}x${size['height']}' : '')
    ..writeln(props.isEmpty ? '' : '  ${props.join(', ')}');
  final children = node['children'] as List<Object?>? ?? const [];
  if (depth != null && level >= depth) {
    if (children.isNotEmpty) {
      out
        ..write('  ' * (level + 1))
        ..writeln('... ${children.length} more below');
    }
    return;
  }
  for (final c in children) {
    if (c is Json) {
      _write(out, c, level + 1, depth);
    }
  }
}
