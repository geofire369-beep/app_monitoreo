import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveBytes({
  required List<int> bytes,
  required String filename,
}) async {
  final blob = html.Blob([Uint8List.fromList(bytes)]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
