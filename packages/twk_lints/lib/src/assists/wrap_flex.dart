/// The wraps of a flex and in one, on [WrapAssist]: [WrapWithRow] and
/// [WrapWithColumn], of the widget at the cursor or of the elements
/// selected in a list of widgets; [WrapWithExpanded] and
/// [WrapWithFlexible], of a child of a flex.
library;

import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../twk_types.dart';
import 'widget_tree.dart';
import 'wrap.dart';

/// Wraps the widget at the cursor in a flex named [flex], as the one
/// element of its `children:`; or, where a selection is in a list of
/// widgets, the elements it reaches, as they are written (comments
/// between them, and `if`, `for` and spread elements, too).
abstract base class _WrapInFlex extends WrapAssist {
  _WrapInFlex({required super.context});

  /// The name of the flex: `Row` or `Column`.
  String get flex;

  @override
  bool get takesNonNullable => true;

  @override
  void writeName(DartEditBuilder builder) {
    builder.writeImportedName([twkLibrary], flex);
  }

  @override
  SourceRange? wrapped() {
    final list = node;
    if (selectionLength > 0 &&
        list is ListLiteral &&
        isWidgetType(listElementType(list))) {
      final selected = [
        for (final element in list.elements)
          if (element.end > selectionOffset && element.offset < selectionEnd)
            element,
      ];
      return selected.isEmpty
          ? null
          : range.startEnd(selected.first, selected.last);
    }
    return super.wrapped();
  }

  @override
  void writeChild(DartEditBuilder builder, String source, String? inner) {
    if (inner == null) {
      builder
        ..write('children: [')
        ..write(source)
        ..write(']');
      return;
    }
    final eol = utils.endOfLine;
    final deeper = '$inner${utils.oneIndent}';
    builder
      ..write('children: [')
      ..write(eol)
      ..write(deeper)
      ..write(reindent(source, inner, deeper))
      ..write(',')
      ..write(eol)
      ..write(inner)
      ..write(']');
  }
}

/// Wraps the widget at the cursor, or the elements selected in a list of
/// widgets, in a `Row`.
///
/// `Text('a'), Text('b')` selected in a list of widgets becomes:
///
/// ```dart-nocheck
/// Row(children: [Text('a'), Text('b')])
/// ```
final class WrapWithRow extends _WrapInFlex {
  /// The assist for the request [context] describes.
  WrapWithRow({required super.context});

  /// The assist as the editor lists it: "Wrap with Row".
  static const kind = AssistKind(
    'twk.assist.wrapWithRow',
    DartFixKindPriority.standard,
    'Wrap with Row',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  String get flex => 'Row';
}

/// Wraps the widget at the cursor, or the elements selected in a list of
/// widgets, in a `Column`.
///
/// `Text('a')` at the cursor becomes:
///
/// ```dart-nocheck
/// Column(children: [Text('a')])
/// ```
final class WrapWithColumn extends _WrapInFlex {
  /// The assist for the request [context] describes.
  WrapWithColumn({required super.context});

  /// The assist as the editor lists it: "Wrap with Column".
  static const kind = AssistKind(
    'twk.assist.wrapWithColumn',
    DartFixKindPriority.standard,
    'Wrap with Column',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  String get flex => 'Column';
}

/// Wraps a child of a flex in a flexible named [name]: offered only for a
/// widget in the `children:` written in place of a `Flex` (a `Row`, a
/// `Column`), directly or in an `if` or `for` element there, and not for
/// one that is a flexible already (a `Flexible`, an `Expanded`, a
/// `Spacer`), which a flexible may not hold.
abstract base class _WrapInFlexible extends WrapAssist {
  _WrapInFlexible({required super.context});

  /// The name of the flexible: `Expanded` or `Flexible`.
  String get name;

  @override
  bool get takesNonNullable => true;

  @override
  void writeName(DartEditBuilder builder) {
    builder.writeImportedName([twkLibrary], name);
  }

  @override
  bool offeredFor(Expression widget) {
    final type = widget.staticType;
    if (isTwkSubtype(type, 'Flexible') || isTwkSubtype(type, 'Spacer')) {
      return false;
    }
    var parent = widget.parent;
    while (parent is IfElement || parent is ForElement) {
      parent = parent!.parent;
    }
    final argument = parent?.parent;
    final creation = argument?.parent?.parent;
    return parent is ListLiteral &&
        argument is NamedArgument &&
        argument.name.lexeme == 'children' &&
        creation is InstanceCreationExpression &&
        isTwkSubtype(creation.staticType, 'Flex');
  }
}

/// Wraps a child of a flex in an `Expanded`, which fills its share.
///
/// The cursor on `Text('a')` in a `Row`:
///
/// ```dart-nocheck
/// Row(children: [Expanded(child: Text('a'))])
/// ```
final class WrapWithExpanded extends _WrapInFlexible {
  /// The assist for the request [context] describes.
  WrapWithExpanded({required super.context});

  /// The assist as the editor lists it: "Wrap with Expanded".
  static const kind = AssistKind(
    'twk.assist.wrapWithExpanded',
    DartFixKindPriority.standard,
    'Wrap with Expanded',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  String get name => 'Expanded';
}

/// Wraps a child of a flex in a `Flexible`, which takes up to its share.
///
/// The cursor on `Text('a')` in a `Row`:
///
/// ```dart-nocheck
/// Row(children: [Flexible(child: Text('a'))])
/// ```
final class WrapWithFlexible extends _WrapInFlexible {
  /// The assist for the request [context] describes.
  WrapWithFlexible({required super.context});

  /// The assist as the editor lists it: "Wrap with Flexible".
  static const kind = AssistKind(
    'twk.assist.wrapWithFlexible',
    DartFixKindPriority.standard,
    'Wrap with Flexible',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  String get name => 'Flexible';
}
