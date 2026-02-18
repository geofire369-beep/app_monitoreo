import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/report_models.dart';
import '../../../services/report_service.dart';
import '../../../utils/excel_export.dart';
import 'reports_history_page.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String? _greenhouseId;
  String _greenhouseName = "";

  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  bool _loading = false;
  List<IncidenceRow> _rows = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reportes"),
        actions: [
          IconButton(
            tooltip: "Historial",
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportsHistoryPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _controls(),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_rows.isNotEmpty) _table(),
          if (_rows.isNotEmpty) const SizedBox(height: 12),
          if (_rows.isNotEmpty) _actions(),
          if (_rows.isEmpty && !_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text("Genera un reporte para ver la tabla.")),
            ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _greenhousePicker(),
            const SizedBox(height: 10),

            // ✅ FIX: ambos botones con Expanded para evitar ancho infinito en Web
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () async {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020, 1, 1),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              initialDateRange: _range,
                            );
                            if (picked != null) setState(() => _range = picked);
                          },
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      "${_range.start.toString().split(' ').first} → ${_range.end.toString().split(' ').first}",
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_greenhouseId == null || _loading) ? null : _generate,
                    icon: const Icon(Icons.analytics),
                    label: const Text("Generar"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _greenhousePicker() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection("greenhouses").orderBy("name").snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return InputDecorator(
            decoration: const InputDecoration(
              labelText: "Invernadero",
              border: OutlineInputBorder(),
            ),
            child: Text(
              "Error leyendo invernaderos: ${snap.error}",
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        if (!snap.hasData) return const LinearProgressIndicator();

        final docs = snap.data!.docs;

        // ✅ Si el seleccionado ya no existe en items, resetea a null
        final selectedExists =
            _greenhouseId != null && docs.any((d) => d.id == _greenhouseId);

        if (!selectedExists && _greenhouseId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _greenhouseId = null;
              _greenhouseName = "";
              _rows = [];
            });
          });
        }

        return DropdownButtonFormField<String?>(
          // Nota: en Flutter 3.35 puede avisar que value está deprecated,
          // pero funciona. Si lo quieres "perfecto" lo migramos luego.
          value: selectedExists ? _greenhouseId : null,
          decoration: const InputDecoration(
            labelText: "Invernadero",
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text("Selecciona..."),
            ),
            ...docs.map((d) {
              final name = (d.data()["name"] ?? d.id).toString();
              return DropdownMenuItem<String?>(
                value: d.id,
                child: Text(name, overflow: TextOverflow.ellipsis),
              );
            }),
          ],
          onChanged: _loading
              ? null
              : (v) {
                  if (v == null) {
                    setState(() {
                      _greenhouseId = null;
                      _greenhouseName = "";
                      _rows = [];
                    });
                    return;
                  }
                  final doc = docs.firstWhere((x) => x.id == v);
                  final name = (doc.data()["name"] ?? v).toString();
                  setState(() {
                    _greenhouseId = v;
                    _greenhouseName = name;
                    _rows = [];
                  });
                },
        );
      },
    );
  }

  Future<void> _generate() async {
    final ghId = _greenhouseId;
    if (ghId == null) return;

    setState(() {
      _loading = true;
      _rows = [];
    });

    try {
      final reportSvc = ReportService(FirebaseFirestore.instance);

      final agg = await reportSvc.incidenceByPest(
        greenhouseId: ghId,
        from: _range.start,
        to: _range.end,
      );

      // catálogo pests
      final pestsSnap = await FirebaseFirestore.instance.collection("pests").get();
      final pests = <String, Map<String, dynamic>>{};
      for (final d in pestsSnap.docs) {
        pests[d.id] = d.data();
      }

      final rows = <IncidenceRow>[];
      for (final entry in agg.entries) {
        final pestId = entry.key;

        final checkedNum = entry.value["checked"] ?? 0;
        final affectedNum = entry.value["affected"] ?? 0;

        final checked = (checkedNum is num) ? checkedNum.toInt() : 0;
        final affected = (affectedNum is num) ? affectedNum.toInt() : 0;

        final pct = checked == 0 ? 0.0 : (affected / checked) * 100.0;

        final pestData = pests[pestId];
        final pestName = pestData?["name"]?.toString() ?? pestId;

        final thr = (pestData?["thresholdIncidence"] is num)
            ? (pestData!["thresholdIncidence"] as num).toDouble()
            : null;

        final status = (thr != null && pct >= thr) ? "Alerta" : "Normal";

        rows.add(
          IncidenceRow(
            pestName: pestName,
            plantsChecked: checked,
            plantsAffected: affected,
            incidencePercent: pct,
            threshold: thr,
            status: status,
          ),
        );
      }

      rows.sort((a, b) => b.incidencePercent.compareTo(a.incidencePercent));

      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error generando reporte: $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _table() {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text("Plaga/Enf.")),
            DataColumn(label: Text("Evaluadas")),
            DataColumn(label: Text("Afectadas")),
            DataColumn(label: Text("Incidencia %")),
            DataColumn(label: Text("Umbral")),
            DataColumn(label: Text("Estado")),
          ],
          rows: _rows.map((r) {
            return DataRow(cells: [
              DataCell(Text(r.pestName)),
              DataCell(Text(r.plantsChecked.toString())),
              DataCell(Text(r.plantsAffected.toString())),
              DataCell(Text(r.incidencePercent.toStringAsFixed(2))),
              DataCell(Text(r.threshold?.toStringAsFixed(2) ?? "—")),
              DataCell(Text(r.status)),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              final ghId = _greenhouseId;
              if (ghId == null) return;

              final payload = ReportPayload(
                greenhouseId: ghId,
                greenhouseName: _greenhouseName,
                from: _range.start,
                to: _range.end,
                rows: _rows,
              );

              final bytes = ExcelExport.buildIncidenceExcel(payload);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Excel generado: ${bytes.lengthInBytes} bytes")),
              );
            },
            icon: const Icon(Icons.table_view),
            label: const Text("Exportar Excel"),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _saveReport,
            icon: const Icon(Icons.save),
            label: const Text("Guardar reporte"),
          ),
        ),
      ],
    );
  }

  Future<void> _saveReport() async {
    final ghId = _greenhouseId;
    if (ghId == null) return;

    final now = DateTime.now();
    final ref = FirebaseFirestore.instance.collection("reports").doc();

    final top = _rows.take(3).map((e) => {
          "pestName": e.pestName,
          "incidencePercent": e.incidencePercent,
        }).toList();

    await ref.set({
      "greenhouseId": ghId,
      "greenhouseName": _greenhouseName,
      "from": Timestamp.fromDate(_range.start),
      "to": Timestamp.fromDate(_range.end),
      "createdAt": Timestamp.fromDate(now),
      "summaryTop": top,
      "rows": _rows.map((r) => {
            "pestName": r.pestName,
            "plantsChecked": r.plantsChecked,
            "plantsAffected": r.plantsAffected,
            "incidencePercent": r.incidencePercent,
            "threshold": r.threshold,
            "status": r.status,
          }).toList(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reporte guardado.")));
  }
}
