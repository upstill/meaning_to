// Stub implementation for non-web platforms
class WebFilePicker {
  static Future<Map<String, dynamic>> pickFile() async {
    throw UnsupportedError('Web file picker is not available on this platform');
  }
}
