// lib/pages/admin/admin_trap_monitoreo_table_view.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/mapa_model.dart';
import '../../theme/app_theme.dart';

class AdminTrapMonitoreoTableView extends StatefulWidget {
  final GreenhouseMap map;
  final Set<String> weekKeys;

  const AdminTrapMonitoreoTableView({
    super.key,
    required this.map,
    required this.weekKeys,
  });

  @override
  State<AdminTrapMonitoreoTableView> createState() =>
      _AdminTrapMonitoreoTableViewState();
}

class _AdminTrapMonitoreoTableViewState
    extends State<AdminTrapMonitoreoTableView> {
  final _fs = FirebaseFirestore.instance;

  // ✅ filtros (SIN filtro por línea)
  String? _selectedPest;
  String? _selectedMonitor;
  String? _selectedCapillaId;
  DateTime? _filterDate;

  final Map<String, String> _uidNameCache = {};

  final ScrollController _topBarCtrl = ScrollController();
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  @override
  void dispose() {
    _topBarCtrl.dispose();
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  String _greenhouseLabel(GreenhouseMap map) {
    try {
      final dyn = map as dynamic;
      final name = (dyn.name ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return map.id;
  }

  int _lineNoFromKey(String lineKey) {
    // north_7 / south_12 / etc -> 7 / 12
    final parts = lineKey.split('_');
    if (parts.length < 2) return 0;
    return int.tryParse(parts.last.trim()) ?? 0;
  }

  String _lineLabelOnlyNumber(String lineKey) => '${_lineNoFromKey(lineKey)}';

  bool _lineIsNorth(String lineKey) =>
      lineKey.toLowerCase().startsWith('north_');

  // ✅ semanas permitidas: actual y pasada
  Set<String> _allowedWeeksTwo() {
    final now = DateTime.now();
    final cur = _isoWeekKey(now);
    final prev = _isoWeekKey(now.subtract(const Duration(days: 7)));
    return {cur, prev};
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ✅ capilla lines: primero intenta cap.lines, si no, deriva por columns
  List<String> _lineKeysForCapilla(GreenhouseMap map, String capId) {
    // 1) si existe cap.lines en tu modelo
    try {
      final cap = map.capillas.firstWhere((c) => c.id == capId);
      final dynCap = cap as dynamic;
      final linesAny = dynCap.lines;
      if (linesAny is Iterable) {
        final out = <String>{};
        for (final l in linesAny) {
          final dl = l as dynamic;
          final side = dl.side; // NS
          final lineNo = dl.lineNo; // int
          final k = '${nsToStr(side).toLowerCase()}_${(lineNo as int)}';
          out.add(k);
        }
        final list = out.toList()
          ..sort((a, b) {
            final na = _lineNoFromKey(a);
            final nb = _lineNoFromKey(b);
            final ca = _lineIsNorth(a) ? 1 : 0; // south primero
            final cb = _lineIsNorth(b) ? 1 : 0;
            if (ca != cb) return ca.compareTo(cb);
            return na.compareTo(nb);
          });
        return list;
      }
    } catch (_) {
      // fallthrough
    }

    // 2) fallback: columnInfo
    final set = <String>{};
    for (int col = 0; col < map.totalColumns; col++) {
      final ci = map.columnInfo(col);
      if (ci.capilla.id != capId) continue;
      final n = ci.northLineNo;
      final s = ci.southLineNo;
      if (s != null) set.add('south_$s');
      if (n != null) set.add('north_$n');
    }

    final out = set.toList()
      ..sort((a, b) {
        final sa = _lineIsNorth(a) ? 1 : 0; // south primero
        final sb = _lineIsNorth(b) ? 1 : 0;
        if (sa != sb) return sa.compareTo(sb);
        return _lineNoFromKey(a).compareTo(_lineNoFromKey(b));
      });

    return out;
  }

  // ✅ traps activas para capilla+lineKey
  List<TrapDef> _trapsForCapLine(
    GreenhouseMap map,
    String capId,
    String lineKey,
  ) {
    final side = _lineIsNorth(lineKey) ? NS.north : NS.south;
    final ln = _lineNoFromKey(lineKey);

    // guardrail: validar que esa línea existe en esa capilla
    bool capHasLine = false;
    for (int col = 0; col < map.totalColumns; col++) {
      final ci = map.columnInfo(col);
      if (ci.capilla.id != capId) continue;
      final capLn = (side == NS.north) ? ci.northLineNo : ci.southLineNo;
      if (capLn == ln) {
        capHasLine = true;
        break;
      }
    }
    if (!capHasLine) return const [];

    final out = <TrapDef>[];

    for (final t in map.traps) {
      bool isActive = true;
      try {
        final dyn = t as dynamic;
        if (dyn.active is bool) isActive = dyn.active as bool;
      } catch (_) {}
      if (!isActive) continue;

      final any = t.cells.any((c) {
        if (c.side != side) return false;
        if (c.lineNo != ln) return false;
        try {
          if (!map.isActive(c.side, c.poste, c.lineNo)) return false;
        } catch (_) {}
        return true;
      });

      if (any) out.add(t);
    }

    out.sort((a, b) {
      final an = (a.name).trim();
      final bn = (b.name).trim();
      final la = an.isEmpty ? a.id : an;
      final lb = bn.isEmpty ? b.id : bn;
      return la.toLowerCase().compareTo(lb.toLowerCase());
    });

    return out;
  }

  // ✅ SOLO para "Nuevo": líneas de la capilla que SÍ tienen trampas activas
  // (Optimizado: 1 pasada por traps)
  List<String> _lineKeysForCapillaWithTraps(GreenhouseMap map, String capId) {
    final capLines = _lineKeysForCapilla(map, capId);
    if (capLines.isEmpty) return const [];

    final valid = capLines.toSet();
    final hasTraps = <String>{};

    for (final t in map.traps) {
      bool isActive = true;
      try {
        final dyn = t as dynamic;
        if (dyn.active is bool) isActive = dyn.active as bool;
      } catch (_) {}
      if (!isActive) continue;

      for (final c in t.cells) {
        final lk = '${nsToStr(c.side).toLowerCase()}_${c.lineNo}';
        if (!valid.contains(lk)) continue;
        try {
          if (!map.isActive(c.side, c.poste, c.lineNo)) continue;
        } catch (_) {}
        hasTraps.add(lk);
      }
    }

    return capLines.where(hasTraps.contains).toList();
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
          child: FutureBuilder<List<_TrapRowRec>>(
            future: _loadRowsForWeeks(widget.map, weeks),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final all = snap.data!;

              final optPests = _buildPestOptions(all);
              final optMonitors = _buildMonitorOptions(all);
              final optCaps = _buildCapillaOptions(all);

              if (_selectedPest != null && !optPests.contains(_selectedPest)) {
                _selectedPest = null;
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
                if (_selectedPest != null && r.pest != _selectedPest) {
                  return false;
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

              // ✅ ORDEN: más reciente -> más viejo (principal),
              // luego capilla, luego línea, luego trampa, luego plaga
              filtered.sort((a, b) {
                final da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
                final db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
                final c0 = db.compareTo(da);
                if (c0 != 0) return c0;

                int capCmp(String x, String y) {
                  final ax = x.trim();
                  final ay = y.trim();
                  if (ax.isEmpty && ay.isEmpty) return 0;
                  if (ax.isEmpty) return 1;
                  if (ay.isEmpty) return -1;
                  return ax.toLowerCase().compareTo(ay.toLowerCase());
                }

                final c1 = capCmp(a.capillaName, b.capillaName);
                if (c1 != 0) return c1;

                final la = _lineNoFromKey(a.lineKey);
                final lb = _lineNoFromKey(b.lineKey);
                final c2 = la.compareTo(lb);
                if (c2 != 0) return c2;

                final c3 = a.trapName.toLowerCase().compareTo(
                  b.trapName.toLowerCase(),
                );
                if (c3 != 0) return c3;

                return a.pest.toLowerCase().compareTo(b.pest.toLowerCase());
              });

              return Column(
                children: [
                  _FiltersBarTrap(
                    accent: accent,
                    topBarCtrl: _topBarCtrl,
                    greenhouseLabel: _greenhouseLabel(widget.map),
                    weeksCount: weeks.length,
                    pestOptions: optPests,
                    selectedPest: _selectedPest,
                    onPest: (v) => setState(() => _selectedPest = v),
                    monitorOptions: optMonitors,
                    selectedMonitor: _selectedMonitor,
                    onMonitor: (v) => setState(() => _selectedMonitor = v),
                    capillaOptions: optCaps,
                    selectedCapillaId: _selectedCapillaId,
                    onCapilla: (v) => setState(() => _selectedCapillaId = v),
                    date: _filterDate,
                    onDate: (d) => setState(() => _filterDate = d),
                    onClear: () => setState(() {
                      _selectedPest = null;
                      _selectedMonitor = null;
                      _selectedCapillaId = null;
                      _filterDate = null;
                    }),
                    onAdd: () async {
                      // ✅ abrir SIEMPRE el diálogo; validaciones dentro del diálogo
                      await _showAddDialog(context: context, weeks: weeks);
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? _EmptyCard(
                            accent: accent,
                            title: 'Sin registros',
                            message:
                                'No hay registros de trampas para las semanas/filtros seleccionados.',
                            icon: Icons.table_rows_outlined,
                          )
                        : _TrapTableCard(
                            accent: accent,
                            rows: filtered,
                            hCtrl: _hCtrl,
                            vCtrl: _vCtrl,
                            lineNoFromKey: _lineNoFromKey,
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

  // ========================= dialogs =========================

  Future<void> _showEditDialog(BuildContext context, _TrapRowRec r) async {
    final accent = AppTheme.pepperGreen;

    final qtyCtrl = TextEditingController(text: '${r.qty}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
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
                      subtitle:
                          'Actualiza la cantidad de la plaga en la trampa.',
                    ),
                    const SizedBox(height: 16),
                    _miniInfo(
                      accent,
                      'Capilla: ${r.capillaName.isEmpty ? "(Sin nombre)" : r.capillaName}\n'
                      'Línea: ${_lineNoFromKey(r.lineKey)}\n'
                      'Trampa: ${r.trapName}\n'
                      'Plaga: ${r.pest}',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Cantidad',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.015),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onChanged: (_) => setLocal(() {}),
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

    final newQty = int.tryParse(qtyCtrl.text.trim()) ?? 0;

    await _updateTrapPestQty(
      weekKey: r.weekKey,
      greenhouseId: widget.map.id,
      capillaId: r.capillaId,
      lineKey: r.lineKey,
      trapId: r.trapId,
      trapName: r.trapName,
      pest: r.pest,
      qty: newQty,
      createIfMissing: false,
    );
  }

  Future<void> _confirmDelete(BuildContext context, _TrapRowRec r) async {
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
                'Se eliminará esta plaga de la trampa.\n\n'
                'Capilla: ${r.capillaName.isEmpty ? "(Sin nombre)" : r.capillaName}\n'
                'Línea: ${_lineNoFromKey(r.lineKey)}\n'
                'Trampa: ${r.trapName}\n'
                'Plaga: ${r.pest}',
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

    await _updateTrapPestQty(
      weekKey: r.weekKey,
      greenhouseId: widget.map.id,
      capillaId: r.capillaId,
      lineKey: r.lineKey,
      trapId: r.trapId,
      trapName: r.trapName,
      pest: r.pest,
      qty: 0,
      createIfMissing: false,
    );
  }

  // ✅ NUEVO (corregido): validaciones se hacen DENTRO del diálogo (no al presionar "Nuevo")
  Future<void> _showAddDialog({
    required BuildContext context,
    required Set<String> weeks,
  }) async {
    final accent = AppTheme.pepperGreen;

    // permitidas
    final allowedWeeks = _allowedWeeksTwo().toList()
      ..sort((a, b) => b.compareTo(a));
    final allowedSet = allowedWeeks.toSet();

    // solo para mostrar aviso dentro del diálogo
    final requested = weeks.toList()..sort((a, b) => b.compareTo(a));
    final hasExtras = requested.any((w) => !allowedSet.contains(w));
    final warningText = hasExtras
        ? 'Únicamente permitido semanas: ${allowedWeeks.join(", ")}'
        : null;

    final caps = widget.map.capillas;
    if (caps.isEmpty) {
      _showSnack('No hay capillas en el mapa.');
      return;
    }

    // intenta arrancar en una capilla que sí tenga líneas con trampas
    String selectedCapId = caps.first.id;
    for (final c in caps) {
      final lines = _lineKeysForCapillaWithTraps(widget.map, c.id);
      if (lines.isNotEmpty) {
        selectedCapId = c.id;
        break;
      }
    }

    // estado inicial (puede quedar vacío; se manejará dentro del diálogo)
    String selectedWeek = allowedWeeks.first;

    List<String> lineOptions = _lineKeysForCapillaWithTraps(
      widget.map,
      selectedCapId,
    );
    String selectedLineKey = lineOptions.isNotEmpty ? lineOptions.first : '';

    List<TrapDef> trapOptions = selectedLineKey.isEmpty
        ? const []
        : _trapsForCapLine(widget.map, selectedCapId, selectedLineKey);
    TrapDef? selectedTrap = trapOptions.isNotEmpty ? trapOptions.first : null;

    const otherOption = 'Otra…';
    String? selectedPest;
    final pestOtherCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');

    String capLabelById(String id) {
      final cap = caps.where((c) => c.id == id).toList();
      if (cap.isEmpty) return id;
      final name = (cap.first.name ?? '').toString().trim();
      return name.isEmpty ? '(Sin nombre)' : name;
    }

    String trapLabel(TrapDef t) {
      final n = t.name.toString().trim();
      return n.isEmpty ? t.id : n;
    }

    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.black.withOpacity(0.015),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );

    bool canSaveNow() {
      if (selectedLineKey.trim().isEmpty) return false;
      if (selectedTrap == null) return false;
      final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
      if (qty <= 0) return false;

      final pestSel = (selectedPest ?? '').trim();
      if (pestSel.isEmpty) return false;
      if (pestSel == otherOption && pestOtherCtrl.text.trim().isEmpty) {
        return false;
      }
      return true;
    }

    void recalcForCap({required void Function(void Function()) setLocal}) {
      lineOptions = _lineKeysForCapillaWithTraps(widget.map, selectedCapId);

      if (lineOptions.isEmpty) {
        selectedLineKey = '';
        trapOptions = const [];
        selectedTrap = null;
        return;
      }

      if (!lineOptions.contains(selectedLineKey)) {
        selectedLineKey = lineOptions.first;
      }

      trapOptions = _trapsForCapLine(
        widget.map,
        selectedCapId,
        selectedLineKey,
      );
      if (trapOptions.isEmpty) {
        selectedTrap = null;
      } else {
        if (selectedTrap == null ||
            trapOptions.every((t) => t.id != selectedTrap!.id)) {
          selectedTrap = trapOptions.first;
        }
      }
    }

    void recalcForLine({required void Function(void Function()) setLocal}) {
      if (selectedLineKey.trim().isEmpty) {
        trapOptions = const [];
        selectedTrap = null;
        return;
      }

      trapOptions = _trapsForCapLine(
        widget.map,
        selectedCapId,
        selectedLineKey,
      );
      selectedTrap = trapOptions.isNotEmpty ? trapOptions.first : null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            // ✅ aquí sí hacemos validaciones/recalculos (ya dentro del menú)
            // (solo “normaliza” si quedaron combos inválidos por cambios previos)
            if (selectedLineKey.isNotEmpty &&
                !lineOptions.contains(selectedLineKey)) {
              recalcForCap(setLocal: setLocal);
            }

            return Container(
              width: 680,
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
                      title: 'Nuevo registro (trampa)',
                      subtitle:
                          'Selecciona semana, capilla, línea, trampa y plaga.',
                    ),
                    const SizedBox(height: 14),

                    if (warningText != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.pepperRed.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.pepperRed.withOpacity(0.18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: AppTheme.pepperRed,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                warningText,
                                style: TextStyle(
                                  color: Colors.black.withOpacity(0.78),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    _miniInfo(
                      accent,
                      'Semanas permitidas: ${allowedWeeks.join(" / ")}',
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      value: selectedWeek,
                      decoration: deco('Semana'),
                      items: allowedWeeks
                          .map(
                            (w) => DropdownMenuItem(value: w, child: Text(w)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setLocal(() => selectedWeek = v ?? selectedWeek),
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: selectedCapId,
                      decoration: deco('Capilla'),
                      items: caps
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: Text(capLabelById(c.id)),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setLocal(() {
                          selectedCapId = v;
                          // ✅ al elegir capilla, recalcula líneas (solo con trampas)
                          recalcForCap(setLocal: setLocal);
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: (lineOptions.contains(selectedLineKey))
                          ? selectedLineKey
                          : (lineOptions.isEmpty ? null : lineOptions.first),
                      decoration: deco('Línea (solo número)'),
                      items: lineOptions
                          .map(
                            (lk) => DropdownMenuItem<String>(
                              value: lk,
                              child: Text(_lineLabelOnlyNumber(lk)),
                            ),
                          )
                          .toList(),
                      onChanged: lineOptions.isEmpty
                          ? null
                          : (v) {
                              if (v == null) return;
                              setLocal(() {
                                selectedLineKey = v;
                                // ✅ al elegir línea, recalcula trampas
                                recalcForLine(setLocal: setLocal);
                              });
                            },
                    ),
                    if (lineOptions.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Esta capilla no tiene líneas con trampas activas.',
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.65),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: (selectedTrap == null)
                          ? null
                          : (trapOptions.any((t) => t.id == selectedTrap!.id)
                                ? selectedTrap!.id
                                : null),
                      decoration: deco('Trampa'),
                      items: trapOptions
                          .map(
                            (t) => DropdownMenuItem<String>(
                              value: t.id,
                              child: Text(trapLabel(t)),
                            ),
                          )
                          .toList(),
                      onChanged: trapOptions.isEmpty
                          ? null
                          : (v) {
                              if (v == null) return;
                              setLocal(() {
                                selectedTrap = trapOptions.firstWhere(
                                  (t) => t.id == v,
                                );
                              });
                            },
                    ),
                    if (trapOptions.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'No hay trampas activas para esa línea.',
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.65),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _fs
                          .collection('plagas')
                          .orderBy('nombre')
                          .snapshots(),
                      builder: (ctx2, snapP) {
                        final list = <String>[];
                        if (snapP.hasData) {
                          for (final d in snapP.data!.docs) {
                            final m = d.data();
                            final nombre = (m['nombre'] ?? '')
                                .toString()
                                .trim();
                            if (nombre.isNotEmpty) list.add(nombre);
                          }
                        }
                        list.sort(
                          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                        );
                        if (!list.contains(otherOption)) list.add(otherOption);

                        // default selection
                        if ((selectedPest == null || selectedPest!.isEmpty) &&
                            list.isNotEmpty) {
                          selectedPest = list.first;
                        }
                        if (selectedPest != null &&
                            !list.contains(selectedPest)) {
                          selectedPest = list.isNotEmpty ? list.first : null;
                        }

                        return Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: selectedPest,
                              decoration: deco('Plaga'),
                              items: list
                                  .map(
                                    (p) => DropdownMenuItem<String>(
                                      value: p,
                                      child: Text(
                                        p,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setLocal(() => selectedPest = v),
                            ),
                            if (selectedPest == otherOption) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: pestOtherCtrl,
                                decoration: deco('Escribe la plaga'),
                                onChanged: (_) => setLocal(() {}),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: deco('Cantidad'),
                      onChanged: (_) => setLocal(() {}),
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
                            onPressed: canSaveNow()
                                ? () => Navigator.pop(ctx, true)
                                : null,
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
      ),
    );

    if (ok != true) return;

    // ✅ Validación final (por si cambió algo raro)
    if (selectedLineKey.trim().isEmpty) {
      _showSnack('Selecciona una línea válida.');
      return;
    }
    if (selectedTrap == null) {
      _showSnack('Selecciona una trampa.');
      return;
    }

    var pest = (selectedPest ?? '').trim();
    if (pest == otherOption) pest = pestOtherCtrl.text.trim();

    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
    if (pest.isEmpty || qty <= 0) {
      _showSnack('Plaga y cantidad son obligatorias.');
      return;
    }

    final trapId = selectedTrap!.id;
    final trapName = (selectedTrap!.name).toString().trim().isNotEmpty
        ? (selectedTrap!.name).toString().trim()
        : trapId;

    await _updateTrapPestQty(
      weekKey: selectedWeek,
      greenhouseId: widget.map.id,
      capillaId: selectedCapId,
      lineKey: selectedLineKey,
      trapId: trapId,
      trapName: trapName,
      pest: pest,
      qty: qty,
      createIfMissing: true,
    );
  }

  // ========================= Firestore update =========================

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

  Future<void> _updateTrapPestQty({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
    required String lineKey,
    required String trapId,
    required String trapName,
    required String pest,
    required int qty,
    required bool createIfMissing,
  }) async {
    final ref = _capDocRef(
      weekKey: weekKey,
      greenhouseId: greenhouseId,
      capillaId: capillaId,
    );

    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists && !createIfMissing) return;

      final base = snap.exists
          ? Map<String, dynamic>.from(snap.data() ?? {})
          : <String, dynamic>{};

      final trapLinesAny = base['trapLines'];
      final trapLines = (trapLinesAny is Map)
          ? Map<String, dynamic>.from(trapLinesAny)
          : <String, dynamic>{};

      Map<String, dynamic> linePayload;
      if (trapLines[lineKey] is Map) {
        linePayload = Map<String, dynamic>.from(trapLines[lineKey] as Map);
      } else {
        if (!createIfMissing) return;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        linePayload = <String, dynamic>{
          'status': 'FINISHED',
          'byUid': 'admin_manual',
          'startedAtMs': nowMs,
          'finishedAtMs': nowMs,
          'updatedAtMs': nowMs,
          'observations': <String, dynamic>{'traps': <String, dynamic>{}},
        };
      }

      final obsAny = linePayload['observations'];
      final obs = (obsAny is Map)
          ? Map<String, dynamic>.from(obsAny)
          : <String, dynamic>{};

      final trapsAny = obs['traps'];
      final traps = (trapsAny is Map)
          ? Map<String, dynamic>.from(trapsAny)
          : <String, dynamic>{};

      Map<String, dynamic> trapObj;
      if (traps[trapId] is Map) {
        trapObj = Map<String, dynamic>.from(traps[trapId] as Map);
      } else {
        trapObj = <String, dynamic>{
          'name': trapName,
          'counts': <String, dynamic>{},
        };
      }

      final existingName = (trapObj['name'] ?? '').toString().trim();
      if (trapName.trim().isNotEmpty && trapName.trim() != existingName) {
        trapObj['name'] = trapName.trim();
      }

      final countsAny = trapObj['counts'];
      final counts = (countsAny is Map)
          ? Map<String, dynamic>.from(countsAny)
          : <String, dynamic>{};

      if (qty <= 0) {
        counts.remove(pest);
      } else {
        counts[pest] = qty;
      }

      if (counts.isEmpty) {
        traps.remove(trapId);
      } else {
        trapObj['counts'] = counts;
        traps[trapId] = trapObj;
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      final updates = <String, dynamic>{
        'trapLines.$lineKey.observations.traps': traps,
        'trapLines.$lineKey.updatedAtMs': now,
      };

      if (!snap.exists) {
        tx.set(ref, {
          'trapLines': {lineKey: linePayload},
        }, SetOptions(merge: true));
      } else {
        if (trapLines[lineKey] == null && createIfMissing) {
          tx.set(ref, {
            'trapLines': {lineKey: linePayload},
          }, SetOptions(merge: true));
        }
      }

      tx.update(ref, updates);
    });
  }

  // ========================= loaders =========================

  Future<List<_TrapRowRec>> _loadRowsForWeeks(
    GreenhouseMap map,
    Set<String> weekKeys,
  ) async {
    final rows = <_TrapRowRec>[];
    final uids = <String>{};

    final wkSorted = weekKeys.toList()..sort((a, b) => b.compareTo(a));

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

        final trapLinesAny = capData['trapLines'];
        if (trapLinesAny is! Map) continue;

        final trapLines = Map<String, dynamic>.from(trapLinesAny);

        for (final entry in trapLines.entries) {
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

          final trapsAny = obs['traps'];
          final trapsObs = (trapsAny is Map)
              ? Map<String, dynamic>.from(trapsAny)
              : <String, dynamic>{};

          if (trapsObs.isEmpty) continue;

          for (final tEntry in trapsObs.entries) {
            final trapId = tEntry.key.toString();
            final tAny = tEntry.value;
            if (tAny is! Map) continue;

            final t = Map<String, dynamic>.from(tAny);
            final trapName = (t['name'] ?? '').toString().trim().isEmpty
                ? trapId
                : (t['name'] ?? '').toString().trim();

            final countsAny = t['counts'];
            final counts = (countsAny is Map)
                ? Map<String, dynamic>.from(countsAny)
                : <String, dynamic>{};

            if (counts.isEmpty) continue;

            for (final c in counts.entries) {
              final pest = c.key.toString().trim();
              final qty = _asInt(c.value);
              if (pest.isEmpty || qty <= 0) continue;

              rows.add(
                _TrapRowRec(
                  weekKey: weekKey,
                  capillaId: capId,
                  capillaName: capName,
                  lineKey: lineKey,
                  trapId: trapId,
                  trapName: trapName,
                  date: date,
                  hourText: hourRange,
                  byUid: byUid,
                  monitorName: '',
                  pest: pest,
                  qty: qty,
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

  // ========================= filter option builders =========================

  List<String> _buildPestOptions(List<_TrapRowRec> rows) {
    final set = <String>{};
    for (final r in rows) {
      final p = r.pest.trim();
      if (p.isNotEmpty) set.add(p);
    }
    final out = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  List<String> _buildMonitorOptions(List<_TrapRowRec> rows) {
    final set = <String>{};
    for (final r in rows) {
      final m = r.monitorName.trim();
      if (m.isNotEmpty) set.add(m);
    }
    final out = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  List<_CapOpt> _buildCapillaOptions(List<_TrapRowRec> rows) {
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

  // ========================= small helpers =========================

  String _capNameFromMap(GreenhouseMap map, String capId) {
    final cap = map.capillas.where((c) => c.id == capId).toList();
    if (cap.isEmpty) return '';
    return (cap.first.name ?? '').trim();
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
}

// ========================= UI widgets =========================

class _FiltersBarTrap extends StatelessWidget {
  final Color accent;
  final ScrollController topBarCtrl;
  final String greenhouseLabel;
  final int weeksCount;

  final List<String> pestOptions;
  final String? selectedPest;
  final ValueChanged<String?> onPest;

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

  const _FiltersBarTrap({
    required this.accent,
    required this.topBarCtrl,
    required this.greenhouseLabel,
    required this.weeksCount,
    required this.pestOptions,
    required this.selectedPest,
    required this.onPest,
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
                icon: Icons.warehouse_outlined,
                text: greenhouseLabel,
              ),
              const SizedBox(width: 8),
              _TopBadge(
                accent: accent,
                icon: Icons.date_range_outlined,
                text: 'Semanas: $weeksCount',
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedPest,
                  decoration: deco('Plaga', Icons.bug_report_outlined),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ...pestOptions.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p,
                        child: Text(p, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: onPest,
                ),
              ),
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

class _TrapTableCard extends StatelessWidget {
  final Color accent;
  final List<_TrapRowRec> rows;
  final ScrollController hCtrl;
  final ScrollController vCtrl;
  final int Function(String lineKey) lineNoFromKey;
  final ValueChanged<_TrapRowRec> onEdit;
  final ValueChanged<_TrapRowRec> onDelete;

  const _TrapTableCard({
    required this.accent,
    required this.rows,
    required this.hCtrl,
    required this.vCtrl,
    required this.lineNoFromKey,
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
                        DataColumn(label: _head('Capilla', width: 110)),
                        DataColumn(label: _head('Línea', width: 52)),
                        DataColumn(label: _head('Trampa', width: 140)),
                        DataColumn(label: _head('Fecha', width: 90)),
                        DataColumn(label: _head('Hora', width: 110)),
                        DataColumn(label: _head('Monitora', width: 120)),
                        DataColumn(label: _head('Plaga', width: 140)),
                        DataColumn(label: _head('Cantidad', width: 70)),
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

                        final lineNo = lineNoFromKey(r.lineKey);

                        Widget qtyChip(int qty) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
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
                              '$qty',
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
                            DataCell(_cellText(capCell, width: 110)),
                            DataCell(_cellText('$lineNo', width: 52)),
                            DataCell(_cellText(r.trapName, width: 140)),
                            DataCell(_cellText(dateText, width: 90)),
                            DataCell(_cellText(r.hourText, width: 110)),
                            DataCell(
                              _cellText(
                                r.monitorName.isEmpty ? r.byUid : r.monitorName,
                                width: 120,
                              ),
                            ),
                            DataCell(_cellText(r.pest, width: 140)),
                            DataCell(Center(child: qtyChip(r.qty))),
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

// ========================= data models =========================

class _CapOpt {
  final String id;
  final String name;
  const _CapOpt({required this.id, required this.name});
}

class _TrapRowRec {
  final String weekKey;
  final String capillaId;
  final String capillaName;

  final String lineKey; // guardado, en tabla se muestra solo el número
  final String trapId;
  final String trapName;

  final DateTime? date;
  final String hourText;

  final String byUid;
  final String monitorName;

  final String pest;
  final int qty;

  const _TrapRowRec({
    required this.weekKey,
    required this.capillaId,
    required this.capillaName,
    required this.lineKey,
    required this.trapId,
    required this.trapName,
    required this.date,
    required this.hourText,
    required this.byUid,
    required this.monitorName,
    required this.pest,
    required this.qty,
  });

  _TrapRowRec copyWith({String? monitorName}) {
    return _TrapRowRec(
      weekKey: weekKey,
      capillaId: capillaId,
      capillaName: capillaName,
      lineKey: lineKey,
      trapId: trapId,
      trapName: trapName,
      date: date,
      hourText: hourText,
      byUid: byUid,
      monitorName: monitorName ?? this.monitorName,
      pest: pest,
      qty: qty,
    );
  }
}
