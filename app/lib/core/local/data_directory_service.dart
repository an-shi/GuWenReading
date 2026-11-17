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
    await _copyDirectory(Directory(source), targetDir);

    final sourceDb = File(p.join(source, 'guwen.db'));
    if (await sourceDb.exists()) {
      final targetDb = File(p.join(target, 'guwen.db'));
      if (!await targetDb.exists()) {
        throw DataDirectoryException('数据库复制失败，未切换数据目录');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppPaths.dataRootKey, target);

    try {
      await Directory(source).delete(recursive: true);
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
