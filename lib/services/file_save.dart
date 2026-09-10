// 平台文件保存：Web = Blob 下载；Android(io) = 系统"保存到"对话框（SAF）。
export 'file_save_stub.dart'
    if (dart.library.html) 'file_save_web.dart'
    if (dart.library.io) 'file_save_io.dart';
