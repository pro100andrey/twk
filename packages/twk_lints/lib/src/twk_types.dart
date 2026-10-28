/// What the rules and assists know of twk's classes: they are found by
/// name and package, so the plugin does not depend on twk itself.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Whether [element] is declared in package [package] (any library of it).
bool isFromPackage(Element? element, String package) {
  final uri = element?.library?.uri;
  if (uri == null) {
    return false;
  }
  // the text of a `package:` URI is kept; its pathSegments is a new list
  // and a string per segment on every call
  final text = uri.toString();
  final n = package.length;
  return text.length > 9 + n &&
      text.startsWith('package:') &&
      text.startsWith(package, 8) &&
      text.codeUnitAt(8 + n) == 0x2F; // '/'
}

/// Whether [element] is the class [name] of twk (or of twk_core, which twk
/// exports).
bool isTwkClass(Element? element, String name) =>
    element is InterfaceElement && element.name == name && _isTwk(element);

/// Whether [type] is twk's class [name] or a subtype of it.
bool isTwkSubtype(DartType? type, String name) =>
    type is InterfaceType && _twkClassesOf(type.element).contains(name);

/// The names of twk's classes that [element] is or has for a supertype,
/// found once per element and kept while it is, as the element keeps its
/// supertypes.
Set<String> _twkClassesOf(InterfaceElement element) =>
    _twkClasses[element] ?? _findTwkClasses(element);

final _twkClasses = Expando<Set<String>>('twk classes');

/// The names of [element], if it is twk's, and of its direct supertypes',
/// which hold theirs: a class of no twk name of its own whose twk names
/// all come from one supertype (an app's widget, a `State`) shares that
/// supertype's set rather than building one.
Set<String> _findTwkClasses(InterfaceElement element) {
  // in place while the supertypes are asked, should they lead back here
  _twkClasses[element] = const {};
  final name = element.name;
  var names = name != null && _isTwk(element) ? {name} : const <String>{};
  names = _withTwkClassesOf(names, element.supertype);
  for (final type in element.mixins) {
    names = _withTwkClassesOf(names, type);
  }
  for (final type in element.interfaces) {
    names = _withTwkClassesOf(names, type);
  }
  if (element is MixinElement) {
    for (final type in element.superclassConstraints) {
      names = _withTwkClassesOf(names, type);
    }
  }
  return _twkClasses[element] = names;
}

/// [names] and the twk names of [type]'s class: [names] itself, or the
/// class's set, where one holds the other; a new set only where neither
/// does.
Set<String> _withTwkClassesOf(Set<String> names, InterfaceType? type) {
  if (type == null) {
    return names;
  }
  final more = _twkClassesOf(type.element);
  if (names.containsAll(more)) {
    return names;
  }
  return names.isEmpty || more.containsAll(names) ? more : {...names, ...more};
}

bool _isTwk(Element element) =>
    isFromPackage(element, 'twk') || isFromPackage(element, 'twk_core');

/// Whether [type] is a twk `Widget`.
bool isWidgetType(DartType? type) => isTwkSubtype(type, 'Widget');

/// Whether [type] is a twk `StatefulWidget`.
bool isStatefulWidgetType(DartType? type) =>
    isTwkSubtype(type, 'StatefulWidget');

/// Whether [element] is a subclass of twk's `State`.
bool isStateClass(InterfaceElement? element) =>
    element != null && isTwkSubtype(element.thisType, 'State');

/// The class [node] declares, if resolved.
InterfaceElement? classElementOf(ClassDeclaration node) =>
    node.declaredFragment?.element;

/// The expression of the widget at [node]: the instance creation whose
/// constructor name it is in, the invocation whose method name it is, or
/// the identifier it is, when that has a widget type; else null.
Expression? widgetExpressionAt(AstNode? node) {
  var current = node;
  // the parts of a constructor name: `prefix.Name<T>.named`
  while (current is ImportPrefixReference ||
      current is NamedType ||
      current is TypeArgumentList ||
      current is ConstructorName ||
      (current is SimpleIdentifier && current.parent is ConstructorName)) {
    current = current?.parent;
  }
  final expression = switch (current) {
    InstanceCreationExpression() => current,
    SimpleIdentifier(parent: MethodInvocation(:final methodName) && final m)
        when identical(methodName, current) =>
      m,
    SimpleIdentifier(parent: PrefixedIdentifier(:final identifier) && final p)
        when identical(identifier, current) =>
      p,
    SimpleIdentifier(parent: PropertyAccess(:final propertyName) && final p)
        when identical(propertyName, current) =>
      p,
    SimpleIdentifier() => current,
    MethodInvocation() => current,
    _ => null,
  };
  if (expression == null || !isWidgetType(expression.staticType)) {
    return null;
  }
  // a name being declared or labelled, not read
  if (expression is SimpleIdentifier &&
      (expression.inDeclarationContext() || expression.parent is Label)) {
    return null;
  }
  return expression;
}
