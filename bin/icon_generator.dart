import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:svg_to_font/generate_flutter_class.dart';
import 'package:svg_to_font/templates/npm_package.dart';
import 'package:svg_to_font/utils.dart';
import 'package:path/path.dart' as path;

void main() async {
  List<String> args = [
    '--from=./example/icons',
    '--class-name=UiIcons',
    '--out-font=./example/lib/icon_font/ui_icons.ttf',
    '--out-flutter=./example/lib/widgets/icons.dart',
  ];
  final runner = CommandRunner('icon_font_generator', 'Generate you own fonts')
    ..addCommand(GenerateCommand());
  try {
    await runner.run(['gen', ...args]);
  } on UsageException catch (error) {
    print(error);
    exit(1);
  }
}

class GenerateCommand extends Command {
  GenerateCommand() {
    argParser
      ..addOption(
        'from',
        abbr: 'f',
        help: 'Input dir with svg\'s',
      )
      ..addOption(
        'out-font',
        help: 'Output icon font',
      )
      ..addOption(
        'out-flutter',
        help: 'Output flutter icon class',
      )
      ..addOption(
        'class-name',
        help: 'Flutter class name / family for generating file',
      )
      ..addOption(
        'height',
        help: 'Fixed font height value',
        defaultsTo: '512',
      )
      ..addOption(
        'descent',
        help: 'Offset applied to the baseline',
        defaultsTo: '240',
      )
      ..addOption(
        'package',
        help: 'Name of package for generated icon data (if another package)',
      )
      ..addOption(
        'indent',
        help: 'Indent for generating dart file, for example: ' ' ',
        defaultsTo: '  ',
      )
      ..addFlag(
        'normalize',
        help: 'Normalize icons sizes',
        defaultsTo: false,
      )
      ..addFlag(
        'yarn',
        help: 'Use yarn instead npm',
        defaultsTo: false,
      )
      ..addOption(
        'naming-strategy',
        help: 'Icons name strategy',
        defaultsTo: 'snake',
        allowed: {'camel', 'snake'},
      );
  }

  @override
  String get name => 'gen';

  @override
  String get description => 'Generate you own fonts';

  @override
  Future<void> run() async {
    print('Verificando versão do Node...');
    final nodeCheckResult =
        await Process.run('node', ['--version'], runInShell: true);
    if (nodeCheckResult.exitCode != 0) {
      print('Por favor, instale o Node.js. Versão recomendada: v10+');
      exit(1);
    }

    // Verificação de parâmetros obrigatórios
    if (argResults!['from'] == null ||
        argResults!['out-font'] == null ||
        argResults!['out-flutter'] == null ||
        argResults!['class-name'] == null) {
      print('--from, --out-font, --out-flutter, '
          '--class-name são parâmetros obrigatórios!');
      exit(1);
    }

    final genRootDir = Directory.fromUri(Platform.script.resolve('..'));

    final npmPackage = File(path.join(genRootDir.path, 'package.json'));
    if (!npmPackage.existsSync()) {
      print('Criando arquivo package.json...');
      await npmPackage.writeAsString(npmPackageTemplate);
    }

    final tempSourceDirectory =
        Directory.fromUri(genRootDir.uri.resolve('temp_icons'));
    final tempOutDirectory =
        Directory.fromUri(genRootDir.uri.resolve('temp_font'));
    final iconsMap = File(path.join(tempOutDirectory.path,
        '${path.basenameWithoutExtension(argResults!['out-font'])}.json'));

    // Deletando diretórios temporários se existirem
    if (tempSourceDirectory.existsSync()) {
      print('Deletando diretório temporário de ícones...');
      await tempSourceDirectory.delete(recursive: true);
    }
    if (tempOutDirectory.existsSync()) {
      print('Deletando diretório temporário de fontes...');
      await tempOutDirectory.delete(recursive: true);
    }
    if (iconsMap.existsSync()) {
      print('Deletando arquivo de mapa de ícones...');
      await iconsMap.delete();
    }

    print('Instalando dependências npm...');
    final nodeInstallDependencies = await Process.start(
      (argResults!['yarn'] as bool) ? 'yarn' : 'npm',
      ['install', '--no-fund'],
      workingDirectory: genRootDir.path,
      runInShell: true,
    );
    await stdout.addStream(nodeInstallDependencies.stdout);

    // Captura erros relacionados a gyp
    final gypErr = 'gyp ERR!';
    await stderr.addStream(nodeInstallDependencies.stderr
        .where((bytes) => !utf8.decode(bytes).contains(gypErr)));

    print('Copiando ícones para diretório temporário...');
    final sourceIconsDirectory = Directory.fromUri(Directory.current.uri
        .resolve(argResults!['from'].replaceAll('\\', '/')));
    final outIconsFile = File(Directory.fromUri(Directory.current.uri
            .resolve(argResults!['out-font'].replaceAll('\\', '/')))
        .path);
    final outFlutterClassFile = File(Directory.fromUri(Directory.current.uri
            .resolve(argResults!['out-flutter'].replaceAll('\\', '/')))
        .path);
    await tempSourceDirectory.create();
    await tempOutDirectory.create();

    await copyDirectory(
      sourceIconsDirectory,
      tempSourceDirectory,
    );

    // Gerando fonte
    print('Gerando fonte...');
    final generateFont = await Process.start(
      path.join(
        genRootDir.path,
        'node_modules/.bin/fantasticon${Platform.isWindows ? '.cmd' : ''}',
      ),
      [
        path.absolute(tempSourceDirectory.path),
        '--font-height',
        argResults!['height'],
        '--descent',
        argResults!['descent'],
        '--normalize',
        argResults!['normalize'].toString(),
        '--name',
        path.basenameWithoutExtension(argResults!['out-font']),
        '--output',
        path.absolute(tempOutDirectory.path),
        '--asset-types',
        'json',
        '--font-types',
        'ttf',
      ],
      workingDirectory: genRootDir.path,
      runInShell: true,
    );

    await stdout.addStream(generateFont.stdout.map((bytes) {
      var message = utf8.decode(bytes);
      if (message == '\x1b[32mDone\x1b[39m\n') {
        message = '\x1b[32mFonte gerada com sucesso\x1b[39m\n';
      }
      return utf8.encode(message);
    }));
    final stdlib = 'Invalid member of stdlib';
    await stderr.addStream(generateFont.stderr
        .where((bytes) => !utf8.decode(bytes).contains(stdlib)));

    print('Copiando arquivo de ícones gerado...');
    await File(path.join(
      tempOutDirectory.path,
      path.basename(argResults!['out-font']),
    )).copy(outIconsFile.path);

    if (!outIconsFile.existsSync()) {
      await outIconsFile.create(recursive: true);
    }

    // Gerando a classe Flutter
    print('Gerando classe Flutter...');
    final generateClassResult = await generateFlutterClass(
      iconMap: iconsMap,
      className: argResults!['class-name'],
      packageName: argResults!['package'],
      namingStrategy: argResults!['naming-strategy'],
      indent: argResults!['indent'],
    );

    // Escrevendo a classe gerada
    await outFlutterClassFile.writeAsString(generateClassResult.content);
    print('Classe gerada com sucesso!');

    print('Ícones gerados: ${generateClassResult.iconsCount}');
    print('Arquivo gerado em: ${outFlutterClassFile.path}');

    // Deletando diretórios temporários
    await tempSourceDirectory.delete(recursive: true);
    await tempOutDirectory.delete(recursive: true);
  }
}
