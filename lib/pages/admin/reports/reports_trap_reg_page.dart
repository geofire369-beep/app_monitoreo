import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/mapa_model.dart';
import '../../../theme/app_theme.dart';

class ReportsTrapRegPage extends StatefulWidget {
  final Set<String> greenhouseIds;
  final Set<String> weekKeys;

  const ReportsTrapRegPage({
    super.key,
    required this.greenhouseIds,
    required this.weekKeys,
  });

  @override
  State<ReportsTrapRegPage> createState() => _ReportsTrapRegPageState();
}

class _ReportsTrapRegPageState extends State<ReportsTrapRegPage> {
  final _fs = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  final Map<String, GreenhouseMap> _mapByGh = {};
  final Map<String, String> _ghName = {};

  final List<_TrapRegRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows.clear();
      _mapByGh.clear();
      _ghName.clear();
    });

    try {
      final ghIds = widget.greenhouseIds.toList();
      final weekKeys = widget.weekKeys.toList()
        ..sort((a, b) => _weekOrder(b).compareTo(_weekOrder(a)));

      if (ghIds.isEmpty || weekKeys.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      const chunkSize = 10;
      for (int i = 0; i < ghIds.length; i += chunkSize) {
        final chunk = ghIds.sublist(i, math.min(i + chunkSize, ghIds.length));

        final snap = await _fs
            .collection('greenhouses_maps')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final d in snap.docs) {
          final data = Map<String, dynamic>.from(d.data());
          final map = GreenhouseMap.fromDoc(d.id, data);
          _mapByGh[d.id] = map;
          _ghName[d.id] = (data['name'] ?? d.id).toString();
        }
      }

      final out = <_TrapRegRow>[];

      for (final wk in weekKeys) {
        for (final ghId in ghIds) {
          final byPest = await _loadTrapTotalsForGreenhouseWeek(
            ghId: ghId,
            weekKey: wk,
          );
          if (byPest.isEmpty) continue;

          final map = _mapByGh[ghId];
          final denom = (map?.weeklyActiveTraps[wk] ?? 0);
          final denomSafe = denom <= 0 ? 0 : denom;

          final weekNo = _weekNoFromKey(wk);

          final pests = byPest.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          for (final pest in pests) {
            final pop = byPest[pest] ?? 0;
            if (pop <= 0) continue;

            final avg = (denomSafe <= 0) ? 0.0 : (pop / denomSafe);

            out.add(
              _TrapRegRow(
                ghId: ghId,
                weekKey: wk,
                weekNo: weekNo,
                pest: pest,
                population: pop,
                average: avg,
                activeTraps: denomSafe,
              ),
            );
          }
        }
      }

      out.sort((a, b) {
        final wa = _weekOrder(a.weekKey);
        final wb = _weekOrder(b.weekKey);
        if (wa != wb) return wb.compareTo(wa);

        final gha = (_ghName[a.ghId] ?? a.ghId).toLowerCase();
        final ghb = (_ghName[b.ghId] ?? b.ghId).toLowerCase();
        if (gha != ghb) return gha.compareTo(ghb);

        return a.pest.toLowerCase().compareTo(b.pest.toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(out);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<Map<String, int>> _loadTrapTotalsForGreenhouseWeek({
    required String ghId,
    required String weekKey,
  }) async {
    final ghRef = _fs
        .collection('monitoreo_weeks')
        .doc(weekKey)
        .collection('greenhouses')
        .doc(ghId);

    final caps = await ghRef.collection('capillas').get();
    if (caps.docs.isEmpty) return {};

    final out = <String, int>{};

    for (final cap in caps.docs) {
      final data = Map<String, dynamic>.from(cap.data());

      final trapLinesAny = data['trapLines'];
      if (trapLinesAny is! Map) continue;

      final trapLines = Map<String, dynamic>.from(trapLinesAny);

      trapLines.forEach((_, payloadAny) {
        if (payloadAny is! Map) return;
        final payload = Map<String, dynamic>.from(payloadAny);

        final totalsAny = payload['totalsByPest'];
        if (totalsAny is Map) {
          final totals = Map<String, dynamic>.from(totalsAny);
          totals.forEach((p, v) {
            final n = _asInt(v);
            if (n > 0) out[p.toString()] = (out[p.toString()] ?? 0) + n;
          });
          return;
        }

        final obsAny = payload['observations'];
        final obs = (obsAny is Map)
            ? Map<String, dynamic>.from(obsAny)
            : <String, dynamic>{};

        final trapsAny = obs['traps'];
        final trapsObs = (trapsAny is Map)
            ? Map<String, dynamic>.from(trapsAny)
            : <String, dynamic>{};

        trapsObs.forEach((_, tAny) {
          if (tAny is! Map) return;
          final t = Map<String, dynamic>.from(tAny);
          final countsAny = t['counts'];
          if (countsAny is! Map) return;

          final counts = Map<String, dynamic>.from(countsAny);
          counts.forEach((p, v) {
            final n = _asInt(v);
            if (n > 0) out[p.toString()] = (out[p.toString()] ?? 0) + n;
          });
        });
      });
    }

    return out;
  }

  int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;
    final dark = _greenDark(accent);

    final ghSorted = _sortedGhIds();
    final ghColor = <String, Color>{};
    for (int i = 0; i < ghSorted.length; i++) {
      ghColor[ghSorted[i]] = _pastelGreen(i);
    }

    final weekKeys = _rows.map((e) => e.weekKey).toSet().toList()
      ..sort((a, b) => _weekOrder(b).compareTo(_weekOrder(a)));

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF6),
      appBar: AppBar(
        backgroundColor: dark,
        foregroundColor: Colors.white,
        title: const Text(
          'Reg trampa',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [dark, accent, _greenMid(accent)],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _greenPale(accent),
              Colors.white,
              _greenSoft(accent).withValues(alpha: 0.35),
              Colors.white,
            ],
            stops: const [0, 0.20, 0.62, 1],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _topSummary(accent, dark),
              const SizedBox(height: 12),
              if (_loading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: _greenPale(accent),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              if (!_loading && _error != null) _errorCard(accent, _error!),
              if (!_loading && _error == null && _rows.isEmpty)
                _emptyCard(accent),
              if (!_loading && _error == null && _rows.isNotEmpty) ...[
                for (final wk in weekKeys) ...[
                  const SizedBox(height: 12),
                  _weekHeader(accent, wk),
                  const SizedBox(height: 10),
                  _weekTable(
                    accent: accent,
                    weekKey: wk,
                    rows: _rows.where((r) => r.weekKey == wk).toList(),
                    ghColor: ghColor,
                  ),
                ],
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _topSummary(Color accent, Color dark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, _greenPale(accent), Colors.white],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent.withValues(alpha: 0.95), dark],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.local_activity_outlined,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Registro de trampas',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Ordenado por semana (desc) e invernadero. Promedio = población / trampas activas de esa semana.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(
                        accent,
                        'Invernaderos',
                        '${widget.greenhouseIds.length}',
                      ),
                      _pill(accent, 'Semanas', '${widget.weekKeys.length}'),
                      _pill(accent, 'Registros', '${_rows.length}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(Color accent, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: _greenPale(accent),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.10)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: _greenDark(accent),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _weekHeader(Color accent, String wk) {
    final dark = _greenDark(accent);
    final wno = _weekNoFromKey(wk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.date_range_outlined, color: dark, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Semana $wno • $wk',
              style: TextStyle(fontWeight: FontWeight.w900, color: dark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekTable({
    required Color accent,
    required String weekKey,
    required List<_TrapRegRow> rows,
    required Map<String, Color> ghColor,
  }) {
    rows.sort((a, b) {
      final gha = (_ghName[a.ghId] ?? a.ghId).toLowerCase();
      final ghb = (_ghName[b.ghId] ?? b.ghId).toLowerCase();
      if (gha != ghb) return gha.compareTo(ghb);
      return a.pest.toLowerCase().compareTo(b.pest.toLowerCase());
    });

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1300),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.12)),
            color: Colors.white,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  Color(0xFF4E5D78),
                ),
                dataRowMinHeight: 46,
                dataRowMaxHeight: 58,
                headingRowHeight: 52,
                columnSpacing: 18,
                horizontalMargin: 12,
                dividerThickness: 1,
                showCheckboxColumn: false,
                headingTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
                dataTextStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                columns: const [
                  DataColumn(
                    label: SizedBox(
                      width: 170,
                      child: Center(child: Text('Invernadero')),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 80,
                      child: Center(child: Text('Semana')),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 200,
                      child: Center(child: Text('Plaga')),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 120,
                      child: Center(child: Text('Población')),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 120,
                      child: Center(child: Text('Promedio')),
                    ),
                  ),
                  DataColumn(
                    label: SizedBox(
                      width: 140,
                      child: Center(child: Text('Trampas activas')),
                    ),
                  ),
                ],
                rows: rows.map((r) {
                  final bg = ghColor[r.ghId] ?? Colors.white;
                  final fg = _foregroundForGreen(bg);

                  return DataRow(
                    color: WidgetStatePropertyAll(bg),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 170,
                          child: Center(
                            child: Text(
                              _ghName[r.ghId] ?? r.ghId,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 80,
                          child: Center(
                            child: Text(
                              r.weekNo.toString(),
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 200,
                          child: Center(
                            child: Text(
                              r.pest,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Center(
                            child: Text(
                              r.population.toString(),
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Center(
                            child: Text(
                              r.average.toStringAsFixed(2),
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: Center(
                            child: Text(
                              r.activeTraps.toString(),
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyCard(Color accent) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Icon(
                  Icons.inbox_outlined,
                  color: _greenDark(accent),
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No hay registros de trampas para las semanas/invernaderos seleccionados.',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorCard(Color accent, String err) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.red.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.10),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Error cargando reporte:\n$err',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _sortedGhIds() {
    final gh = widget.greenhouseIds.toList()
      ..sort((a, b) {
        final aa = (_ghName[a] ?? a).toLowerCase();
        final bb = (_ghName[b] ?? b).toLowerCase();
        return aa.compareTo(bb);
      });
    return gh;
  }

  int _weekOrder(String wk) {
    final m = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(wk);
    if (m == null) return 0;
    final y = int.tryParse(m.group(1)!) ?? 0;
    final w = int.tryParse(m.group(2)!) ?? 0;
    return y * 100 + w;
  }

  int _weekNoFromKey(String wk) {
    final m = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(wk);
    if (m == null) return 0;
    return int.tryParse(m.group(2)!) ?? 0;
  }

  Color _pastelGreen(int i) {
    const base = [
      Color(0xFFD9E2DD),
      Color(0xFFC9D6C1),
      Color(0xFFD6E0B8),
      Color(0xFFD2DAA8),
      Color(0xFFD7E5D2),
    ];
    return base[i % base.length];
  }

  Color _foregroundForGreen(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance < 0.50 ? Colors.white : const Color(0xFF2F3A34);
  }

  Color _greenDark(Color base) {
    final hsv = HSVColor.fromColor(base);
    return hsv
        .withSaturation((hsv.saturation + 0.12).clamp(0.0, 1.0))
        .withValue((hsv.value - 0.25).clamp(0.0, 1.0))
        .toColor();
  }

  Color _greenMid(Color base) {
    final hsv = HSVColor.fromColor(base);
    return hsv
        .withSaturation((hsv.saturation + 0.05).clamp(0.0, 1.0))
        .withValue((hsv.value - 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  Color _greenSoft(Color base) {
    return Color.alphaBlend(base.withValues(alpha: 0.10), Colors.white);
  }

  Color _greenPale(Color base) {
    return Color.alphaBlend(base.withValues(alpha: 0.14), Colors.white);
  }
}

class _TrapRegRow {
  final String ghId;
  final String weekKey;
  final int weekNo;
  final String pest;
  final int population;
  final double average;
  final int activeTraps;

  _TrapRegRow({
    required this.ghId,
    required this.weekKey,
    required this.weekNo,
    required this.pest,
    required this.population,
    required this.average,
    required this.activeTraps,
  });
}
