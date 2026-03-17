import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';

import '../save_bytes/save_bytes.dart';

class MonitoreoExportRow {
  final String invernadero;
  final int semana;
  final String plaga;
  final String capilla;
  final int linea;
  final int poste;
  final int total;
  final String? nivel;

  MonitoreoExportRow({
    required this.invernadero,
    required this.semana,
    required this.plaga,
    required this.capilla,
    required this.linea,
    required this.poste,
    required this.total,
    required this.nivel,
  });
}

class MonitoreoExcelExporter {
  static Future<void> exportSimpleTable({
    required BuildContext context,
    required String filename,
    required List<MonitoreoExportRow> rows,
  }) async {
    final excel = ex.Excel.createExcel();

    // hoja final
    final sheet = excel['Tabla'];

    // eliminar hoja default para que no salga "Sheet1"
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headers = <String>[
      'Invernadero',
      'Semana',
      'Plaga',
      'Capilla',
      'Línea',
      'Poste',
      'TOTAL',
      'Nivel',
    ];

    final thinBorder = ex.Border(borderStyle: ex.BorderStyle.Thin);

    final headerStyle = ex.CellStyle(
      bold: true,
      horizontalAlign: ex.HorizontalAlign.Center,
      verticalAlign: ex.VerticalAlign.Center,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );

    final cellStyle = ex.CellStyle(
      verticalAlign: ex.VerticalAlign.Center,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
      topBorder: thinBorder,
      bottomBorder: thinBorder,
    );

    // Header
    for (int c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = ex.TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }

    // Rows
    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];

      final nivelExport = (row.nivel == null || row.nivel!.trim().isEmpty)
          ? '-'
          : row.nivel!;

      final values = <Object?>[
        row.invernadero,
        row.semana,
        row.plaga,
        row.capilla,
        row.linea,
        row.poste,
        row.total,
        nivelExport,
      ];

      for (int c = 0; c < values.length; c++) {
        final cell = sheet.cell(
          ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
        );
        final v = values[c];

        if (v is int) {
          cell.value = ex.IntCellValue(v);
        } else {
          cell.value = ex.TextCellValue(v.toString());
        }
        cell.cellStyle = cellStyle;
      }
    }

    // widths
    sheet.setColumnWidth(0, 18); // Invernadero
    sheet.setColumnWidth(1, 10); // Semana
    sheet.setColumnWidth(2, 22); // Plaga
    sheet.setColumnWidth(3, 18); // Capilla
    sheet.setColumnWidth(4, 10); // Línea
    sheet.setColumnWidth(5, 10); // Poste
    sheet.setColumnWidth(6, 10); // TOTAL
    sheet.setColumnWidth(7, 12); // Nivel

    final bytes = excel.encode();
    if (bytes == null) return;

    await saveBytes(bytes: bytes, filename: filename);
  }
}
