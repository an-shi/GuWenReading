import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_database.dart';

class DataDirectoryService {
  Future<void> migrate({
    required AppPaths current,
    required String targetPath,
  }) async {
    final source = p.normalize(p.absolute(current.root.path));
    final target = p.normalize(p.absolute(targetPath));
    if (p.equals(source, target)) {
      throw DataDirectoryException('新目录与当前目录相同');
    }
    if (p.isWithin(source, target) || p.isWithin(target, source)) {
      throw DataDirectoryException('新旧目录不能互相包含');
    }

    final targetDir = Directory(target);
    await targetDir.create(recursive: true);
    if (await File(p.join(target, 'guwen.db')).exists() ||
        await Directory(p.join(target, 'books')).exists() ||
        await Directory(p.join(target, 'covers')).exists()) {
      throw DataDirectoryException('目标目录包含旧版数据，请选择空目录或新建子目录');
    }
    final sourceLibrary = Directory(p.join(source, 'library'));
    final sourceDatabase = Directory(p.join(source, 'database'));
    final targetLibrary = Directory(p.join(target, 'library'));
    final targetDatabase = Directory(p.join(target, 'database'));
    await targetDatabase.create(recursive: true);
    if (await sourceLibrary.exists()) {
      await _copyDirectory(sourceLibrary, targetLibrary);
    }
    if (await sourceDatabase.exists()) {
      await _copyDirectory(sourceDatabase, targetDatabase);
    }
    // Compatibility with data roots created before the library/database split.
    for (final name in ['books', 'covers', 'backups', 'tmp']) {
      final dir = Directory(p.join(source, name));
      if (await dir.exists()) {
        await _copyDirectory(dir, Directory(p.join(targetLibrary.path, name)));
      }
    }
    for (final name in ['guwen.db', 'guwen.db-wal', 'guwen.db-shm']) {
      final file = File(p.join(source, name));
      if (await file.exists()) {
        await file.copy(p.join(targetDatabase.path, name));
      }
    }

    final sourceDb = File(current.dbPath);
    if (await sourceDb.exists()) {
      final relativeDb = p.relative(current.dbPath, from: source);
      final targetDb = File(p.join(target, relativeDb));
      if (!await targetDb.exists()) {
        throw DataDirectoryException('数据库复制失败，未切换数据目录');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppPaths.dataRootKey, target);

    // Never delete the whole data root: on desktop it may also contain the
    // Flutter runtime bundle (flutter_assets/data). Only remove our own data.
    await _deleteQuietly(sourceLibrary);
    await _deleteQuietly(sourceDatabase);
    for (final name in ['books', 'covers', 'backups', 'tmp']) {
      await _deleteQuietly(Directory(p.join(source, name)));
    }
    for (final name in ['guwen.db', 'guwen.db-wal', 'guwen.db-shm']) {
      await _deleteQuietly(File(p.join(source, name)));
    }
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (!await entity.exists()) return;
      if (entity is Directory) {
        await entity.delete(recursive: true);
      } else {
        await entity.delete();
      }
    } catch (_) {
      // The new copy is already usable; a locked old file can be removed later.
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final destination = File(p.join(target.path, relative));
      if (entity is File) {
        await destination.parent.create(recursive: true);
        await entity.copy(destination.path);
      } else if (entity is Directory) {
        await Directory(p.join(target.path, relative)).create(recursive: true);
      }
    }
  }

  Future<void> restartApp() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await Process.start(
        Platform.resolvedExecutable,
        const [],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }
    await SystemNavigator.pop();
  }
}

class DataDirectoryException implements Exception {
  DataDirectoryException(this.message);
  final String message;
  @override
  String toString() => message;
}
