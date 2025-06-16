import 'dart:async';
import 'package:meaning_to/utils/text_importer.dart';

/// A helper class that exposes private methods of TextImporter for testing
class TextImporterTestHelper {
  /// Exposes the private _parsePlainTextItem method
  static ImportItem? parsePlainTextItem(String text) {
    return TextImporter._parsePlainTextItem(text);
  }

  /// Exposes the private _parseJsonItem method
  static ImportItem? parseJsonItem(Map<String, dynamic> json) {
    return TextImporter._parseJsonItem(json);
  }

  /// Exposes the private _processTextData method
  static Future<void> processTextData(
    String textData,
    ImportContext context,
    StreamController<ImportItem> controller,
  ) async {
    await TextImporter._processTextData(textData, context, controller);
  }

  /// Exposes the private _processForNewCategory method
  static Future<void> processForNewCategory(
    String textData,
    StreamController<ImportItem> controller,
  ) async {
    await TextImporter._processForNewCategory(textData, controller);
  }

  /// Exposes the private _processForAddToCategory method
  static Future<void> processForAddToCategory(
    String textData,
    StreamController<ImportItem> controller,
  ) async {
    await TextImporter._processForAddToCategory(textData, controller);
  }

  /// Exposes the private _processForAddToTask method
  static Future<void> processForAddToTask(
    String textData,
    StreamController<ImportItem> controller,
  ) async {
    await TextImporter._processForAddToTask(textData, controller);
  }
}
