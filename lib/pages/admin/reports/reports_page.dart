import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as ex;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:sdp/pages/admin/reports/reports_trap_reg_page.dart';

import '../../../theme/app_theme.dart';

enum _ReportView { incidencias, tdSemana }

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _fs = FirebaseFirestore.instance;

  _ReportView _view = _ReportView.incidencias;

  bool _loading = false;
  bool _generated = false;

  final Set<String> _selectedGreenhouseIds = <String>{};
  final Set<String> _selectedWeekKeys = <String>{};

  final Set<String> _fGh = <String>{};
  final Set<String> _fWeeks = <String>{};
  final Set<String> _fPests = <String>{};
  String _fType = 'TODOS';

  _ReportData? _data;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedWeekKeys
      ..add(_isoWeekKey(now))
      ..add(_isoWeekKey(now.subtract(const Duration(days: 7))));
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;
    final darkGreen = _greenDark(accent);
    final softGreen = _greenSoft(accent);
    final paleGreen = _greenPale(accent);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF6),
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        backgroundColor: darkGreen,
        title: const Text(
          'Reportes',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [darkGreen, accent, _greenMid(accent)],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              paleGreen,
              Colors.white,
              softGreen.withValues(alpha: 0.35),
              Colors.white,
            ],
            stops: const [0, 0.20, 0.62, 1],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _topControls(accent),
              const SizedBox(height: 12),
              if (_loading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: paleGreen,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              if (_generated && _data != null) ...[
                const SizedBox(height: 12),
                _viewSwitch(accent),
                const SizedBox(height: 10),
                _trapRegButton(accent),
                const SizedBox(height: 12),
                if (_view == _ReportView.incidencias)
                  _IncidenciasTable(
                    accent: accent,
                    data: _data!,
                    fGh: _fGh,
                    fWeeks: _fWeeks,
                    fPests: _fPests,
                    fType: _fType,
                    onPickFilters: _openIncidenciasFilterDialog,
                    onClearFilters: _clearIncidenciasFilters,
                    onExportExcel: _exportIncidenciasExcel,
                    onExportWord: _exportIncidenciasWord,
                  )
                else
                  _TdSemanaGrid(accent: accent, data: _data!),
              ],
              if (!_generated && !_loading)
                Padding(
                  padding: const EdgeInsets.only(top: 38),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(alpha: 0.12),
                            ),
                            child: Icon(
                              Icons.insights_rounded,
                              color: accent,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Selecciona invernaderos y semanas,\nluego “Generar”.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              height: 1.3,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.black.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trapRegButton(Color accent) {
    final darkGreen = _greenDark(accent);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.local_activity_outlined,
                color: darkGreen,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Trampas',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: darkGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReportsTrapRegPage(
                      greenhouseIds: Set<String>.from(_selectedGreenhouseIds),
                      weekKeys: Set<String>.from(_selectedWeekKeys),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.table_chart_outlined),
              label: const Text(
                'Reg trampa',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topControls(Color accent) {
    final darkGreen = _greenDark(accent);

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
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent.withValues(alpha: 0.95), darkGreen],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generación de reportes',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16.5,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Selecciona invernaderos y semanas para construir el reporte.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF5F6E62),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _generated
                        ? const Color(0xFFE5F6E8)
                        : const Color(0xFFF1F4F1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _generated
                          ? const Color(0xFF9AD4A2)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    _generated ? 'Generado' : 'Sin generar',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _generated
                          ? const Color(0xFF2F8F46)
                          : Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: accent.withValues(alpha: 0.12)),
            const SizedBox(height: 14),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _fs
                  .collection('greenhouses_maps')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      backgroundColor: _greenPale(accent),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  );
                }
                final docs = snap.data!.docs;

                final items = docs
                    .map(
                      (d) => _PickItem(
                        d.id,
                        (d.data()['name'] ?? d.id).toString(),
                      ),
                    )
                    .toList(growable: false);

                return Row(
                  children: [
                    Expanded(
                      child: _PillButton(
                        icon: Icons.yard_outlined,
                        title:
                            'Invernaderos (${_selectedGreenhouseIds.length})',
                        subtitle: _selectedGreenhouseIds.isEmpty
                            ? 'Seleccionar'
                            : 'Listos para generar',
                        color: _greenPale(accent),
                        borderColor: accent.withValues(alpha: 0.16),
                        iconColor: darkGreen,
                        textColor: darkGreen,
                        onTap: _loading
                            ? null
                            : () async {
                                final res = await _multiSelectDialog(
                                  context,
                                  title: 'Seleccionar invernaderos',
                                  items: items,
                                  initial: Set<String>.from(
                                    _selectedGreenhouseIds,
                                  ),
                                  hint: 'Selecciona 1 o más',
                                  accent: accent,
                                );
                                if (res == null) return;
                                setState(() {
                                  _selectedGreenhouseIds
                                    ..clear()
                                    ..addAll(res);
                                  _generated = false;
                                  _data = null;
                                });
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PillButton(
                        icon: Icons.date_range_outlined,
                        title: 'Semanas (${_selectedWeekKeys.length})',
                        subtitle: _selectedWeekKeys.isEmpty
                            ? 'Seleccionar'
                            : 'Rango configurado',
                        color: const Color(0xFFE8F7EC),
                        borderColor: accent.withValues(alpha: 0.16),
                        iconColor: darkGreen,
                        textColor: darkGreen,
                        onTap: _loading
                            ? null
                            : () async {
                                final opts = _recentWeekOptions(24);
                                final res = await _multiSelectDialog(
                                  context,
                                  title: 'Seleccionar semanas',
                                  items: opts
                                      .map((wk) => _PickItem(wk, wk))
                                      .toList(),
                                  initial: Set<String>.from(_selectedWeekKeys),
                                  hint: 'Selecciona 1 o más',
                                  accent: accent,
                                );
                                if (res == null) return;
                                setState(() {
                                  _selectedWeekKeys
                                    ..clear()
                                    ..addAll(
                                      res.isEmpty
                                          ? {_isoWeekKey(DateTime.now())}
                                          : res,
                                    );
                                  _generated = false;
                                  _data = null;
                                });
                              },
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      elevation: 0,
                      backgroundColor: darkGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _loading ? null : _generate,
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text(
                      'Generar',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: darkGreen,
                      side: BorderSide(color: accent.withValues(alpha: 0.22)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() {
                              _generated = false;
                              _data = null;
                              _fGh.clear();
                              _fWeeks.clear();
                              _fPests.clear();
                              _fType = 'TODOS';
                            });
                          },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'Reset',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewSwitch(Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: _greenPale(accent),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Tabla:',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _greenDark(accent),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SegmentedButton<_ReportView>(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return accent.withValues(alpha: 0.14);
                    }
                    return Colors.white;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return _greenDark(accent);
                    }
                    return Colors.black.withValues(alpha: 0.70);
                  }),
                  side: WidgetStatePropertyAll(
                    BorderSide(color: accent.withValues(alpha: 0.16)),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: _ReportView.incidencias,
                    label: Text('Registro de incidencias'),
                  ),
                  ButtonSegment(
                    value: _ReportView.tdSemana,
                    label: Text('TD-Semana'),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    if (_selectedGreenhouseIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos 1 invernadero.')),
      );
      return;
    }
    if (_selectedWeekKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos 1 semana.')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _generated = false;
      _data = null;
      _fGh.clear();
      _fWeeks.clear();
      _fPests.clear();
      _fType = 'TODOS';
    });

    try {
      final plSnap = await _fs.collection('plagas').get();
      final pestTypeByLower = <String, String>{};
      for (final d in plSnap.docs) {
        final m = d.data();
        final name = (m['nombre'] ?? '').toString().trim();
        final tipo = (m['tipo'] ?? 'PLAGA').toString().trim().toUpperCase();
        if (name.isNotEmpty) {
          pestTypeByLower[name.toLowerCase()] = (tipo == 'ENFERMEDAD')
              ? 'ENFERMEDAD'
              : 'PLAGA';
        }
      }

      final mapsSnap = await _fs
          .collection('greenhouses_maps')
          .where(FieldPath.documentId, whereIn: _selectedGreenhouseIds.toList())
          .get();

      final ghName = <String, String>{};
      final weeklyPlantsByGh = <String, Map<String, int>>{};

      for (final d in mapsSnap.docs) {
        final m = d.data();
        ghName[d.id] = (m['name'] ?? d.id).toString();
        final wpAny = m['weeklyPlants'];
        if (wpAny is Map) {
          final wp = <String, int>{};
          wpAny.forEach(
            (k, v) => wp[k.toString()] = (v is num)
                ? v.toInt()
                : int.tryParse(v.toString()) ?? 0,
          );
          weeklyPlantsByGh[d.id] = wp;
        } else {
          weeklyPlantsByGh[d.id] = <String, int>{};
        }
      }

      final totalsByGroup = <_GroupKey, Map<String, int>>{};
      final allWeeksLoaded = <String>{};
      final allPests = <String>{};

      for (final wk in _selectedWeekKeys) {
        for (final ghId in _selectedGreenhouseIds) {
          final totals = await _loadTotalsForGreenhouseWeek(
            ghId: ghId,
            weekKey: wk,
          );
          if (totals.isEmpty) continue;

          final merged = <String, int>{};
          totals.forEach((k, v) {
            if (v <= 0) return;
            final base = _baseName(k);
            merged[base] = (merged[base] ?? 0) + v;
          });

          if (merged.isEmpty) continue;

          totalsByGroup[_GroupKey(ghId: ghId, weekKey: wk)] = merged;
          allWeeksLoaded.add(wk);
          allPests.addAll(merged.keys);
        }
      }

      final data = _ReportData(
        greenhouseIds: Set<String>.from(_selectedGreenhouseIds),
        greenhouseNameById: ghName,
        weeklyPlantsByGh: weeklyPlantsByGh,
        totalsByGroup: totalsByGroup,
        weekKeys: allWeeksLoaded,
        allPests: allPests,
        pestTypeByNameLower: pestTypeByLower,
      );

      if (!mounted) return;
      setState(() {
        _data = data;
        _generated = true;

        _fWeeks
          ..clear()
          ..addAll(_selectedWeekKeys.where(allWeeksLoaded.contains));
        _fGh
          ..clear()
          ..addAll(_selectedGreenhouseIds);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error generando: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, int>> _loadTotalsForGreenhouseWeek({
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
      final linesAny = data['lines'];
      if (linesAny is! Map) continue;
      final lines = Map<String, dynamic>.from(linesAny);

      lines.forEach((_, payloadAny) {
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
        final leftAny = obs['left'];
        final rightAny = obs['right'];
        final left = (leftAny is Map)
            ? Map<String, dynamic>.from(leftAny)
            : <String, dynamic>{};
        final right = (rightAny is Map)
            ? Map<String, dynamic>.from(rightAny)
            : <String, dynamic>{};

        void accSide(Map<String, dynamic> side) {
          side.forEach((_, pestsAny) {
            if (pestsAny is! Map) return;
            final pests = Map<String, dynamic>.from(pestsAny);
            pests.forEach((p, v) {
              final n = _asInt(v);
              if (n > 0) out[p.toString()] = (out[p.toString()] ?? 0) + n;
            });
          });
        }

        accSide(left);
        accSide(right);
      });
    }

    return out;
  }

  Future<void> _openIncidenciasFilterDialog() async {
    final d = _data;
    if (d == null) return;

    final ghItems =
        d.greenhouseIds
            .map((id) => _PickItem(id, d.greenhouseNameById[id] ?? id))
            .toList()
          ..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
          );

    final weeks = d.weekKeys.toList()
      ..sort((a, b) => _weekOrder(a).compareTo(_weekOrder(b)));
    final weekItems = weeks.map((w) => _PickItem(w, w)).toList();

    final pests = d.allPests.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final pestItems = pests.map((p) => _PickItem(p, p)).toList();

    final accent = AppTheme.pepperGreen;

    final res = await showDialog<_IncFiltersResult>(
      context: context,
      builder: (ctx) {
        var tmpGh = Set<String>.from(_fGh.isEmpty ? d.greenhouseIds : _fGh);
        var tmpW = Set<String>.from(_fWeeks.isEmpty ? d.weekKeys : _fWeeks);
        var tmpP = Set<String>.from(_fPests);
        var tmpT = _fType;

        return AlertDialog(
          backgroundColor: const Color(0xFFF9FDF9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.tune_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              const Text(
                'Filtros',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                Widget sectionTitle(String t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    t,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _greenDark(accent),
                    ),
                  ),
                );

                Widget wrapTypeChip(String label) {
                  final selected = tmpT == label;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => setLocal(() => tmpT = label),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: selected
                          ? _greenDark(accent)
                          : Colors.black.withValues(alpha: 0.70),
                    ),
                    selectedColor: accent.withValues(alpha: 0.18),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: selected
                          ? accent.withValues(alpha: 0.28)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionTitle('Invernaderos (del generado)'),
                      _MiniMultiList(
                        items: ghItems,
                        selected: tmpGh,
                        onToggle: (id, on) => setLocal(
                          () => on ? tmpGh.add(id) : tmpGh.remove(id),
                        ),
                        accent: accent,
                      ),
                      const SizedBox(height: 12),
                      sectionTitle('Semanas (con registros cargados)'),
                      _MiniMultiList(
                        items: weekItems,
                        selected: tmpW,
                        onToggle: (id, on) =>
                            setLocal(() => on ? tmpW.add(id) : tmpW.remove(id)),
                        accent: accent,
                      ),
                      const SizedBox(height: 12),
                      sectionTitle('Plagas (del dataset)'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _greenPale(accent),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Vacío = todas',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _MiniMultiList(
                        items: pestItems,
                        selected: tmpP,
                        onToggle: (id, on) =>
                            setLocal(() => on ? tmpP.add(id) : tmpP.remove(id)),
                        accent: accent,
                      ),
                      const SizedBox(height: 12),
                      sectionTitle('Tipo'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          wrapTypeChip('TODOS'),
                          wrapTypeChip('PLAGA'),
                          wrapTypeChip('ENFERMEDAD'),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(foregroundColor: _greenDark(accent)),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _greenDark(accent),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.pop(
                  ctx,
                  _IncFiltersResult(
                    gh: tmpGh,
                    weeks: tmpW,
                    pests: tmpP,
                    type: tmpT,
                  ),
                );
              },
              child: const Text(
                'Aplicar',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (res == null) return;

    setState(() {
      _fGh
        ..clear()
        ..addAll(res.gh);
      _fWeeks
        ..clear()
        ..addAll(res.weeks);
      _fPests
        ..clear()
        ..addAll(res.pests);
      _fType = res.type;
    });
  }

  void _clearIncidenciasFilters() {
    final d = _data;
    if (d == null) return;

    setState(() {
      _fGh
        ..clear()
        ..addAll(d.greenhouseIds);
      _fWeeks
        ..clear()
        ..addAll(d.weekKeys);
      _fPests.clear();
      _fType = 'TODOS';
    });
  }

  Future<void> _exportIncidenciasExcel() async {
    final d = _data;
    if (d == null) return;

    try {
      final rows = _buildVisibleIncidenciaRows(
        data: d,
        fGh: _fGh,
        fWeeks: _fWeeks,
        fPests: _fPests,
        fType: _fType,
      );

      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay datos para exportar a Excel.')),
        );
        return;
      }

      final excel = ex.Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != 'Incidencias') {
        excel.rename(defaultSheet, 'Incidencias');
      }
      final sheet = excel['Incidencias'];

      final headers = <ex.CellValue>[
        ex.TextCellValue('Invernadero'),
        ex.TextCellValue('Semana'),
        ex.TextCellValue('Plaga'),
        ex.TextCellValue('Num plantas'),
        ex.TextCellValue('% Incidencia'),
        ex.TextCellValue('Inventario'),
        ex.TextCellValue('Tipo'),
        ex.TextCellValue('Plantas sanas'),
      ];

      sheet.appendRow(headers);

      final headStyle = ex.CellStyle(
        bold: true,
        horizontalAlign: ex.HorizontalAlign.Center,
        verticalAlign: ex.VerticalAlign.Center,
        backgroundColorHex: ex.ExcelColor.fromHexString('#4E5D78'),
        fontColorHex: ex.ExcelColor.fromHexString('#FFFFFF'),
        leftBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
        rightBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
        topBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
        bottomBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
      );

      for (int c = 0; c < headers.length; c++) {
        final cell = sheet.cell(
          ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        );
        cell.cellStyle = headStyle;
      }

      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        final bg = _excelGreenForGhIndex(_sortedGhIds(d).indexOf(r.ghId));

        sheet.appendRow([
          ex.TextCellValue(d.greenhouseNameById[r.ghId] ?? r.ghId),
          ex.IntCellValue(r.weekNo),
          ex.TextCellValue(r.pest),
          ex.IntCellValue(r.affected),
          ex.DoubleCellValue(double.parse(r.pct.toStringAsFixed(2))),
          ex.IntCellValue(r.inventory),
          ex.TextCellValue(r.tipo),
          ex.IntCellValue(r.healthyAfter),
        ]);

        final rowStyle = ex.CellStyle(
          horizontalAlign: ex.HorizontalAlign.Center,
          verticalAlign: ex.VerticalAlign.Center,
          backgroundColorHex: ex.ExcelColor.fromHexString(bg),
          leftBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
          rightBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
          topBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
          bottomBorder: ex.Border(borderStyle: ex.BorderStyle.Thin),
        );

        final excelRowIndex = i + 1;
        for (int c = 0; c < 8; c++) {
          final cell = sheet.cell(
            ex.CellIndex.indexByColumnRow(
              columnIndex: c,
              rowIndex: excelRowIndex,
            ),
          );
          cell.cellStyle = rowStyle;
        }
      }

      for (int c = 0; c < 8; c++) {
        sheet.setColumnAutoFit(c);
      }

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('No se pudo generar el archivo Excel.');
      }

      final fileName = _exportFileBaseName('registro_incidencias');

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'xlsx',
        mimeType: MimeType.custom,
        customMimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );

      if (!mounted) return;

      _showExportSuccessDialog(formatLabel: 'xlsx', fileName: fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error exportando Excel: $e')));
    }
  }

  Future<void> _exportIncidenciasWord() async {
    final d = _data;
    if (d == null) return;

    try {
      final rows = _buildVisibleIncidenciaRows(
        data: d,
        fGh: _fGh,
        fWeeks: _fWeeks,
        fPests: _fPests,
        fType: _fType,
      );

      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay datos para exportar a Word.')),
        );
        return;
      }

      final esc = const HtmlEscape();

      final buffer = StringBuffer()
        ..writeln('<html>')
        ..writeln('<head>')
        ..writeln('<meta charset="utf-8">')
        ..writeln('<title>Registro de incidencias</title>')
        ..writeln('</head>')
        ..writeln('<body>')
        ..writeln('<h2>Registro de incidencias</h2>')
        ..writeln('<table border="1" cellspacing="0" cellpadding="4">')
        ..writeln('<tr>')
        ..writeln('<th>Invernadero</th>')
        ..writeln('<th>Semana</th>')
        ..writeln('<th>Plaga</th>')
        ..writeln('<th>Num plantas</th>')
        ..writeln('<th>% Incidencia</th>')
        ..writeln('<th>Inventario</th>')
        ..writeln('<th>Tipo</th>')
        ..writeln('<th>Plantas sanas</th>')
        ..writeln('</tr>');

      for (final r in rows) {
        buffer.writeln('<tr>');
        buffer.writeln(
          '<td>${esc.convert(d.greenhouseNameById[r.ghId] ?? r.ghId)}</td>',
        );
        buffer.writeln('<td>${r.weekNo}</td>');
        buffer.writeln('<td>${esc.convert(r.pest)}</td>');
        buffer.writeln('<td>${r.affected}</td>');
        buffer.writeln('<td>${r.pct.toStringAsFixed(2)}</td>');
        buffer.writeln('<td>${r.inventory}</td>');
        buffer.writeln('<td>${esc.convert(r.tipo)}</td>');
        buffer.writeln('<td>${r.healthyAfter}</td>');
        buffer.writeln('</tr>');
      }

      buffer
        ..writeln('</table>')
        ..writeln('</body>')
        ..writeln('</html>');

      final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
      final fileName = _exportFileBaseName('registro_incidencias');

      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        fileExtension: 'doc',
        mimeType: MimeType.custom,
        customMimeType: 'application/msword',
      );

      if (!mounted) return;

      _showExportSuccessDialog(formatLabel: 'doc', fileName: fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error exportando Word: $e')));
    }
  }

  void _showExportSuccessDialog({
    required String formatLabel,
    String? fileName,
  }) {
    final accent = AppTheme.pepperGreen;
    final dark = _greenDark(accent);

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, _greenPale(accent), Colors.white],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [accent.withValues(alpha: 0.95), dark],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      formatLabel.toLowerCase() == 'xlsx'
                          ? Icons.grid_on_rounded
                          : Icons.description_outlined,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Exportación completada',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: dark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    fileName == null
                        ? 'El archivo en formato $formatLabel se exportó correctamente.'
                        : 'El archivo $fileName.$formatLabel se exportó correctamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.35,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _greenPale(accent),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent.withValues(alpha: 0.10)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: dark,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tu exportación ya está lista.',
                            style: TextStyle(
                              color: dark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: dark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text(
                        'Aceptar',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _exportFileBaseName(String prefix) {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    return '${prefix}_${now.year}$mm$dd\_$hh$mi';
  }

  List<String> _recentWeekOptions(int count) {
    final now = DateTime.now();
    return List.generate(
      count,
      (i) => _isoWeekKey(now.subtract(Duration(days: 7 * i))),
    );
  }

  int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _baseName(String pestKey) {
    final raw = pestKey.trim();
    final idx = raw.lastIndexOf('|');
    if (idx <= 0) return raw;
    final name = raw.substring(0, idx).trim();
    return name.isEmpty ? raw : name;
  }

  String _isoWeekKey(DateTime dt) {
    final w = _isoWeekNumber(dt);
    final y = _isoWeekYear(dt);
    final ww = w.toString().padLeft(2, '0');
    return '$y-W$ww';
  }

  int _isoWeekYear(DateTime dt) {
    final thursday = dt.add(Duration(days: 3 - ((dt.weekday + 6) % 7)));
    return thursday.year;
  }

  int _isoWeekNumber(DateTime dt) {
    final thursday = dt.add(Duration(days: 3 - ((dt.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstWeekThursday = firstThursday.add(
      Duration(days: 3 - ((firstThursday.weekday + 6) % 7)),
    );
    final diff = thursday.difference(firstWeekThursday).inDays;
    return 1 + (diff ~/ 7);
  }
}

@immutable
class _GroupKey {
  final String ghId;
  final String weekKey;
  const _GroupKey({required this.ghId, required this.weekKey});

  @override
  bool operator ==(Object other) =>
      other is _GroupKey && other.ghId == ghId && other.weekKey == weekKey;

  @override
  int get hashCode => Object.hash(ghId, weekKey);
}

class _ReportData {
  final Set<String> greenhouseIds;
  final Map<String, String> greenhouseNameById;
  final Map<String, Map<String, int>> weeklyPlantsByGh;
  final Map<_GroupKey, Map<String, int>> totalsByGroup;
  final Set<String> weekKeys;
  final Set<String> allPests;
  final Map<String, String> pestTypeByNameLower;

  _ReportData({
    required this.greenhouseIds,
    required this.greenhouseNameById,
    required this.weeklyPlantsByGh,
    required this.totalsByGroup,
    required this.weekKeys,
    required this.allPests,
    required this.pestTypeByNameLower,
  });

  String pestTypeOf(String pestName) =>
      pestTypeByNameLower[pestName.toLowerCase()] ?? 'PLAGA';

  int inventoryOf(String ghId, String weekKey) =>
      weeklyPlantsByGh[ghId]?[weekKey] ?? 0;
}

List<_IncRow> _buildVisibleIncidenciaRows({
  required _ReportData data,
  required Set<String> fGh,
  required Set<String> fWeeks,
  required Set<String> fPests,
  required String fType,
}) {
  final out = <_IncRow>[];

  final groups = data.totalsByGroup.keys.toList();
  groups.sort((a, b) {
    final wa = _weekOrder(a.weekKey);
    final wb = _weekOrder(b.weekKey);
    if (wa != wb) return wa.compareTo(wb);
    final gha = (data.greenhouseNameById[a.ghId] ?? a.ghId).toLowerCase();
    final ghb = (data.greenhouseNameById[b.ghId] ?? b.ghId).toLowerCase();
    return gha.compareTo(ghb);
  });

  for (final g in groups) {
    final totals = data.totalsByGroup[g] ?? const <String, int>{};
    if (totals.isEmpty) continue;

    final weekNo = _weekNoFromKey(g.weekKey);
    final inv = data.inventoryOf(g.ghId, g.weekKey);

    final pests = totals.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    var healthy = inv;
    for (final pest in pests) {
      final affected = totals[pest] ?? 0;
      final pct = inv <= 0 ? 0.0 : (affected / inv) * 100.0;
      healthy = math.max(0, healthy - affected);
      final tipo = data.pestTypeOf(pest);

      final row = _IncRow(
        ghId: g.ghId,
        weekKey: g.weekKey,
        weekNo: weekNo,
        pest: pest,
        affected: affected,
        pct: pct,
        inventory: inv,
        tipo: tipo,
        healthyAfter: healthy,
      );

      if (fGh.isNotEmpty && !fGh.contains(row.ghId)) continue;
      if (fWeeks.isNotEmpty && !fWeeks.contains(row.weekKey)) continue;
      if (fPests.isNotEmpty && !fPests.contains(row.pest)) continue;
      if (fType != 'TODOS' && row.tipo != fType) continue;

      out.add(row);
    }
  }

  out.sort((a, b) {
    final wa = _weekOrder(a.weekKey);
    final wb = _weekOrder(b.weekKey);
    if (wa != wb) return wa.compareTo(wb);
    final gha = (data.greenhouseNameById[a.ghId] ?? a.ghId).toLowerCase();
    final ghb = (data.greenhouseNameById[b.ghId] ?? b.ghId).toLowerCase();
    if (gha != ghb) return gha.compareTo(ghb);
    return a.pest.toLowerCase().compareTo(b.pest.toLowerCase());
  });

  return out;
}

int _weekNoFromKey(String wk) {
  final m = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(wk);
  if (m == null) return 0;
  return int.tryParse(m.group(2)!) ?? 0;
}

List<String> _sortedGhIds(_ReportData data) {
  final ghList = data.greenhouseIds.toList()
    ..sort(
      (a, b) => (data.greenhouseNameById[a] ?? a).toLowerCase().compareTo(
        (data.greenhouseNameById[b] ?? b).toLowerCase(),
      ),
    );
  return ghList;
}

class _IncidenciasTable extends StatelessWidget {
  final Color accent;
  final _ReportData data;

  final Set<String> fGh;
  final Set<String> fWeeks;
  final Set<String> fPests;
  final String fType;

  final VoidCallback onPickFilters;
  final VoidCallback onClearFilters;
  final Future<void> Function() onExportExcel;
  final Future<void> Function() onExportWord;

  const _IncidenciasTable({
    required this.accent,
    required this.data,
    required this.fGh,
    required this.fWeeks,
    required this.fPests,
    required this.fType,
    required this.onPickFilters,
    required this.onClearFilters,
    required this.onExportExcel,
    required this.onExportWord,
  });

  @override
  Widget build(BuildContext context) {
    final visible = _buildVisibleIncidenciaRows(
      data: data,
      fGh: fGh,
      fWeeks: fWeeks,
      fPests: fPests,
      fType: fType,
    );

    final ghList = _sortedGhIds(data);
    final ghColor = <String, Color>{};
    for (int i = 0; i < ghList.length; i++) {
      ghColor[ghList[i]] = _pastelGreen(i);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.90),
                        _greenDark(accent),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.table_chart_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Registro de incidencias',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onPickFilters,
                      icon: const Icon(Icons.filter_alt_outlined),
                      label: const Text('Filtros'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _greenDark(accent),
                        backgroundColor: _greenPale(accent),
                        side: BorderSide(color: accent.withValues(alpha: 0.14)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onClearFilters,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Limpiar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _greenDark(accent),
                        backgroundColor: Colors.white,
                        side: BorderSide(color: accent.withValues(alpha: 0.14)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: onExportExcel,
                      icon: const Icon(Icons.grid_on_rounded),
                      label: const Text('Excel'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _greenDark(accent),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: onExportWord,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Word'),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: accent.withValues(alpha: 0.12)),
            const SizedBox(height: 12),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1300),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withValues(alpha: 0.12)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: accent.withValues(alpha: 0.10),
                        ),
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
                                width: 150,
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
                                width: 160,
                                child: Center(child: Text('Plaga')),
                              ),
                            ),
                            DataColumn(
                              label: SizedBox(
                                width: 110,
                                child: Center(child: Text('Num plantas')),
                              ),
                            ),
                            DataColumn(
                              label: SizedBox(
                                width: 110,
                                child: Center(child: Text('% Incidencia')),
                              ),
                            ),
                            DataColumn(
                              label: SizedBox(
                                width: 100,
                                child: Center(child: Text('Inventario')),
                              ),
                            ),
                            DataColumn(
                              label: SizedBox(
                                width: 120,
                                child: Center(child: Text('Tipo')),
                              ),
                            ),
                            DataColumn(
                              label: SizedBox(
                                width: 120,
                                child: Center(child: Text('Plantas sanas')),
                              ),
                            ),
                          ],
                          rows: visible.map((r) {
                            final bg = ghColor[r.ghId] ?? Colors.white;
                            final textColor = _foregroundForGreen(bg);

                            return DataRow(
                              color: WidgetStatePropertyAll(bg),
                              cells: [
                                DataCell(
                                  SizedBox(
                                    width: 150,
                                    child: Center(
                                      child: Text(
                                        data.greenhouseNameById[r.ghId] ??
                                            r.ghId,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: textColor,
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
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 160,
                                    child: Center(
                                      child: Text(
                                        r.pest,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 110,
                                    child: Center(
                                      child: Text(
                                        r.affected.toString(),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 110,
                                    child: Center(
                                      child: Text(
                                        r.pct.toStringAsFixed(2),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 100,
                                    child: Center(
                                      child: Text(
                                        r.inventory.toString(),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: textColor,
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
                                        r.tipo,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: textColor,
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
                                        r.healthyAfter.toString(),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: textColor,
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
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniStatChip(
                        label: 'Invernaderos',
                        value: fGh.isEmpty
                            ? '${data.greenhouseIds.length}'
                            : '${fGh.length}',
                        accent: accent,
                      ),
                      _MiniStatChip(
                        label: 'Semanas',
                        value: fWeeks.isEmpty
                            ? '${data.weekKeys.length}'
                            : '${fWeeks.length}',
                        accent: accent,
                      ),
                      _MiniStatChip(
                        label: 'Plagas',
                        value: fPests.isEmpty ? 'Todas' : '${fPests.length}',
                        accent: accent,
                      ),
                      _MiniStatChip(
                        label: 'Tipo',
                        value: fType,
                        accent: accent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _greenPale(accent),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Registros: ${visible.length}',
                    style: TextStyle(
                      color: _greenDark(accent),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
}

class _MiniStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _MiniStatChip({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
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
}

class _IncRow {
  final String ghId;
  final String weekKey;
  final int weekNo;
  final String pest;
  final int affected;
  final double pct;
  final int inventory;
  final String tipo;
  final int healthyAfter;

  _IncRow({
    required this.ghId,
    required this.weekKey,
    required this.weekNo,
    required this.pest,
    required this.affected,
    required this.pct,
    required this.inventory,
    required this.tipo,
    required this.healthyAfter,
  });
}

class _IncFiltersResult {
  final Set<String> gh;
  final Set<String> weeks;
  final Set<String> pests;
  final String type;

  _IncFiltersResult({
    required this.gh,
    required this.weeks,
    required this.pests,
    required this.type,
  });
}

class _TdSemanaGrid extends StatefulWidget {
  final Color accent;
  final _ReportData data;

  const _TdSemanaGrid({required this.accent, required this.data});

  @override
  State<_TdSemanaGrid> createState() => _TdSemanaGridState();
}

class _TdSemanaGridState extends State<_TdSemanaGrid> {
  final Map<String, Set<String>> _weeksByGh = {};
  final Map<String, Set<String>> _pestsByGh = {};
  final Map<String, bool> _showChartByGh = {};

  @override
  void didUpdateWidget(covariant _TdSemanaGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _weeksByGh.clear();
      _pestsByGh.clear();
      _showChartByGh.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;

    final ghs = d.greenhouseIds.toList()
      ..sort(
        (a, b) => (d.greenhouseNameById[a] ?? a).toLowerCase().compareTo(
          (d.greenhouseNameById[b] ?? b).toLowerCase(),
        ),
      );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: widget.accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: widget.accent.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) {
            const gap = 12.0;
            final targetCols = (c.maxWidth >= 1200)
                ? 3
                : (c.maxWidth >= 820)
                ? 2
                : 1;

            final itemW = (c.maxWidth - (gap * (targetCols - 1))) / targetCols;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.accent.withValues(alpha: 0.90),
                            _greenDark(widget.accent),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.grid_view_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'TD-Semana',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _greenPale(widget.accent),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${ghs.length} invernaderos',
                        style: TextStyle(
                          color: _greenDark(widget.accent),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  color: widget.accent.withValues(alpha: 0.12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final ghId in ghs)
                      SizedBox(
                        width: itemW,
                        child: _TdMiniCard(
                          accent: widget.accent,
                          data: d,
                          ghId: ghId,
                          weeksSelected: _weeksByGh.putIfAbsent(
                            ghId,
                            () => <String>{},
                          ),
                          pestsSelected: _pestsByGh.putIfAbsent(
                            ghId,
                            () => <String>{},
                          ),
                          showChart: _showChartByGh[ghId] ?? false,
                          onShowChart: (v) =>
                              setState(() => _showChartByGh[ghId] = v),
                          onWeeksChanged: (s) =>
                              setState(() => _weeksByGh[ghId] = s),
                          onPestsChanged: (s) =>
                              setState(() => _pestsByGh[ghId] = s),
                          onClear: () => setState(() {
                            _weeksByGh[ghId]?.clear();
                            _pestsByGh[ghId]?.clear();
                          }),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TdMiniCard extends StatelessWidget {
  final Color accent;
  final _ReportData data;
  final String ghId;
  final Set<String> weeksSelected;
  final Set<String> pestsSelected;
  final bool showChart;
  final ValueChanged<bool> onShowChart;
  final ValueChanged<Set<String>> onWeeksChanged;
  final ValueChanged<Set<String>> onPestsChanged;
  final VoidCallback onClear;

  const _TdMiniCard({
    required this.accent,
    required this.data,
    required this.ghId,
    required this.weeksSelected,
    required this.pestsSelected,
    required this.showChart,
    required this.onShowChart,
    required this.onWeeksChanged,
    required this.onPestsChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final ghName = data.greenhouseNameById[ghId] ?? ghId;
    final weeksAvail = _weeksAvailForGh();
    final pestsAvail = _pestsAvailForGh();
    final sum = _sumForGh(weeksAvail: weeksAvail, pestsAvail: pestsAvail);

    final pests = sum.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final total = pests.fold<int>(0, (acc, p) => acc + (sum[p] ?? 0));

    final weeksUse =
        (weeksSelected.isEmpty ? weeksAvail : weeksSelected.toList())
          ..sort((a, b) => _weekOrder(a).compareTo(_weekOrder(b)));
    final pestsUse =
        (pestsSelected.isEmpty ? pestsAvail : pestsSelected.toList())
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final series = <String, List<int>>{};
    for (final pest in pestsUse) {
      series[pest] = [
        for (final wk in weeksUse)
          _valueAt(ghId: ghId, weekKey: wk, pest: pest),
      ];
    }

    int yMax = 0;
    for (final vals in series.values) {
      for (final v in vals) {
        if (v > yMax) yMax = v;
      }
    }
    if (yMax <= 0) yMax = 1;

    final colors = <String, Color>{};
    for (final p in pestsUse) {
      colors[p] = _colorFromString(p).withValues(alpha: 0.95);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, _greenPale(accent).withValues(alpha: 0.85)],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.95),
                        _greenDark(accent),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.yard_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ghName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _PillButton(
                  icon: Icons.date_range_outlined,
                  title:
                      'Sem (${weeksSelected.isEmpty ? weeksAvail.length : weeksSelected.length})',
                  subtitle: 'Filtrar semanas',
                  color: _greenPale(accent),
                  borderColor: accent.withValues(alpha: 0.14),
                  iconColor: _greenDark(accent),
                  textColor: _greenDark(accent),
                  onTap: () async {
                    final res = await _multiSelectDialog(
                      context,
                      title: 'Semanas • $ghName',
                      items: weeksAvail.map((wk) => _PickItem(wk, wk)).toList(),
                      initial: Set<String>.from(weeksSelected),
                      hint: 'Vacío = no filtra',
                      accent: accent,
                    );
                    if (res == null) return;
                    onWeeksChanged(res);
                  },
                ),
                _PillButton(
                  icon: Icons.bug_report_outlined,
                  title:
                      'Plag (${pestsSelected.isEmpty ? pestsAvail.length : pestsSelected.length})',
                  subtitle: 'Filtrar plagas',
                  color: const Color(0xFFEAF7ED),
                  borderColor: accent.withValues(alpha: 0.14),
                  iconColor: _greenDark(accent),
                  textColor: _greenDark(accent),
                  onTap: () async {
                    final res = await _multiSelectDialog(
                      context,
                      title: 'Plagas • $ghName',
                      items: pestsAvail.map((p) => _PickItem(p, p)).toList(),
                      initial: Set<String>.from(pestsSelected),
                      hint: 'Vacío = no filtra',
                      accent: accent,
                    );
                    if (res == null) return;
                    onPestsChanged(res);
                  },
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.12)),
                  ),
                  child: IconButton(
                    tooltip: 'Limpiar filtros (solo este invernadero)',
                    onPressed: onClear,
                    icon: Icon(
                      Icons.cleaning_services_outlined,
                      color: _greenDark(accent),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: _greenPale(accent),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.show_chart_rounded,
                    color: _greenDark(accent),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Mostrar gráfica',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Switch.adaptive(
                    value: showChart,
                    onChanged: onShowChart,
                    activeThumbColor: Colors.white,
                    activeTrackColor: _greenDark(accent),
                    inactiveTrackColor: accent.withValues(alpha: 0.22),
                  ),
                ],
              ),
            ),
            if (showChart) ...[
              const SizedBox(height: 10),
              _LineChartCard(
                accent: accent,
                weeks: weeksUse,
                series: series,
                seriesColors: colors,
                yMax: yMax,
              ),
            ],
            const SizedBox(height: 10),
            Divider(height: 1, color: accent.withValues(alpha: 0.10)),
            const SizedBox(height: 8),
            if (pests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Sin registros',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.60),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.12)),
                  color: Colors.white,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    children: [
                      for (int i = 0; i < pests.length; i++)
                        _TdRow(
                          label: pests[i],
                          value: sum[pests[i]] ?? 0,
                          shaded: i.isEven,
                          accent: accent,
                        ),
                      _TdTotalRow(total: total, accent: accent),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _valueAt({
    required String ghId,
    required String weekKey,
    required String pest,
  }) {
    final m = data.totalsByGroup[_GroupKey(ghId: ghId, weekKey: weekKey)];
    if (m == null) return 0;
    return m[pest] ?? 0;
  }

  Map<String, int> _sumForGh({
    required List<String> weeksAvail,
    required List<String> pestsAvail,
  }) {
    final allowedWeeks = weeksSelected.isEmpty
        ? weeksAvail.toSet()
        : weeksSelected;
    final allowedPests = pestsSelected.isEmpty
        ? pestsAvail.toSet()
        : pestsSelected;

    final out = <String, int>{};

    for (final entry in data.totalsByGroup.entries) {
      final key = entry.key;
      if (key.ghId != ghId) continue;
      if (!allowedWeeks.contains(key.weekKey)) continue;

      entry.value.forEach((pest, n) {
        if (!allowedPests.contains(pest)) return;
        if (n <= 0) return;
        out[pest] = (out[pest] ?? 0) + n;
      });
    }

    return out;
  }

  List<String> _weeksAvailForGh() {
    final set = <String>{};
    for (final k in data.totalsByGroup.keys) {
      if (k.ghId == ghId) set.add(k.weekKey);
    }
    final list = set.toList();
    list.sort((a, b) => _weekOrder(a).compareTo(_weekOrder(b)));
    return list;
  }

  List<String> _pestsAvailForGh() {
    final set = <String>{};
    for (final e in data.totalsByGroup.entries) {
      if (e.key.ghId != ghId) continue;
      set.addAll(e.value.keys);
    }
    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Color _colorFromString(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final hue = (h % 360).toDouble();
    return HSVColor.fromAHSV(1.0, hue, 0.62, 0.92).toColor();
  }
}

class _TdRow extends StatelessWidget {
  final String label;
  final int value;
  final bool shaded;
  final Color accent;

  const _TdRow({
    required this.label,
    required this.value,
    required this.shaded,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: shaded
            ? _greenPale(accent).withValues(alpha: 0.45)
            : Colors.white,
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.10)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: _greenPale(accent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              value.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _greenDark(accent),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TdTotalRow extends StatelessWidget {
  final int total;
  final Color accent;

  const _TdTotalRow({required this.total, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      color: _greenPale(accent),
      child: Row(
        children: [
          Text(
            'Total',
            style: TextStyle(
              color: _greenDark(accent),
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: _greenDark(accent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              total.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartCard extends StatelessWidget {
  final Color accent;
  final List<String> weeks;
  final Map<String, List<int>> series;
  final Map<String, Color> seriesColors;
  final int yMax;

  const _LineChartCard({
    required this.accent,
    required this.weeks,
    required this.series,
    required this.seriesColors,
    required this.yMax,
  });

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty || series.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _greenPale(accent),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.10)),
        ),
        child: Text(
          'Sin datos para gráfica (ajusta filtros).',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.65),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final pests = series.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_greenPale(accent), Colors.white],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gráfica • plantas afectadas por semana',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: _greenDark(accent),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: _LineChart(
              weeks: weeks,
              yMax: yMax,
              series: series,
              colors: seriesColors,
              accent: accent,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final p in pests)
                _LegendChip(color: seriesColors[p] ?? Colors.black, text: p),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendChip({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LineChart extends StatefulWidget {
  final List<String> weeks;
  final int yMax;
  final Map<String, List<int>> series;
  final Map<String, Color> colors;
  final Color accent;

  const _LineChart({
    required this.weeks,
    required this.yMax,
    required this.series,
    required this.colors,
    required this.accent,
  });

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  _HitPoint? _hit;
  Offset? _lastPos;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return MouseRegion(
          onHover: (e) {
            _lastPos = e.localPosition;
            _updateHit(e.localPosition, Size(c.maxWidth, c.maxHeight));
          },
          onExit: (_) => setState(() => _hit = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              _lastPos = d.localPosition;
              _updateHit(
                d.localPosition,
                Size(c.maxWidth, c.maxHeight),
                forceShow: true,
              );
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LineChartPainter(
                      weeks: widget.weeks,
                      yMax: widget.yMax,
                      series: widget.series,
                      colors: widget.colors,
                      hit: _hit,
                      accent: widget.accent,
                    ),
                  ),
                ),
                if (_hit != null && _lastPos != null)
                  Positioned(
                    left: (_lastPos!.dx + 14).clamp(
                      8.0,
                      math.max(8.0, c.maxWidth - 200),
                    ),
                    top: (_lastPos!.dy - 10).clamp(
                      8.0,
                      math.max(8.0, c.maxHeight - 72),
                    ),
                    child: IgnorePointer(
                      child: Container(
                        width: 190,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _greenDark(
                            widget.accent,
                          ).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Semana: ${_weekShort(widget.weeks[_hit!.xIndex])}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _hit!.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _hit!.pest,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Cantidad: ${_hit!.value}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateHit(Offset p, Size size, {bool forceShow = false}) {
    final hit = _hitTest(p, size);
    if (!forceShow) {
      if (hit == null && _hit == null) return;
      if (hit != null && _hit != null && hit.key == _hit!.key) return;
    }
    setState(() => _hit = hit);
  }

  _HitPoint? _hitTest(Offset p, Size size) {
    const padL = 42.0;
    const padR = 10.0;
    const padT = 10.0;
    const padB = 28.0;

    final plot = Rect.fromLTWH(
      padL,
      padT,
      size.width - padL - padR,
      size.height - padT - padB,
    );
    if (plot.width <= 20 || plot.height <= 20) return null;
    if (!plot.contains(p)) return null;

    final n = widget.weeks.length;
    if (n <= 0) return null;

    final dx = (n == 1) ? 0.0 : plot.width / (n - 1);
    final yMax = widget.yMax.toDouble().clamp(1.0, double.infinity);

    _HitPoint? best;
    double bestDist = 999999;

    widget.series.forEach((pest, vals) {
      if (vals.length != n) return;
      final color = widget.colors[pest] ?? Colors.blue;

      for (int i = 0; i < n; i++) {
        final v = vals[i].toDouble().clamp(0.0, yMax);
        final x = plot.left + dx * i;
        final y = plot.bottom - (v / yMax) * plot.height;
        final d = (Offset(x, y) - p).distance;
        if (d < bestDist) {
          bestDist = d;
          best = _HitPoint(pest: pest, xIndex: i, value: vals[i], color: color);
        }
      }
    });

    if (bestDist <= 14) return best;
    return null;
  }
}

class _HitPoint {
  final String pest;
  final int xIndex;
  final int value;
  final Color color;

  _HitPoint({
    required this.pest,
    required this.xIndex,
    required this.value,
    required this.color,
  });

  String get key => '$pest@$xIndex';
}

class _LineChartPainter extends CustomPainter {
  final List<String> weeks;
  final int yMax;
  final Map<String, List<int>> series;
  final Map<String, Color> colors;
  final _HitPoint? hit;
  final Color accent;

  _LineChartPainter({
    required this.weeks,
    required this.yMax,
    required this.series,
    required this.colors,
    required this.hit,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 42.0;
    const padR = 10.0;
    const padT = 10.0;
    const padB = 28.0;

    final plot = Rect.fromLTWH(
      padL,
      padT,
      size.width - padL - padR,
      size.height - padT - padB,
    );
    if (plot.width <= 10 || plot.height <= 10) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(plot, const Radius.circular(12)),
      Paint()..color = Colors.white.withValues(alpha: 0.96),
    );

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: 0.10);

    final axis = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _greenDark(accent).withValues(alpha: 0.26);

    for (int i = 0; i <= 5; i++) {
      final y = plot.top + (plot.height * i / 5);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);

      final val = (yMax * (5 - i) / 5).round();
      _text(
        canvas,
        '$val',
        Offset(4, y - 7),
        color: _greenDark(accent).withValues(alpha: 0.65),
        weight: FontWeight.w800,
      );
    }

    canvas.drawLine(
      Offset(plot.left, plot.top),
      Offset(plot.left, plot.bottom),
      axis,
    );
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      axis,
    );

    final n = weeks.length;
    final dx = (n == 1) ? 0.0 : plot.width / (n - 1);
    final yMaxD = yMax.toDouble().clamp(1.0, double.infinity);

    final step = (n <= 10) ? 1 : 2;
    for (int i = 0; i < n; i += step) {
      final x = plot.left + dx * i;
      canvas.drawLine(Offset(x, plot.bottom), Offset(x, plot.bottom + 4), axis);

      _text(
        canvas,
        _weekShort(weeks[i]),
        Offset(x - 12, plot.bottom + 6),
        color: _greenDark(accent).withValues(alpha: 0.70),
        weight: FontWeight.w800,
        size: 10.5,
      );
    }

    series.forEach((pest, vals) {
      if (vals.length != n) return;
      final c = colors[pest] ?? Colors.blue;

      final linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = c.withValues(alpha: 0.92);

      final path = Path();
      for (int i = 0; i < n; i++) {
        final v = vals[i].toDouble().clamp(0.0, yMaxD);
        final x = plot.left + dx * i;
        final y = plot.bottom - (v / yMaxD) * plot.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, linePaint);

      final pPaint = Paint()..color = c.withValues(alpha: 0.98);
      for (int i = 0; i < n; i++) {
        final v = vals[i].toDouble().clamp(0.0, yMaxD);
        final x = plot.left + dx * i;
        final y = plot.bottom - (v / yMaxD) * plot.height;

        final isHit = hit != null && hit!.pest == pest && hit!.xIndex == i;

        canvas.drawCircle(Offset(x, y), isHit ? 5.5 : 4.0, pPaint);

        if (isHit) {
          canvas.drawCircle(
            Offset(x, y),
            9.0,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = _greenDark(accent).withValues(alpha: 0.24),
          );
        }
      }
    });
  }

  void _text(
    Canvas canvas,
    String s,
    Offset p, {
    required Color color,
    FontWeight weight = FontWeight.w700,
    double size = 11,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, p);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) {
    return old.weeks != weeks ||
        old.yMax != yMax ||
        old.series != series ||
        old.colors != colors ||
        old.hit?.key != hit?.key;
  }
}

class _PickItem {
  final String id;
  final String label;
  const _PickItem(this.id, this.label);
}

Future<Set<String>?> _multiSelectDialog(
  BuildContext context, {
  required String title,
  required List<_PickItem> items,
  required Set<String> initial,
  required String hint,
  required Color accent,
}) async {
  final tmp = Set<String>.from(initial);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFFF9FDF9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.checklist_rounded, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _greenPale(accent),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      hint,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.10),
                        ),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final it = items[i];
                          final checked = tmp.contains(it.id);
                          return CheckboxListTile(
                            activeColor: _greenDark(accent),
                            checkColor: Colors.white,
                            value: checked,
                            title: Text(
                              it.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) {
                              setLocal(() {
                                if (v == true) {
                                  tmp.add(it.id);
                                } else {
                                  tmp.remove(it.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: _greenDark(accent)),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _greenDark(accent),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Aplicar',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      );
    },
  );

  if (ok != true) return null;
  return tmp;
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final Color? borderColor;
  final Color? iconColor;
  final Color? textColor;
  final VoidCallback? onTap;

  const _PillButton({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.borderColor,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? Colors.black.withValues(alpha: 0.78);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Colors.white.withValues(alpha: 0.72)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor ?? Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.80),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: iconColor ?? fg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w900, color: fg),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: fg.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniMultiList extends StatelessWidget {
  final List<_PickItem> items;
  final Set<String> selected;
  final void Function(String id, bool on) onToggle;
  final Color accent;

  const _MiniMultiList({
    required this.items,
    required this.selected,
    required this.onToggle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 170),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.10)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) {
            final it = items[i];
            final on = selected.contains(it.id);
            return Container(
              color: i.isEven
                  ? _greenPale(accent).withValues(alpha: 0.35)
                  : Colors.white,
              child: CheckboxListTile(
                dense: true,
                activeColor: _greenDark(accent),
                checkColor: Colors.white,
                value: on,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  it.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onChanged: (v) => onToggle(it.id, v == true),
              ),
            );
          },
        ),
      ),
    );
  }
}

int _weekOrder(String wk) {
  final m = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(wk);
  if (m == null) return 999999;
  final y = int.tryParse(m.group(1)!) ?? 9999;
  final w = int.tryParse(m.group(2)!) ?? 99;
  return y * 100 + w;
}

String _weekShort(String wk) {
  final m = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(wk);
  if (m == null) return wk;
  return 'W${m.group(2)}';
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

String _excelGreenForGhIndex(int i) {
  const base = ['#D9E2DD', '#C9D6C1', '#D6E0B8', '#D2DAA8', '#D7E5D2'];
  return base[i % base.length];
}
