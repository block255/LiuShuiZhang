import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Android（dart:io）文件选择：系统文件选择器（SAF ACTION_OPEN_DOCUMENT），
/// 用户自选任意位置的文件（账单导入 / JSON 备份恢复共用）。
/// 返回 (文件名, 文件字节)；取消返回 null；非安卓抛 UnsupportedError。
Future<({String name, Uint8List bytes})?> pickBillFile(
    {String accept = '.csv,.xlsx,.txt'}) async {
  try {
    final r = await const MethodChannel('lsz_file')
        .invokeMethod<Map<dynamic, dynamic>>('pickFile');
    if (r == null) return null;
    final name = (r['name'] as String?) ?? 'file';
    final bytes = r['bytes'];
    if (bytes is Uint8List) return (name: name, bytes: bytes);
    if (bytes is ByteBuffer) {
      return (name: name, bytes: bytes.asUint8List());
    }
    if (bytes is List<int>) {
      return (name: name, bytes: Uint8List.fromList(bytes));
    }
    return null;
  } on MissingPluginException {
    throw UnsupportedError('文件选择仅支持 Web / 安卓真机');
  }
}
