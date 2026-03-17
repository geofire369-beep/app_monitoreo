import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/mapa_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/export/monitoreo_excel_exporter.dart';

class AdminMonitoreoTableView extends StatefulWidget {
  final GreenhouseMap map;
  final Set<String> weekKeys;

  const AdminMonitoreoTableView({
    super.key,
    required this.map,
    required this.weekKeys,
  });

  @override
  State<AdminMonitoreoTableView> createState() =>
      _AdminMonitoreoTableViewState();
}

class _AdminMonitoreoTableViewState extends State<AdminMonitoreoTableView> {
  final _fs = FirebaseFirestore.instance;

  String? _selectedPestName;
  String? _selectedPestLevel;
  String? _selectedMonitor;
  String? _selectedCapillaId;
  DateTime? _filterDate;

  final Map<String, String> _uidNameCache = {};

  bool _pestsLoaded = false;
  List<String> _pestsCache = const <String>[];
  final Map<String, List<String>> _pestLevelsByName = {};

  final ScrollController _topBarCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_ensurePestsLoaded());
  }

  @override
  void dispose() {
    _topBarCtrl.dispose();
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  String _composePestKey(String name, String? level) {
    final n = name.trim();
    final l = (level ?? '').trim();
    if (l.isEmpty) return n;
    return '$n|$l';
  }

  ({String name, String? level}) _parsePestKey(String key) {
    final raw = key.trim();
    final idx = raw.lastIndexOf('|');
    if (idx <= 0) return (name: raw, level: null);
    final name = raw.substring(0, idx).trim();
    final level = raw.substring(idx + 1).trim();
    if (name.isEmpty || level.isEmpty) return (name: raw, level: null);
    return (name: name, level: level);
  }

  String _pestLabelFromKey(String pestKey) {
    final parsed = _parsePestKey(pestKey);
    return parsed.name.trim();
  }

  String _pestLevelFromKeyOrNull(String pestKey) {
    final parsed = _parsePestKey(pestKey);
    final level = parsed.level;
    if (level == null || level.trim().isEmpty) return '-';
    return level.trim();
  }

  int _weekNumberFromKey(String weekKey) {
    final idx = weekKey.indexOf('-W');
    if (idx < 0) return 0;
    return int.tryParse(weekKey.substring(idx + 2).trim()) ?? 0;
  }

  String _greenhouseLabel(GreenhouseMap map) {
    try {
      final dyn = map as dynamic;
      final name = (dyn.name ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return map.id;
  }

  Future<void> _showExportSuccessDialog(String fileName) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final accent = AppTheme.pepperGreen;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withOpacity(0.18)),
                  ),
                  child: Icon(
                    Icons.file_download_done_rounded,
                    color: accent,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Exportación completada',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  fileName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black.withOpacity(0.65),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Entendido'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportFiltered({
    required BuildContext context,
    required GreenhouseMap map,
    required List<_RowRec> rows,
  }) async {
    final inv = _greenhouseLabel(map);

    final exportRows = rows.map((r) {
      final parsed = _parsePestKey(r.pest);
      return MonitoreoExportRow(
        invernadero: inv,
        semana: _weekNumberFromKey(r.weekKey),
        plaga: parsed.name,
        capilla: r.capillaName.trim().isEmpty ? '' : r.capillaName.trim(),
        linea: r.lineNo,
        poste: r.poste,
        total: r.total,
        nivel: (parsed.level == null || parsed.level!.trim().isEmpty)
            ? '-'
            : parsed.level!.trim(),
      );
    }).toList();

    final fileName = 'monitoreo_${inv.replaceAll(" ", "_")}.xlsx';

    await MonitoreoExcelExporter.exportSimpleTable(
      context: context,
      filename: fileName,
      rows: exportRows,
    );

    await _showExportSuccessDialog(fileName);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;
    final weeks = widget.weekKeys.isEmpty
        ? {_isoWeekKey(DateTime.now())}
        : widget.weekKeys;

    return Column(
      children: [
        Expanded(
          child: FutureBuilder<List<_RowRec>>(
            future: _loadRowsForWeeks(widget.map, weeks),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final all = snap.data!;

              final optPestNames = _buildPestNameOptions(all);
              final optPestLevels = _buildLevelOptionsForSelectedPest(
                all,
                _selectedPestName,
              );
              final optMonitors = _buildMonitorOptions(all);
              final optCaps = _buildCapillaOptions(all);

              if (_selectedPestName != null &&
                  !optPestNames.contains(_selectedPestName)) {
                _selectedPestName = null;
                _selectedPestLevel = null;
              }
              if (_selectedPestLevel != null &&
                  !optPestLevels.contains(_selectedPestLevel)) {
                _selectedPestLevel = null;
              }
              if (_selectedMonitor != null &&
                  !optMonitors.contains(_selectedMonitor)) {
                _selectedMonitor = null;
              }
              if (_selectedCapillaId != null &&
                  !optCaps.any((c) => c.id == _selectedCapillaId)) {
                _selectedCapillaId = null;
              }

              final filtered = all.where((r) {
                if (_selectedPestName != null) {
                  final parsed = _parsePestKey(r.pest);
                  if (parsed.name != _selectedPestName) return false;
                  if (_selectedPestLevel != null &&
                      (parsed.level ?? '').trim() !=
                          _selectedPestLevel!.trim()) {
                    return false;
                  }
                }

                if (_selectedMonitor != null &&
                    r.monitorName != _selectedMonitor) {
                  return false;
                }

                if (_selectedCapillaId != null &&
                    r.capillaId != _selectedCapillaId) {
                  return false;
                }

                if (_filterDate != null) {
                  final d = _filterDate!;
                  if (r.date == null) return false;
                  if (r.date!.year != d.year ||
                      r.date!.month != d.month ||
                      r.date!.day != d.day) {
                    return false;
                  }
                }

                return true;
              }).toList();

              // ✅✅✅ ORDEN: MÁS VIEJO -> MÁS NUEVO (sin tocar nada más)
              filtered.sort((a, b) {
                // 1) Fecha/hora ASC (null al final)
                final ad = a.date;
                final bd = b.date;
                if (ad == null && bd != null) return 1;
                if (ad != null && bd == null) return -1;
                if (ad != null && bd != null) {
                  final cd = ad.compareTo(bd);
                  if (cd != 0) return cd;
                }

                // 2) Semana ASC (por si hay fechas iguales o null)
                final cw = a.weekKey.compareTo(b.weekKey);
                if (cw != 0) return cw;

                // 3) Desempates: capilla, línea, poste, plaga
                int capCmp(String x, String y) {
                  final ax = x.trim();
                  final ay = y.trim();
                  if (ax.isEmpty && ay.isEmpty) return 0;
                  if (ax.isEmpty) return 1;
                  if (ay.isEmpty) return -1;
                  return ax.compareTo(ay);
                }

                final c2 = capCmp(a.capillaName, b.capillaName);
                if (c2 != 0) return c2;

                final c3 = a.lineNo.compareTo(b.lineNo);
                if (c3 != 0) return c3;

                final c4 = a.poste.compareTo(b.poste);
                if (c4 != 0) return c4;

                return _pestLabelFromKey(a.pest).toLowerCase().compareTo(
                  _pestLabelFromKey(b.pest).toLowerCase(),
                );
              });

              return Column(
                children: [
                  _FiltersBar(
                    accent: accent,
                    topBarCtrl: _topBarCtrl,
                    weeksCount: weeks.length,
                    pestNames: optPestNames,
                    selectedPestName: _selectedPestName,
                    onPestName: (v) => setState(() {
                      _selectedPestName = v;
                      _selectedPestLevel = null;
                    }),
                    pestLevels: optPestLevels,
                    selectedPestLevel: _selectedPestLevel,
                    onPestLevel: (v) => setState(() => _selectedPestLevel = v),
                    monitorOptions: optMonitors,
                    selectedMonitor: _selectedMonitor,
                    onMonitor: (v) => setState(() => _selectedMonitor = v),
                    capillaOptions: optCaps,
                    selectedCapillaId: _selectedCapillaId,
                    onCapilla: (v) => setState(() => _selectedCapillaId = v),
                    date: _filterDate,
                    onDate: (d) => setState(() => _filterDate = d),
                    onClear: () => setState(() {
                      _selectedPestName = null;
                      _selectedPestLevel = null;
                      _selectedMonitor = null;
                      _selectedCapillaId = null;
                      _filterDate = null;
                    }),
                    onAdd: () async {
                      await _showAddRecordDialog(
                        context: context,
                        weeks: weeks,
                      );
                      if (mounted) setState(() {});
                    },
                    exportEnabled: filtered.isNotEmpty,
                    onExport: () async {
                      await _exportFiltered(
                        context: context,
                        map: widget.map,
                        rows: filtered,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? _EmptyCard(
                            accent: accent,
                            title: 'Sin registros',
                            message:
                                'No hay registros para las semanas/filtros seleccionados.',
                            icon: Icons.table_rows_outlined,
                          )
                        : _TableCard(
                            accent: accent,
                            rows: filtered,
                            hCtrl: _hCtrl,
                            vCtrl: _vCtrl,
                            pestLabel: _pestLabelFromKey,
                            pestLevelLabel: _pestLevelFromKeyOrNull,
                            onEdit: (r) async {
                              await _showEditDialog(context, r);
                              if (mounted) setState(() {});
                            },
                            onDelete: (r) async {
                              await _confirmDelete(context, r);
                              if (mounted) setState(() {});
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showEditDialog(BuildContext context, _RowRec r) async {
    final accent = AppTheme.pepperGreen;

    final leftCtrl = TextEditingController(text: '${r.qtyLeft}');
    final rightCtrl = TextEditingController(text: '${r.qtyRight}');

    bool focoL = r.focoLeft;
    bool focoR = r.focoRight;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            final curL = int.tryParse(leftCtrl.text.trim()) ?? 0;
            final curR = int.tryParse(rightCtrl.text.trim()) ?? 0;

            if (curL <= 0 && focoL) focoL = false;
            if (curR <= 0 && focoR) focoR = false;

            return Container(
              width: 560,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DialogHeader(
                      accent: accent,
                      icon: Icons.edit_note_rounded,
                      title: 'Editar registro',
                      subtitle: 'Actualiza cantidades y focos del registro.',
                    ),
                    const SizedBox(height: 16),
                    _miniInfo(
                      accent,
                      'Capilla: ${r.capillaName.isEmpty ? "(Sin nombre)" : r.capillaName}\n'
                      'Línea: ${r.lineNo} • Poste: ${r.poste}\n'
                      'Plaga: ${_pestLabelFromKey(r.pest)}\n'
                      'Nivel: ${_pestLevelFromKeyOrNull(r.pest)}',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _dialogTextField(
                            controller: leftCtrl,
                            label: 'Cantidad Izquierda (L)',
                            onChanged: (_) => setLocal(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _dialogTextField(
                            controller: rightCtrl,
                            label: 'Cantidad Derecha (R)',
                            onChanged: (_) => setLocal(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (curL > 0 || curR > 0)
                      Column(
                        children: [
                          if (curL > 0)
                            _focoSwitchTile(
                              label: 'FOCO Izquierda (L)',
                              value: focoL,
                              onChanged: (v) => setLocal(() => focoL = v),
                            ),
                          if (curR > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _focoSwitchTile(
                                label: 'FOCO Derecha (R)',
                                value: focoR,
                                onChanged: (v) => setLocal(() => focoR = v),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            icon: const Icon(Icons.save_rounded),
                            label: const Text('Guardar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    if (ok != true) return;

    final newL = int.tryParse(leftCtrl.text.trim()) ?? 0;
    final newR = int.tryParse(rightCtrl.text.trim()) ?? 0;

    final finalFocoL = (newL > 0) ? focoL : false;
    final finalFocoR = (newR > 0) ? focoR : false;

    await _updateRecordQuantities(
      weekKey: r.weekKey,
      greenhouseId: widget.map.id,
      capillaId: r.capillaId,
      lineKey: r.lineKey,
      post: r.poste,
      pestKey: r.pest,
      qtyLeft: newL,
      qtyRight: newR,
      focoLeft: finalFocoL,
      focoRight: finalFocoR,
      createIfMissing: false,
    );
  }

  Future<void> _confirmDelete(BuildContext context, _RowRec r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.pepperRed.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_forever_rounded,
                  color: AppTheme.pepperRed,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Eliminar registro',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                'Se eliminará esta plaga del poste y también FOCO si existía.\n\n'
                'Capilla: ${r.capillaName.isEmpty ? "(Sin nombre)" : r.capillaName}\n'
                'Línea: ${r.lineNo} • Poste: ${r.poste}\n'
                'Plaga: ${_pestLabelFromKey(r.pest)}\n'
                'Nivel: ${_pestLevelFromKeyOrNull(r.pest)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withOpacity(0.70),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.pepperRed,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Eliminar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;

    await _deleteRecord(
      weekKey: r.weekKey,
      greenhouseId: widget.map.id,
      capillaId: r.capillaId,
      lineKey: r.lineKey,
      post: r.poste,
      pestKey: r.pest,
    );
  }

  Future<void> _showAddRecordDialog({
    required BuildContext context,
    required Set<String> weeks,
  }) async {
    final accent = AppTheme.pepperGreen;
    final weekOptions = weeks.toList()..sort((a, b) => b.compareTo(a));
    String selectedWeek = weekOptions.isNotEmpty
        ? weekOptions.first
        : _isoWeekKey(DateTime.now());

    await _ensurePestsLoaded();

    final messenger = ScaffoldMessenger.of(context);
    final caps = widget.map.capillas;

    if (caps.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No hay capillas en el mapa.')),
      );
      return;
    }

    if (_pestsCache.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No hay plagas en la colección "plagas".'),
        ),
      );
      return;
    }

    String selectedCapId = caps.first.id;
    String selectedPestName = _pestsCache.first;
    String? selectedPestLevel;

    final leftCtrl = TextEditingController(text: '0');
    final rightCtrl = TextEditingController(text: '0');

    bool focoL = false;
    bool focoR = false;

    int? selectedLineNo;
    int? selectedPost;

    List<int> lineOptionsForCap(String capId) {
      final cap = caps.firstWhere((c) => c.id == capId);
      final ls =
          cap
              .resolvedSideLines(widget.map)
              .map((e) => e.lineNo)
              .toSet()
              .toList()
            ..sort();
      return ls;
    }

    List<int> postOptionsForLine(int lineNo) {
      final ns = widget.map.lineSide(lineNo);
      final max = ns == NS.north
          ? widget.map.postsNorth
          : widget.map.postsSouth;
      if (max <= 0) return const <int>[];
      return List<int>.generate(max, (i) => i + 1);
    }

    final initLines = lineOptionsForCap(selectedCapId);
    if (initLines.isNotEmpty) selectedLineNo = initLines.first;
    final initPosts = selectedLineNo == null
        ? const <int>[]
        : postOptionsForLine(selectedLineNo!);
    if (initPosts.isNotEmpty) selectedPost = initPosts.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              final lineOptions = lineOptionsForCap(selectedCapId);
              if (selectedLineNo == null ||
                  !lineOptions.contains(selectedLineNo)) {
                selectedLineNo = lineOptions.isNotEmpty
                    ? lineOptions.first
                    : null;
              }

              final postOptions = (selectedLineNo == null)
                  ? const <int>[]
                  : postOptionsForLine(selectedLineNo!);
              if (selectedPost == null || !postOptions.contains(selectedPost)) {
                selectedPost = postOptions.isNotEmpty
                    ? postOptions.first
                    : null;
              }

              final sideLabel = (selectedLineNo == null)
                  ? ''
                  : (widget.map.lineSide(selectedLineNo!) == NS.north
                        ? 'NORTE'
                        : 'SUR');

              final curL = int.tryParse(leftCtrl.text.trim()) ?? 0;
              final curR = int.tryParse(rightCtrl.text.trim()) ?? 0;

              if (curL <= 0 && focoL) focoL = false;
              if (curR <= 0 && focoR) focoR = false;

              final levels =
                  _pestLevelsByName[selectedPestName] ?? const <String>[];
              if (levels.isNotEmpty) {
                selectedPestLevel ??= levels.first;
                if (!levels.contains(selectedPestLevel)) {
                  selectedPestLevel = levels.first;
                }
              } else {
                selectedPestLevel = null;
              }

              return Container(
                width: 620,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DialogHeader(
                        accent: accent,
                        icon: Icons.playlist_add_rounded,
                        title: 'Nuevo registro manual',
                        subtitle:
                            'Completa o corrige un registro faltante del monitoreo.',
                      ),
                      const SizedBox(height: 16),
                      _miniInfo(
                        accent,
                        'Este formulario te permite agregar un registro directamente en la semana seleccionada.',
                      ),
                      const SizedBox(height: 16),
                      _dialogDropdown<String>(
                        value: selectedWeek,
                        label: 'Semana',
                        items: weekOptions
                            .map(
                              (w) => DropdownMenuItem(value: w, child: Text(w)),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setLocal(() => selectedWeek = v ?? selectedWeek),
                      ),
                      const SizedBox(height: 12),
                      _dialogDropdown<String>(
                        value: selectedCapId,
                        label: 'Capilla',
                        items: caps.map((c) {
                          final label = (c.name ?? '').trim().isEmpty
                              ? '(Sin nombre)'
                              : c.name!.trim();
                          return DropdownMenuItem(
                            value: c.id,
                            child: Text(label),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() {
                            selectedCapId = v;
                            selectedLineNo = null;
                            selectedPost = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _dialogDropdown<int>(
                              value: selectedLineNo,
                              label: 'Línea ($sideLabel)',
                              items: lineOptions
                                  .map(
                                    (ln) => DropdownMenuItem(
                                      value: ln,
                                      child: Text('$ln'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setLocal(() {
                                selectedLineNo = v;
                                selectedPost = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dialogDropdown<int>(
                              value: selectedPost,
                              label: 'Poste',
                              items: postOptions
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text('$p'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setLocal(() => selectedPost = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _dialogDropdown<String>(
                        value: selectedPestName,
                        label: 'Plaga',
                        items: _pestsCache
                            .map(
                              (p) => DropdownMenuItem(value: p, child: Text(p)),
                            )
                            .toList(),
                        onChanged: (v) => setLocal(() {
                          selectedPestName = v ?? selectedPestName;
                          selectedPestLevel = null;
                        }),
                      ),
                      if (levels.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _dialogDropdown<String>(
                          value: selectedPestLevel,
                          label: 'Nivel',
                          items: levels
                              .map(
                                (l) =>
                                    DropdownMenuItem(value: l, child: Text(l)),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setLocal(() => selectedPestLevel = v),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _dialogTextField(
                              controller: leftCtrl,
                              label: 'Cantidad Izquierda (L)',
                              onChanged: (_) => setLocal(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dialogTextField(
                              controller: rightCtrl,
                              label: 'Cantidad Derecha (R)',
                              onChanged: (_) => setLocal(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (curL > 0 || curR > 0)
                        Column(
                          children: [
                            if (curL > 0)
                              _focoSwitchTile(
                                label: 'FOCO Izquierda (L)',
                                value: focoL,
                                onChanged: (v) => setLocal(() => focoL = v),
                              ),
                            if (curR > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _focoSwitchTile(
                                  label: 'FOCO Derecha (R)',
                                  value: focoR,
                                  onChanged: (v) => setLocal(() => focoR = v),
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Si la plaga no usa niveles, el nivel quedará como - en la tabla/exportación.',
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.62),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              icon: const Icon(Icons.save_alt_rounded),
                              label: const Text('Guardar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (ok != true) return;
    if (selectedLineNo == null || selectedPost == null) return;

    final qtyL = int.tryParse(leftCtrl.text.trim()) ?? 0;
    final qtyR = int.tryParse(rightCtrl.text.trim()) ?? 0;
    if (qtyL <= 0 && qtyR <= 0) return;

    final ns = widget.map.lineSide(selectedLineNo!);
    final lineKey = '${nsToStr(ns).toLowerCase()}_${selectedLineNo!}';

    final finalFocoL = (qtyL > 0) ? focoL : false;
    final finalFocoR = (qtyR > 0) ? focoR : false;

    final pestKey = _composePestKey(selectedPestName, selectedPestLevel);

    await _updateRecordQuantities(
      weekKey: selectedWeek,
      greenhouseId: widget.map.id,
      capillaId: selectedCapId,
      lineKey: lineKey,
      post: selectedPost!,
      pestKey: pestKey,
      qtyLeft: qtyL,
      qtyRight: qtyR,
      focoLeft: finalFocoL,
      focoRight: finalFocoR,
      createIfMissing: true,
    );
  }

  Widget _dialogTextField({
    required TextEditingController controller,
    required String label,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.black.withOpacity(0.015),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onChanged: onChanged,
    );
  }

  Widget _dialogDropdown<T>({
    required T? value,
    required String label,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.black.withOpacity(0.015),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _miniInfo(Color accent, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, height: 1.35),
      ),
    );
  }

  Widget _focoSwitchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? AppTheme.pepperRed.withOpacity(0.08)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value
              ? AppTheme.pepperRed.withOpacity(0.30)
              : Colors.black.withOpacity(0.12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.flash_on_rounded,
            color: value ? AppTheme.pepperRed : Colors.black54,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: value
                    ? AppTheme.pepperRed
                    : Colors.black.withOpacity(0.75),
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppTheme.pepperRed,
            activeTrackColor: AppTheme.pepperRed.withOpacity(0.35),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  DocumentReference<Map<String, dynamic>> _capDocRef({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
  }) {
    return _fs
        .collection('monitoreo_weeks')
        .doc(weekKey)
        .collection('greenhouses')
        .doc(greenhouseId)
        .collection('capillas')
        .doc(capillaId);
  }

  Future<void> _updateRecordQuantities({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
    required String lineKey,
    required int post,
    required String pestKey,
    required int qtyLeft,
    required int qtyRight,
    required bool focoLeft,
    required bool focoRight,
    bool createIfMissing = false,
  }) async {
    final ref = _capDocRef(
      weekKey: weekKey,
      greenhouseId: greenhouseId,
      capillaId: capillaId,
    );

    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists && !createIfMissing) return;

      final data = snap.exists
          ? Map<String, dynamic>.from(snap.data() ?? {})
          : <String, dynamic>{};
      final linesAny = data['lines'];
      final lines = (linesAny is Map)
          ? Map<String, dynamic>.from(linesAny)
          : <String, dynamic>{};

      Map<String, dynamic> payload;
      if (lines[lineKey] is Map) {
        payload = Map<String, dynamic>.from(lines[lineKey] as Map);
      } else {
        if (!createIfMissing) return;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        payload = <String, dynamic>{
          'status': 'FINISHED',
          'byUid': 'admin_manual',
          'startedAtMs': nowMs,
          'finishedAtMs': nowMs,
          'updatedAtMs': nowMs,
          'observations': <String, dynamic>{
            'left': <String, dynamic>{},
            'right': <String, dynamic>{},
          },
        };
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

      Map<String, dynamic> postMap(Map<String, dynamic> side, int post) {
        final pAny = side[post.toString()];
        if (pAny is Map) return Map<String, dynamic>.from(pAny);
        return <String, dynamic>{};
      }

      void setQty(Map<String, dynamic> side, int post, String pest, int qty) {
        final pKey = post.toString();
        final m = postMap(side, post);

        if (qty <= 0) {
          m.remove(pest);
        } else {
          m[pest] = qty;
        }

        if (m.isEmpty) {
          side.remove(pKey);
        } else {
          side[pKey] = m;
        }
      }

      setQty(left, post, pestKey, qtyLeft);
      setQty(right, post, pestKey, qtyRight);

      final baseLinePath = 'lines.$lineKey';
      final leftPath = '$baseLinePath.observations.left';
      final rightPath = '$baseLinePath.observations.right';
      final updatedAtPath = '$baseLinePath.updatedAtMs';

      final focusAny = obs['focus'];
      final focus = (focusAny is Map)
          ? Map<String, dynamic>.from(focusAny)
          : <String, dynamic>{};
      final fLeftAny = focus['left'];
      final fRightAny = focus['right'];
      final fLeft = (fLeftAny is Map)
          ? Map<String, dynamic>.from(fLeftAny)
          : <String, dynamic>{};
      final fRight = (fRightAny is Map)
          ? Map<String, dynamic>.from(fRightAny)
          : <String, dynamic>{};

      bool willPostFocusBeEmpty({
        required Map<String, dynamic> focusSide,
        required bool keepOn,
      }) {
        if (keepOn) return false;
        final pAny = focusSide[post.toString()];
        if (pAny is! Map) return false;
        final m = Map<String, dynamic>.from(pAny);
        if (!m.containsKey(pestKey)) return false;
        return m.length <= 1;
      }

      final keepLeft = (qtyLeft > 0) && focoLeft;
      final keepRight = (qtyRight > 0) && focoRight;

      final updates = <String, dynamic>{
        leftPath: left,
        rightPath: right,
        updatedAtPath: DateTime.now().millisecondsSinceEpoch,
      };

      final focusLeftPestPath =
          '$baseLinePath.observations.focus.left.${post.toString()}.$pestKey';
      final focusRightPestPath =
          '$baseLinePath.observations.focus.right.${post.toString()}.$pestKey';

      updates[focusLeftPestPath] = keepLeft ? true : FieldValue.delete();
      updates[focusRightPestPath] = keepRight ? true : FieldValue.delete();

      if (willPostFocusBeEmpty(focusSide: fLeft, keepOn: keepLeft)) {
        updates['$baseLinePath.observations.focus.left.${post.toString()}'] =
            FieldValue.delete();
      }
      if (willPostFocusBeEmpty(focusSide: fRight, keepOn: keepRight)) {
        updates['$baseLinePath.observations.focus.right.${post.toString()}'] =
            FieldValue.delete();
      }

      if (qtyLeft <= 0 && qtyRight <= 0) {
        updates[focusLeftPestPath] = FieldValue.delete();
        updates[focusRightPestPath] = FieldValue.delete();
        updates['$baseLinePath.observations.focus.left.${post.toString()}'] =
            FieldValue.delete();
        updates['$baseLinePath.observations.focus.right.${post.toString()}'] =
            FieldValue.delete();
      }

      if (!snap.exists) {
        tx.set(ref, {
          'lines': {lineKey: payload},
        }, SetOptions(merge: true));
      }

      tx.update(ref, updates);
    });
  }

  Future<void> _deleteRecord({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
    required String lineKey,
    required int post,
    required String pestKey,
  }) async {
    await _updateRecordQuantities(
      weekKey: weekKey,
      greenhouseId: greenhouseId,
      capillaId: capillaId,
      lineKey: lineKey,
      post: post,
      pestKey: pestKey,
      qtyLeft: 0,
      qtyRight: 0,
      focoLeft: false,
      focoRight: false,
      createIfMissing: false,
    );
  }

  Future<void> _ensurePestsLoaded() async {
    if (_pestsLoaded) return;
    try {
      final snap = await _fs.collection('plagas').orderBy('nombre').get();
      final out = <String>[];
      final levelsMap = <String, List<String>>{};

      for (final d in snap.docs) {
        final m = Map<String, dynamic>.from(d.data());
        final n = (m['nombre'] ?? '').toString().trim();
        if (n.isEmpty) continue;

        out.add(n);

        final nivelesAny = m['niveles'];
        if (nivelesAny is List) {
          final lv = nivelesAny
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          lv.sort((a, b) {
            final ai = int.tryParse(a);
            final bi = int.tryParse(b);
            if (ai != null && bi != null) return ai.compareTo(bi);
            return a.compareTo(b);
          });
          levelsMap[n] = lv;
        } else {
          levelsMap[n] = <String>[];
        }
      }

      if (!mounted) return;
      setState(() {
        _pestsLoaded = true;
        _pestsCache = out;
        _pestLevelsByName
          ..clear()
          ..addAll(levelsMap);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pestsLoaded = true;
        _pestsCache = const <String>[];
        _pestLevelsByName.clear();
      });
    }
  }

  List<String> _buildPestNameOptions(List<_RowRec> rows) {
    final set = <String>{};
    for (final r in rows) {
      final parsed = _parsePestKey(r.pest);
      final name = parsed.name.trim();
      if (name.isNotEmpty) set.add(name);
    }
    final out = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  List<String> _buildLevelOptionsForSelectedPest(
    List<_RowRec> rows,
    String? pestName,
  ) {
    if (pestName == null || pestName.trim().isEmpty) return const <String>[];

    final levelsFound = <String>{};
    for (final r in rows) {
      final p = _parsePestKey(r.pest);
      if (p.name != pestName) continue;
      final lv = (p.level ?? '').trim();
      if (lv.isNotEmpty) levelsFound.add(lv);
    }

    final fromCatalog = _pestLevelsByName[pestName] ?? const <String>[];
    levelsFound.addAll(
      fromCatalog.map((e) => e.trim()).where((e) => e.isNotEmpty),
    );

    final out = levelsFound.toList();
    out.sort((a, b) {
      final ai = int.tryParse(a);
      final bi = int.tryParse(b);
      if (ai != null && bi != null) return ai.compareTo(bi);
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return out;
  }

  List<String> _buildMonitorOptions(List<_RowRec> rows) {
    final set = <String>{};
    for (final r in rows) {
      final m = r.monitorName.trim();
      if (m.isNotEmpty) set.add(m);
    }
    final out = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  List<_CapOpt> _buildCapillaOptions(List<_RowRec> rows) {
    final map = <String, String>{};
    for (final r in rows) {
      map[r.capillaId] = r.capillaName;
    }

    final out =
        map.entries.map((e) => _CapOpt(id: e.key, name: e.value)).toList()
          ..sort((a, b) {
            final an = a.name.trim();
            final bn = b.name.trim();
            if (an.isEmpty && bn.isEmpty) return 0;
            if (an.isEmpty) return 1;
            if (bn.isEmpty) return -1;
            return an.toLowerCase().compareTo(bn.toLowerCase());
          });

    return out;
  }

  Future<List<_RowRec>> _loadRowsForWeeks(
    GreenhouseMap map,
    Set<String> weekKeys,
  ) async {
    final rows = <_RowRec>[];
    final uids = <String>{};

    // ✅✅✅ semanas: más vieja -> más nueva (sin tocar nada más)
    final wkSorted = weekKeys.toList()..sort((a, b) => a.compareTo(b));

    for (final weekKey in wkSorted) {
      final ghRef = _fs
          .collection('monitoreo_weeks')
          .doc(weekKey)
          .collection('greenhouses')
          .doc(map.id);
      final capsSnap = await ghRef.collection('capillas').get();

      for (final capDoc in capsSnap.docs) {
        final capId = capDoc.id;
        final capData = Map<String, dynamic>.from(capDoc.data());

        final capName = _capNameFromMap(map, capId);

        final linesAny = capData['lines'];
        if (linesAny is! Map) continue;
        final lines = Map<String, dynamic>.from(linesAny);

        for (final entry in lines.entries) {
          final lineKey = entry.key.toString();
          final payloadAny = entry.value;
          if (payloadAny is! Map) continue;
          final payload = Map<String, dynamic>.from(payloadAny);

          final byUid = (payload['byUid'] ?? '').toString().trim();
          if (byUid.isNotEmpty) uids.add(byUid);

          final startedAt = _asDateTime(
            payload['startedAt'] ?? payload['startedAtMs'],
          );
          final finishedAt = _asDateTime(
            payload['finishedAt'] ?? payload['finishedAtMs'],
          );
          final updatedAt = _asDateTime(
            payload['updatedAt'] ?? payload['updatedAtMs'],
          );

          final date = startedAt ?? finishedAt ?? updatedAt;
          final hourRange = (startedAt != null && finishedAt != null)
              ? '${_fmtHMS(startedAt)} - ${_fmtHMS(finishedAt)}'
              : (finishedAt != null
                    ? _fmtHMS(finishedAt)
                    : (updatedAt != null ? _fmtHMS(updatedAt) : ''));

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

          final focusAny = obs['focus'];
          final focus = (focusAny is Map)
              ? Map<String, dynamic>.from(focusAny)
              : <String, dynamic>{};
          final fLeftAny = focus['left'];
          final fRightAny = focus['right'];
          final fLeft = (fLeftAny is Map)
              ? Map<String, dynamic>.from(fLeftAny)
              : <String, dynamic>{};
          final fRight = (fRightAny is Map)
              ? Map<String, dynamic>.from(fRightAny)
              : <String, dynamic>{};

          final posts = <int>{};
          posts.addAll(
            left.keys
                .map((k) => int.tryParse(k.toString()) ?? -1)
                .where((x) => x > 0),
          );
          posts.addAll(
            right.keys
                .map((k) => int.tryParse(k.toString()) ?? -1)
                .where((x) => x > 0),
          );
          if (posts.isEmpty) continue;

          final parsedLine = _parseLineKey(lineKey);
          final lineNo = parsedLine.lineNo;

          for (final post in posts) {
            final pestsL = _pestsForPost(left, post);
            final pestsR = _pestsForPost(right, post);
            final allPests = <String>{...pestsL.keys, ...pestsR.keys};

            for (final pestKey in allPests) {
              final l = pestsL[pestKey] ?? 0;
              final r = pestsR[pestKey] ?? 0;
              final total = l + r;
              if (total <= 0) continue;

              final focusSides = _focusForPostPest(
                post: post,
                pestKey: pestKey,
                fLeft: fLeft,
                fRight: fRight,
              );

              rows.add(
                _RowRec(
                  weekKey: weekKey,
                  capillaId: capId,
                  capillaName: capName,
                  lineKey: lineKey,
                  lineNo: lineNo,
                  poste: post,
                  date: date,
                  hourText: hourRange,
                  byUid: byUid,
                  monitorName: '',
                  pest: pestKey,
                  qtyLeft: l,
                  qtyRight: r,
                  focoLeft: focusSides.left,
                  focoRight: focusSides.right,
                ),
              );
            }
          }
        }
      }
    }

    await _warmUserNames(uids);

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      final name = (r.byUid.isNotEmpty)
          ? (_uidNameCache[r.byUid] ?? r.byUid)
          : '';
      rows[i] = r.copyWith(monitorName: name);
    }

    return rows;
  }

  Map<String, int> _pestsForPost(Map<String, dynamic> side, int post) {
    final any = side[post.toString()];
    if (any is! Map) return const <String, int>{};
    final m = Map<String, dynamic>.from(any);
    final out = <String, int>{};
    m.forEach((k, v) {
      final n = _asInt(v);
      if (n > 0) out[k.toString()] = n;
    });
    return out;
  }

  bool _hasFocusInSide({
    required Map<String, dynamic> sideFocus,
    required int post,
    required String pestKey,
  }) {
    final pAny = sideFocus[post.toString()];
    if (pAny is! Map) return false;
    final p = Map<String, dynamic>.from(pAny);
    final v = p[pestKey];
    if (v is bool) return v;
    return v?.toString() == 'true';
  }

  ({bool left, bool right}) _focusForPostPest({
    required int post,
    required String pestKey,
    required Map<String, dynamic> fLeft,
    required Map<String, dynamic> fRight,
  }) {
    final l = _hasFocusInSide(sideFocus: fLeft, post: post, pestKey: pestKey);
    final r = _hasFocusInSide(sideFocus: fRight, post: post, pestKey: pestKey);
    return (left: l, right: r);
  }

  Future<void> _warmUserNames(Set<String> uids) async {
    final pending = uids
        .where((u) => u.isNotEmpty && !_uidNameCache.containsKey(u))
        .toList();
    if (pending.isEmpty) return;

    const chunkSize = 10;
    for (int i = 0; i < pending.length; i += chunkSize) {
      final chunk = pending.sublist(i, math.min(i + chunkSize, pending.length));
      try {
        final qs = await _fs
            .collection('app_users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in qs.docs) {
          final m = Map<String, dynamic>.from(d.data());

          final fullName = (m['fullName'] ?? '').toString().trim();
          final first = (m['firstName'] ?? '').toString().trim();
          final last = (m['lastName'] ?? '').toString().trim();

          String name;
          if (fullName.isNotEmpty) {
            name = fullName;
          } else if (first.isNotEmpty || last.isNotEmpty) {
            name = ('$first $last').trim();
          } else {
            name = (m['name'] ?? m['displayName'] ?? m['email'] ?? d.id)
                .toString()
                .trim();
          }

          _uidNameCache[d.id] = name.isEmpty ? d.id : name;
        }
      } catch (_) {}
    }
  }

  String _capNameFromMap(GreenhouseMap map, String capId) {
    final cap = map.capillas.where((c) => c.id == capId).toList();
    if (cap.isEmpty) return '';
    return (cap.first.name ?? '').trim();
  }

  _ParsedLineKey _parseLineKey(String lineKey) {
    final parts = lineKey.split('_');
    if (parts.length < 2) {
      return const _ParsedLineKey(side: 'unknown', lineNo: 0);
    }
    final side = parts[0].trim().toLowerCase();
    final lineNo = int.tryParse(parts[1].trim()) ?? 0;
    return _ParsedLineKey(side: side, lineNo: lineNo);
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

  int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  DateTime? _asDateTime(Object? v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }

  String _fmtHMS(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
}

class _FiltersBar extends StatelessWidget {
  final Color accent;
  final ScrollController topBarCtrl;
  final int weeksCount;

  final List<String> pestNames;
  final String? selectedPestName;
  final ValueChanged<String?> onPestName;

  final List<String> pestLevels;
  final String? selectedPestLevel;
  final ValueChanged<String?> onPestLevel;

  final List<String> monitorOptions;
  final String? selectedMonitor;
  final ValueChanged<String?> onMonitor;

  final List<_CapOpt> capillaOptions;
  final String? selectedCapillaId;
  final ValueChanged<String?> onCapilla;

  final DateTime? date;
  final ValueChanged<DateTime?> onDate;

  final VoidCallback onClear;
  final VoidCallback onAdd;
  final bool exportEnabled;
  final VoidCallback onExport;

  const _FiltersBar({
    required this.accent,
    required this.topBarCtrl,
    required this.weeksCount,
    required this.pestNames,
    required this.selectedPestName,
    required this.onPestName,
    required this.pestLevels,
    required this.selectedPestLevel,
    required this.onPestLevel,
    required this.monitorOptions,
    required this.selectedMonitor,
    required this.onMonitor,
    required this.capillaOptions,
    required this.selectedCapillaId,
    required this.onCapilla,
    required this.date,
    required this.onDate,
    required this.onClear,
    required this.onAdd,
    required this.exportEnabled,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label, IconData icon) => InputDecoration(
      isDense: true,
      labelText: label,
      prefixIcon: Icon(icon, size: 16, color: accent),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent.withOpacity(0.55), width: 1.2),
      ),
      labelStyle: TextStyle(
        color: accent,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );

    final dateText = (date == null)
        ? 'Fecha'
        : '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Scrollbar(
        controller: topBarCtrl,
        thumbVisibility: true,
        notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: topBarCtrl,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _TopBadge(
                accent: accent,
                icon: Icons.date_range_outlined,
                text: 'Semanas: $weeksCount',
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedPestName,
                  decoration: deco('Plaga', Icons.bug_report_outlined),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ...pestNames.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p,
                        child: Text(p, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: onPestName,
                ),
              ),
              if (selectedPestName != null && pestLevels.isNotEmpty) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedPestLevel,
                    decoration: deco('Nivel', Icons.stairs_rounded),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos'),
                      ),
                      ...pestLevels.map(
                        (l) =>
                            DropdownMenuItem<String?>(value: l, child: Text(l)),
                      ),
                    ],
                    onChanged: onPestLevel,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedMonitor,
                  decoration: deco('Monitora', Icons.person_outline),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ...monitorOptions.map(
                      (m) => DropdownMenuItem<String?>(
                        value: m,
                        child: Text(m, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: onMonitor,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedCapillaId,
                  decoration: deco('Capilla', Icons.grid_view_rounded),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ...capillaOptions.map((c) {
                      final label = c.name.trim().isEmpty
                          ? '(Sin nombre)'
                          : c.name.trim();
                      return DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(label, overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: onCapilla,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 132,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date ?? DateTime.now(),
                      firstDate: DateTime(2020, 1, 1),
                      lastDate: DateTime(2100, 1, 1),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: ColorScheme.light(
                              primary: accent,
                              onPrimary: Colors.white,
                              surface: Colors.white,
                              onSurface: const Color(0xFF1F2937),
                            ),
                            dialogTheme: DialogThemeData(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              backgroundColor: Colors.white,
                            ),
                            datePickerTheme: DatePickerThemeData(
                              backgroundColor: Colors.white,
                              surfaceTintColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              headerBackgroundColor: accent.withOpacity(0.08),
                              headerForegroundColor: accent,
                              dividerColor: Colors.black.withOpacity(0.06),
                              weekdayStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF374151),
                              ),
                              dayStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                              yearStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                              todayForegroundColor: WidgetStatePropertyAll(
                                accent,
                              ),
                              todayBackgroundColor: WidgetStatePropertyAll(
                                accent.withOpacity(0.10),
                              ),
                              dayForegroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return Colors.white;
                                    }
                                    if (states.contains(WidgetState.disabled)) {
                                      return Colors.black38;
                                    }
                                    return const Color(0xFF1F2937);
                                  }),
                              dayBackgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return accent;
                                    }
                                    return Colors.transparent;
                                  }),
                              dayOverlayColor: WidgetStatePropertyAll(
                                accent.withOpacity(0.10),
                              ),
                              yearForegroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return Colors.white;
                                    }
                                    return const Color(0xFF1F2937);
                                  }),
                              yearBackgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return accent;
                                    }
                                    return Colors.transparent;
                                  }),
                              cancelButtonStyle: TextButton.styleFrom(
                                foregroundColor: Colors.black54,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              confirmButtonStyle: TextButton.styleFrom(
                                foregroundColor: accent,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          child: child ?? const SizedBox.shrink(),
                        );
                      },
                    );

                    onDate(picked);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: Colors.black.withOpacity(0.16)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  icon: const Icon(Icons.event_outlined, size: 16),
                  label: Text(dateText, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              _ActionPillButton(
                icon: Icons.refresh_rounded,
                label: 'Limpiar',
                color: accent,
                onPressed: onClear,
              ),
              const SizedBox(width: 8),
              _ActionPillButton(
                icon: Icons.add_rounded,
                label: 'Nuevo',
                color: accent,
                onPressed: onAdd,
              ),
              const SizedBox(width: 8),
              _ActionPillButton(
                icon: Icons.file_download_rounded,
                label: 'Exportar',
                color: accent,
                onPressed: exportEnabled ? onExport : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBadge extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String text;

  const _TopBadge({
    required this.accent,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ActionPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionPillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: disabled ? Colors.black12 : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: disabled ? Colors.black12 : color.withOpacity(0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: disabled ? Colors.black38 : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: disabled ? Colors.black38 : color,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;

  const _DialogHeader({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            shape: BoxShape.circle,
            border: Border.all(color: accent.withOpacity(0.18)),
          ),
          child: Icon(icon, color: accent, size: 30),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black.withOpacity(0.65),
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _MiniActionIcon extends StatelessWidget {
  final Color bg;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _MiniActionIcon({
    required this.bg,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final Color accent;
  final List<_RowRec> rows;
  final ScrollController hCtrl;
  final ScrollController vCtrl;
  final String Function(String pestKey) pestLabel;
  final String Function(String pestKey) pestLevelLabel;
  final ValueChanged<_RowRec> onEdit;
  final ValueChanged<_RowRec> onDelete;

  const _TableCard({
    required this.accent,
    required this.rows,
    required this.hCtrl,
    required this.vCtrl,
    required this.pestLabel,
    required this.pestLevelLabel,
    required this.onEdit,
    required this.onDelete,
  });

  Widget _head(String text, {double? width}) => SizedBox(
    width: width,
    child: Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 12,
        height: 1.15,
      ),
    ),
  );

  Widget _cellText(String text, {double? width}) => SizedBox(
    width: width,
    child: Text(
      text,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Scrollbar(
          controller: hCtrl,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: hCtrl,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: screenWidth - 32),
              child: Scrollbar(
                controller: vCtrl,
                thumbVisibility: true,
                notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                child: SingleChildScrollView(
                  controller: vCtrl,
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.black.withOpacity(0.05)),
                    child: DataTable(
                      headingRowHeight: 56,
                      dataRowMinHeight: 42,
                      dataRowMaxHeight: 56,
                      horizontalMargin: 8,
                      columnSpacing: 10,
                      showBottomBorder: true,
                      headingRowColor: WidgetStatePropertyAll(
                        accent.withOpacity(0.10),
                      ),
                      headingTextStyle: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.black.withOpacity(0.88),
                        fontSize: 12,
                      ),
                      dataTextStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withOpacity(0.82),
                        fontSize: 12,
                      ),
                      columns: [
                        DataColumn(label: _head('Capilla', width: 100)),
                        DataColumn(label: _head('Línea', width: 42)),
                        DataColumn(label: _head('Poste', width: 42)),
                        DataColumn(label: _head('Fecha', width: 90)),
                        DataColumn(label: _head('Hora', width: 110)),
                        DataColumn(label: _head('Monitora', width: 120)),
                        DataColumn(label: _head('Plaga', width: 130)),
                        DataColumn(label: _head('Nivel', width: 66)),
                        DataColumn(label: _head('Izq', width: 38)),
                        DataColumn(label: _head('Der', width: 38)),
                        DataColumn(label: _head('Total', width: 56)),
                        DataColumn(label: _head('FOCO L', width: 64)),
                        DataColumn(label: _head('FOCO R', width: 64)),
                        DataColumn(label: _head('Acciones', width: 78)),
                      ],
                      rows: rows.asMap().entries.map((entry) {
                        final i = entry.key;
                        final r = entry.value;

                        final dateText = r.date == null
                            ? ''
                            : '${r.date!.year}-${r.date!.month.toString().padLeft(2, '0')}-${r.date!.day.toString().padLeft(2, '0')}';

                        final capCell = r.capillaName.trim().isEmpty
                            ? '(Sin nombre)'
                            : r.capillaName.trim();

                        final rowBg = i.isOdd
                            ? Colors.black.withOpacity(0.015)
                            : Colors.transparent;

                        Widget focoChip(bool on) {
                          if (!on) {
                            return Text(
                              '—',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.30),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            );
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.pepperRed.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppTheme.pepperRed.withOpacity(0.20),
                              ),
                            ),
                            child: Text(
                              'Sí',
                              style: TextStyle(
                                color: AppTheme.pepperRed,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }

                        Widget totalChip(int total) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: accent.withOpacity(0.18),
                              ),
                            ),
                            child: Text(
                              '$total',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: accent,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }

                        return DataRow(
                          color: WidgetStatePropertyAll(rowBg),
                          cells: [
                            DataCell(_cellText(capCell, width: 100)),
                            DataCell(_cellText('${r.lineNo}', width: 42)),
                            DataCell(_cellText('${r.poste}', width: 42)),
                            DataCell(_cellText(dateText, width: 90)),
                            DataCell(_cellText(r.hourText, width: 110)),
                            DataCell(
                              _cellText(
                                r.monitorName.isEmpty ? r.byUid : r.monitorName,
                                width: 120,
                              ),
                            ),
                            DataCell(_cellText(pestLabel(r.pest), width: 130)),
                            DataCell(
                              _cellText(pestLevelLabel(r.pest), width: 66),
                            ),
                            DataCell(_cellText('${r.qtyLeft}', width: 38)),
                            DataCell(_cellText('${r.qtyRight}', width: 38)),
                            DataCell(Center(child: totalChip(r.total))),
                            DataCell(Center(child: focoChip(r.focoLeft))),
                            DataCell(Center(child: focoChip(r.focoRight))),
                            DataCell(
                              Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _MiniActionIcon(
                                      bg: accent.withOpacity(0.08),
                                      color: accent,
                                      icon: Icons.edit_rounded,
                                      onTap: () => onEdit(r),
                                    ),
                                    const SizedBox(width: 6),
                                    _MiniActionIcon(
                                      bg: AppTheme.pepperRed.withOpacity(0.08),
                                      color: AppTheme.pepperRed,
                                      icon: Icons.delete_outline_rounded,
                                      onTap: () => onDelete(r),
                                    ),
                                  ],
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
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final Color accent;
  final String title;
  final String message;
  final IconData icon;

  const _EmptyCard({
    required this.accent,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 650),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withOpacity(0.18)),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.70),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParsedLineKey {
  final String side;
  final int lineNo;
  const _ParsedLineKey({required this.side, required this.lineNo});
}

class _CapOpt {
  final String id;
  final String name;
  const _CapOpt({required this.id, required this.name});
}

class _RowRec {
  final String weekKey;
  final String capillaId;
  final String capillaName;
  final String lineKey;
  final int lineNo;
  final int poste;
  final DateTime? date;
  final String hourText;
  final String byUid;
  final String monitorName;
  final String pest;
  final int qtyLeft;
  final int qtyRight;
  final bool focoLeft;
  final bool focoRight;

  const _RowRec({
    required this.weekKey,
    required this.capillaId,
    required this.capillaName,
    required this.lineKey,
    required this.lineNo,
    required this.poste,
    required this.date,
    required this.hourText,
    required this.byUid,
    required this.monitorName,
    required this.pest,
    required this.qtyLeft,
    required this.qtyRight,
    required this.focoLeft,
    required this.focoRight,
  });

  int get total => qtyLeft + qtyRight;

  _RowRec copyWith({String? monitorName}) {
    return _RowRec(
      weekKey: weekKey,
      capillaId: capillaId,
      capillaName: capillaName,
      lineKey: lineKey,
      lineNo: lineNo,
      poste: poste,
      date: date,
      hourText: hourText,
      byUid: byUid,
      monitorName: monitorName ?? this.monitorName,
      pest: pest,
      qtyLeft: qtyLeft,
      qtyRight: qtyRight,
      focoLeft: focoLeft,
      focoRight: focoRight,
    );
  }
}
