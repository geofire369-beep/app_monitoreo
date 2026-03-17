import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;

import '../models/report_models.dart';

class ExcelExport {
  static Uint8List buildIncidenceExcel(ReportPayload payload) {
    final excel = ex.Excel.createExcel();

    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Incidencia') {
      excel.rename(defaultSheet, 'Incidencia');
    }

    final sheet = excel['Incidencia'];

    sheet.appendRow([
      ex.TextCellValue('Invernadero'),
      ex.TextCellValue(payload.greenhouseName),
    ]);
    sheet.appendRow([
      ex.TextCellValue('Desde'),
      ex.TextCellValue(payload.from.toIso8601String()),
    ]);
    sheet.appendRow([
      ex.TextCellValue('Hasta'),
      ex.TextCellValue(payload.to.toIso8601String()),
    ]);
    sheet.appendRow([ex.TextCellValue('')]);

    sheet.appendRow([
      ex.TextCellValue('Plaga/Enfermedad'),
      ex.TextCellValue('Plantas evaluadas'),
      ex.TextCellValue('Plantas afectadas'),
      ex.TextCellValue('Incidencia %'),
      ex.TextCellValue('Umbral'),
      ex.TextCellValue('Estado'),
    ]);

    final headerStyle = ex.CellStyle(
      bold: true,
      horizontalAlign: ex.HorizontalAlign.Center,
      verticalAlign: ex.VerticalAlign.Center,
      backgroundColorHex: ex.ExcelColor.fromHexString('#DFF3E3'),
      leftBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
      rightBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
      topBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
      bottomBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
    );

    final dataStyle = ex.CellStyle(
      horizontalAlign: ex.HorizontalAlign.Center,
      verticalAlign: ex.VerticalAlign.Center,
      leftBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
      rightBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
      topBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
      bottomBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
    );

    const headerRowIndex = 4;
    for (int c = 0; c < 6; c++) {
      final cell = sheet.cell(
        ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRowIndex),
      );
      cell.cellStyle = headerStyle;
    }

    for (int i = 0; i < payload.rows.length; i++) {
      final r = payload.rows[i];

      sheet.appendRow([
        ex.TextCellValue(r.pestName),
        ex.IntCellValue(r.plantsChecked),
        ex.IntCellValue(r.plantsAffected),
        ex.DoubleCellValue(double.parse(r.incidencePercent.toStringAsFixed(2))),
        r.threshold == null
            ? ex.TextCellValue('—')
            : ex.DoubleCellValue(r.threshold!),
        ex.TextCellValue(r.status),
      ]);

      final excelRowIndex = headerRowIndex + 1 + i;
      for (int c = 0; c < 6; c++) {
        final cell = sheet.cell(
          ex.CellIndex.indexByColumnRow(
            columnIndex: c,
            rowIndex: excelRowIndex,
          ),
        );
        cell.cellStyle = dataStyle;
      }
    }

    for (int c = 0; c < 6; c++) {
      sheet.setColumnAutoFit(c);
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? <int>[]);
  }
}
