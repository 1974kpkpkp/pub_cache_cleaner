import "dart:io";
import "package:args/args.dart";
import "package:globbing/globbing.dart";
import "package:file_utils/file_utils.dart";

void main(List<String> args) {
  exit(new PubCacheCleaner().run(args));
}

class PubCacheCleaner {
  static const SEPARATOR = '----------------------------------------';

  bool _clean = false;

  bool _help = false;

  int run(List<String> arguments) {
    if (!_parseArguments(arguments)) {
      return -1;
    }

    if (_help) {
      return 0;
    }

    var cachePath = _getPubCachePath();
    var mask = "~/{.*,*}**";
    mask = FilePath.expand(mask);
    var glob = new Glob(mask);
    if (!glob.match(cachePath)) {
      return _error("pub cache is located outside of the home directory.");
    }

    stdout.writeln(
        "Please be patient. Search Dart applications may take awhile.");
    _cleanOrList(cachePath);
    return 0;
  }

  void _cleanOrList(String cachePath) {
    var pubspecs = FileUtils.glob("~/**/pubspec.yaml");
    if (pubspecs.isEmpty) {
      _displayTitle("Dart applications not found.");
      return;
    }

    // Remove cached packages from list
    var cacheGlob = new Glob(cachePath + "/**");
    var applications = new List<String>();
    for (var pubspec in pubspecs) {
      if (!cacheGlob.match(pubspec)) {
        applications.add(pubspec);
      }
    }

    _displayTitle("List of found applications:");
    for (var application in applications) {
      stdout.writeln(application);
    }

    var references = new Set<String>();
    for (var application in applications) {
      var appPath = FileUtils.dirname(application);
      references.addAll(_findLinksToPackages(appPath, cacheGlob));
    }

    var cachedPackages = new Set<String>.from(_getCachedPackages(cachePath));
    for (var reference in references) {
      if (cachedPackages.contains(reference)) {
        cachedPackages.remove(reference);
      }
    }

    if (cachedPackages.length == 0) {
      _displayTitle("The package cache does not contain obsolete packages");
      return;
    }

    var sorted = cachedPackages.toList();
    sorted.sort((e1, e2) => e1.compareTo(e2));
    if (!_clean) {
      _displayTitle("List of obsolete packages:");
      sorted.forEach((e) => stdout.writeln(e));
    } else {
      _displayTitle("List of removed packages:");
      for (var link in sorted) {
        var dir = new Directory(link);
        if (!dir.existsSync()) {
          continue;
        }

        try {
          dir.deleteSync(recursive: true);
          stdout.writeln(link);
        } catch (exception) {
        }
      }

      _clearGitCache();
    }
  }

  void _clearGitCache() {
    // Not implemented
  }

  void _displayTitle(String title) {
    stdout.writeln(SEPARATOR);
    stdout.writeln(title);
    stdout.writeln(SEPARATOR);
  }

  int _error(String message) {
    stderr.writeln("Error: $message");
    return -1;
  }

  List<String> _findLinksToPackages(String appPath, Glob cacheGlob) {
    var links = [];
    var packages = FileUtils.glob(appPath + "/packages/*/");
    for (var package in packages) {
      var link = new Link(package);
      if (link.existsSync()) {
        var targetPath = link.targetSync();
        if (cacheGlob.match(targetPath)) {
          if (FileUtils.basename(targetPath) == "lib") {
            links.add(FileUtils.dirname(targetPath));
          }
        }
      }
    }

    return links;
  }

  List<String> _getCachedPackages(String cachePath) {
    var results = [];
    results.addAll(_getGitPackages(cachePath));
    results.addAll(_getHostedPackages(cachePath));
    return results;
  }

  List<String> _getGitPackages(String cachePath) {
    var packages = FileUtils.glob(cachePath + "/git/*/");
    var glob = new Glob(cachePath + "/git/cache");
    var result = [];
    for (var package in packages) {
      if (!glob.match(package)) {
        result.add(package);
      }
    }

    return result;
  }

  List<String> _getHostedPackages(String cachePath) {
    var packages = FileUtils.glob(cachePath + "/hosted/*/*/");
    return packages;
  }

  String _getPubCachePath() {
    var result = Platform.environment["PUB_CACHE"];
    if (result != null) {
      return result;
    }

    if (Platform.isWindows) {
      result = FilePath.expand(r"$APPDATA/Pub/Cache");
    } else {
      result = FilePath.expand("~/.pub-cache");
    }

    return result;
  }

  bool _parseArguments(List<String> arguments) {
    ArgResults argumentResults;
    var parser = new ArgParser();
    parser.addFlag("help", help: "Display help");
    parser.addFlag("clean", help: "Clean cache");

    try {
      argumentResults = parser.parse(arguments);
    } on FormatException catch (exception) {
      stdout.writeln(exception.message);
      _printUsage(parser);
      return false;
    } catch (e) {
      throw (e);
    }

    if (argumentResults != null) {
      if (argumentResults["clean"] != null) {
        _clean = argumentResults["clean"];
      }

      if (argumentResults["help"] != null) {
        _help = argumentResults["help"];
        if (_help) {
          _printUsage(parser);
        }
      }
    }

    return true;
  }

  void _printUsage(ArgParser parser) {
    stdout.writeln("Usage:");
    stdout.writeln(parser.getUsage());
  }
}
