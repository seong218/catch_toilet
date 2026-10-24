import 'dart:io';

// Run with `dart tool/bootstrap.dart` from a machine with Flutter on PATH.
// Platform projects come from that machine's official Flutter SDK templates.
// Existing app code and existing platform projects are never overwritten.
Future<void> main() async {
  final app = File.fromUri(Platform.script).absolute.parent.parent;
  if (!File('${app.path}/pubspec.yaml').existsSync()) {
    stderr.writeln(
      'Run this script from the Catchy Toilet app/tool directory.',
    );
    exitCode = 1;
    return;
  }
  final missing = [
    'android',
    'ios',
    'web',
  ].where((name) => !Directory('${app.path}/$name').existsSync()).toList();
  try {
    if (missing.isNotEmpty) {
      final seed = Directory(
        '${app.path}/.tools/platform_seed_'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      await seed.parent.create(recursive: true);
      final generated = await runFlutter([
        'create',
        '--empty',
        '--no-pub',
        '--platforms=${missing.join(',')}',
        '--project-name=catchy_toilet',
        '--org=dev.catchytoilet',
        seed.path,
      ], app.path);
      if (generated != 0) {
        exitCode = generated;
        return;
      }
      for (final name in missing) {
        final source = Directory('${seed.path}/$name');
        final destination = Directory('${app.path}/$name');
        if (!source.existsSync() || destination.existsSync()) {
          throw FileSystemException('Cannot safely install platform: $name');
        }
        await source.rename(destination.path);
      }
      final metadata = File('${seed.path}/.metadata');
      if (metadata.existsSync() &&
          !File('${app.path}/.metadata').existsSync()) {
        await metadata.copy('${app.path}/.metadata');
      }
      stdout.writeln(
        'Generated: ${missing.join(', ')}. Existing lib/ preserved.',
      );
    }
    exitCode = await runFlutter(['pub', 'get'], app.path);
    if (exitCode == 0) {
      stdout.writeln('Ready. Run: flutter run -d <device-id>');
    }
  } on ProcessException catch (error) {
    stderr.writeln(
      'Flutter could not start. Add the Flutter SDK bin directory '
      'to PATH, then run this script again.\n$error',
    );
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

Future<int> runFlutter(List<String> arguments, String workingDirectory) async {
  final process = await Process.start(
    'flutter',
    arguments,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
