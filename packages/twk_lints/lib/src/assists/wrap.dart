/// The assists that wrap the widget at the cursor in another, on
/// [WrapAssist]: [WrapInWidget], [WrapWithPadding], [WrapWithBox],
/// [WrapWithCenter] and [WrapWithSizedBox].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../twk_types.dart';
import 'widget_tree.dart';

/// The library the assists name twk's widgets from.
final Uri twkLibrary = Uri.parse('package:twk/twk.dart');

/// Wraps the widget at the cursor in another: `name(child: widget)`, on
/// lines of their own when the widget takes more than one or when the
/// wrapper takes more arguments. What is wrapped ([wrapped]), where the
/// wrapper takes it ([writeChild]) and where it is offered
/// ([offeredFor]) are its subclasses' to say.
abstract base class WrapAssist extends ResolvedCorrectionProducer {
  /// The assist for the request [context] describes.
  WrapAssist({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  /// Whether [writeArguments] writes any.
  bool get hasArguments => false;

  /// Whether the wrapper takes no null where the widget goes: a widget of
  /// a nullable type is not wrapped.
  bool get takesNonNullable => false;

  /// Writes the name of the wrapper.
  void writeName(DartEditBuilder builder);

  /// Writes the arguments before the widget's, each ended by `,` and
  /// [next].
  void writeArguments(DartEditBuilder builder, String next) {}

  /// Writes the argument the wrapper takes [source] as: `child: source`.
  /// [inner] is the indent of the wrapper's arguments, which [source] is
  /// indented as from; null where the wrapper is on one line.
  void writeChild(DartEditBuilder builder, String source, String? inner) {
    builder
      ..write('child: ')
      ..write(source);
  }

  /// Whether the assist is offered for [widget], the widget at the
  /// cursor.
  bool offeredFor(Expression widget) => true;

  /// What is wrapped: the widget at the cursor, where the assist is
  /// offered for it; else null.
  SourceRange? wrapped() {
    final widget = widgetExpressionAt(node);
    final type = widget?.staticType;
    if (widget == null ||
        type == null ||
        (takesNonNullable && !typeSystem.isNonNullable(type)) ||
        !offeredFor(widget)) {
      return null;
    }
    return range.node(widget);
  }

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final wrapped = this.wrapped();
    if (wrapped == null) {
      return;
    }
    final source = textOf(wrapped.offset, wrapped.end);
    final eol = utils.endOfLine;
    final indent = utils.getLinePrefix(wrapped.offset);
    final inner = '$indent${utils.oneIndent}';
    final lines = hasArguments || source.contains(eol);
    await builder.addDartFileEdit(file, (builder) {
      builder.addReplacement(wrapped, (builder) {
        writeName(builder);
        builder.write('(');
        if (lines) {
          builder
            ..write(eol)
            ..write(inner);
        }
        writeArguments(builder, '$eol$inner');
        if (lines) {
          writeChild(builder, reindent(source, indent, inner), inner);
          builder
            ..write(',')
            ..write(eol)
            ..write(indent);
        } else {
          writeChild(builder, source, null);
        }
        builder.write(')');
      });
    });
  }
}

/// Wraps the widget at the cursor in a widget to name: `widget(child: ...)`,
/// `widget` selected for the name.
///
/// `Text('hi')` at the cursor becomes:
///
/// ```dart-nocheck
/// widget(child: Text('hi'))
/// ```
final class WrapInWidget extends WrapAssist {
  /// The assist for the request [context] describes.
  WrapInWidget({required super.context});

  /// The assist as the editor lists it: "Wrap with widget...".
  static const kind = AssistKind(
    'twk.assist.wrapInWidget',
    DartFixKindPriority.standard,
    'Wrap with widget...',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  void writeName(DartEditBuilder builder) {
    builder.addLinkedEdit('WIDGET', (builder) => builder.write('widget'));
  }
}

/// Wraps the widget at the cursor in a `Padding` of a cell on each side.
///
/// `Text('hi')` at the cursor becomes:
///
/// ```dart-nocheck
/// Padding(
///   padding: const EdgeInsets.all(1),
///   child: Text('hi'),
/// )
/// ```
final class WrapWithPadding extends WrapAssist {
  /// The assist for the request [context] describes.
  WrapWithPadding({required super.context});

  /// The assist as the editor lists it: "Wrap with Padding".
  static const kind = AssistKind(
    'twk.assist.wrapWithPadding',
    DartFixKindPriority.standard,
    'Wrap with Padding',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  bool get hasArguments => true;

  @override
  void writeName(DartEditBuilder builder) {
    builder.writeImportedName([twkLibrary], 'Padding');
  }

  @override
  void writeArguments(DartEditBuilder builder, String next) {
    builder
      ..write('padding: const ')
      ..writeImportedName([twkLibrary], 'EdgeInsets')
      ..write('.all(1),')
      ..write(next);
  }
}

/// Wraps the widget at the cursor in a `Box` with a border.
///
/// `Text('hi')` at the cursor becomes:
///
/// ```dart-nocheck
/// Box(
///   border: const Border.all(),
///   child: Text('hi'),
/// )
/// ```
final class WrapWithBox extends WrapAssist {
  /// The assist for the request [context] describes.
  WrapWithBox({required super.context});

  /// The assist as the editor lists it: "Wrap with Box".
  static const kind = AssistKind(
    'twk.assist.wrapWithBox',
    DartFixKindPriority.standard,
    'Wrap with Box',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  bool get hasArguments => true;

  @override
  void writeName(DartEditBuilder builder) {
    builder.writeImportedName([twkLibrary], 'Box');
  }

  @override
  void writeArguments(DartEditBuilder builder, String next) {
    builder
      ..write('border: const ')
      ..writeImportedName([twkLibrary], 'Border')
      ..write('.all(),')
      ..write(next);
  }
}

/// Wraps the widget at the cursor in a `Center`.
///
/// `Text('hi')` at the cursor becomes:
///
/// ```dart-nocheck
/// Center(child: Text('hi'))
/// ```
final class WrapWithCenter extends WrapAssist {
  /// The assist for the request [context] describes.
  WrapWithCenter({required super.context});

  /// The assist as the editor lists it: "Wrap with Center".
  static const kind = AssistKind(
    'twk.assist.wrapWithCenter',
    DartFixKindPriority.standard,
    'Wrap with Center',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  void writeName(DartEditBuilder builder) {
    builder.writeImportedName([twkLibrary], 'Center');
  }
}

/// Wraps the widget at the cursor in a `SizedBox` of a cell by a cell,
/// the width and the height linked for the editor to step through.
///
/// `Text('hi')` at the cursor becomes:
///
/// ```dart-nocheck
/// SizedBox(
///   width: 1,
///   height: 1,
///   child: Text('hi'),
/// )
/// ```
final class WrapWithSizedBox extends WrapAssist {
  /// The assist for the request [context] describes.
  WrapWithSizedBox({required super.context});

  /// The assist as the editor lists it: "Wrap with SizedBox".
  static const kind = AssistKind(
    'twk.assist.wrapWithSizedBox',
    DartFixKindPriority.standard,
    'Wrap with SizedBox',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  bool get hasArguments => true;

  @override
  void writeName(DartEditBuilder builder) {
    builder.writeImportedName([twkLibrary], 'SizedBox');
  }

  @override
  void writeArguments(DartEditBuilder builder, String next) {
    builder
      ..write('width: ')
      ..addLinkedEdit('WIDTH', (builder) => builder.write('1'))
      ..write(',')
      ..write(next)
      ..write('height: ')
      ..addLinkedEdit('HEIGHT', (builder) => builder.write('1'))
      ..write(',')
      ..write(next);
  }
}
