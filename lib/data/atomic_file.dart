import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:uuid/uuid.dart';

typedef _MoveNative = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _MoveDart = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _ErrorNative = Uint32 Function();
typedef _ErrorDart = int Function();

/// Replace in the same directory without deleting the destination first.
class AtomicFile {
  static final _kernel = Platform.isWindows
      ? DynamicLibrary.open('kernel32.dll')
      : null;
  static final _move = _kernel?.lookupFunction<_MoveNative, _MoveDart>(
    'MoveFileExW',
    isLeaf: true,
  );
  static final _lastError = _kernel?.lookupFunction<_ErrorNative, _ErrorDart>(
    'GetLastError',
    isLeaf: true,
  );

  static Future<void> write(File destination, List<int> bytes) async {
    final temporary = File('${destination.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      if (!Platform.isWindows) {
        await temporary.rename(destination.path);
        return;
      }
      final source = temporary.absolute.path.toNativeUtf16();
      final target = destination.absolute.path.toNativeUtf16();
      // Resolve both lazy symbols before MoveFileEx sets thread-local last error.
      final move = _move!;
      final lastError = _lastError!;
      try {
        for (var attempt = 0; ; attempt++) {
          // MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
          if (move(source, target, 0x9) != 0) break;
          final error = lastError();
          if (attempt == 3 || (error != 5 && error != 32 && error != 33)) {
            throw FileSystemException(
              '无法替换文件，请关闭占用此文件的程序。',
              destination.path,
              OSError('Windows', error),
            );
          }
          await Future<void>.delayed(
            Duration(milliseconds: 50 * (attempt + 1)),
          );
        }
      } finally {
        calloc.free(source);
        calloc.free(target);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
