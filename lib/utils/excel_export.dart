import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../models/report_models.dart';

class ExcelExport {
  static Uint8List buildIncidenceExcel(ReportPayload payload) {
    final excel = Excel.createExcel();
    final sheet = excel['Incidencia'];

    sheet.appendRow([TextCellValue("Invernadero"), TextCellValue(payload.greenhouseName)]);
    sheet.appendRow([TextCellValue("Desde"), TextCellValue(payload.from.toIso8601String())]);
    sheet.appendRow([TextCellValue("Hasta"), TextCellValue(payload.to.toIso8601String())]);
    sheet.appendRow([TextCellValue("")]);

    sheet.appendRow([
      TextCellValue("Plaga/Enfermedad"),
      TextCellValue("Plantas evaluadas"),
      TextCellValue("Plantas afectadas"),
      TextCellValue("Incidencia %"),
      TextCellValue("Umbral"),
      TextCellValue("Estado"),
    ]);

    for (final r in payload.rows) {
      sheet.appendRow([
        TextCellValue(r.pestName),
        IntCellValue(r.plantsChecked),
        IntCellValue(r.plantsAffected),
        DoubleCellValue(double.parse(r.incidencePercent.toStringAsFixed(2))),
        r.threshold == null ? TextCellValue("—") : DoubleCellValue(r.threshold!),
        TextCellValue(r.status),
      ]);
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? <int>[]);
  }
}
