/// What `ext.twk.find` answers: [Found] nodes and their [Cells].
library;

import 'app_client.dart' show Json;
import 'errors.dart';

/// A rectangle of cells.
final class Cells {
  /// The rectangle at ([x], [y]) of [width] by [height] cells.
  const Cells(this.x, this.y, this.width, this.height);

  /// The rectangle `json` writes (`x`, `y`, `width`, `height`).
  factory Cells.fromJson(Object? json) {
    if (json case {
      'x': final int x,
      'y': final int y,
      'width': final int width,
      'height': final int height,
    }) {
      return Cells(x, y, width, height);
    }
    throw DriverError('not a rectangle of cells: $json');
  }

  /// The leftmost column.
  final int x;

  /// The top row.
  final int y;

  /// How many columns.
  final int width;

  /// How many rows.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is Cells &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => '$x,$y ${width}x$height';
}

/// A node of the app's widget tree a finder matched, as the app described
/// it.
final class Found {
  /// A node [id] of [type] (its widget's `runtimeType`), with its [key]
  /// as the tree writes it, its [text] if it is a `Text`, its [rect] and
  /// the [shown] part of it.
  const Found({
    required this.id,
    required this.type,
    required this.key,
    required this.text,
    required this.rect,
    required this.shown,
  });

  /// One match of the answer's `matches`.
  factory Found.fromJson(Json json) => Found(
    id: json['id']! as int,
    type: json['type']! as String,
    key: json['key'] as String?,
    text: json['text'] as String?,
    rect: json['rect'] == null ? null : Cells.fromJson(json['rect']),
    shown: json['shown'] == null ? null : Cells.fromJson(json['shown']),
  );

  /// The node's id, kept while it is in the tree.
  final int id;

  /// Its widget's type, with its type arguments.
  final String type;

  /// Its key, as the tree writes it, null for none.
  final String? key;

  /// The whole of a `Text`'s text; null for any other widget.
  final String? text;

  /// The cells of its render object; null before it is laid out.
  final Cells? rect;

  /// The part of [rect] the screen shows, no ancestor cutting it off; null
  /// when no cell shows.
  final Cells? shown;

  /// A short description for a failure: `Text 'Save' (node 44)`.
  String get describe =>
      '$type${text == null ? '' : " '$text'"}'
      '${key == null ? '' : ' [$key]'} (node $id)';

  @override
  String toString() => describe;
}

/// The `matches` of an `ext.twk.find` [answer].
List<Found> foundOf(Json answer) => [
  for (final m in answer['matches']! as List<Object?>)
    Found.fromJson(m! as Json),
];
