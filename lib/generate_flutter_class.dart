import 'dart:convert';
import 'dart:io';

import 'package:svg_to_font/templates/flutter_icons.dart' as template;
import 'package:recase/recase.dart';

class GenerateResult {
  GenerateResult(this.content, this.iconsCount);

  final String content;
  final int iconsCount;
}

Future<GenerateResult> generateFlutterClass({
  required File iconMap,
  required String className,
  required String? packageName,
  required String namingStrategy,
  String indent = '  ',
}) async {
  final Map<String, dynamic> icons = jsonDecode(await iconMap.readAsString());

  // Gerar métodos get para os ícones
  final getMethodsEntries = icons.entries.map((entry) {
    final iconName = namingStrategy == 'snake'
        ? ReCase(entry.key).snakeCase
        : ReCase(entry.key).camelCase;
    final iconCode = entry.value.toRadixString(16).toString();

    return someReplace(
      template.getMethod
          .replaceFirst('%ICON_NAME%', iconName)
          .replaceFirst('%ICON_CODE%', iconCode),
      className: className,
      indent: indent,
    );
  }).join('\n');

  // Substituir no template base
  final content = someReplace(
    template.base
        .replaceFirst(
            '%PACKAGE%',
            packageName == null
                ? ''
                : someReplace(
                    template.package
                        .replaceFirst('%PACKAGE_NAME%', packageName),
                    className: className,
                    indent: indent,
                  ))
        .replaceFirst('%CONTENT%', '') // Remove constantes
        .replaceFirst(
            '%GET_METHODS%', getMethodsEntries), // Adiciona os métodos
    className: className,
    indent: indent,
  );

  return GenerateResult(content, icons.length);
}

String someReplace(
  String template, {
  required String indent,
  required String className,
}) =>
    template
        .replaceAll('%INDENT%', indent)
        .replaceAll('%CLASS_NAME%', className);
