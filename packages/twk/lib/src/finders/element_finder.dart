import '../framework/framework.dart';
import '../text/text.dart';
import 'whole_text.dart';

/// What picks elements out of an app's tree, as a value: it has a
/// [description] for messages, [apply]s to the elements it is given, and
/// is JSON ([toJson], [ElementFinder.fromJson]), so that a tool outside the
/// app can send one to the app (`ext.twk.find`) which evaluates it on the
/// live tree with this same code. twk_test's `find` makes them.
///
/// The kinds that cross the wire, and what each finds:
///
/// * `{"text": "Save"}`: a [Text] whose whole text is equal.
/// * `{"textContaining": "Sav"}`: a [Text] with that string in it.
/// * `{"textMatches": {"source": "^Sa", "caseSensitive": true}}`: a [Text]
///   a [RegExp] matches.
/// * `{"type": "DropDown<String>"}`: a widget whose
///   `runtimeType.toString()` is equal.
/// * `{"key": {"value": "save"}}` or `{"key": {"value": 3}}`: a widget with
///   that [ValueKey], of a [String] or an int.
/// * `{"node": 44}`: the element an earlier answer gave that id.
/// * `{"descendant": F, "of": G}`, `{"ancestor": F, "of": G}`: what F finds
///   strictly below, or above, what G finds.
/// * `{"at": 2, "of": F}`, `{"first": F}`, `{"last": F}`: that one of what
///   F finds.
///
/// A finder made in the app's own process may be more than that: a [Type]
/// that is compared as a type, a key of any kind, a [RegExp] with its
/// flags. [toJson] of one the wire cannot carry throws an
/// [UnsupportedError] that says why. A class of the app's own can extend
/// this to find what no kind above does, and then it cannot be sent.
///
/// ```dart
/// final finder = ElementFinder.descendant(
///   of: ElementFinder.type(Column),
///   matching: ElementFinder.text('Save'),
/// );
/// print(finder.toJson());
/// // {descendant: {text: Save}, of: {type: Column}}
/// ```
abstract class ElementFinder {
  /// Lets a subclass be constant.
  const ElementFinder();

  /// The [Text]s whose whole text ([wholeText]) is [text].
  const factory ElementFinder.text(String text) = _TextFinder;

  /// The [Text]s whose whole text has [text] in it.
  const factory ElementFinder.textContaining(String text) = _TextFinder.part;

  /// The [Text]s whose whole text has a match of [pattern] in it. On the
  /// wire its source and whether it is case sensitive go: [toJson] of a
  /// [RegExp] that is multiline, dot-all, unicode or sticky throws.
  const factory ElementFinder.textMatches(RegExp pattern) = _TextFinder.regExp;

  /// The widgets of exactly the type [type], not of its subtypes, with its
  /// type arguments. On the wire it is `type.toString()` that is compared,
  /// the same answer unless two classes of one name from two libraries are
  /// in the tree: both are found, as a program cannot tell their libraries
  /// apart.
  const factory ElementFinder.type(Type type) = _TypeFinder;

  /// The widgets whose key is [key]. Only a [ValueKey] of a [String] or an
  /// int crosses the wire; reach any other by `node`.
  const factory ElementFinder.key(Key key) = _KeyFinder;

  /// What [matching] finds strictly below what [of] finds, in the order of
  /// the tree.
  const factory ElementFinder.descendant({
    required ElementFinder of,
    required ElementFinder matching,
  }) = _RelativeFinder.below;

  /// What [matching] finds strictly above what [of] finds: above the first
  /// from the nearest up, then above the next.
  const factory ElementFinder.ancestor({
    required ElementFinder of,
    required ElementFinder matching,
  }) = _RelativeFinder.above;

  /// The finder [json] is, as [toJson] writes it. A `node` is the element
  /// [nodeOf] gives for its id, which it throws a [StateError] for when
  /// that has left the tree, once it applies; [nodeOf] absent, a `node` is
  /// refused here. A [FormatException] for [json] that is none of the
  /// kinds.
  factory ElementFinder.fromJson(
    Object? json, {
    Element? Function(int id)? nodeOf,
  }) => _fromJson(json, nodeOf);

  /// What it finds, for messages: `type Text`, `text "Save"`.
  String get description;

  /// The elements this finds among [candidates], in their order.
  Iterable<Element> apply(Iterable<Element> candidates);

  /// This as JSON, which [ElementFinder.fromJson] reads; an
  /// [UnsupportedError] naming what cannot cross the wire.
  Object? toJson();

  /// The elements this finds in the tree of [root] and below it, in the
  /// order of the tree.
  List<Element> evaluate(Element root) {
    final all = <Element>[];
    void visit(Element e) {
      all.add(e);
      e.visitChildren(visit);
    }

    visit(root);
    return apply(all).toList();
  }

  /// The first of what this finds.
  ElementFinder get first => _IndexFinder(this, 0);

  /// The last of what this finds.
  ElementFinder get last => _IndexFinder(this, -1);

  /// What this finds at [index], from 0.
  ElementFinder at(int index) => _IndexFinder(this, index);

  @override
  String toString() => description;
}

ElementFinder _fromJson(Object? json, Element? Function(int id)? nodeOf) {
  if (json is! Map<String, Object?>) {
    throw FormatException('a finder is a JSON object, not $json');
  }
  ElementFinder child(String key) => _fromJson(json[key], nodeOf);
  T field<T>(Object? value, String what) =>
      value is T ? value : throw FormatException('$what: not a $T: $value');

  if (json.length == 1) {
    final MapEntry(:key, :value) = json.entries.single;
    switch (key) {
      case 'text':
        return ElementFinder.text(field<String>(value, key));
      case 'textContaining':
        return ElementFinder.textContaining(field<String>(value, key));
      case 'textMatches':
        final spec = field<Map<String, Object?>>(value, key);
        final source = field<String>(spec['source'], 'textMatches.source');
        final caseSensitive = switch (spec['caseSensitive']) {
          null => true,
          final bool b => b,
          final other => throw FormatException(
            'textMatches.caseSensitive: not a bool: $other',
          ),
        };
        return ElementFinder.textMatches(
          RegExp(source, caseSensitive: caseSensitive),
        );
      case 'type':
        return _TypeFinder.named(field<String>(value, key));
      case 'key':
        final spec = field<Map<String, Object?>>(value, key);
        return switch (spec['value']) {
          final String s => ElementFinder.key(ValueKey<String>(s)),
          final int i => ElementFinder.key(ValueKey<int>(i)),
          final other => throw FormatException(
            'key.value: a string or an int, not $other',
          ),
        };
      case 'node':
        final id = field<int>(value, key);
        final resolve =
            nodeOf ??
            (throw const FormatException('a node needs an app to name it'));
        return _NodeFinder(id, resolve);
      case 'first':
        return _fromJson(value, nodeOf).first;
      case 'last':
        return _fromJson(value, nodeOf).last;
    }
  } else if (json.length == 2 && json.containsKey('of')) {
    final of = child('of');
    if (json.containsKey('descendant')) {
      return ElementFinder.descendant(of: of, matching: child('descendant'));
    }
    if (json.containsKey('ancestor')) {
      return ElementFinder.ancestor(of: of, matching: child('ancestor'));
    }
    if (json.containsKey('at')) {
      return _IndexFinder(of, field<int>(json['at'], 'at'));
    }
  }
  throw FormatException('not a finder: ${json.keys.join(', ')}');
}

/// The [Text]s a test of their whole text takes.
final class _TextFinder extends ElementFinder {
  const _TextFinder(String this._equal) : _contains = null, _pattern = null;
  const _TextFinder.part(String this._contains)
    : _equal = null,
      _pattern = null;
  const _TextFinder.regExp(RegExp this._pattern)
    : _equal = null,
      _contains = null;

  final String? _equal;
  final String? _contains;
  final RegExp? _pattern;

  @override
  String get description => switch ((_equal, _contains, _pattern)) {
    (final s?, _, _) => 'text "$s"',
    (_, final s?, _) => 'text containing "$s"',
    (_, _, final p?) => 'text containing ${p.pattern}',
    _ => throw StateError('no test'),
  };

  bool _takes(String text) => switch ((_equal, _contains, _pattern)) {
    (final s?, _, _) => text == s,
    (_, final s?, _) => text.contains(s),
    (_, _, final p?) => p.hasMatch(text),
    _ => false,
  };

  @override
  Iterable<Element> apply(Iterable<Element> candidates) => candidates.where(
    (e) => switch (e.widget) {
      final Text t => _takes(wholeText(t)),
      _ => false,
    },
  );

  @override
  Object? toJson() => switch ((_equal, _contains, _pattern)) {
    (final s?, _, _) => {'text': s},
    (_, final s?, _) => {'textContaining': s},
    (_, _, final p?) when p.isMultiLine || p.isDotAll || p.isUnicode =>
      throw UnsupportedError(
        '$description: a RegExp with flags other than case sensitivity '
        'cannot cross the wire',
      ),
    (_, _, final p?) => {
      'textMatches': {'source': p.pattern, 'caseSensitive': p.isCaseSensitive},
    },
    _ => throw StateError('no test'),
  };
}

/// The widgets of one type.
final class _TypeFinder extends ElementFinder {
  const _TypeFinder(Type this._type) : _name = null;

  // Of the type whose `toString()` is the name, as the wire has it.
  const _TypeFinder.named(String this._name) : _type = null;

  final Type? _type;
  final String? _name;

  @override
  String get description => 'type ${_type ?? _name}';

  @override
  Iterable<Element> apply(Iterable<Element> candidates) => candidates.where((
    e,
  ) {
    final type = e.widget.runtimeType;
    return _type != null ? type == _type : type.toString() == _name;
  });

  @override
  Object? toJson() => {'type': '${_type ?? _name}'};
}

/// The widgets with one key.
final class _KeyFinder extends ElementFinder {
  const _KeyFinder(this._key);

  final Key _key;

  @override
  String get description => 'key $_key';

  @override
  Iterable<Element> apply(Iterable<Element> candidates) =>
      candidates.where((e) => e.widget.key == _key);

  @override
  Object? toJson() => switch (_key) {
    ValueKey<String>(:final value) => {
      'key': {'value': value},
    },
    ValueKey<int>(:final value) => {
      'key': {'value': value},
    },
    _ => throw UnsupportedError(
      '$description: only a ValueKey of a String or an int crosses the '
      'wire; find the widget some other way and use its node',
    ),
  };
}

/// The element an id names.
final class _NodeFinder extends ElementFinder {
  const _NodeFinder(this._id, this._nodeOf);

  final int _id;
  final Element? Function(int id) _nodeOf;

  @override
  String get description => 'node $_id';

  @override
  Iterable<Element> apply(Iterable<Element> candidates) {
    final node =
        _nodeOf(_id) ?? (throw StateError('no node $_id in the app any more'));
    return candidates.where((e) => identical(e, node));
  }

  @override
  Object? toJson() => {'node': _id};
}

/// What [_matching] finds below, or above, what [_of] finds.
final class _RelativeFinder extends ElementFinder {
  const _RelativeFinder.below({
    required ElementFinder of,
    required ElementFinder matching,
  }) : this._(of, matching, true);
  const _RelativeFinder.above({
    required ElementFinder of,
    required ElementFinder matching,
  }) : this._(of, matching, false);
  const _RelativeFinder._(this._of, this._matching, this._below);

  final ElementFinder _of;
  final ElementFinder _matching;
  final bool _below;

  @override
  String get description => '$_matching ${_below ? 'below' : 'above'} $_of';

  @override
  Iterable<Element> apply(Iterable<Element> candidates) =>
      _below ? _belowOf(candidates) : _aboveOf(candidates);

  Iterable<Element> _belowOf(Iterable<Element> candidates) {
    final all = candidates.toList();
    final above = _of.apply(all).toSet();
    bool below(Element e) {
      var found = false;
      e.visitAncestorElements((a) {
        found = above.contains(a);
        return !found;
      });
      return found;
    }

    return _matching.apply(all.where(below));
  }

  Iterable<Element> _aboveOf(Iterable<Element> candidates) {
    final all = candidates.toSet();
    final above = <Element>{};
    for (final e in _of.apply(all)) {
      // up to the app's widget
      e.visitAncestorElements((a) {
        if (!all.contains(a)) {
          return false;
        }
        above.add(a);
        return true;
      });
    }
    return _matching.apply(above);
  }

  @override
  Object? toJson() => {
    _below ? 'descendant' : 'ancestor': _matching.toJson(),
    'of': _of.toJson(),
  };
}

/// What [_finder] finds at [_index], from the last back when negative.
final class _IndexFinder extends ElementFinder {
  const _IndexFinder(this._finder, this._index);

  final ElementFinder _finder;
  final int _index;

  @override
  String get description => switch (_index) {
    0 => 'the first of $_finder',
    -1 => 'the last of $_finder',
    _ => '$_finder at $_index',
  };

  @override
  Iterable<Element> apply(Iterable<Element> candidates) {
    final found = _finder.apply(candidates).toList();
    final i = _index < 0 ? found.length + _index : _index;
    return [if (i >= 0 && i < found.length) found[i]];
  }

  @override
  Object? toJson() => switch (_index) {
    0 => {'first': _finder.toJson()},
    -1 => {'last': _finder.toJson()},
    _ => {'at': _index, 'of': _finder.toJson()},
  };
}
