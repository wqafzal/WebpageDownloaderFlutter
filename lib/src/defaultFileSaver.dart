import 'dart:io';
import 'dart:async';

import 'package:download_webview/src/webPageDownloader.dart';

class DefaultFileSaver extends FileSaver {
  late final Directory _outputDir;

  DefaultFileSaver(Directory outputDir) {
    _outputDir = outputDir;
    _outputDir.createSync(recursive: true);
  }

  Future<void> save(String filename, String content) async {
    final file = File('${_outputDir.path}/Skoop/$filename');
    await file.writeAsString(content);
  }

  Future<void> saveStream(String filename, Stream<List<int>> content) async {
    final file = File('${_outputDir.path}/Skoop/$filename');
    await file.openWrite().addStream(content);
  }
}

// abstract class FileSaver {
//   Future<void> save(String filename, String content);
//   Future<void> saveStream(String filename, Stream<List<int>> content);
// }
