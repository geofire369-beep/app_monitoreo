// lib/pages/monitora/agro_apply/monitora_agro_apply_foco_new_page.dart
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/mapa_model.dart';
import '../../../services/offline/offline_sync_service.dart';
import 'monitora_agro_apply_foco_line_page.dart';

class MonitoraAgroApplyFocoNewPage extends StatefulWidget {
  const MonitoraAgroApplyFocoNewPage({super.key});

  @override
  State<MonitoraAgroApplyFocoNewPage> createState() =>
      _MonitoraAgroApplyFocoNewPageState();
}

class _MonitoraAgroApplyFocoNewPageState
    extends State<MonitoraAgroApplyFocoNewPage> {
  static const String _mapsCol = 'greenhouses_maps';

  // ✅ Nueva paleta naranja
  static const Color _agroAccent = Color(0xFFF55000);
  static const Color _agroAccentDark = Color(0xFFB63A00);
  static const Color _agroBorder = Color(0xFFFF9A6B);
  static const Color _agroFill = Color(0xFFFFF6F1);

  String? _selectedMapId;
  GreenhouseMap? _selectedMap;

  CapillaDef? _selectedCapilla;
  int? _selectedLine;

  final Map<String, Map<String, dynamic>> _docCache = {};

  @override
  Widget build(BuildContext context) {
    const accent = _agroAccent;
    final weekKey = _isoWeekKey(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4EE),
      appBar: AppBar(
        title: const Text('Aplicar agroquímicos (FOCO)'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection(_mapsCol).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator(color: accent));
          }

          final docs = snap.data!.docs;
          final items = <_GreenhouseItem>[];

          for (final d in docs) {
            final data = d.data();
            _docCache[d.id] = data;

            final name = (data['name'] ?? '').toString().trim();
            items.add(
              _GreenhouseItem(
                id: d.id,
                name: name.isEmpty ? '(sin nombre)' : name,
              ),
            );
          }

          items.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

          if (_selectedMapId != null &&
              items.every((x) => x.id != _selectedMapId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _resetAll();
            });
          }

          return LayoutBuilder(
            builder: (context, c) {
              final isWide = c.maxWidth >= 980;

              final bg = Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accent.withValues(alpha: 0.14),
                      const Color(0xFFFFF7F2),
                      Colors.white,
                    ],
                  ),
                ),
              );

              if (_selectedMap == null) {
                final leftPanel = _LeftPanel(
                  accent: accent,
                  accentDark: _agroAccentDark,
                  borderColor: _agroBorder,
                  fillColor: _agroFill,
                  items: items,
                  selectedMapId: _selectedMapId,
                  onSelectMap: _selectGreenhouse,
                  selectedCapilla: _selectedCapilla,
                  capillaItems: const [],
                  onSelectCapilla: (_) {},
                  canSelectCapilla: false,
                  selectedMapName: _selectedMap?.name,
                  selectedCapName: _selectedCapilla == null
                      ? null
                      : _capName(_selectedCapilla!),
                  selectedLine: _selectedLine,
                );

                final rightPanel = _RightPanel(
                  accent: accent,
                  accentDark: _agroAccentDark,
                  selectedMap: _selectedMap,
                  selectedCapilla: _selectedCapilla,
                  linesWidget: _emptyLinesHint(accent),
                  expandBody: isWide,
                );

                return Stack(
                  children: [
                    Positioned.fill(child: bg),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 440,
                                    child: SingleChildScrollView(
                                      child: leftPanel,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(child: rightPanel),
                                ],
                              )
                            : SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: Column(
                                  children: [
                                    leftPanel,
                                    const SizedBox(height: 14),
                                    rightPanel,
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              }

              final ghRef = FirebaseFirestore.instance
                  .collection('monitoreo_weeks')
                  .doc(weekKey)
                  .collection('greenhouses')
                  .doc(_selectedMap!.id);

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ghRef.collection('capillas').snapshots(),
                builder: (context, capSnap) {
                  final capDocs =
                      capSnap.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                  final capillasWithFoco = _extractCapillaIdsWithAnyFoco(
                    capDocs,
                  );

                  if (_selectedCapilla != null &&
                      !capillasWithFoco.contains(_selectedCapilla!.id)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        _selectedCapilla = null;
                        _selectedLine = null;
                      });
                    });
                  }

                  final leftPanel = _LeftPanel(
                    accent: accent,
                    accentDark: _agroAccentDark,
                    borderColor: _agroBorder,
                    fillColor: _agroFill,
                    items: items,
                    selectedMapId: _selectedMapId,
                    onSelectMap: _selectGreenhouse,
                    selectedCapilla: _selectedCapilla,
                    capillaItems: _capillaItemsOnlyNameFilteredByFoco(
                      capillasWithFoco,
                    ),
                    onSelectCapilla: (cap) {
                      if (cap == null) return;
                      setState(() {
                        _selectedCapilla = cap;
                        _selectedLine = null;
                      });
                    },
                    canSelectCapilla:
                        _selectedMap != null && capillasWithFoco.isNotEmpty,
                    selectedMapName: _selectedMap?.name,
                    selectedCapName: _selectedCapilla == null
                        ? null
                        : _capName(_selectedCapilla!),
                    selectedLine: _selectedLine,
                  );

                  if (_selectedCapilla == null) {
                    final rightPanel = _RightPanel(
                      accent: accent,
                      accentDark: _agroAccentDark,
                      selectedMap: _selectedMap,
                      selectedCapilla: _selectedCapilla,
                      linesWidget: capillasWithFoco.isEmpty
                          ? _emptyNoCapillasWithFocoHint(accent)
                          : _emptyLinesHint(accent),
                      expandBody: isWide,
                    );

                    return Stack(
                      children: [
                        Positioned.fill(child: bg),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: isWide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 440,
                                        child: SingleChildScrollView(
                                          child: leftPanel,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(child: rightPanel),
                                    ],
                                  )
                                : SingleChildScrollView(
                                    padding: const EdgeInsets.only(bottom: 18),
                                    child: Column(
                                      children: [
                                        leftPanel,
                                        const SizedBox(height: 14),
                                        rightPanel,
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    );
                  }

                  return ValueListenableBuilder(
                    valueListenable:
                        OfflineSyncService.instance.outboxListenable,
                    builder: (context, _, __) {
                      final focusLineKeys = _extractLineKeysWithFocoFromCapDocs(
                        capDocs: capDocs,
                        capillaId: _selectedCapilla!.id,
                      );

                      final doneKeys = <String>{};

                      final capDocData = capDocs
                          .where((d) => d.id == _selectedCapilla!.id)
                          .map((d) => d.data())
                          .toList();
                      if (capDocData.isNotEmpty) {
                        final data = capDocData.first;
                        final linesAny = data['lines'];
                        if (linesAny is Map) {
                          final lines = Map<String, dynamic>.from(linesAny);
                          lines.forEach((k, v) {
                            if (v is Map) {
                              final agroAny = v['agroFoco'];
                              if (agroAny is Map) {
                                final st = (agroAny['status'] ?? '')
                                    .toString()
                                    .toUpperCase();
                                if (st == 'FINISHED') {
                                  doneKeys.add(k.toString());
                                }
                              }
                            }
                          });
                        }
                      }

                      final localPending = OfflineSyncService.instance
                          .pendingAgroFocoLineKeys(
                            weekKey: weekKey,
                            greenhouseId: _selectedMap!.id,
                            capillaId: _selectedCapilla!.id,
                          );
                      doneKeys.addAll(localPending);

                      if (_selectedLine != null) {
                        final lineObj = _findLineByNo(_selectedLine!);
                        if (lineObj != null) {
                          final k = _lineKey(lineObj);
                          final allowed = focusLineKeys.contains(k);
                          final done = doneKeys.contains(k);
                          if (!allowed || done) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() => _selectedLine = null);
                            });
                          }
                        }
                      }

                      final selectedLineDone = _isSelectedLineDone(doneKeys);
                      final canStart =
                          _selectedLine != null && !selectedLineDone;

                      final bottom = !canStart
                          ? null
                          : SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  14,
                                ),
                                child: SizedBox(
                                  height: 54,
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: accent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: _startApply,
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text(
                                      'Iniciar aplicación',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );

                      final linesWidgetMobile = _linesTwoSidesListFocoOnly(
                        focusLineKeys: focusLineKeys,
                        doneKeys: doneKeys,
                        shrinkWrap: true,
                        scrollable: false,
                      );

                      final linesWidgetWide = _linesTwoSidesListFocoOnly(
                        focusLineKeys: focusLineKeys,
                        doneKeys: doneKeys,
                        shrinkWrap: false,
                        scrollable: true,
                      );

                      final rightPanelWide = _RightPanel(
                        accent: accent,
                        accentDark: _agroAccentDark,
                        selectedMap: _selectedMap,
                        selectedCapilla: _selectedCapilla,
                        linesWidget: linesWidgetWide,
                        expandBody: true,
                      );

                      final rightPanelMobile = _RightPanel(
                        accent: accent,
                        accentDark: _agroAccentDark,
                        selectedMap: _selectedMap,
                        selectedCapilla: _selectedCapilla,
                        linesWidget: linesWidgetMobile,
                        expandBody: false,
                      );

                      final bottomSafeExtra = (bottom == null) ? 18.0 : 90.0;

                      return Scaffold(
                        backgroundColor: Colors.transparent,
                        bottomNavigationBar: bottom,
                        body: Stack(
                          children: [
                            Positioned.fill(child: bg),
                            SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: isWide
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 440,
                                            child: SingleChildScrollView(
                                              child: leftPanel,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(child: rightPanelWide),
                                        ],
                                      )
                                    : SingleChildScrollView(
                                        padding: EdgeInsets.only(
                                          bottom: bottomSafeExtra,
                                        ),
                                        child: Column(
                                          children: [
                                            leftPanel,
                                            const SizedBox(height: 14),
                                            rightPanelMobile,
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyLinesHint(Color accent) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCFA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Icon(Icons.flash_on_rounded, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Selecciona invernadero y capilla.\nSolo aparecerán capillas y líneas que tengan FOCO en la semana actual.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyNoCapillasWithFocoHint(Color accent) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCFA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Icon(Icons.info_outline_rounded, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'En este invernadero no hay capillas con FOCO en la semana actual.\nPrimero marca FOCO en el monitoreo de plagas.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetAll() {
    setState(() {
      _selectedMapId = null;
      _selectedMap = null;
      _selectedCapilla = null;
      _selectedLine = null;
    });
  }

  void _selectGreenhouse(String docId) {
    final data = _docCache[docId];
    if (data == null) return;

    final map = GreenhouseMap.fromDoc(docId, data);

    setState(() {
      _selectedMapId = docId;
      _selectedMap = map;
      _selectedCapilla = null;
      _selectedLine = null;
    });
  }

  List<DropdownMenuItem<CapillaDef>> _capillaItemsOnlyNameFilteredByFoco(
    Set<String> capillasWithFoco,
  ) {
    final map = _selectedMap;
    if (map == null) return const [];

    final caps = [...map.capillas]
      ..sort((a, b) => a.startLineNo.compareTo(b.startLineNo));

    final filtered = caps
        .where((c) => capillasWithFoco.contains(c.id))
        .toList();

    return [
      for (final cap in filtered)
        DropdownMenuItem(value: cap, child: Text(_capName(cap))),
    ];
  }

  String _capName(CapillaDef cap) {
    final name = (cap.name ?? '').trim();
    return name.isEmpty ? '(sin nombre)' : name;
  }

  CapLine? _findLineByNo(int no) {
    final cap = _selectedCapilla;
    if (cap == null) return null;
    for (final l in cap.lines) {
      if (l.lineNo == no) return l;
    }
    return null;
  }

  String _lineKey(CapLine l) => '${nsToStr(l.side).toLowerCase()}_${l.lineNo}';

  bool _isSelectedLineDone(Set<String> doneKeys) {
    final no = _selectedLine;
    if (no == null) return false;
    final l = _findLineByNo(no);
    if (l == null) return false;
    return doneKeys.contains(_lineKey(l));
  }

  Set<String> _extractCapillaIdsWithAnyFoco(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> capDocs,
  ) {
    final out = <String>{};

    for (final d in capDocs) {
      final data = d.data();
      final linesAny = data['lines'];
      if (linesAny is! Map) continue;

      final lines = Map<String, dynamic>.from(linesAny);
      var hasFoco = false;

      for (final e in lines.entries) {
        final v = e.value;
        if (v is! Map) continue;

        final line = Map<String, dynamic>.from(v);
        final obsAny = line['observations'];
        if (obsAny is! Map) continue;

        final obs = Map<String, dynamic>.from(obsAny);
        final focusAny = obs['focus'];
        if (focusAny is! Map) continue;

        final focus = Map<String, dynamic>.from(focusAny);
        if (_hasAnyTrueInFocusSide(focus['left']) ||
            _hasAnyTrueInFocusSide(focus['right'])) {
          hasFoco = true;
          break;
        }
      }

      if (hasFoco) out.add(d.id);
    }

    return out;
  }

  Set<String> _extractLineKeysWithFocoFromCapDocs({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> capDocs,
    required String capillaId,
  }) {
    final out = <String>{};

    final doc = capDocs.where((d) => d.id == capillaId).toList();
    if (doc.isEmpty) return out;

    final data = doc.first.data();
    final linesAny = data['lines'];
    if (linesAny is! Map) return out;

    final lines = Map<String, dynamic>.from(linesAny);
    for (final e in lines.entries) {
      final lk = e.key.toString();
      final v = e.value;
      if (v is! Map) continue;
      final line = Map<String, dynamic>.from(v);

      final obsAny = line['observations'];
      if (obsAny is! Map) continue;
      final obs = Map<String, dynamic>.from(obsAny);

      final focusAny = obs['focus'];
      if (focusAny is! Map) continue;
      final focus = Map<String, dynamic>.from(focusAny);

      if (_hasAnyTrueInFocusSide(focus['left']) ||
          _hasAnyTrueInFocusSide(focus['right'])) {
        out.add(lk);
      }
    }

    return out;
  }

  bool _hasAnyTrueInFocusSide(Object? sideAny) {
    if (sideAny is! Map) return false;
    final side = Map<String, dynamic>.from(sideAny as Map);

    for (final postEntry in side.entries) {
      final pestsAny = postEntry.value;
      if (pestsAny is! Map) continue;
      final pests = Map<String, dynamic>.from(pestsAny as Map);

      for (final v in pests.values) {
        if (v is bool && v) return true;
        if (v?.toString() == 'true') return true;
      }
    }

    return false;
  }

  Widget _linesTwoSidesListFocoOnly({
    required Set<String> focusLineKeys,
    required Set<String> doneKeys,
    required bool shrinkWrap,
    required bool scrollable,
  }) {
    final cap = _selectedCapilla!;
    final all = [...cap.lines];
    if (all.isEmpty) return _emptyLinesHint(_agroAccent);

    all.sort((a, b) => a.lineNo.compareTo(b.lineNo));

    final filtered = all
        .where((l) => focusLineKeys.contains(_lineKey(l)))
        .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No hay líneas con FOCO en esta capilla (semana actual).',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.65),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final south = <CapLine>[];
    final north = <CapLine>[];

    for (final l in filtered) {
      if (l.side == NS.south) {
        south.add(l);
      } else {
        north.add(l);
      }
    }

    final rows = math.max(south.length, north.length);

    const tileH = 44.0;
    const gap = 10.0;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: rows,
      shrinkWrap: shrinkWrap,
      physics: scrollable
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemBuilder: (context, i) {
        final s = (i < south.length) ? south[i] : null;
        final n = (i < north.length) ? north[i] : null;

        return Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: tileH,
                  child: (s == null)
                      ? _emptySlot()
                      : _lineTile(
                          accent: _agroAccent,
                          line: s,
                          done: doneKeys.contains(_lineKey(s)),
                          selected: _selectedLine == s.lineNo,
                          onTap: () => _onTapLine(s, doneKeys),
                        ),
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: SizedBox(
                  height: tileH,
                  child: (n == null)
                      ? _emptySlot()
                      : _lineTile(
                          accent: _agroAccent,
                          line: n,
                          done: doneKeys.contains(_lineKey(n)),
                          selected: _selectedLine == n.lineNo,
                          onTap: () => _onTapLine(n, doneKeys),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onTapLine(CapLine line, Set<String> doneKeys) {
    final k = _lineKey(line);
    if (doneKeys.contains(k)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _agroAccentDark,
          content: const Text('Línea ya finalizada (o pendiente de subir).'),
        ),
      );
      return;
    }
    setState(() => _selectedLine = line.lineNo);
  }

  Widget _emptySlot() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _agroAccent.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
    );
  }

  Widget _lineTile({
    required Color accent,
    required CapLine line,
    required bool done,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final baseBg = accent.withValues(alpha: 0.10);
    final borderColor = accent.withValues(alpha: 0.36);

    final doneBg = const Color(0xFFF6F6F6);
    final doneBorder = Colors.black.withValues(alpha: 0.14);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: done
                ? doneBg
                : (selected ? accent.withValues(alpha: 0.18) : baseBg),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: done ? doneBorder : (selected ? accent : borderColor),
              width: selected ? 1.8 : 1.15,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                done ? Icons.check_circle_rounded : Icons.flash_on_rounded,
                size: 16,
                color: done
                    ? Colors.black.withValues(alpha: 0.50)
                    : _agroAccentDark,
              ),
              const SizedBox(width: 8),
              Text(
                'Línea ${line.lineNo}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  color: done
                      ? Colors.black.withValues(alpha: 0.55)
                      : Colors.black.withValues(alpha: 0.82),
                  decoration: done
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startApply() {
    final map = _selectedMap;
    final cap = _selectedCapilla;
    final lineNo = _selectedLine;

    if (map == null || cap == null || lineNo == null) return;

    CapLine? found;
    for (final l in cap.lines) {
      if (l.lineNo == lineNo) {
        found = l;
        break;
      }
    }

    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró la línea seleccionada en la capilla.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MonitoraAgroApplyFocoLinePage(map: map, capilla: cap, line: found!),
      ),
    );
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

class _GreenhouseItem {
  final String id;
  final String name;
  _GreenhouseItem({required this.id, required this.name});
}

class _LeftPanel extends StatelessWidget {
  final Color accent;
  final Color accentDark;
  final Color borderColor;
  final Color fillColor;

  final List<_GreenhouseItem> items;
  final String? selectedMapId;
  final ValueChanged<String> onSelectMap;

  final CapillaDef? selectedCapilla;
  final List<DropdownMenuItem<CapillaDef>> capillaItems;
  final ValueChanged<CapillaDef?> onSelectCapilla;
  final bool canSelectCapilla;

  final String? selectedMapName;
  final String? selectedCapName;
  final int? selectedLine;

  const _LeftPanel({
    required this.accent,
    required this.accentDark,
    required this.borderColor,
    required this.fillColor,
    required this.items,
    required this.selectedMapId,
    required this.onSelectMap,
    required this.selectedCapilla,
    required this.capillaItems,
    required this.onSelectCapilla,
    required this.canSelectCapilla,
    required this.selectedMapName,
    required this.selectedCapName,
    required this.selectedLine,
  });

  InputDecoration _deco({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: accentDark, fontWeight: FontWeight.w800),
      floatingLabelStyle: TextStyle(
        color: accentDark,
        fontWeight: FontWeight.w900,
      ),
      hintStyle: TextStyle(
        color: Colors.black.withValues(alpha: 0.45),
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(icon),
      prefixIconColor: accent,
      iconColor: accent,
      filled: true,
      fillColor: fillColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent, width: 1.7),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: borderColor.withValues(alpha: 0.40),
          width: 1.1,
        ),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapLabel =
        (selectedMapName == null || selectedMapName!.trim().isEmpty)
        ? '—'
        : selectedMapName!.trim();
    final capLabel =
        (selectedCapName == null || selectedCapName!.trim().isEmpty)
        ? '—'
        : selectedCapName!.trim();
    final lineLabel = (selectedLine == null) ? '—' : 'Línea $selectedLine';

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCFA),
            borderRadius: BorderRadius.circular(20),
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
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Icon(Icons.local_pharmacy_outlined, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aplicación a FOCO',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: accentDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Selecciona invernadero y capilla (solo con FOCO). Luego elige una línea con FOCO.',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
          ),
          child: Wrap(
            runSpacing: 10,
            spacing: 10,
            children: [
              _chip(
                icon: Icons.yard_outlined,
                label: 'Invernadero',
                value: mapLabel,
              ),
              _chip(
                icon: Icons.grid_view_rounded,
                label: 'Capilla',
                value: capLabel,
              ),
              _chip(
                icon: Icons.view_week_outlined,
                label: 'Línea',
                value: lineLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCFA),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1) Invernadero',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: accentDark,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('map_${selectedMapId ?? "none"}'),
                initialValue: selectedMapId,
                isExpanded: true,
                decoration: _deco(
                  label: 'Selecciona invernadero',
                  icon: Icons.yard_outlined,
                  hint: 'Selecciona',
                ),
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
                dropdownColor: Colors.white,
                iconEnabledColor: accent,
                iconDisabledColor: accent.withValues(alpha: 0.55),
                items: items
                    .map(
                      (x) => DropdownMenuItem(value: x.id, child: Text(x.name)),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  onSelectMap(id);
                },
              ),
              const SizedBox(height: 16),
              Text(
                '2) Capilla (con FOCO)',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: accentDark,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<CapillaDef>(
                key: ValueKey(
                  'cap_${selectedCapilla?.startLineNo ?? -1}_${selectedCapilla?.endLineNo ?? -1}',
                ),
                initialValue: selectedCapilla,
                isExpanded: true,
                decoration: _deco(
                  label: 'Selecciona capilla',
                  icon: Icons.grid_view_rounded,
                  hint: canSelectCapilla
                      ? 'Selecciona'
                      : 'No hay capillas con FOCO (semana actual)',
                ),
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
                dropdownColor: Colors.white,
                iconEnabledColor: accent,
                iconDisabledColor: accent.withValues(alpha: 0.55),
                items: capillaItems,
                onChanged: canSelectCapilla ? onSelectCapilla : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: accentDark.withValues(alpha: 0.80),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La lista de capillas ya está filtrada por FOCO (semana actual).',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.64),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RightPanel extends StatelessWidget {
  final Color accent;
  final Color accentDark;
  final GreenhouseMap? selectedMap;
  final CapillaDef? selectedCapilla;
  final Widget linesWidget;
  final bool expandBody;

  const _RightPanel({
    required this.accent,
    required this.accentDark,
    required this.selectedMap,
    required this.selectedCapilla,
    required this.linesWidget,
    this.expandBody = true,
  });

  @override
  Widget build(BuildContext context) {
    final ready = selectedMap != null && selectedCapilla != null;

    final body = Padding(padding: const EdgeInsets.all(14), child: linesWidget);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border.all(color: accent.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.alt_route_rounded, color: accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '3) Líneas con FOCO',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: accentDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ready
                            ? 'Sur (izquierda) • Norte (derecha)'
                            : 'Primero elige invernadero y capilla.',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (expandBody) Expanded(child: body) else body,
        ],
      ),
    );
  }
}
