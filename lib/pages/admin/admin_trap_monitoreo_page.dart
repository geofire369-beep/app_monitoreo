// lib/pages/admin/admin_trap_monitoreo_page.dart
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/mapa_model.dart';
import '../../theme/app_theme.dart';

// ✅ NUEVO: tabla
import 'admin_trap_monitoreo_table_view.dart';

enum AdminTrapOverlayMode { avance, plagas }

// ✅ NUEVO: modo de vista
enum AdminTrapViewMode { mapa, tabla }

class AdminTrapMonitoreoPage extends StatefulWidget {
  final GreenhouseMap map;
  final Set<String> initialWeekKeys;

  const AdminTrapMonitoreoPage({
    super.key,
    required this.map,
    required this.initialWeekKeys,
  });

  @override
  State<AdminTrapMonitoreoPage> createState() => _AdminTrapMonitoreoPageState();
}

class _AdminTrapMonitoreoPageState extends State<AdminTrapMonitoreoPage> {
  final _fs = FirebaseFirestore.instance;

  // ✅ NUEVO: view mode
  AdminTrapViewMode _viewMode = AdminTrapViewMode.mapa;

  AdminTrapOverlayMode _mode = AdminTrapOverlayMode.avance;

  final Set<String> _weekKeys = <String>{};

  final Set<String> _selectedPests = <String>{}; // vacío => todas
  final Map<String, Color> _pestColors = <String, Color>{};

  final Map<String, String> _uidNameCache = {};

  final TransformationController _tx = TransformationController();
  bool _fittedOnce = false;

  _TrapHoverKey? _hoverTrap;
  Offset? _hoverPos;

  @override
  void initState() {
    super.initState();
    _weekKeys.addAll(
      widget.initialWeekKeys.isEmpty
          ? {_isoWeekKey(DateTime.now())}
          : widget.initialWeekKeys,
    );
  }

  @override
  void dispose() {
    _tx.dispose();
    super.dispose();
  }

  // ---------------------- Firestore loaders ----------------------

  Future<_TrapAggData> _loadTrapAgg(
    GreenhouseMap map,
    Set<String> weekKeys,
  ) async {
    final agg = _TrapAggData();

    for (final wk in weekKeys) {
      final ghRef = _fs
          .collection('monitoreo_weeks')
          .doc(wk)
          .collection('greenhouses')
          .doc(map.id);

      final capsSnap = await ghRef.collection('capillas').get();

      for (final capDoc in capsSnap.docs) {
        final capId = capDoc.id;
        final data = Map<String, dynamic>.from(capDoc.data());

        // ✅ AJUSTA ESTA KEY si en tu BD se llama distinto
        final trapLinesAny = data['trapLines'];
        if (trapLinesAny is! Map) continue;

        final trapLines = Map<String, dynamic>.from(trapLinesAny);

        trapLines.forEach((lineKey, payloadAny) {
          if (payloadAny is! Map) return;
          final payload = Map<String, dynamic>.from(payloadAny);

          final byUid = (payload['byUid'] ?? '').toString();

          final startedAt = _asDateTime(
            payload['startedAt'] ?? payload['startedAtMs'],
          );
          final finishedAt = _asDateTime(
            payload['finishedAt'] ?? payload['finishedAtMs'],
          );
          final updatedAt = _asDateTime(
            payload['updatedAt'] ?? payload['updatedAtMs'],
          );

          final statusRaw = (payload['status'] ?? '').toString().trim();
          final status = statusRaw.toUpperCase();

          final lk = _TrapLineKey(capId: capId, lineKey: lineKey.toString());
          final prevLine = agg.lines[lk];

          agg.lines[lk] = _TrapLineMeta(
            byUid: (byUid.isEmpty ? prevLine?.byUid : byUid),
            startedAt: startedAt ?? prevLine?.startedAt,
            finishedAt: finishedAt ?? prevLine?.finishedAt,
            updatedAt: updatedAt ?? prevLine?.updatedAt,
            status: status.isEmpty ? (prevLine?.status ?? '') : status,
          );

          if (byUid.isNotEmpty) agg.uids.add(byUid);

          // observations.traps = { trapId : { name, counts } }
          final obsAny = payload['observations'];
          final obs = (obsAny is Map)
              ? Map<String, dynamic>.from(obsAny)
              : <String, dynamic>{};

          final trapsAny = obs['traps'];
          final trapsObs = (trapsAny is Map)
              ? Map<String, dynamic>.from(trapsAny)
              : <String, dynamic>{};

          if (trapsObs.isEmpty) return;

          trapsObs.forEach((trapId, tAny) {
            if (tAny is! Map) return;
            final t = Map<String, dynamic>.from(tAny);

            final name = (t['name'] ?? '').toString();
            final countsAny = t['counts'];
            final countsMap = (countsAny is Map)
                ? Map<String, dynamic>.from(countsAny)
                : <String, dynamic>{};

            final add = <String, int>{};
            countsMap.forEach((p, v) {
              final n = _asInt(v);
              if (n <= 0) return;
              final key = p.toString().trim();
              add[key] = n;
              agg.allPests.add(key);
            });

            final key = _TrapKey(capId: capId, trapId: trapId.toString());
            final prev = agg.traps[key];

            final merged = <String, int>{};
            if (prev != null) merged.addAll(prev.pestsTotals);
            add.forEach((p, n) => merged[p] = (merged[p] ?? 0) + n);

            DateTime? bestFinished = prev?.finishedAt;
            DateTime? bestUpdated = prev?.updatedAt;
            DateTime? bestStarted = prev?.startedAt;
            String? bestUid = prev?.byUid;

            bool tookCurrent = false;
            if (finishedAt != null) {
              if (bestFinished == null || finishedAt.isAfter(bestFinished)) {
                bestFinished = finishedAt;
                bestStarted = startedAt ?? bestStarted;
                bestUid = byUid.isEmpty ? bestUid : byUid;
                bestUpdated = updatedAt ?? bestUpdated;
                tookCurrent = true;
              }
            }

            if (!tookCurrent && updatedAt != null) {
              if (bestUpdated == null || updatedAt.isAfter(bestUpdated)) {
                bestUpdated = updatedAt;
                bestStarted = startedAt ?? bestStarted;
                bestUid = byUid.isEmpty ? bestUid : byUid;
              }
            }

            agg.traps[key] = _TrapAggTrap(
              capId: capId,
              trapId: trapId.toString(),
              trapName: name,
              byUid: bestUid,
              startedAt: bestStarted,
              finishedAt: bestFinished,
              updatedAt: bestUpdated,
              pestsTotals: merged,
              status: (status.isEmpty ? (prev?.status ?? '') : status),
            );
          });
        });
      }
    }

    await _warmUserNames(agg.uids);
    return agg;
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
    if (mounted) setState(() {});
  }

  // ---------------------- UI ----------------------

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('Trampas (Admin)'),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0.08),
              Colors.white,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _TopBarTrap(
                  accent: accent,

                  // ✅ NUEVO: selector mapa/tabla
                  viewMode: _viewMode,
                  onViewMode: (v) => setState(() => _viewMode = v),

                  mode: _mode,
                  onMode: (m) => setState(() => _mode = m),
                  selectedWeeks: _weekKeys,
                  onWeeks: _pickWeeksDialog,
                  mapName: widget.map.name,
                  onFit: _fitToViewport,
                ),
                const SizedBox(height: 12),

                // ✅ NUEVO: switch real entre mapa y tabla
                Expanded(
                  child: _viewMode == AdminTrapViewMode.tabla
                      ? AdminTrapMonitoreoTableView(
                          map: widget.map,
                          weekKeys: _weekKeys,
                        )
                      : FutureBuilder<_TrapAggData>(
                          future: _loadTrapAgg(widget.map, _weekKeys),
                          builder: (context, snap) {
                            if (!snap.hasData)
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            final agg = snap.data!;

                            final pests = agg.allPests.toList()..sort();
                            for (final p in pests) {
                              _pestColors.putIfAbsent(
                                p,
                                () => _colorFromString(p),
                              );
                            }

                            return Column(
                              children: [
                                _LegendBarMultiTrap(
                                  accent: accent,
                                  mode: _mode,
                                  pests: pests,
                                  selectedPests: _selectedPests,
                                  pestColors: _pestColors,
                                  onTogglePest: (p) {
                                    setState(() {
                                      if (p == null) {
                                        _selectedPests.clear();
                                      } else {
                                        if (_selectedPests.contains(p)) {
                                          _selectedPests.remove(p);
                                        } else {
                                          _selectedPests.add(p);
                                        }
                                      }
                                    });
                                  },
                                  onPickColor: (p) async {
                                    final c = await _pickColorDialog(
                                      context,
                                      initial:
                                          _pestColors[p] ?? _colorFromString(p),
                                    );
                                    if (c == null) return;
                                    setState(() => _pestColors[p] = c);
                                  },
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: _TrapMapViewer(
                                    map: widget.map,
                                    agg: agg,
                                    mode: _mode,
                                    selectedPests: _selectedPests,
                                    pestColors: _pestColors,
                                    tx: _tx,
                                    fittedOnce: _fittedOnce,
                                    onFittedOnce: () => _fittedOnce = true,
                                    onHoverTrap: (t) =>
                                        setState(() => _hoverTrap = t),
                                    onHoverPos: (p) =>
                                        setState(() => _hoverPos = p),
                                    hoverTrap: _hoverTrap,
                                    hoverPos: _hoverPos,
                                    uidName: (uid) => _uidNameCache[uid] ?? uid,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _fitToViewport() {
    setState(() {
      _fittedOnce = false;
      _tx.value = Matrix4.identity();
      _hoverTrap = null;
      _hoverPos = null;
    });
  }

  Future<void> _pickWeeksDialog() async {
    final accent = AppTheme.pepperGreen;
    final now = DateTime.now();

    final options = List.generate(
      12,
      (i) => _isoWeekKey(now.subtract(Duration(days: 7 * i))),
    );
    final temp = Set<String>.from(_weekKeys);

    String prettyWeek(String key) {
      final parts = key.split('-W');
      if (parts.length != 2) return key;
      final year = parts[0];
      final week = int.tryParse(parts[1]) ?? parts[1];
      return 'Semana $week • $year';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accent.withValues(alpha: 0.10), Colors.white],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: StatefulBuilder(
              builder: (ctx2, setLocal) {
                final selectedSorted = temp.toList()
                  ..sort((a, b) => b.compareTo(a));

                Widget chip(String wk) {
                  return Container(
                    margin: const EdgeInsets.only(right: 8, bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_available_rounded,
                          color: accent,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          wk,
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.80),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setLocal(() => temp.remove(wk)),
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.black.withValues(alpha: 0.55),
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Icon(
                              Icons.date_range_outlined,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Seleccionar semanas',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.pop(ctx, false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    if (temp.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            children: selectedSorted
                                .take(10)
                                .map(chip)
                                .toList(),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => setLocal(
                              () => temp
                                ..clear()
                                ..add(_isoWeekKey(DateTime.now())),
                            ),
                            icon: const Icon(Icons.today_rounded),
                            label: const Text('Solo actual'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accent,
                              side: BorderSide(
                                color: accent.withValues(alpha: 0.26),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () => setLocal(() => temp.clear()),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Limpiar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black.withValues(
                                alpha: 0.75,
                              ),
                              side: BorderSide(
                                color: Colors.black.withValues(alpha: 0.12),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              '${temp.length} seleccionada(s)',
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.70),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.14),
                          ),
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: options.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                          itemBuilder: (_, i) {
                            final w = options[i];
                            final checked = temp.contains(w);

                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => setLocal(() {
                                if (checked) {
                                  temp.remove(w);
                                } else {
                                  temp.add(w);
                                }
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: checked
                                      ? accent.withValues(alpha: 0.08)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: checked
                                        ? accent.withValues(alpha: 0.22)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: checked
                                            ? accent
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: checked
                                              ? accent
                                              : Colors.black.withValues(
                                                  alpha: 0.22,
                                                ),
                                          width: 1.3,
                                        ),
                                      ),
                                      child: checked
                                          ? const Icon(
                                              Icons.check_rounded,
                                              color: Colors.white,
                                              size: 16,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            w,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            prettyWeek(w),
                                            style: TextStyle(
                                              color: Colors.black.withValues(
                                                alpha: 0.62,
                                              ),
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
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => Navigator.pop(ctx, true),
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                            ),
                            label: const Text('Aplicar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (ok == true && mounted) {
      setState(() {
        _weekKeys
          ..clear()
          ..addAll(temp.isEmpty ? {_isoWeekKey(DateTime.now())} : temp);

        _hoverTrap = null;
        _hoverPos = null;
      });
    }
  }

  Future<Color?> _pickColorDialog(
    BuildContext context, {
    required Color initial,
  }) async {
    final palette = <Color>[
      const Color(0xFFe53935),
      const Color(0xFFfb8c00),
      const Color(0xFFfdd835),
      const Color(0xFF43a047),
      const Color(0xFF00acc1),
      const Color(0xFF1e88e5),
      const Color(0xFF5e35b1),
      const Color(0xFF8e24aa),
      const Color(0xFF6d4c41),
      const Color(0xFF546e7a),
      const Color(0xFF263238),
      const Color(0xFFd81b60),
    ];

    Color chosen = initial;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Elegir color'),
          content: SizedBox(
            width: 520,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ...palette.map((c) {
                  final sel = c.value == chosen.value;
                  return InkWell(
                    onTap: () {
                      chosen = c;
                      (ctx as Element).markNeedsBuild();
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel
                              ? Colors.black.withValues(alpha: 0.7)
                              : Colors.black.withValues(alpha: 0.15),
                          width: sel ? 2.2 : 1.0,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );

    return ok == true ? chosen : null;
  }

  // ---------------------- helpers ----------------------

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

  Color _colorFromString(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final hue = (h % 360).toDouble();
    return HSVColor.fromAHSV(1.0, hue, 0.55, 0.90).toColor();
  }
}

// ========================= TOP UI =========================

class _TopBarTrap extends StatelessWidget {
  final Color accent;

  // ✅ NUEVO
  final AdminTrapViewMode viewMode;
  final ValueChanged<AdminTrapViewMode> onViewMode;

  final AdminTrapOverlayMode mode;
  final ValueChanged<AdminTrapOverlayMode> onMode;

  final Set<String> selectedWeeks;
  final VoidCallback onWeeks;

  final String mapName;
  final VoidCallback onFit;

  const _TopBarTrap({
    required this.accent,

    required this.viewMode,
    required this.onViewMode,

    required this.mode,
    required this.onMode,
    required this.selectedWeeks,
    required this.onWeeks,
    required this.mapName,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Wrap(
        runSpacing: 10,
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // ✅ NUEVO: Mapa / Tabla
          SegmentedButton<AdminTrapViewMode>(
            segments: const [
              ButtonSegment(
                value: AdminTrapViewMode.mapa,
                label: Text('Mapa'),
                icon: Icon(Icons.map_outlined),
              ),
              ButtonSegment(
                value: AdminTrapViewMode.tabla,
                label: Text('Tabla'),
                icon: Icon(Icons.table_rows_outlined),
              ),
            ],
            selected: {viewMode},
            onSelectionChanged: (s) => onViewMode(s.first),
          ),

          // ✅ Solo relevante en MAPA
          if (viewMode == AdminTrapViewMode.mapa)
            SegmentedButton<AdminTrapOverlayMode>(
              segments: const [
                ButtonSegment(
                  value: AdminTrapOverlayMode.avance,
                  label: Text('Avance'),
                  icon: Icon(Icons.timeline_outlined),
                ),
                ButtonSegment(
                  value: AdminTrapOverlayMode.plagas,
                  label: Text('Plagas'),
                  icon: Icon(Icons.bug_report_outlined),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onMode(s.first),
            ),

          OutlinedButton.icon(
            onPressed: onWeeks,
            icon: const Icon(Icons.date_range_outlined),
            label: Text('Semanas (${selectedWeeks.length})'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: onFit,
            icon: const Icon(Icons.fit_screen_outlined),
            label: const Text('Ajustar'),
          ),
          const SizedBox(width: 8),
          Text(
            mapName,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black.withValues(alpha: 0.60),
            ),
          ),
        ],
      ),
    );
  }
}

// ========================= LEGEND =========================

class _LegendBarMultiTrap extends StatelessWidget {
  final Color accent;
  final AdminTrapOverlayMode mode;
  final List<String> pests;

  final Set<String> selectedPests; // vacío => todas
  final Map<String, Color> pestColors;

  final ValueChanged<String?> onTogglePest;
  final ValueChanged<String> onPickColor;

  const _LegendBarMultiTrap({
    required this.accent,
    required this.mode,
    required this.pests,
    required this.selectedPests,
    required this.pestColors,
    required this.onTogglePest,
    required this.onPickColor,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == AdminTrapOverlayMode.avance) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            _Dot(color: Colors.green.withValues(alpha: 0.85)),
            const SizedBox(width: 8),
            const Text(
              'Trampa con datos',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 16),
            _Dot(color: Colors.black.withValues(alpha: 0.20)),
            const SizedBox(width: 8),
            const Text(
              'Sin datos',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              'Hover para ver detalles',
              style: TextStyle(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    final allSelected = selectedPests.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Plagas:', style: TextStyle(fontWeight: FontWeight.w900)),
          FilterChip(
            selected: allSelected,
            label: const Text('Todas'),
            onSelected: (_) => onTogglePest(null),
          ),
          ...pests.map((p) {
            final selected = selectedPests.contains(p);
            final c = pestColors[p] ?? accent;

            return InputChip(
              selected: selected,
              onPressed: () => onTogglePest(p),
              onDeleted: () => onPickColor(p),
              deleteIcon: Icon(
                Icons.palette_outlined,
                size: 18,
                color: Colors.black.withValues(alpha: 0.70),
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.95),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(p),
                ],
              ),
            );
          }),
          if (pests.isEmpty)
            Text(
              'No hay plagas en las semanas seleccionadas.',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.65),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ========================= MAP VIEWER =========================

class _TrapMapViewer extends StatefulWidget {
  final GreenhouseMap map;
  final _TrapAggData agg;
  final AdminTrapOverlayMode mode;

  final Set<String> selectedPests;
  final Map<String, Color> pestColors;

  final TransformationController tx;
  final bool fittedOnce;
  final VoidCallback onFittedOnce;

  final ValueChanged<_TrapHoverKey?> onHoverTrap;
  final ValueChanged<Offset?> onHoverPos;
  final _TrapHoverKey? hoverTrap;
  final Offset? hoverPos;

  final String Function(String uid) uidName;

  const _TrapMapViewer({
    required this.map,
    required this.agg,
    required this.mode,
    required this.selectedPests,
    required this.pestColors,
    required this.tx,
    required this.fittedOnce,
    required this.onFittedOnce,
    required this.onHoverTrap,
    required this.onHoverPos,
    required this.hoverTrap,
    required this.hoverPos,
    required this.uidName,
  });

  @override
  State<_TrapMapViewer> createState() => _TrapMapViewerState();
}

class _TrapMapViewerState extends State<_TrapMapViewer> {
  bool _dragging = false;
  bool _overTrap = false;

  static const double _minScale = 0.08;
  static const double _maxScale = 10.0;

  Offset? _lastTapPos;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(
          builder: (context, c) {
            final metrics = _TrapMapMetrics(widget.map);
            final canvasSize = metrics.canvasSize;

            if (!widget.fittedOnce) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fitTo(c.maxWidth, c.maxHeight, canvasSize);
                widget.onFittedOnce();
              });
            }

            final cursor = _dragging
                ? SystemMouseCursors.grabbing
                : (_overTrap
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic);

            final pos = widget.hoverPos;
            final tooltipW = 420.0;
            final tooltipH = 280.0;
            final tooltipOffset = const Offset(16, 16);

            double left = 12;
            double top = 12;

            if (pos != null) {
              left = (pos.dx + tooltipOffset.dx).clamp(
                12.0,
                math.max(12.0, c.maxWidth - tooltipW - 12),
              );
              top = (pos.dy + tooltipOffset.dy).clamp(
                12.0,
                math.max(12.0, c.maxHeight - tooltipH - 12),
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerDown: (e) {
                      if (e.kind == PointerDeviceKind.mouse)
                        setState(() => _dragging = true);
                    },
                    onPointerUp: (_) => setState(() => _dragging = false),
                    onPointerCancel: (_) => setState(() => _dragging = false),
                    child: MouseRegion(
                      cursor: cursor,
                      opaque: true,
                      onHover: (evt) {
                        if (evt.kind != PointerDeviceKind.mouse) return;

                        widget.onHoverPos(evt.localPosition);

                        final scene = widget.tx.toScene(evt.localPosition);

                        final trapHover = _hitTestTrap(
                          canvasLocal: scene,
                          map: widget.map,
                        );

                        final over = trapHover != null;
                        if (over != _overTrap) setState(() => _overTrap = over);

                        widget.onHoverTrap(trapHover);
                      },
                      onExit: (_) {
                        if (_overTrap) setState(() => _overTrap = false);
                        widget.onHoverTrap(null);
                        widget.onHoverPos(null);
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTapDown: (d) => _lastTapPos = d.localPosition,
                        onDoubleTap: () {
                          final fp =
                              _lastTapPos ??
                              Offset(c.maxWidth / 2, c.maxHeight / 2);
                          _zoomBy(factor: 1.65, focalPoint: fp);
                        },
                        child: InteractiveViewer(
                          transformationController: widget.tx,
                          minScale: _minScale,
                          maxScale: _maxScale,
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(800),
                          panEnabled: true,
                          scaleEnabled: true,
                          trackpadScrollCausesScale: true,
                          child: SizedBox(
                            width: canvasSize.width,
                            height: canvasSize.height,
                            child: CustomPaint(
                              painter: _AdminTrapMapPainter(
                                map: widget.map,
                                agg: widget.agg,
                                mode: widget.mode,
                                selectedPests: widget.selectedPests,
                                pestColors: widget.pestColors,
                                hoverTrap: widget.hoverTrap,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: left,
                  top: top,
                  child: IgnorePointer(
                    ignoring: true,
                    child: _TrapHoverInfo(
                      accent: accent,
                      map: widget.map,
                      agg: widget.agg,
                      hover: widget.hoverTrap,
                      uidName: widget.uidName,
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _ZoomControls(
                    accent: accent,
                    onZoomIn: () => _zoomBy(
                      factor: 1.25,
                      focalPoint: Offset(c.maxWidth / 2, c.maxHeight / 2),
                    ),
                    onZoomOut: () => _zoomBy(
                      factor: 1 / 1.25,
                      focalPoint: Offset(c.maxWidth / 2, c.maxHeight / 2),
                    ),
                    onFit: () => _fitTo(c.maxWidth, c.maxHeight, canvasSize),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _fitTo(double vw, double vh, Size canvas) {
    const pad = 24.0;
    final sx = (vw - pad) / canvas.width;
    final sy = (vh - pad) / canvas.height;
    final s = math.min(sx, sy).clamp(_minScale, 2.5);

    final dx = (vw - canvas.width * s) / 2;
    final dy = (vh - canvas.height * s) / 2;

    widget.tx.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(s);
  }

  void _zoomBy({required double factor, required Offset focalPoint}) {
    final currentScale = widget.tx.value.getMaxScaleOnAxis();
    var f = factor;

    final nextScale = currentScale * f;
    if (nextScale < _minScale) f = _minScale / currentScale;
    if (nextScale > _maxScale) f = _maxScale / currentScale;

    final m = Matrix4.identity()
      ..translate(focalPoint.dx, focalPoint.dy)
      ..scale(f)
      ..translate(-focalPoint.dx, -focalPoint.dy);

    widget.tx.value = m.multiplied(widget.tx.value);
    setState(() {});
  }

  _TrapHoverKey? _hitTestTrap({
    required Offset canvasLocal,
    required GreenhouseMap map,
  }) {
    final x = canvasLocal.dx;
    final y = canvasLocal.dy;

    final m = _TrapMapMetrics(map);

    final gridX0 = m.gutterW;
    final gridW = m.gridW;

    if (x < gridX0 || x > gridX0 + gridW) return null;

    final northY0 = m.northY0;
    final northY1 = m.northY1;

    final midY1 = northY1 + m.midHeaderH;
    final southY0 = midY1 + m.labelH;
    final southY1 = southY0 + map.postsSouth * m.cellH;

    final col = ((x - gridX0) / m.cellW).floor();
    if (col < 0 || col >= map.totalColumns) return null;

    NS? ns;
    int post = -1;

    if (y >= northY0 && y < northY1) {
      ns = NS.north;
      final rowFromTop = ((y - northY0) / m.cellH).floor();
      if (rowFromTop < 0 || rowFromTop >= map.postsNorth) return null;
      post = map.postsNorth - rowFromTop; // NORTE abajo->arriba
      if (post < 1 || post > map.postsNorth) return null;
    } else if (y >= southY0 && y < southY1) {
      ns = NS.south;
      final rowFromTop = ((y - southY0) / m.cellH).floor();
      if (rowFromTop < 0 || rowFromTop >= map.postsSouth) return null;
      post = rowFromTop + 1;
    } else {
      return null;
    }

    final ci = map.columnInfo(col);
    final lineNo = (ns == NS.north) ? ci.northLineNo : ci.southLineNo;
    if (lineNo == null) return null;

    if (!map.isActive(ns, post, lineNo)) return null;

    final trapId = map.trapIdAt(ns, post, lineNo);
    if (trapId == null) return null;

    return _TrapHoverKey(
      capillaId: ci.capilla.id,
      trapId: trapId,
      ns: ns,
      lineNo: lineNo,
      post: post,
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final Color accent;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  const _ZoomControls({
    required this.accent,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback onTap) {
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.add, 'Zoom in', onZoomIn),
        const SizedBox(height: 8),
        btn(Icons.remove, 'Zoom out', onZoomOut),
        const SizedBox(height: 8),
        btn(Icons.fit_screen_outlined, 'Ajustar', onFit),
      ],
    );
  }
}

// ========================= TOOLTIP =========================

class _TrapHoverInfo extends StatelessWidget {
  final Color accent;
  final GreenhouseMap map;
  final _TrapAggData agg;
  final _TrapHoverKey? hover;
  final String Function(String uid) uidName;

  const _TrapHoverInfo({
    required this.accent,
    required this.map,
    required this.agg,
    required this.hover,
    required this.uidName,
  });

  @override
  Widget build(BuildContext context) {
    if (hover == null) {
      return _pill('Hover sobre una trampa', Icons.mouse_outlined);
    }

    final key = _TrapKey(capId: hover!.capillaId, trapId: hover!.trapId);
    final t = agg.traps[key];

    final trapDef = map.traps.firstWhere(
      (x) => x.id == hover!.trapId,
      orElse: () =>
          TrapDef(id: hover!.trapId, name: '(trampa)', cells: const []),
    );

    final name = (t?.trapName.trim().isNotEmpty == true)
        ? t!.trapName.trim()
        : trapDef.name.trim();
    final uid = t?.byUid;
    final who = (uid == null || uid.isEmpty) ? null : uidName(uid);

    final st = t?.startedAt;
    final ft = t?.finishedAt;
    final up = t?.updatedAt;

    String? hora;
    if (st != null && ft != null) {
      hora = '${_fmtHMS(st)} - ${_fmtHMS(ft)}';
    } else if (ft != null) {
      hora = _fmtFull(ft);
    } else if (up != null) {
      hora = _fmtFull(up);
    }

    final fecha = st != null
        ? _fmtDate(st)
        : (ft != null ? _fmtDate(ft) : (up != null ? _fmtDate(up) : null));

    final pests = t?.pestsTotals ?? const <String, int>{};
    final pestKeys = pests.keys.toList()
      ..sort((a, b) => (pests[b] ?? 0).compareTo(pests[a] ?? 0));

    final title =
        '$name • ${hover!.ns == NS.north ? "NORTE" : "SUR"} Línea ${hover!.lineNo} Poste ${hover!.post}';
    final statusText = (t == null || pests.isEmpty)
        ? 'Sin datos en semanas seleccionadas'
        : 'Con datos';

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_activity_outlined, color: accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              statusText,
              style: TextStyle(
                color: (t != null && pests.isNotEmpty)
                    ? Colors.greenAccent
                    : Colors.white70,
              ),
            ),
            if (who != null) ...[
              const SizedBox(height: 4),
              Text('Por: $who', style: const TextStyle(color: Colors.white)),
            ],
            if (fecha != null || hora != null) ...[
              const SizedBox(height: 2),
              Text(
                'Hora: ${hora ?? "--"}${fecha != null ? " • $fecha" : ""}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Plagas:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            if (pestKeys.isEmpty)
              const Text(
                'Sin plagas registradas.',
                style: TextStyle(color: Colors.white70),
              )
            else
              ...pestKeys
                  .take(10)
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $p: ${pests[p] ?? 0}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
            if (pestKeys.length > 10)
              Text(
                '+ ${pestKeys.length - 10} más...',
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  String _fmtHMS(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtFull(DateTime d) => '${_fmtDate(d)} ${_fmtHMS(d)}';
}

// ========================= PAINTER (TRAMPAS) =========================

class _AdminTrapMapPainter extends CustomPainter {
  final GreenhouseMap map;
  final _TrapAggData agg;
  final AdminTrapOverlayMode mode;

  final Set<String> selectedPests;
  final Map<String, Color> pestColors;

  final _TrapHoverKey? hoverTrap;

  // ✅ mapping trapId -> capId
  late final Map<String, String> _trapIdToCapId;

  _AdminTrapMapPainter({
    required this.map,
    required this.agg,
    required this.mode,
    required this.selectedPests,
    required this.pestColors,
    required this.hoverTrap,
  }) {
    _trapIdToCapId = {};
    for (final t in map.traps) {
      String? cap;
      for (final cell in t.cells) {
        for (int col = 0; col < map.totalColumns; col++) {
          final ci = map.columnInfo(col);
          final ln = (cell.side == NS.north) ? ci.northLineNo : ci.southLineNo;
          if (ln == cell.lineNo) {
            cap = ci.capilla.id;
            break;
          }
        }
        if (cap != null) break;
      }
      if (cap != null) _trapIdToCapId[t.id] = cap!;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final m = _TrapMapMetrics(map);

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    _drawBand(canvas, m, NS.north);
    _drawBand(canvas, m, NS.south);

    _drawCapillaDividersAndLabels(canvas, m);
    _drawPostLabelsAndRowDividers(canvas, m, NS.north);
    _drawPostLabelsAndRowDividers(canvas, m, NS.south);

    for (final trap in map.traps) {
      _paintTrap(canvas, m, trap);
    }

    if (hoverTrap != null) {
      final trap = map.traps.firstWhere(
        (t) => t.id == hoverTrap!.trapId,
        orElse: () => TrapDef(id: '', name: '', cells: const []),
      );
      if (trap.id.isNotEmpty) {
        _paintTrap(canvas, m, trap, forceHighlight: true);
      }
    }
  }

  void _paintTrap(
    Canvas canvas,
    _TrapMapMetrics m,
    TrapDef trap, {
    bool forceHighlight = false,
  }) {
    if (trap.cells.isEmpty) return;

    final cellsRects = <Rect>[];

    for (final c in trap.cells) {
      final col = _colForCell(c, map);
      if (col == null) continue;
      if (!map.isActive(c.side, c.poste, c.lineNo)) continue;

      final rect = Rect.fromLTWH(
        m.gutterW + col * m.cellW + 1.0,
        _cellTopY(m, c.side, c.poste) + 1.0,
        m.cellW - 2.0,
        m.cellH - 2.0,
      );

      cellsRects.add(rect);
    }

    if (cellsRects.isEmpty) return;

    final capId = _trapIdToCapId[trap.id];
    final aggTrap = (capId == null)
        ? null
        : agg.traps[_TrapKey(capId: capId, trapId: trap.id)];

    Color fill;

    if (mode == AdminTrapOverlayMode.avance) {
      final hasData = (aggTrap != null && aggTrap.pestsTotals.isNotEmpty);
      fill = hasData
          ? Colors.green.withValues(alpha: 0.60)
          : Colors.black.withValues(alpha: 0.08);
    } else {
      final pests = aggTrap?.pestsTotals ?? const <String, int>{};

      if (pests.isEmpty) {
        fill = Colors.black.withValues(alpha: 0.08);
      } else {
        if (selectedPests.isNotEmpty) {
          final tag = _topPestAmong(pests, selectedPests);
          if (tag == null) {
            fill = Colors.black.withValues(alpha: 0.08);
          } else {
            fill = (pestColors[tag] ?? _colorFromString(tag)).withValues(
              alpha: 0.78,
            );
          }
        } else {
          final best = _topPest(pests);
          fill = (pestColors[best] ?? _colorFromString(best)).withValues(
            alpha: 0.78,
          );
        }
      }
    }

    final cellPaint = Paint()..color = fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.20);

    final borderStrong = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = AppTheme.pepperGreen.withValues(alpha: 0.95);

    for (final r in cellsRects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(6)),
        cellPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(6)),
        border,
      );
    }

    final bb = _boundingBox(cellsRects);
    if (bb != null) {
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.black.withValues(alpha: 0.25);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bb.inflate(3), const Radius.circular(10)),
        outline,
      );
      if (forceHighlight) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(bb.inflate(5), const Radius.circular(12)),
          borderStrong,
        );
      }

      final label = trap.name.trim().isEmpty ? trap.id : trap.name.trim();
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.85),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, bb.width - 8));

      tp.paint(
        canvas,
        Offset(bb.center.dx - tp.width / 2, bb.top - tp.height - 4),
      );
    }
  }

  Rect? _boundingBox(List<Rect> rects) {
    if (rects.isEmpty) return null;
    var left = rects.first.left;
    var top = rects.first.top;
    var right = rects.first.right;
    var bottom = rects.first.bottom;
    for (final r in rects.skip(1)) {
      left = math.min(left, r.left);
      top = math.min(top, r.top);
      right = math.max(right, r.right);
      bottom = math.max(bottom, r.bottom);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  int? _colForCell(TrapCell c, GreenhouseMap map) {
    for (int col = 0; col < map.totalColumns; col++) {
      final ci = map.columnInfo(col);
      final ln = (c.side == NS.north) ? ci.northLineNo : ci.southLineNo;
      if (ln == c.lineNo) return col;
    }
    return null;
  }

  double _cellTopY(_TrapMapMetrics m, NS ns, int post) {
    final rows = (ns == NS.north) ? map.postsNorth : map.postsSouth;
    final top = (ns == NS.north) ? m.northY0 : m.southY0;

    if (ns == NS.north) {
      return top + (rows - post) * m.cellH; // NORTE abajo->arriba
    }
    return top + (post - 1) * m.cellH;
  }

  void _drawBand(Canvas canvas, _TrapMapMetrics m, NS ns) {
    final top = (ns == NS.north) ? m.northY0 : m.southY0;
    final h = (ns == NS.north)
        ? map.postsNorth * m.cellH
        : map.postsSouth * m.cellH;

    final bandPaint = Paint()
      ..color = (ns == NS.north)
          ? Colors.black.withValues(alpha: 0.02)
          : Colors.black.withValues(alpha: 0.015);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(m.gutterW, top, m.gridW, h),
        const Radius.circular(14),
      ),
      bandPaint,
    );
  }

  void _drawCapillaDividersAndLabels(Canvas canvas, _TrapMapMetrics m) {
    final divider = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.08);

    final double topLabelY = (m.northY0 - 16.0).clamp(0.0, double.infinity);

    final textStyle = TextStyle(
      color: Colors.black.withValues(alpha: 0.55),
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );

    String? lastCapId;
    int capStartCol = 0;
    String? capName;

    void flushCap(int endColExclusive) {
      if (capName == null) return;
      final x0 = m.gutterW + capStartCol * m.cellW;
      final x1 = m.gutterW + endColExclusive * m.cellW;

      final tp = TextPainter(
        text: TextSpan(text: capName!, style: textStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0.0, x1 - x0 - 6.0));

      final dx = x0 + ((x1 - x0 - tp.width) / 2.0);
      tp.paint(canvas, Offset(dx, topLabelY));

      canvas.drawLine(Offset(x0, m.northY0), Offset(x0, m.southY1), divider);
    }

    for (int col = 0; col < map.totalColumns; col++) {
      final ci = map.columnInfo(col);
      final capId = ci.capilla.id;
      final capNameRaw = (ci.capilla.name ?? '').toString();
      final name = capNameRaw.trim().isEmpty
          ? ci.capilla.id
          : capNameRaw.trim();

      if (lastCapId == null) {
        lastCapId = capId;
        capStartCol = col;
        capName = name;
      } else if (capId != lastCapId) {
        flushCap(col);
        lastCapId = capId;
        capStartCol = col;
        capName = name;
      }
    }
    flushCap(map.totalColumns);

    final xEnd = m.gutterW + map.totalColumns * m.cellW;
    canvas.drawLine(Offset(xEnd, m.northY0), Offset(xEnd, m.southY1), divider);
  }

  void _drawPostLabelsAndRowDividers(Canvas canvas, _TrapMapMetrics m, NS ns) {
    final rows = (ns == NS.north) ? map.postsNorth : map.postsSouth;

    final textStyle = TextStyle(
      color: Colors.black.withValues(alpha: 0.45),
      fontSize: 10,
      fontWeight: FontWeight.w800,
    );

    final rowDivider = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.black.withValues(alpha: 0.06);

    for (int post = 1; post <= rows; post++) {
      final y = _cellTopY(m, ns, post);

      final shouldLabel = (post == 1) || (post == rows) || (post % 5 == 0);
      if (shouldLabel) {
        final tp = TextPainter(
          text: TextSpan(text: '$post', style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();

        tp.paint(
          canvas,
          Offset(m.gutterW - tp.width - 8.0, y + (m.cellH - tp.height) / 2.0),
        );
      }

      if (post % 5 == 0) {
        final yy = y + m.cellH;
        canvas.drawLine(
          Offset(m.gutterW, yy),
          Offset(m.gutterW + m.gridW, yy),
          rowDivider,
        );
      }
    }
  }

  String? _topPestAmong(Map<String, int> pests, Set<String> allowed) {
    var best = '';
    var bestV = 0;
    for (final p in allowed) {
      final v = pests[p] ?? 0;
      if (v > bestV) {
        bestV = v;
        best = p;
      }
    }
    return bestV > 0 ? best : null;
  }

  String _topPest(Map<String, int> pests) {
    var best = '';
    var bestV = -1;
    pests.forEach((k, v) {
      if (v > bestV) {
        best = k;
        bestV = v;
      }
    });
    return best.isEmpty ? 'PLAGA' : best;
  }

  Color _colorFromString(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final hue = (h % 360).toDouble();
    return HSVColor.fromAHSV(1.0, hue, 0.55, 0.90).toColor();
  }

  @override
  bool shouldRepaint(covariant _AdminTrapMapPainter old) {
    return old.map != map ||
        old.agg != agg ||
        old.mode != mode ||
        !setEquals(old.selectedPests, selectedPests) ||
        old.pestColors.length != pestColors.length ||
        old.hoverTrap != hoverTrap;
  }
}

class _TrapMapMetrics {
  final GreenhouseMap map;

  final double cellW = 18;
  final double cellH = 18;
  final double margin = 14;
  final double gutterW = 96;
  final double labelH = 12;
  final double midHeaderH = 26;

  _TrapMapMetrics(this.map);

  double get gridW => map.totalColumns * cellW;

  double get northY0 => margin + labelH;
  double get northY1 => northY0 + map.postsNorth * cellH;

  double get southY0 =>
      (margin + labelH + map.postsNorth * cellH + midHeaderH + labelH);
  double get southY1 => southY0 + map.postsSouth * cellH;

  Size get canvasSize {
    final w = gutterW + gridW + margin;
    final h =
        margin +
        labelH +
        map.postsNorth * cellH +
        midHeaderH +
        labelH +
        map.postsSouth * cellH +
        margin;
    return Size(w, h);
  }
}

// ========================= DATA MODELS =========================

class _TrapAggData {
  final Map<_TrapKey, _TrapAggTrap> traps = {};
  final Map<_TrapLineKey, _TrapLineMeta> lines = {};
  final Set<String> allPests = {};
  final Set<String> uids = {};
}

@immutable
class _TrapKey {
  final String capId;
  final String trapId;
  const _TrapKey({required this.capId, required this.trapId});

  @override
  bool operator ==(Object other) =>
      other is _TrapKey && other.capId == capId && other.trapId == trapId;

  @override
  int get hashCode => Object.hash(capId, trapId);
}

@immutable
class _TrapLineKey {
  final String capId;
  final String lineKey;
  const _TrapLineKey({required this.capId, required this.lineKey});

  @override
  bool operator ==(Object other) =>
      other is _TrapLineKey && other.capId == capId && other.lineKey == lineKey;

  @override
  int get hashCode => Object.hash(capId, lineKey);
}

class _TrapLineMeta {
  final String? byUid;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? updatedAt;
  final String status;

  const _TrapLineMeta({
    required this.byUid,
    required this.startedAt,
    required this.finishedAt,
    required this.updatedAt,
    required this.status,
  });
}

class _TrapAggTrap {
  final String capId;
  final String trapId;
  final String trapName;

  final String? byUid;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? updatedAt;

  final Map<String, int> pestsTotals;
  final String status;

  const _TrapAggTrap({
    required this.capId,
    required this.trapId,
    required this.trapName,
    required this.byUid,
    required this.startedAt,
    required this.finishedAt,
    required this.updatedAt,
    required this.pestsTotals,
    required this.status,
  });
}

@immutable
class _TrapHoverKey {
  final String capillaId;
  final String trapId;
  final NS ns;
  final int lineNo;
  final int post;

  const _TrapHoverKey({
    required this.capillaId,
    required this.trapId,
    required this.ns,
    required this.lineNo,
    required this.post,
  });
}
