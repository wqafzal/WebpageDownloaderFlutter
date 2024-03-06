import 'dart:math';
import 'package:html/dom.dart' as html_dom;

class DownloadInfo {
  final String url;
  final String filename;

  DownloadInfo(this.url, this.filename);
}

class ParsedCss {
  final String newCss;
  final Set<DownloadInfo> filesToDownload;
  final Set<DownloadInfo> cssToDownload;

  ParsedCss(this.newCss, this.filesToDownload, this.cssToDownload);
}

class CssAndLinks {
  final String css;
  final Set<DownloadInfo> links;

  CssAndLinks(this.css, this.links);
}

class HtmlUtil {
  final RegExp FILE_NAME_SANITIZE_PATTERN = RegExp(r'[^a-zA-Z0-9-_.]');
  final RegExp URL_PATTERN = RegExp(r'''url\s*\(\s*['"]?\s*(.*?)\s*['"]?\s*\)''');
  final RegExp IMPORT_PATTERN = RegExp(r'''@import\s*['"]\s*(.*)\s*['"]\s*''');

  Set<DownloadInfo> findAndUpdateSrc(html_dom.Document document, String cssQuery) {
    final links = document.querySelectorAll(cssQuery);
    final filesToDownload = <DownloadInfo>{};

    for (var link in links) {
      final absUrl = link.attributes['abs:src'];
      if (absUrl == null || !absUrl.startsWith('http')) continue;
      final newFileName = urlToFileName(absUrl);
      filesToDownload.add(DownloadInfo(absUrl, newFileName));
      link.attributes['src'] = newFileName;
      link.attributes.remove('srcset');
      link.attributes.remove('crossorigin');
      link.attributes.remove('integrity');
    }
    return filesToDownload;
  }

  ParsedCss parseCssForUrlAndImport(String cssToParse, String baseUrl) {
    final filesToDownload = <DownloadInfo>{};
    final cssToDownload = <DownloadInfo>{};

    final cssAndLinks = parseCssForPattern(cssToParse, baseUrl, URL_PATTERN);
    for (var entry in cssAndLinks.links) {
      if (entry.filename.endsWith('.css')) {
        cssToDownload.add(entry);
      } else {
        filesToDownload.add(entry);
      }
    }

    final cssAndCssLinks = parseCssForPattern(cssAndLinks.css, baseUrl, IMPORT_PATTERN);
    cssToDownload.addAll(cssAndCssLinks.links);
    return ParsedCss(cssAndCssLinks.css, filesToDownload, cssToDownload);
  }

  CssAndLinks parseCssForUrl(String cssToParse, String baseUrl) {
    return parseCssForPattern(cssToParse, baseUrl, URL_PATTERN);
  }

  CssAndLinks parseCssForPattern(String cssToParse, String baseUrl, RegExp pattern) {
    var css = cssToParse;
    final links = <DownloadInfo>{};

    final matcher = pattern.allMatches(css);
    final sb = StringBuffer();
    for (var match in matcher) {
      final matchValue = match.group(1);
      if (matchValue == null || matchValue.startsWith('data:image/')) continue;
      final absMatch = resolve(Uri.parse(baseUrl), matchValue);
      final filename = urlToFileName(absMatch);
      final replacement = match.group(0)!.replaceFirst(matchValue, filename);
      sb.write(replacement);
      links.add(DownloadInfo(absMatch, filename));
    }
    css = sb.toString();

    return CssAndLinks(css, links);
  }

  String urlToFileName(String url) {
    var filename = url.substring(url.lastIndexOf('/') + 1);
    filename = filename.substring(max(filename.length - 90, 0));
    final hash = url.hashCode.abs;

    if (filename.contains('?')) {
      filename = filename.substring(0, filename.indexOf('?'));
    }
    late String extension;
    if (filename.contains('.')) {
      extension = filename.substring(filename.lastIndexOf('.'));
      filename = filename.substring(0, filename.lastIndexOf('.'));
    } else {
      extension = '.$filename';
      filename = 'no-name';
    }
    filename = '${filename}-${hash}${extension}';
    filename = FILE_NAME_SANITIZE_PATTERN.allReplace(filename, '_');

    return filename;
  }

  String resolve(Uri base, String relUrl) {
    try {
      return base.resolve(relUrl).toString();
    } catch (e) {
      return '';
    }
  }
}

extension RegExpReplaceAll on RegExp {
  String allReplace(String input, String replacement) {
    return allMatches(input).fold(
      input,
          (result, match) => result.replaceRange(match.start, match.end, replacement),
    );
  }
}
