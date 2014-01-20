import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as pathos;

void main(List<String> args) {
  exit(new PubCacheCleaner().run(args));
}

class PubCacheCleaner {
  static const SEPARATOR = '----------------------------------------';

  bool _clean = false;
  bool _help = false;
  bool _displayTitleFoundApplication = true;

  int run(List<String> arguments) {
    _displayTitleFoundApplication = true;
    if(!_parseArguments(arguments)) {
      return -1;
    }

    if(_help) {
      return 0;
    }

    if(!_checkOperatingSystem()) {
      return _error('${_capitalize(Platform.operatingSystem)} operating system not supported');
    }

    var homePath = _getHomePath();
    if(homePath == null) {
      return _error('Cannot determine home path');
    }

    var cachePath = _getPubCachePath(homePath);
    if(!_isSubdir(homePath, cachePath)) {
      return _error('pub cache is located outside of the home directory');
    }

    stdout.writeln('Please be patient. Search Dart applications may take awhile.');
    _cleanOrList(homePath, cachePath);
    return 0;
  }

  String _capitalize(String name) {
    if(name == null || name.isEmpty) {
      return name;
    }

    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  bool _checkOperatingSystem() {
    switch(Platform.operatingSystem) {
      case 'linux':
      case 'macos':
        return true;
      default:
        return false;
    }
  }

  void _cleanOrList(String homePath, String cachePath) {
    var pubspecs = [];
    var links = new Set<String>();
    _findPubSpecs(homePath, new Set<String>(), pubspecs);
    for(var pubspec in pubspecs) {
      var appPath = pathos.dirname(pubspec);
      links.addAll(_findLinksToPackages(appPath, cachePath));
    }

    var cached = new Set<String>.from(_getCachedPackages(cachePath));
    for(var link in links) {
      if(cached.contains(link)) {
        cached.remove(link);
      }
    }

    if(cached.length == 0) {
      _displayTitle('The package cache does not contain obsolete packages');
      return;
    }

    var sorted = cached.toList();
    sorted.sort((e1, e2) => e1.compareTo(e2));
    if(!_clean) {
      _displayTitle('List of obsolete packages:');
      sorted.forEach((e) => stdout.writeln(e));
    } else {
      _displayTitle('List of removed packages:');
      for(var link in sorted) {
        var dir = new Directory(link);
        if(!dir.existsSync()) {
          continue;
        }

        try {
          dir.deleteSync(recursive: true);
          stdout.writeln(link);
        } catch(exception) {
        }
      }
    }
  }

  void _displayTitle(String title) {
    stdout.writeln(SEPARATOR);
    stdout.writeln(title);
    stdout.writeln(SEPARATOR);
  }

  int _error(String message) {
    stderr.writeln('Error: $message');
    return -1;
  }

  List<String> _findLinksToPackages(String appPath, String cachePath) {
    var subdirs = [];
    for(var entry in _listDirectory(appPath, recursive: true, followLinks: false)) {
      var entryPath = entry.path;
      if(FileSystemEntity.isDirectorySync(entryPath)) {
        if(pathos.basename(entryPath) == 'packages') {
          subdirs.add(entryPath);
        }
      }
    }

    var links = [];
    for(var subdir in subdirs) {
      var entries = _listDirectory(subdir);
      for(var entry in entries) {
        var entryPath = entry.path;
        if(FileSystemEntity.isLinkSync(entryPath)) {
          var link = entry as Link;
          var targetPath = link.targetSync();
          if(_isSubdir(cachePath, targetPath)) {
            if(pathos.basename(targetPath) == 'lib') {
              links.add(pathos.dirname(targetPath));
            }
          }
        }
      }
    }

    return links;
  }

  void _findPubSpecs(String path, Set<String> passed, List<String> pubspecs) {
    var entries = _listDirectory(path);
    var dirs = [];
    String pubspec = null;
    for(var entry in entries) {
      var entryPath = entry.path;
      if(FileSystemEntity.isFileSync(entryPath)) {
        if(pathos.basename(entryPath) == 'pubspec.yaml') {
          pubspec = entryPath;
          break;
        }
      }

      if(FileSystemEntity.isDirectorySync(entryPath)) {
        if(!passed.contains(entryPath)) {
          passed.add(entryPath);
          dirs.add(entryPath);
        }
      }
    }

    if(pubspec != null) {
      if(_displayTitleFoundApplication) {
        _displayTitle('List of found packages:');
        _displayTitleFoundApplication = false;
      }

      pubspecs.add(pubspec);
      stdout.writeln(path);
    } else {
      for(var dir in dirs) {
        _findPubSpecs(dir, passed, pubspecs);
      }
    }
  }

  String _getHomePath() {
    var home = Platform.environment['HOME'];
    if(home != null) {
      return pathos.normalize(home);
    } else {
      return null;
    }
  }

  List<String> _getCachedPackages(String cachePath) {
    var results = [];
    results.addAll(_getGitPackages(cachePath));
    results.addAll(_getHostedPackages(cachePath));
    return results;
  }

  List<String> _getDirectories(String path) {
    var entries = _listDirectory(path);
    var results = [];
    for(var entry in entries) {
      var entryPath = entry.path;
      if(FileSystemEntity.isDirectorySync(entryPath)) {
        results.add(entryPath);
      }
    }

    return results;
  }

  List<String> _getGitPackages(String cachePath) {
    var gitPath = pathos.join(cachePath, 'git');
    var results = [];
    results.addAll(_getDirectories(gitPath));
    results.remove(pathos.join(gitPath, 'cache'));
    return results;
  }

  List<String> _getHostedPackages(String cachePath) {
    var hostedPath = pathos.join(cachePath, 'hosted');
    var dirs = _getDirectories(hostedPath);
    var results = [];
    for(var dir in dirs) {
      results.addAll(_getDirectories(pathos.normalize(dir)));
    }

    return results;
  }

  String _getPubCachePath(String homePath) {
    var pubCache = Platform.environment['PUB_CACHE'];
    if(pubCache != null) {
      return  pathos.normalize(pubCache);
    } else {
      return pathos.join(homePath, '.pub-cache');
    }
  }

  bool _isSubdir(String dir, String subdir) {
    var segments1 = pathos.split(dir);
    var segments2 = pathos.split(subdir);
    var length = segments1.length;
    if(length > segments2.length) {
      return false;
    }

    for(var i = 0; i < length; i++) {
      if(segments1[i] != segments2[i]) {
        return false;
      }
    }

    return true;
  }

  List<FileSystemEntity> _listDirectory(String path, {bool followLinks: false,
    bool recursive: false}) {
    var entries = [];
    var dir = new Directory(path);
    try {
      entries = dir.listSync(followLinks: followLinks, recursive: recursive);
    } catch(exception) {
      return entries;
    }

    return entries;
  }

  bool _parseArguments(List<String> arguments) {
    ArgResults argumentResults;
    var parser = new ArgParser();
    parser.addFlag('help', help: 'Display help');
    parser.addFlag('clean', help: 'Clean cache');

    try {
      argumentResults = parser.parse(arguments);
    } on FormatException catch (exception) {
      stdout.writeln(exception.message);
      _printUsage(parser);
      return false;
    } catch(e) {
      throw(e);
    }

    if(argumentResults != null) {
      if(argumentResults['clean'] != null) {
        _clean = argumentResults['clean'];
      }

      if(argumentResults['help'] != null) {
        _help = argumentResults['help'];
        if(_help) {
          _printUsage(parser);
        }
      }
    }

    return true;
  }

  void _printUsage(ArgParser parser) {
    stdout.writeln('Usage:');
    stdout.writeln(parser.getUsage());
  }
}
