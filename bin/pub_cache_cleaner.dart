import 'dart:io';
import 'package:args/args.dart';

void main() {
  exit(new PubCacheCleaner().run());
}

class PubCacheCleaner {
  bool _clean = false;
  bool _help = false;

  int run() {
    if(!_parseArguments()) {
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

  void _cleanOrList(Path homePath, Path cachePath) {
    var pubspecs = [];
    var links = new Set<String>();
    _findPubSpecs(homePath, new Set<String>(), pubspecs);
    for(var pubspec in pubspecs) {
      var appPath = new Path(pubspec).directoryPath;
      links.addAll(_findLinksToPackages(appPath, cachePath));
    }

    var cached = new Set<String>.from(_getCachedPackages(cachePath));
    for(var link in links) {
      if(cached.contains(link)) {
        cached.remove(link);
      }
    }

    if(cached.length == 0) {
      stdout.writeln('The package cache does not contain obsolete packages');
      return;
    }

    var sorted = cached.toList();
    sorted.sort((e1, e2) => e1.compareTo(e2));
    if(!_clean) {
      stdout.writeln('List of obsolete packages:');
      sorted.forEach((e) => stdout.writeln(e));
    } else {
      stdout.writeln('List of removed packages:');
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

  int _error(String message) {
    stderr.writeln('Error: $message');
    return -1;
  }

  List<String> _findLinksToPackages(Path appPath, Path cachePath) {
    var subdirs = const ['bin', 'example', 'test', 'tool', 'web'];
    var links = [];
    for(var subdir in subdirs) {
      var path = appPath.append(subdir).append('packages');
      var dir = new Directory.fromPath(path);
      if(!dir.existsSync()) {
        continue;
      }

      var entries = _listDirectory(path);
      for(var entry in entries) {
        var entryPath = entry.path;
        if(FileSystemEntity.isLinkSync(entryPath)) {
          var link = entry as Link;
          var targetPath = new Path(link.targetSync());
          if(_isSubdir(cachePath, targetPath)) {
            if(targetPath.filename == 'lib') {
              links.add(targetPath.directoryPath.toString());
            }
          }
        }
      }
    }

    return links;
  }

  void _findPubSpecs(Path path, Set<String> passed, List<String> pubspecs) {
    var entries = _listDirectory(path);
    var dirs = [];
    String pubspec = null;
    for(var entry in entries) {
      var entryPath = entry.path;
      if(FileSystemEntity.isFileSync(entryPath)) {
        if(new Path(entryPath).filename == 'pubspec.yaml') {
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
      pubspecs.add(pubspec);
    } else {
      for(var dir in dirs) {
        _findPubSpecs(new Path(dir), passed, pubspecs);
      }
    }
  }

  Path _getHomePath() {
    var home = Platform.environment['HOME'];
    if(home != null) {
      return new Path(home);
    } else {
      return null;
    }
  }

  List<String> _getCachedPackages(Path cachePath) {
    var results = [];
    results.addAll(_getGitPackages(cachePath));
    results.addAll(_getHostedPackages(cachePath));
    return results;
  }

  List<String> _getDirectories(Path path) {
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

  List<String> _getGitPackages(Path cachePath) {
    var gitPath = cachePath.append('git');
    var results = [];
    results.addAll(_getDirectories(gitPath));
    results.remove(gitPath.append('cache').toString());
    return results;
  }

  List<String> _getHostedPackages(Path cachePath) {
    var hostedPath = cachePath.append('hosted');
    var dirs = _getDirectories(hostedPath);
    var results = [];
    for(var dir in dirs) {
      results.addAll(_getDirectories(new Path(dir)));
    }

    return results;
  }

  Path _getPubCachePath(Path homePath) {
    var pubCache = Platform.environment['PUB_CACHE'];
    if(pubCache != null) {
      return new Path(pubCache);
    } else {
      return homePath.append('.pub-cache');
    }
  }

  bool _isSubdir(Path dir, Path subdir) {
    var segments1 = dir.segments();
    var segments2 = subdir.segments();
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

  List<FileSystemEntity> _listDirectory(Path path, {bool followLinks: false,
    bool recursive: false}) {
    var entries = [];
    var dir = new Directory.fromPath(path);
    try {
      entries = dir.listSync(followLinks: followLinks, recursive: recursive);
    } catch(exception) {
      return entries;
    }

    return entries;
  }

  bool _parseArguments() {
    var arguments = new Options().arguments;
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
