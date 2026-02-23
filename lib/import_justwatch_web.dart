import 'dart:html' as html;

// Web-specific implementation for file picking
class WebFilePicker {
  static Future<Map<String, dynamic>> pickFile() async {
    // Create a file input element
    final input = html.FileUploadInputElement()
      ..accept = '.json'
      ..click();

    // Wait for file selection
    await input.onChange.first;

    if (input.files?.isEmpty ?? true) {
      throw Exception('No file selected');
    }

    final file = input.files!.first;

    // Read file content
    final reader = html.FileReader();
    reader.readAsText(file);

    await reader.onLoad.first;

    final contents = reader.result as String;

    return {
      'name': file.name,
      'contents': contents,
    };
  }
}
