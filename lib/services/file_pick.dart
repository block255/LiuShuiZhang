// 平台文件选择：Web = dart:html；Android(io) = 系统 SAF 选择器。
export 'file_pick_stub.dart'
    if (dart.library.html) 'file_pick_web.dart'
    if (dart.library.io) 'file_pick_io.dart';
