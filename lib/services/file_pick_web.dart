// Web 平台文件选择：点击隐藏 input 选择文件，读为字节。
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// 弹出文件选择框，读取用户选中的文件字节。
/// [accept] 可指定扩展名（账单 .csv/.xlsx/.txt；备份 .json）。
/// 返回 (文件名, 文件字节)；用户取消/失败返回 null。
/// 防死锁设计：回调全 try/catch、读取 onError 竞速、取消检测（窗口焦点恢复）、
/// 60s 绝对超时兜底。
Future<({String name, Uint8List bytes})?> pickBillFile(
    {String accept = '.csv,.xlsx,.txt'}) async {
  final completer = Completer<({String name, Uint8List bytes})?>();
  var changed = false; // 是否已收到过文件 change

  final input = html.FileUploadInputElement()
    ..accept = accept
    ..style.display = 'none';
  html.document.body?.append(input);

  Timer? cancelTimer;

  void finish(({String name, Uint8List bytes})? result) {
    cancelTimer?.cancel();
    if (!completer.isCompleted) completer.complete(result);
  }

  // 用户取消检测：文件对话框关闭时窗口重新聚焦；
  // 若此后从未收到 change（说明用户没选文件而是取消），判为取消
  void armCancelDetect() {
    html.window.onFocus.first.then((_) {
      cancelTimer = Timer(const Duration(milliseconds: 800), () {
        if (!changed) finish(null);
      });
    });
  }

  input.onChange.first.then((_) async {
    changed = true;
    cancelTimer?.cancel();
    try {
      final file = input.files!.isEmpty ? null : input.files!.first;
      if (file == null) {
        finish(null);
        return;
      }
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await Future.any([
        reader.onLoad.first.then((_) {
          final result = reader.result;
          // dart:html 在不同版本/平台把结果包装为 Uint8List 或 ByteBuffer
          if (result is Uint8List) {
            finish((name: file.name, bytes: result));
          } else if (result is ByteBuffer) {
            finish((name: file.name, bytes: result.asUint8List()));
          } else {
            finish(null);
          }
        }),
        reader.onError.first.then((_) => finish(null)),
      ]);
    } catch (_) {
      finish(null);
    }
  });

  input.click();
  armCancelDetect();

  final result = await completer.future
      .timeout(const Duration(seconds: 60), onTimeout: () => null);
  input.remove();
  return result;
}
