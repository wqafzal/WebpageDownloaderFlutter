import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:download_webview/src/defaultFileSaver.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:path_provider/path_provider.dart';

import 'HtmlUtil.dart';
final htmlUtil = HtmlUtil(); // Create an instance of HtmlUtil
class WebpageDownloader {
  static const Map<String, String> HEADERS = {
    'User-Agent':
    'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.132 Mobile Safari/537.36'
  };

  Future<void> download(String url, FileSaver fileSaver, String path, String name) async {
    final http.Client client = http.Client();

    try {
      final String mainPage = await downloadPage(Uri.parse(url), client);
      final ParsedHtml parsedHtml = parseHtml(mainPage, Uri.parse(url));
      await fileSaver.saveText('$path/$name', parsedHtml.newHtml);

      final Set<DownloadInfo> filesToDownload = {...parsedHtml.filesToDownload};

      final List<DownloadInfo> cssList = [...parsedHtml.cssToDownload];
      while (cssList.isNotEmpty) {
        final DownloadInfo cssToDownload = cssList.removeAt(0);
        final String cssPage = await downloadPage(Uri.parse(cssToDownload.url), client);
        final ParsedCss parsedCss = parseCss(cssPage, Uri.parse(url));
        await fileSaver.saveText(cssToDownload.filename, parsedCss.newCss);
        cssList.addAll(parsedCss.cssToDownload);
        filesToDownload.addAll(parsedCss.filesToDownload);
      }

      await Future.wait(filesToDownload.map((fileToDownload) =>
          downloadFile(fileToDownload, fileSaver, client, path)));
    } finally {
      client.close();
    }
  }

  Future<String> downloadPage(Uri url, http.Client client) async {
    final response = await client.get(url, headers: HEADERS);
    return response.body;
  }

  Future<void> downloadFile(DownloadInfo fileToDownload, FileSaver fileSaver, http.Client client, String path) async {
    final response = await client.get(Uri.parse(fileToDownload.url), headers: HEADERS);
    await fileSaver.saveBinary(fileToDownload.filename, Stream.fromIterable([response.bodyBytes]),path);
  }

  ParsedHtml parseHtml(String htmlToParse, Uri baseUrl) {
    final document = html_parser.parse(htmlToParse, sourceUrl: baseUrl.toString());

    final title = document.head?.querySelector('title')?.text ?? '';
    removeBaseElements(document);
    updateAnchorsToAbsolutePath(document);

    final filesAndCss = findAndUpdateStylesheets(document, baseUrl);

    final Set<DownloadInfo> cssToDownload = {...filesAndCss.cssToDownload, ...findAndUpdateStylesheetLinks(document)};

    final Set<DownloadInfo> filesToDownload = {
      ...filesAndCss.filesToDownload,
      ...findAndUpdateScripts(document),
      ...findAndUpdateImages(document),
      ...findAndUpdateInputImages(document),
      ...findAndUpdateInlineStyles(document,baseUrl)
    };

    return ParsedHtml(title, document.outerHtml, filesToDownload, cssToDownload);
  }

  ParsedCss parseCss(String cssToParse, Uri baseUrl) {
    return htmlUtil.parseCssForUrlAndImport(cssToParse, baseUrl.toString());
  }

  void removeBaseElements(html_dom.Document document) {
    final bases = document.querySelectorAll('base[href]');
    bases.forEach((base) => base.remove());
  }

  void updateAnchorsToAbsolutePath(html_dom.Document document) {
    final anchors = document.querySelectorAll('a[href]');
    anchors.forEach((anchor) {
      final absUrl = anchor.attributes['abs:href'];
      if (absUrl != null && absUrl.startsWith('http')) {
        anchor.attributes['href'] = absUrl;
      }
    });
  }

  Set<DownloadInfo> findAndUpdateStylesheetLinks(html_dom.Document document) {
    final filesToDownload = <DownloadInfo>{};

    final links = document.querySelectorAll('link[href][rel=stylesheet]');
    for (final link in links) {
      final absUrl = link.attributes['abs:href'];
      if (absUrl != null && absUrl.startsWith('http')) {
        var newFileName = htmlUtil.urlToFileName(absUrl);
        if (!newFileName.endsWith('.css')) {
          newFileName += '.css';
        }
        filesToDownload.add(DownloadInfo(absUrl, newFileName));
        link.attributes['href'] = newFileName;
        link.attributes.remove('crossorigin');
        link.attributes.remove('integrity');
      }
    }
    return filesToDownload;
  }

  ToDownload findAndUpdateStylesheets(html_dom.Document document, Uri baseUrl) {
    final styles = document.querySelectorAll('style');
    final filesToDownload = <DownloadInfo>{};
    final cssToDownload = <DownloadInfo>{};

    for (final style in styles) {
      final cssToParse = style.text;

      final toDownloadAndCss = htmlUtil.parseCssForUrlAndImport(cssToParse, baseUrl.toString());
      filesToDownload.addAll(toDownloadAndCss.filesToDownload);
      cssToDownload.addAll(toDownloadAndCss.cssToDownload);

      // Clearing child nodes and setting text content
      style.nodes.clear();
      style.innerHtml = toDownloadAndCss.newCss;
    }
    return ToDownload(filesToDownload, cssToDownload);
  }




  Set<DownloadInfo> findAndUpdateInlineStyles(html_dom.Document document, Uri baseUrl) {
    final styles = document.querySelectorAll('[style]');
    final filesToDownload = <DownloadInfo>{};

    for (final style in styles) {
      final cssToParse = style.attributes['style'] ?? '';
      final cssAndLinks = htmlUtil.parseCssForUrl(cssToParse, baseUrl.toString());
      style.attributes['style'] = cssAndLinks.css;
      filesToDownload.addAll(cssAndLinks.links);
    }
    return filesToDownload;
  }



  Set<DownloadInfo> findAndUpdateScripts(html_dom.Document document) {
    return htmlUtil.findAndUpdateSrc(document, 'script[src]');
  }

  Set<DownloadInfo> findAndUpdateImages(html_dom.Document document) {
    return htmlUtil.findAndUpdateSrc(document, 'img[src]');
  }

  Set<DownloadInfo> findAndUpdateInputImages(html_dom.Document document) {
    return htmlUtil.findAndUpdateSrc(document, 'input[type=image]');
  }
}

class FileSaver {
  Future<void> saveText(String filename, String content,) async {
    final file = File(filename);
    await file.create(recursive: true);
    await file.writeAsString(content);
  }

  Future<void> saveBinary(String filename, Stream<List<int>> content, String path) async {
    final file = File('$path/$filename');
    await file.create(recursive: true);
    await file.openWrite().addStream(content);
  }
  // Future<void> saveText(String filename, String content) async {
  //   final file = File(filename);
  //   await file.create(recursive: true); // Ensure directory structure exists
  //   await file.writeAsString(content);
  // }
  //
  // Future<void> saveBinary(String filename, Uint8List content) async {
  //   var appDocDirOS;
  //   var path;
  //   if (Platform.isIOS) {
  //     appDocDirOS = await getApplicationDocumentsDirectory();
  //   }
  //   if (Platform.isIOS) {
  //     path = '${appDocDirOS?.path}/Skoop2';
  //   }
  //   final file = File('$path/$filename');
  //   await file.create(recursive: true); // Ensure directory structure exists
  //   await file.writeAsBytes(content);
  // }
}



class ToDownload {
  final Set<DownloadInfo> filesToDownload;
  final Set<DownloadInfo> cssToDownload;

  ToDownload(this.filesToDownload, this.cssToDownload);
}

class ParsedHtml {
  final String title;
  final String newHtml;
  final Set<DownloadInfo> filesToDownload;
  final Set<DownloadInfo> cssToDownload;

  ParsedHtml(this.title, this.newHtml, this.filesToDownload, this.cssToDownload);
}


