// lib/pages/admin/admin_monitoreo_page.dart
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/mapa_model.dart';
import '../../theme/app_theme.dart';
import 'admin_trap_monitoreo_page.dart';
import 'admin_monitoreo_table_view.dart';

enum AdminOverlayMode { avance, plagas }

/// ✅ En Avance: ver solo puntos (como antes) o marcar toda la línea si está FINISHED
enum AdminAvanceView { puntos, lineas }

// modo
enum AdminViewMode { mapa, tabla }

class AdminMonitoreoPage extends StatefulWidget {
  const AdminMonitoreoPage({super.key});

  @override
  State<AdminMonitoreoPage> createState() => _AdminMonitoreoPageState();
}

class _AdminMonitoreoPageState extends State<AdminMonitoreoPage> {
  final _fs = FirebaseFirestore.instance;

  AdminViewMode _viewMode = AdminViewMode.mapa;

  GreenhouseMap? _selectedMap;
  AdminOverlayMode _mode = AdminOverlayMode.avance;

  /// ✅ selector puntos vs líneas
  AdminAvanceView _avanceView = AdminAvanceView.puntos;

  /// multi-week filter (keys tipo 2026-W04)
  final Set<String> _weekKeys = <String>{};

  // ===================== NUEVO: TAGS + SPLIT NIVELES =====================

  /// ✅ Selección por “TAG”
  /// - agrupado: "Araña roja"
  /// - separado: "Araña roja|1", "Araña roja|2", ...
  /// - sin nivel: "Trips"
  final Set<String> _selectedTags = <String>{}; // vacío => “Todas”

  /// ✅ Color por TAG (base o key nivel)
  final Map<String, Color> _tagColors = <String, Color>{};

  /// ✅ Bases (nombre) que se quieren ver SEPARADAS por niveles
  final Set<String> _splitLevelBases = <String>{};

  /// cache de nombres por UID (para tooltip)
  final Map<String, String> _uidNameCache = {};

  /// hover cell
  _CellKey? _hoverCell;

  /// hover cursor position (viewport coords dentro del _MapViewer)
  Offset? _hoverPos;

  /// zoom controller
  final TransformationController _tx = TransformationController();
  bool _fittedOnce = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekKeys.add(_isoWeekKey(now));
    _weekKeys.add(_isoWeekKey(now.subtract(const Duration(days: 7))));
  }

  @override
  void dispose() {
    _tx.dispose();
    super.dispose();
  }

  // ---------------------- Firestore loaders ----------------------

  Stream<List<GreenhouseMap>> _mapsStream() {
    return _fs.collection('greenhouses_maps').snapshots().map((snap) {
      return snap.docs
          .map(
            (d) => GreenhouseMap.fromDoc(
              d.id,
              Map<String, dynamic>.from(d.data()),
            ),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    });
  }

  Future<_AggData> _loadAgg(GreenhouseMap map, Set<String> weekKeys) async {
    final agg = _AggData();

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
        final linesAny = data['lines'];

        if (linesAny is! Map) continue;
        final lines = Map<String, dynamic>.from(linesAny);

        lines.forEach((lineKey, payloadAny) {
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

          final lk = _LineKey(capId: capId, lineKey: lineKey.toString());
          final prevLine = agg.lines[lk];

          agg.lines[lk] = _LineMeta(
            byUid: (byUid.isEmpty ? prevLine?.byUid : byUid),
            startedAt: startedAt ?? prevLine?.startedAt,
            finishedAt: finishedAt ?? prevLine?.finishedAt,
            updatedAt: updatedAt ?? prevLine?.updatedAt,
            status: status.isEmpty ? (prevLine?.status ?? '') : status,
          );

          if (byUid.isNotEmpty) agg.uids.add(byUid);

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

          if (posts.isEmpty) return;

          for (final post in posts) {
            final pestsLeft = <String, int>{};
            final pestsRight = <String, int>{};
            final pestsTotals = <String, int>{};

            void addSide({
              required Map<String, dynamic> src,
              required Map<String, int> destSide,
            }) {
              final pAny = src[post.toString()];
              if (pAny is! Map) return;
              final p = Map<String, dynamic>.from(pAny);
              p.forEach((pest, v) {
                final n = _asInt(v);
                if (n <= 0) return;
                final k = pest.toString();
                destSide[k] = (destSide[k] ?? 0) + n;
              });
            }

            addSide(src: left, destSide: pestsLeft);
            addSide(src: right, destSide: pestsRight);

            for (final e in pestsLeft.entries) {
              pestsTotals[e.key] = (pestsTotals[e.key] ?? 0) + e.value;
            }
            for (final e in pestsRight.entries) {
              pestsTotals[e.key] = (pestsTotals[e.key] ?? 0) + e.value;
            }

            final k = _AggKey(
              capId: capId,
              lineKey: lineKey.toString(),
              post: post,
            );
            final prev = agg.cells[k];

            if (prev == null) {
              agg.cells[k] = _AggCell(
                byUid: byUid.isEmpty ? null : byUid,
                startedAt: startedAt,
                finishedAt: finishedAt,
                updatedAt: updatedAt,
                pestsLeft: pestsLeft,
                pestsRight: pestsRight,
                pestsTotals: pestsTotals,
              );
            } else {
              final mergedLeft = Map<String, int>.from(prev.pestsLeft);
              pestsLeft.forEach(
                (pest, n) => mergedLeft[pest] = (mergedLeft[pest] ?? 0) + n,
              );

              final mergedRight = Map<String, int>.from(prev.pestsRight);
              pestsRight.forEach(
                (pest, n) => mergedRight[pest] = (mergedRight[pest] ?? 0) + n,
              );

              final mergedTotals = Map<String, int>.from(prev.pestsTotals);
              pestsTotals.forEach(
                (pest, n) => mergedTotals[pest] = (mergedTotals[pest] ?? 0) + n,
              );

              DateTime? bestFinished = prev.finishedAt;
              DateTime? bestUpdated = prev.updatedAt;
              DateTime? bestStarted = prev.startedAt;
              String? bestUid = prev.byUid;

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

              agg.cells[k] = _AggCell(
                byUid: bestUid,
                startedAt: bestStarted,
                finishedAt: bestFinished,
                updatedAt: bestUpdated,
                pestsLeft: mergedLeft,
                pestsRight: mergedRight,
                pestsTotals: mergedTotals,
              );
            }

            for (final pest in pestsTotals.keys) {
              agg.allPests.add(pest);
            }
          }
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

  // ===================== Helpers niveles (TAGS) =====================

  String _baseNameOf(String pestKey) {
    final raw = pestKey.trim();
    final idx = raw.lastIndexOf('|');
    if (idx <= 0) return raw;
    final name = raw.substring(0, idx).trim();
    return name.isEmpty ? raw : name;
  }

  String? _levelOf(String pestKey) {
    final raw = pestKey.trim();
    final idx = raw.lastIndexOf('|');
    if (idx <= 0) return null;
    final level = raw.substring(idx + 1).trim();
    return level.isEmpty ? null : level;
  }

  Map<String, List<String>> _levelsByBaseFromAgg(List<String> pestKeys) {
    final out = <String, Set<String>>{};
    for (final k in pestKeys) {
      final lv = _levelOf(k);
      if (lv == null) continue;
      final base = _baseNameOf(k);
      out.putIfAbsent(base, () => <String>{}).add(k);
    }

    return out.map((base, setKeys) {
      final list = setKeys.toList();
      list.sort((a, b) {
        final ai = int.tryParse(_levelOf(a) ?? '');
        final bi = int.tryParse(_levelOf(b) ?? '');
        if (ai != null && bi != null) return ai.compareTo(bi);
        return a.compareTo(b);
      });
      return MapEntry(base, list);
    });
  }

  List<String> _buildDisplayTags({
    required List<String> allPestKeys,
    required Map<String, List<String>> levelsByBase,
    required Set<String> splitBases,
  }) {
    final tags = <String>{};

    for (final k in allPestKeys) {
      if (_levelOf(k) == null) tags.add(k);
    }

    for (final e in levelsByBase.entries) {
      final base = e.key;
      final levelKeys = e.value;
      if (splitBases.contains(base)) {
        tags.addAll(levelKeys);
      } else {
        tags.add(base);
      }
    }

    final out = tags.toList();
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  // ===================== Dialog config niveles + color =====================

  Future<_LevelsDialogResult?> _pickLevelsAndColorsDialog(
    BuildContext context, {
    required String base,
    required List<String> levelKeys,
    required bool isSplit,
    required Map<String, Color> colors,
    required Color accent,
  }) async {
    bool split = isSplit;

    final localColors = <String, Color>{};
    localColors[base] = colors[base] ?? _colorFromString(base);
    for (final k in levelKeys) {
      localColors[k] = colors[k] ?? _colorFromString(k);
    }

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

    Future<Color?> pickPalette(Color initial) async {
      Color tmp = initial;
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
                    final sel = c.toARGB32() == tmp.toARGB32();
                    return InkWell(
                      onTap: () {
                        tmp = c;
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
      return ok == true ? tmp : null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Config: $base'),
          content: StatefulBuilder(
            builder: (ctx, setLocal) {
              return SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        value: split,
                        onChanged: (v) => setLocal(() => split = v),
                        title: const Text('Separar niveles en el mapa'),
                        subtitle: Text(
                          split
                              ? 'Cada nivel se pinta y filtra por separado.'
                              : 'Se suman todos los niveles en una sola plaga.',
                        ),
                        activeThumbColor: accent,
                        activeTrackColor: accent.withValues(alpha: 0.35),
                      ),
                      const SizedBox(height: 10),
                      if (!split) ...[
                        Text(
                          'Color (agrupado):',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            final c = await pickPalette(localColors[base]!);
                            if (c == null) return;
                            setLocal(() => localColors[base] = c);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: localColors[base]!.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: localColors[base]!.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: localColors[base],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(child: Text('Cambiar color')),
                                Icon(
                                  Icons.palette_outlined,
                                  color: Colors.black.withValues(alpha: 0.65),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Colores por nivel:',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final k in levelKeys)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () async {
                                final c = await pickPalette(localColors[k]!);
                                if (c == null) return;
                                setLocal(() => localColors[k] = c);
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: localColors[k],
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.18,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        k,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.palette_outlined,
                                      color: Colors.black.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            },
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

    if (ok != true) return null;

    final delta = <String, Color>{};
    if (split) {
      for (final k in levelKeys) {
        delta[k] = localColors[k]!;
      }
    } else {
      delta[base] = localColors[base]!;
    }

    return _LevelsDialogResult(isSplit: split, colorsDelta: delta);
  }

  // ---------------------- UI ----------------------

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('Monitoreo (Admin)'),
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
                _TopBar(
                  viewMode: _viewMode,
                  onViewMode: (v) => setState(() => _viewMode = v),
                  accent: accent,
                  mode: _mode,
                  avanceView: _avanceView,
                  onAvanceView: (v) => setState(() => _avanceView = v),
                  selectedWeeks: _weekKeys,
                  onMode: (m) => setState(() => _mode = m),
                  onWeeks: _pickWeeksDialog,
                  onOpenTraps: _openTrapsAdmin,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<List<GreenhouseMap>>(
                    stream: _mapsStream(),
                    builder: (context, snap) {
                      if (!snap.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final maps = snap.data!;
                      if (maps.isEmpty) {
                        return _EmptyCard(
                          accent: accent,
                          title: 'Sin mapas',
                          message: 'No hay mapas en "greenhouses_maps".',
                          icon: Icons.map_outlined,
                        );
                      }

                      _selectedMap ??= maps.first;

                      final mapPicker = _MapPicker(
                        accent: accent,
                        maps: maps,
                        selectedId: _selectedMap!.id,
                        onChanged: (id) {
                          final m = maps.firstWhere((x) => x.id == id);
                          setState(() {
                            _selectedMap = m;
                            _selectedTags.clear();
                            _hoverCell = null;
                            _hoverPos = null;
                            _fittedOnce = false;
                            _tx.value = Matrix4.identity();
                          });
                        },
                        onFit: _fitToViewport,
                      );

                      return Column(
                        children: [
                          mapPicker,
                          const SizedBox(height: 12),
                          Expanded(
                            child: FutureBuilder<_AggData>(
                              future: _loadAgg(_selectedMap!, _weekKeys),
                              builder: (context, aggSnap) {
                                if (!aggSnap.hasData)
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                final agg = aggSnap.data!;
                                final pestKeys = agg.allPests.toList()..sort();

                                final levelsByBase = _levelsByBaseFromAgg(
                                  pestKeys,
                                );
                                final displayTags = _buildDisplayTags(
                                  allPestKeys: pestKeys,
                                  levelsByBase: levelsByBase,
                                  splitBases: _splitLevelBases,
                                );

                                for (final tag in displayTags) {
                                  _tagColors.putIfAbsent(
                                    tag,
                                    () => _colorFromString(tag),
                                  );
                                }
                                for (final base in levelsByBase.keys) {
                                  if (!_splitLevelBases.contains(base)) {
                                    _tagColors.putIfAbsent(
                                      base,
                                      () => _colorFromString(base),
                                    );
                                  }
                                }

                                return Column(
                                  children: [
                                    if (_viewMode == AdminViewMode.mapa) ...[
                                      _LegendBarMulti(
                                        accent: accent,
                                        mode: _mode,
                                        displayTags: displayTags,
                                        levelsByBase: levelsByBase,
                                        splitLevelBases: _splitLevelBases,
                                        selectedTags: _selectedTags,
                                        tagColors: _tagColors,
                                        onToggleTag: (tagOrNull) {
                                          setState(() {
                                            if (tagOrNull == null) {
                                              _selectedTags.clear();
                                            } else {
                                              if (_selectedTags.contains(
                                                tagOrNull,
                                              )) {
                                                _selectedTags.remove(tagOrNull);
                                              } else {
                                                _selectedTags.add(tagOrNull);
                                              }
                                            }
                                          });
                                        },
                                        onConfigLevelsOrColor: (base) async {
                                          final res =
                                              await _pickLevelsAndColorsDialog(
                                                context,
                                                base: base,
                                                levelKeys:
                                                    levelsByBase[base] ??
                                                    const <String>[],
                                                isSplit: _splitLevelBases
                                                    .contains(base),
                                                colors: _tagColors,
                                                accent: accent,
                                              );
                                          if (res == null) return;

                                          setState(() {
                                            if (res.isSplit) {
                                              _splitLevelBases.add(base);

                                              if (_selectedTags.remove(base)) {
                                                for (final k
                                                    in (levelsByBase[base] ??
                                                        const <String>[])) {
                                                  _selectedTags.add(k);
                                                }
                                              }
                                            } else {
                                              _splitLevelBases.remove(base);

                                              final levelKeys =
                                                  levelsByBase[base] ??
                                                  const <String>[];
                                              final hadAny = levelKeys.any(
                                                _selectedTags.contains,
                                              );
                                              _selectedTags.removeWhere(
                                                (t) => levelKeys.contains(t),
                                              );
                                              if (hadAny)
                                                _selectedTags.add(base);
                                            }

                                            _tagColors.addAll(res.colorsDelta);
                                          });
                                        },
                                        onPickColorForTag: (tag) async {
                                          final c = await _pickColorDialog(
                                            context,
                                            initial:
                                                _tagColors[tag] ??
                                                _colorFromString(tag),
                                          );
                                          if (c == null) return;
                                          setState(() => _tagColors[tag] = c);
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    Expanded(
                                      child: (_viewMode == AdminViewMode.mapa)
                                          ? _MapViewer(
                                              map: _selectedMap!,
                                              agg: agg,
                                              mode: _mode,
                                              avanceView: _avanceView,
                                              selectedTags: _selectedTags,
                                              tagColors: _tagColors,
                                              splitLevelBases: _splitLevelBases,
                                              includeFinishedNoPests: false,
                                              tx: _tx,
                                              fittedOnce: _fittedOnce,
                                              onFittedOnce: () =>
                                                  _fittedOnce = true,
                                              onHover: (cell) => setState(
                                                () => _hoverCell = cell,
                                              ),
                                              onHoverPos: (pos) => setState(
                                                () => _hoverPos = pos,
                                              ),
                                              hoverCell: _hoverCell,
                                              hoverPos: _hoverPos,
                                              uidName: (uid) =>
                                                  _uidNameCache[uid] ?? uid,
                                            )
                                          : AdminMonitoreoTableView(
                                              map: _selectedMap!,
                                              weekKeys: _weekKeys,
                                            ),
                                    ),
                                  ],
                                );
                              },
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

  void _openTrapsAdmin() {
    final map = _selectedMap;
    if (map == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminTrapMonitoreoPage(
          map: map,
          initialWeekKeys: Set<String>.from(_weekKeys),
        ),
      ),
    );
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
                  final sel = c.toARGB32() == chosen.toARGB32();
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
                          separatorBuilder: (_, _) => Divider(
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

        _hoverCell = null;
        _hoverPos = null;
      });
    }
  }

  void _fitToViewport() {
    setState(() {
      _fittedOnce = false;
      _tx.value = Matrix4.identity();
    });
  }

  // ---------------------- ISO week helpers ----------------------

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

class _TopBar extends StatelessWidget {
  final AdminViewMode viewMode;
  final ValueChanged<AdminViewMode> onViewMode;
  final Color accent;
  final AdminOverlayMode mode;

  final AdminAvanceView avanceView;
  final ValueChanged<AdminAvanceView> onAvanceView;

  final Set<String> selectedWeeks;
  final ValueChanged<AdminOverlayMode> onMode;
  final VoidCallback onWeeks;

  final VoidCallback onOpenTraps;

  const _TopBar({
    required this.viewMode,
    required this.onViewMode,
    required this.accent,
    required this.mode,
    required this.avanceView,
    required this.onAvanceView,
    required this.selectedWeeks,
    required this.onMode,
    required this.onWeeks,
    required this.onOpenTraps,
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
          SegmentedButton<AdminViewMode>(
            segments: const [
              ButtonSegment(
                value: AdminViewMode.mapa,
                label: Text('Mapa'),
                icon: Icon(Icons.map_outlined),
              ),
              ButtonSegment(
                value: AdminViewMode.tabla,
                label: Text('Tabla'),
                icon: Icon(Icons.table_chart_outlined),
              ),
            ],
            selected: {viewMode},
            onSelectionChanged: (s) => onViewMode(s.first),
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
            onPressed: onOpenTraps,
            icon: const Icon(Icons.local_activity_outlined),
            label: const Text('Trampas'),
          ),
          if (viewMode == AdminViewMode.mapa)
            SegmentedButton<AdminOverlayMode>(
              segments: const [
                ButtonSegment(
                  value: AdminOverlayMode.avance,
                  label: Text('Avance'),
                  icon: Icon(Icons.timeline_outlined),
                ),
                ButtonSegment(
                  value: AdminOverlayMode.plagas,
                  label: Text('Plagas'),
                  icon: Icon(Icons.bug_report_outlined),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onMode(s.first),
            ),
          if (viewMode == AdminViewMode.mapa && mode == AdminOverlayMode.avance)
            SegmentedButton<AdminAvanceView>(
              segments: const [
                ButtonSegment(
                  value: AdminAvanceView.puntos,
                  label: Text('Puntos monitoreados'),
                  icon: Icon(Icons.grid_on_outlined),
                ),
                ButtonSegment(
                  value: AdminAvanceView.lineas,
                  label: Text('Líneas monitoreadas'),
                  icon: Icon(Icons.linear_scale_outlined),
                ),
              ],
              selected: {avanceView},
              onSelectionChanged: (s) => onAvanceView(s.first),
            ),
        ],
      ),
    );
  }
}

class _MapPicker extends StatelessWidget {
  final Color accent;
  final List<GreenhouseMap> maps;
  final String selectedId;
  final ValueChanged<String> onChanged;
  final VoidCallback onFit;

  const _MapPicker({
    required this.accent,
    required this.maps,
    required this.selectedId,
    required this.onChanged,
    required this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.20)),
            ),
            child: Icon(Icons.map_outlined, color: accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: selectedId,
              decoration: const InputDecoration(
                labelText: 'Invernadero',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: maps
                  .map(
                    (m) => DropdownMenuItem(value: m.id, child: Text(m.name)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onFit,
            icon: const Icon(Icons.fit_screen_outlined),
            label: const Text('Ajustar'),
          ),
        ],
      ),
    );
  }
}

class _LegendBarMulti extends StatelessWidget {
  final Color accent;
  final AdminOverlayMode mode;
  final List<String> displayTags;
  final Map<String, List<String>> levelsByBase;
  final Set<String> splitLevelBases;
  final Set<String> selectedTags;
  final Map<String, Color> tagColors;
  final ValueChanged<String?> onToggleTag;
  final ValueChanged<String> onConfigLevelsOrColor;
  final ValueChanged<String> onPickColorForTag;

  const _LegendBarMulti({
    required this.accent,
    required this.mode,
    required this.displayTags,
    required this.levelsByBase,
    required this.splitLevelBases,
    required this.selectedTags,
    required this.tagColors,
    required this.onToggleTag,
    required this.onConfigLevelsOrColor,
    required this.onPickColorForTag,
  });

  bool _isLevelKey(String k) => k.contains('|');

  @override
  Widget build(BuildContext context) {
    if (mode == AdminOverlayMode.avance) {
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
              'Con plagas',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 16),
            _Dot(color: Colors.black.withValues(alpha: 0.25)),
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

    final allSelected = selectedTags.isEmpty;

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
            onSelected: (_) => onToggleTag(null),
          ),
          for (final base in levelsByBase.keys)
            if (splitLevelBases.contains(base))
              ActionChip(
                avatar: const Icon(Icons.tune_rounded, size: 18),
                label: Text('$base • niveles'),
                onPressed: () => onConfigLevelsOrColor(base),
              ),
          ...displayTags.map((tag) {
            final selected = selectedTags.contains(tag);
            final c = tagColors[tag] ?? accent;

            final isBaseWithLevels =
                !_isLevelKey(tag) && levelsByBase.containsKey(tag);
            final onPalette = isBaseWithLevels
                ? () => onConfigLevelsOrColor(tag)
                : () => onPickColorForTag(tag);

            return InputChip(
              selected: selected,
              onPressed: () => onToggleTag(tag),
              onDeleted: onPalette,
              deleteIcon: Icon(
                Icons.palette_outlined,
                size: 18,
                color: Colors.black.withValues(alpha: 0.70),
              ),
              deleteButtonTooltipMessage: isBaseWithLevels
                  ? 'Config niveles / color'
                  : 'Cambiar color',
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
                  Text(tag),
                ],
              ),
            );
          }),
          if (displayTags.isEmpty)
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
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
                      color: Colors.black.withValues(alpha: 0.7),
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

// ========================= MAP VIEWER =========================

class _MapViewer extends StatefulWidget {
  final GreenhouseMap map;
  final _AggData agg;
  final AdminOverlayMode mode;
  final AdminAvanceView avanceView;
  final Set<String> selectedTags;
  final Map<String, Color> tagColors;
  final Set<String> splitLevelBases;
  final bool includeFinishedNoPests;
  final TransformationController tx;
  final bool fittedOnce;
  final VoidCallback onFittedOnce;
  final ValueChanged<_CellKey?> onHover;
  final ValueChanged<Offset?> onHoverPos;
  final _CellKey? hoverCell;
  final Offset? hoverPos;
  final String Function(String uid) uidName;

  const _MapViewer({
    required this.map,
    required this.agg,
    required this.mode,
    required this.avanceView,
    required this.selectedTags,
    required this.tagColors,
    required this.splitLevelBases,
    required this.includeFinishedNoPests,
    required this.tx,
    required this.fittedOnce,
    required this.onFittedOnce,
    required this.onHover,
    required this.onHoverPos,
    required this.hoverCell,
    required this.hoverPos,
    required this.uidName,
  });

  @override
  State<_MapViewer> createState() => _MapViewerState();
}

class _MapViewerState extends State<_MapViewer> {
  bool _dragging = false;
  bool _overCell = false;

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
            final metrics = _MapMetrics(widget.map);
            final canvasSize = metrics.canvasSize;

            if (!widget.fittedOnce) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fitTo(c.maxWidth, c.maxHeight, canvasSize);
                widget.onFittedOnce();
              });
            }

            final cursor = _dragging
                ? SystemMouseCursors.grabbing
                : (_overCell
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic);

            final pos = widget.hoverPos;
            final tooltipW = 380.0;
            final tooltipH = 260.0;
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
                        final cell = _hitTestCell(
                          canvasLocal: scene,
                          map: widget.map,
                        );

                        final over = cell != null;
                        if (over != _overCell) setState(() => _overCell = over);

                        widget.onHover(cell);
                      },
                      onExit: (_) {
                        if (_overCell) setState(() => _overCell = false);
                        widget.onHover(null);
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
                              painter: _AdminMapPainter(
                                map: widget.map,
                                agg: widget.agg,
                                mode: widget.mode,
                                avanceView: widget.avanceView,
                                selectedTags: widget.selectedTags,
                                tagColors: widget.tagColors,
                                splitLevelBases: widget.splitLevelBases,
                                includeFinishedNoPests:
                                    widget.includeFinishedNoPests,
                                hoverCell: widget.hoverCell,
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
                    child: _HoverInfo(
                      accent: accent,
                      map: widget.map,
                      agg: widget.agg,
                      hover: widget.hoverCell,
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

    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, s);
    matrix.setEntry(1, 1, s);
    matrix.setEntry(2, 2, 1.0);
    matrix.setEntry(3, 3, 1.0);
    matrix.setTranslationRaw(dx, dy, 0.0);

    widget.tx.value = matrix;
  }

  void _zoomBy({required double factor, required Offset focalPoint}) {
    final currentScale = widget.tx.value.getMaxScaleOnAxis();
    var nextScale = currentScale * factor;

    if (nextScale < _minScale) nextScale = _minScale;
    if (nextScale > _maxScale) nextScale = _maxScale;

    final sceneBefore = widget.tx.toScene(focalPoint);

    final dx = focalPoint.dx - (sceneBefore.dx * nextScale);
    final dy = focalPoint.dy - (sceneBefore.dy * nextScale);

    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, nextScale);
    matrix.setEntry(1, 1, nextScale);
    matrix.setEntry(2, 2, 1.0);
    matrix.setEntry(3, 3, 1.0);
    matrix.setTranslationRaw(dx, dy, 0.0);

    widget.tx.value = matrix;
    setState(() {});
  }

  _CellKey? _hitTestCell({
    required Offset canvasLocal,
    required GreenhouseMap map,
  }) {
    final x = canvasLocal.dx;
    final y = canvasLocal.dy;

    final m = _MapMetrics(map);

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

      post = map.postsNorth - rowFromTop;
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

    return _CellKey(
      capillaId: ci.capilla.id,
      lineKey: '${nsToStr(ns).toLowerCase()}_$lineNo',
      post: post,
      ns: ns,
      lineNo: lineNo,
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

class _HoverInfo extends StatelessWidget {
  final Color accent;
  final GreenhouseMap map;
  final _AggData agg;
  final _CellKey? hover;
  final String Function(String uid) uidName;

  const _HoverInfo({
    required this.accent,
    required this.map,
    required this.agg,
    required this.hover,
    required this.uidName,
  });

  @override
  Widget build(BuildContext context) {
    if (hover == null) {
      return _pill('Hover sobre una casilla', Icons.mouse_outlined);
    }

    final cellKey = _AggKey(
      capId: hover!.capillaId,
      lineKey: hover!.lineKey,
      post: hover!.post,
    );
    final cell = agg.cells[cellKey];

    final lineKey = _LineKey(capId: hover!.capillaId, lineKey: hover!.lineKey);
    final line = agg.lines[lineKey];

    final isFinished = (line?.status ?? '').toUpperCase() == 'FINISHED';

    final uid = cell?.byUid ?? line?.byUid;
    final who = (uid == null) ? null : uidName(uid);

    final st = cell?.startedAt ?? line?.startedAt;
    final ft = cell?.finishedAt ?? line?.finishedAt;
    final up = cell?.updatedAt ?? line?.updatedAt;

    String? horaMonitoreo;
    if (st != null && ft != null) {
      horaMonitoreo = '${_fmtHMS(st)} - ${_fmtHMS(ft)}';
    } else if (ft != null) {
      horaMonitoreo = _fmtFull(ft);
    } else if (up != null) {
      horaMonitoreo = _fmtFull(up);
    }

    final fecha = st != null
        ? _fmtDate(st)
        : (ft != null ? _fmtDate(ft) : (up != null ? _fmtDate(up) : null));

    final pestsTotals = cell?.pestsTotals ?? const <String, int>{};
    final pestsLeft = cell?.pestsLeft ?? const <String, int>{};
    final pestsRight = cell?.pestsRight ?? const <String, int>{};

    final pestKeys = pestsTotals.keys.toList()
      ..sort((a, b) => (pestsTotals[b] ?? 0).compareTo(pestsTotals[a] ?? 0));

    final title =
        '${hover!.ns == NS.north ? "NORTE" : "SUR"} • Línea ${hover!.lineNo} • Poste ${hover!.post}';

    final statusText = (cell != null)
        ? 'Con plagas registradas'
        : (isFinished
              ? 'Sin plagas en este poste'
              : 'Sin datos en semanas seleccionadas');

    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
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
                Icon(Icons.info_outline, color: accent, size: 18),
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
                color: (cell != null) ? Colors.greenAccent : Colors.white70,
              ),
            ),
            if (who != null) ...[
              const SizedBox(height: 4),
              Text('Por: $who', style: const TextStyle(color: Colors.white)),
            ],
            if (fecha != null || horaMonitoreo != null) ...[
              const SizedBox(height: 2),
              Text(
                'Hora: ${horaMonitoreo ?? "--"}${fecha != null ? " • $fecha" : ""}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            if (cell != null) ...[
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
                  'Sin plagas registradas en este poste.',
                  style: TextStyle(color: Colors.white70),
                )
              else
                ...pestKeys.take(8).map((p) {
                  final l = pestsLeft[p] ?? 0;
                  final r = pestsRight[p] ?? 0;
                  final t = pestsTotals[p] ?? (l + r);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $p: Izq $l • Der $r (Total $t)',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }),
              if (pestKeys.length > 8)
                Text(
                  '+ ${pestKeys.length - 8} más...',
                  style: const TextStyle(color: Colors.white70),
                ),
            ],
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

// ========================= PAINTER =========================

class _AdminMapPainter extends CustomPainter {
  final GreenhouseMap map;
  final _AggData agg;
  final AdminOverlayMode mode;
  final AdminAvanceView avanceView;
  final Set<String> selectedTags;
  final Map<String, Color> tagColors;
  final Set<String> splitLevelBases;
  final bool includeFinishedNoPests;
  final _CellKey? hoverCell;

  _AdminMapPainter({
    required this.map,
    required this.agg,
    required this.mode,
    required this.avanceView,
    required this.selectedTags,
    required this.tagColors,
    required this.splitLevelBases,
    required this.includeFinishedNoPests,
    required this.hoverCell,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final m = _MapMetrics(map);

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    _drawBand(canvas, m, NS.north);
    _drawBand(canvas, m, NS.south);

    _drawCapillaDividersAndLabels(canvas, m);

    _drawPostSectionHeader(canvas, m, NS.north);
    _drawPostLabelsAndRowDividers(canvas, m, NS.north);

    _drawPostSectionHeader(canvas, m, NS.south);
    _drawPostLabelsAndRowDividers(canvas, m, NS.south);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.black.withValues(alpha: 0.06);

    for (int col = 0; col < map.totalColumns; col++) {
      final ci = map.columnInfo(col);
      _paintColumn(canvas, m, ci, col, NS.north, border);
      _paintColumn(canvas, m, ci, col, NS.south, border);
    }

    if (hoverCell != null) {
      final rect = _cellRect(m, hoverCell!);
      if (rect != null) {
        final h = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = AppTheme.pepperGreen.withValues(alpha: 0.95);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          h,
        );
      }
    }
  }

  double _cellTopY(_MapMetrics m, NS ns, int post) {
    final rows = (ns == NS.north) ? map.postsNorth : map.postsSouth;
    final top = (ns == NS.north) ? m.northY0 : m.southY0;

    if (ns == NS.north) {
      return top + (rows - post) * m.cellH;
    }
    return top + (post - 1) * m.cellH;
  }

  void _drawBand(Canvas canvas, _MapMetrics m, NS ns) {
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

  void _drawCapillaDividersAndLabels(Canvas canvas, _MapMetrics m) {
    final divider = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.08);

    final double middleTop = m.northY1;
    final double middleBottom = m.southY0;
    final double middleCenterY = middleTop + ((middleBottom - middleTop) / 2.0);

    final textStyle = TextStyle(
      color: Colors.black.withValues(alpha: 0.74),
      fontSize: 11,
      fontWeight: FontWeight.w900,
    );

    String buildCapillaLabel(ColumnInfo ci) {
      final rawName = (ci.capilla.name ?? '').toString().trim();
      final fallbackName = ci.capilla.id;
      final name = rawName.isNotEmpty ? rawName : fallbackName;

      return name;
    }

    String? lastCapId;
    int capStartCol = 0;
    String? capName;

    void flushCap(int endColExclusive) {
      if (capName == null) return;

      final x0 = m.gutterW + capStartCol * m.cellW;
      final x1 = m.gutterW + endColExclusive * m.cellW;
      final capWidth = x1 - x0;

      final tp = TextPainter(
        text: TextSpan(text: capName, style: textStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
        textAlign: TextAlign.center,
      )..layout(maxWidth: math.max(0.0, capWidth - 10.0));

      final textX = x0 + ((capWidth - tp.width) / 2.0);
      final textY = middleCenterY - (tp.height / 2.0);

      final bgLeft = math.max(x0 + 2.0, textX - 8.0);
      final bgWidth = math.min(capWidth - 4.0, tp.width + 16.0);

      final bgRect = Rect.fromLTWH(
        bgLeft,
        textY - 3.0,
        bgWidth,
        tp.height + 6.0,
      );

      final bg = Paint()..color = Colors.white.withValues(alpha: 0.88);

      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(10)),
        bg,
      );

      tp.paint(canvas, Offset(textX, textY));

      canvas.drawLine(Offset(x0, m.northY0), Offset(x0, m.southY1), divider);
    }

    for (int col = 0; col < map.totalColumns; col++) {
      final ci = map.columnInfo(col);
      final capId = ci.capilla.id;
      final fullLabel = buildCapillaLabel(ci);

      if (lastCapId == null) {
        lastCapId = capId;
        capStartCol = col;
        capName = fullLabel;
      } else if (capId != lastCapId) {
        flushCap(col);
        lastCapId = capId;
        capStartCol = col;
        capName = fullLabel;
      }
    }

    flushCap(map.totalColumns);

    final xEnd = m.gutterW + map.totalColumns * m.cellW;
    canvas.drawLine(Offset(xEnd, m.northY0), Offset(xEnd, m.southY1), divider);
  }

  void _drawPostSectionHeader(Canvas canvas, _MapMetrics m, NS ns) {
    final y = (ns == NS.north) ? (m.northY0 - 14.0) : (m.southY0 - 14.0);
    final label = (ns == NS.north) ? 'POSTES N' : 'POSTES S';

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.45),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(m.gutterW - tp.width - 8.0, y));
  }

  void _drawPostLabelsAndRowDividers(Canvas canvas, _MapMetrics m, NS ns) {
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

  void _paintColumn(
    Canvas canvas,
    _MapMetrics m,
    ColumnInfo ci,
    int col,
    NS ns,
    Paint border,
  ) {
    final lineNo = (ns == NS.north) ? ci.northLineNo : ci.southLineNo;
    if (lineNo == null) return;

    final lineKey = '${nsToStr(ns).toLowerCase()}_$lineNo';
    final lk = _LineKey(capId: ci.capilla.id, lineKey: lineKey);
    final lineMeta = agg.lines[lk];
    final lineFinished = (lineMeta?.status ?? '').toUpperCase() == 'FINISHED';

    final rows = (ns == NS.north) ? map.postsNorth : map.postsSouth;

    String baseOf(String k) {
      final raw = k.trim();
      final idx = raw.lastIndexOf('|');
      if (idx <= 0) return raw;
      final name = raw.substring(0, idx).trim();
      return name.isEmpty ? raw : name;
    }

    for (int post = 1; post <= rows; post++) {
      if (!map.isActive(ns, post, lineNo)) continue;

      final key = _AggKey(capId: ci.capilla.id, lineKey: lineKey, post: post);
      final cell = agg.cells[key];

      Color fill;

      if (mode == AdminOverlayMode.avance) {
        if (avanceView == AdminAvanceView.lineas) {
          fill = lineFinished
              ? Colors.green.withValues(alpha: 0.60)
              : Colors.black.withValues(alpha: 0.05);
        } else {
          fill = (cell != null)
              ? Colors.green.withValues(alpha: 0.65)
              : Colors.black.withValues(alpha: 0.05);
        }
      } else {
        final pests = cell?.pestsTotals ?? const <String, int>{};
        if (pests.isEmpty) {
          fill = Colors.black.withValues(alpha: 0.05);
        } else {
          final buckets = <String, int>{};

          pests.forEach((pestKey, qty) {
            if (qty <= 0) return;
            final base = baseOf(pestKey);
            final tag = splitLevelBases.contains(base) ? pestKey : base;
            buckets[tag] = (buckets[tag] ?? 0) + qty;
          });

          if (buckets.isEmpty) {
            fill = Colors.black.withValues(alpha: 0.05);
          } else {
            Map<String, int> considered = buckets;

            if (selectedTags.isNotEmpty) {
              final filtered = <String, int>{};
              for (final t in selectedTags) {
                final v = buckets[t];
                if (v != null && v > 0) filtered[t] = v;
              }
              if (filtered.isEmpty) {
                fill = Colors.black.withValues(alpha: 0.05);
                final rect = Rect.fromLTWH(
                  m.gutterW + col * m.cellW + 1.0,
                  _cellTopY(m, ns, post) + 1.0,
                  m.cellW - 2.0,
                  m.cellH - 2.0,
                );
                canvas.drawRRect(
                  RRect.fromRectAndRadius(rect, const Radius.circular(6)),
                  Paint()..color = fill,
                );
                canvas.drawRRect(
                  RRect.fromRectAndRadius(rect, const Radius.circular(6)),
                  border,
                );
                continue;
              }
              considered = filtered;
            }

            String topTag = considered.keys.first;
            int topV = -1;
            considered.forEach((k, v) {
              if (v > topV) {
                topV = v;
                topTag = k;
              }
            });

            fill = (tagColors[topTag] ?? _colorFromString(topTag)).withValues(
              alpha: 0.78,
            );
          }
        }
      }

      final rect = Rect.fromLTWH(
        m.gutterW + col * m.cellW + 1.0,
        _cellTopY(m, ns, post) + 1.0,
        m.cellW - 2.0,
        m.cellH - 2.0,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        border,
      );
    }
  }

  Rect? _cellRect(_MapMetrics m, _CellKey c) {
    final col = _findColumnFor(c);
    if (col == null) return null;

    return Rect.fromLTWH(
      m.gutterW + col * m.cellW + 1.0,
      _cellTopY(m, c.ns, c.post) + 1.0,
      m.cellW - 2.0,
      m.cellH - 2.0,
    );
  }

  int? _findColumnFor(_CellKey c) {
    for (int col = 0; col < map.totalColumns; col++) {
      final ci = map.columnInfo(col);
      if (ci.capilla.id != c.capillaId) continue;
      final ln = (c.ns == NS.north) ? ci.northLineNo : ci.southLineNo;
      if (ln == c.lineNo) return col;
    }
    return null;
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
  bool shouldRepaint(covariant _AdminMapPainter old) {
    return old.map != map ||
        old.agg != agg ||
        old.mode != mode ||
        old.avanceView != avanceView ||
        !setEquals(old.selectedTags, selectedTags) ||
        old.tagColors.length != tagColors.length ||
        !setEquals(old.splitLevelBases, splitLevelBases) ||
        old.includeFinishedNoPests != includeFinishedNoPests ||
        old.hoverCell != hoverCell;
  }
}

class _MapMetrics {
  final GreenhouseMap map;

  final double cellW = 18;
  final double cellH = 18;
  final double margin = 14;
  final double gutterW = 96;
  final double labelH = 12;
  final double midHeaderH = 26;

  _MapMetrics(this.map);

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

class _AggData {
  final Map<_AggKey, _AggCell> cells = {};
  final Map<_LineKey, _LineMeta> lines = {};
  final Set<String> allPests = {};
  final Set<String> uids = {};
}

@immutable
class _AggKey {
  final String capId;
  final String lineKey;
  final int post;

  const _AggKey({
    required this.capId,
    required this.lineKey,
    required this.post,
  });

  @override
  bool operator ==(Object other) {
    return other is _AggKey &&
        other.capId == capId &&
        other.lineKey == lineKey &&
        other.post == post;
  }

  @override
  int get hashCode => Object.hash(capId, lineKey, post);
}

@immutable
class _LineKey {
  final String capId;
  final String lineKey;

  const _LineKey({required this.capId, required this.lineKey});

  @override
  bool operator ==(Object other) =>
      other is _LineKey && other.capId == capId && other.lineKey == lineKey;

  @override
  int get hashCode => Object.hash(capId, lineKey);
}

class _LineMeta {
  final String? byUid;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? updatedAt;
  final String status;

  const _LineMeta({
    required this.byUid,
    required this.startedAt,
    required this.finishedAt,
    required this.updatedAt,
    required this.status,
  });
}

class _AggCell {
  final String? byUid;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? updatedAt;

  final Map<String, int> pestsLeft;
  final Map<String, int> pestsRight;
  final Map<String, int> pestsTotals;

  const _AggCell({
    required this.byUid,
    required this.startedAt,
    required this.finishedAt,
    required this.updatedAt,
    required this.pestsLeft,
    required this.pestsRight,
    required this.pestsTotals,
  });
}

@immutable
class _CellKey {
  final String capillaId;
  final String lineKey;
  final int post;
  final NS ns;
  final int lineNo;

  const _CellKey({
    required this.capillaId,
    required this.lineKey,
    required this.post,
    required this.ns,
    required this.lineNo,
  });
}

// ========================= DIALOG RESULT MODEL =========================

class _LevelsDialogResult {
  final bool isSplit;
  final Map<String, Color> colorsDelta;
  const _LevelsDialogResult({required this.isSplit, required this.colorsDelta});
}
