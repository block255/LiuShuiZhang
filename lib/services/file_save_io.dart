import 'package:flutter/services.dart';

/// Android（dart:io）文件保存：走系统"保存到"对话框
/// （SAF ACTION_CREATE_DOCUMENT，用户自选文件夹/文件名，零存储权限）。
/// 用户取消抛 StateError；非安卓（无原生通道）抛 UnsupportedError。
Future<void> saveTextFile(String fileName, String content) async {
  try {
    final ok = await const MethodChannel('lsz_file')
        .invokeMethod<bool>('saveTextFile', {
      'fileName': fileName,
      'content': content,
    });
    if (ok != true) {
      throw StateError('已取消保存');
    }
  } on MissingPluginException {
    throw UnsupportedError('文件保存仅支持 Web / 安卓真机');
  }
}
