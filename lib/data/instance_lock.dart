import 'dart:io';

/// Same first-byte exclusive lock as the original Windows Python launcher.
class InstanceLock {
  InstanceLock._(this._file);
  RandomAccessFile? _file;

  static InstanceLock acquire(Directory directory) {
    directory.createSync(recursive: true);
    final file = File(
      '${directory.path}/.daymark.lock',
    ).openSync(mode: FileMode.append);
    try {
      if (file.lengthSync() == 0) {
        file.writeByteSync(48);
        file.flushSync();
      }
      file.lockSync(FileLock.exclusive, 0, 1);
      return InstanceLock._(file);
    } on FileSystemException {
      file.closeSync();
      throw const FormatException('这个数据目录已由另一个 Daymark 窗口打开，请切换到已有窗口。');
    }
  }

  void close() {
    _file?.closeSync();
    _file = null;
  }
}
