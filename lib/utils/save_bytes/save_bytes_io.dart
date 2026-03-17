import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> saveBytes({
  required List<int> bytes,
  required String filename,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
}
