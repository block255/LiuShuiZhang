import 'dart:typed_data';

/// 非 Web 平台的占位实现（安卓真机用系统 SAF 选择器）
/// 返回 (文件名, 文件字节)；用户取消返回 null。
Future<({String name, Uint8List bytes})?> pickBillFile(
    {String accept = '.csv,.xlsx,.txt'}) async {
  throw UnsupportedError('文件选择在非 Web 平台暂未接入（真机阶段实现）');
}
