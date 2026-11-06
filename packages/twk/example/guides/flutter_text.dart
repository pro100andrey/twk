// Text and styles: the Coming from Flutter guide.
import 'package:twk/twk.dart';

const warn = Style(fg: Color.yellow, attrs: Attr.bold);
final rich = Text.rich(['error: '.bold.fg(.red), 'disk full'.dim]);
