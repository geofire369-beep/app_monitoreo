import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/mapa_model.dart';
import '../../../theme/app_theme.dart';
import '../../../services/offline/offline_sync_service.dart';
import '../monitora/monitora_trap_monitoring_page.dart';

class MonitoraNewTrapMonitoringPage extends StatefulWidget {
  const MonitoraNewTrapMonitoringPage({super.key});

  @override
  State<MonitoraNewTrapMonitoringPage> createState() => _MonitoraNewTrapMonitoringPageState();
}

class _MonitoraNewTrapMonitoringPageState extends State<MonitoraNewTrapMonitoringPage> {
  static const String _mapsCol = 'greenhouses_maps';

  String? _selectedMapId;
  GreenhouseMap? _selectedMap;

  CapillaDef? _selectedCapilla;
  int? _selectedLine;

  final Map<String, Map<String, dynamic>> _docCache = {};

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo monitoreo de trampa'),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection(_mapsCol).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          final items = <_GreenhouseItem>[];

          for (final d in docs) {
            final data = d.data();
            _docCache[d.id] = data;

            final name = (data['name'] ?? '').toString().trim();
            items.add(_GreenhouseItem(
              id: d.id,
              name: name.isEmpty ? '(sin nombre)' : name,
            ));
          }

          items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          if (_selectedMapId != null && items.every((x) => x.id != _selectedMapId)) {
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
                      accent.withValues(alpha: 0.10),
                      Colors.white,
                      Colors.white,
                    ],
                  ),
                ),
              );

              final leftPanel = _LeftPanel(
                accent: accent,
                items: items,
                selectedMapId: _selectedMapId,
                onSelectMap: _selectGreenhouse,
                selectedCapilla: _selectedCapilla,
                capillaItems: _capillaItemsOnlyName(),
                onSelectCapilla: (cap) {
                  if (cap == null) return;
                  setState(() {
                    _selectedCapilla = cap;
                    _selectedLine = null;
                  });
                },
                canSelectCapilla: _selectedMap != null,
                selectedMapName: _selectedMap?.name,
                selectedCapName: _selectedCapilla == null ? null : _capName(_selectedCapilla!),
                selectedLine: _selectedLine,
              );

              // ✅ doneKeys se calcula en cada build
              final doneKeys = _doneTrapLineKeysForSelectedCapillaThisWeek();

              final linesWidget = (_selectedMap == null || _selectedCapilla == null)
                  ? _emptyLinesHint(accent: accent, msg: 'Selecciona un invernadero y una capilla para ver trampas.')
                  : _trapLinesTwoSidesList(
                      doneKeys: doneKeys,
                      shrinkWrap: !isWide,
                      scrollable: isWide,
                    );

              final rightPanel = _RightPanel(
                accent: accent,
                selectedMap: _selectedMap,
                selectedCapilla: _selectedCapilla,
                linesWidget: linesWidget,
                expandBody: isWide,
              );

              final selectedLineObj = (_selectedLine == null) ? null : _findLineByNo(_selectedLine!);
              final selectedKey = (selectedLineObj == null) ? null : _lineKey(selectedLineObj);
              final isSelectedDone = (selectedKey != null) && doneKeys.contains(selectedKey);

              final bottom = (_selectedLine == null)
                  ? null
                  : SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                        child: SizedBox(
                          height: 52,
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: isSelectedDone ? Colors.black.withValues(alpha: 0.25) : accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: isSelectedDone ? null : _startTrapMonitoring, // ✅
                            icon: Icon(isSelectedDone ? Icons.check_circle_outline_rounded : Icons.play_arrow_rounded),
                            label: Text(
                              isSelectedDone ? 'Línea finalizada' : 'Iniciar monitoreo (trampa)',
                              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
                            ),
                          ),
                        ),
                      ),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: 440, child: SingleChildScrollView(child: leftPanel)),
                                  const SizedBox(width: 16),
                                  Expanded(child: rightPanel),
                                ],
                              )
                            : SingleChildScrollView(
                                padding: EdgeInsets.only(bottom: bottomSafeExtra),
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
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------------- Helpers ----------------

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

  List<DropdownMenuItem<CapillaDef>> _capillaItemsOnlyName() {
    final map = _selectedMap;
    if (map == null) return const [];

    final caps = [...map.capillas]..sort((a, b) => a.startLineNo.compareTo(b.startLineNo));

    return [
      for (final cap in caps)
        DropdownMenuItem(
          value: cap,
          child: Text(_capName(cap)),
        ),
    ];
  }

  String _capName(CapillaDef cap) {
    final name = (cap.name ?? '').trim();
    return name.isEmpty ? '(sin nombre)' : name;
  }

  /// Devuelve keys tipo "south_7" "north_14" SOLO para líneas que tengan trampa en la capilla seleccionada.
  Set<String> _trapLineKeysForSelectedCapilla() {
    final map = _selectedMap;
    final cap = _selectedCapilla;
    if (map == null || cap == null) return <String>{};

    final capValid = <String>{};
    for (final l in cap.lines) {
      capValid.add(_lineKey(l));
    }

    final out = <String>{};

    for (final t in map.traps) {
      for (final cell in t.cells) {
        final k = '${nsToStr(cell.side).toLowerCase()}_${cell.lineNo}';
        if (capValid.contains(k)) out.add(k);
      }
    }

    return out;
  }

  /// ✅ LÍNEAS FINALIZADAS (semana actual) en base al marcador local: "trap_done_<lineKey>"
  Set<String> _doneTrapLineKeysForSelectedCapillaThisWeek() {
    final map = _selectedMap;
    final cap = _selectedCapilla;
    if (map == null || cap == null) return <String>{};

    final weekKey = _isoWeekKey(DateTime.now());

    final trapKeys = _trapLineKeysForSelectedCapilla();
    final out = <String>{};

    for (final lk in trapKeys) {
      final markerKey = 'trap_done_$lk';

      final marker = OfflineSyncService.instance.loadDraft(
        weekKey: weekKey,
        greenhouseId: map.id,
        capillaId: cap.id,
        lineKey: markerKey,
      );

      if (marker == null) continue;

      final counts = marker['counts'];
      if (counts is Map && (counts['status']?.toString() == 'FINISHED')) {
        out.add(lk);
      } else {
        // compatibilidad: si existe el marker, lo consideramos done
        out.add(lk);
      }
    }

    return out;
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

  // ---------------- UI: empty hint ----------------

  Widget _emptyLinesHint({required Color accent, required String msg}) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
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
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Icon(Icons.hub_outlined, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.70),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Lines list (traps only) ----------------
  // IZQUIERDA: SUR | DERECHA: NORTE

  Widget _trapLinesTwoSidesList({
    required Set<String> doneKeys,
    required bool shrinkWrap,
    required bool scrollable,
  }) {
    final cap = _selectedCapilla!;
    final trapKeys = _trapLineKeysForSelectedCapilla();

    final filtered = <CapLine>[];
    for (final l in cap.lines) {
      if (trapKeys.contains(_lineKey(l))) filtered.add(l);
    }

    if (filtered.isEmpty) {
      return _emptyLinesHint(
        accent: AppTheme.pepperGreen,
        msg: 'Esta capilla no tiene líneas con trampas registradas.',
      );
    }

    filtered.sort((a, b) => a.lineNo.compareTo(b.lineNo));

    final south = <CapLine>[];
    final north = <CapLine>[];

    for (final l in filtered) {
      if (l.side == NS.south) {
        south.add(l);
      } else {
        north.add(l);
      }
    }

    final rows = (south.length > north.length) ? south.length : north.length;

    const tileH = 50.0; // espacio para "Finalizada"
    const gap = 10.0;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: rows,
      shrinkWrap: shrinkWrap,
      physics: scrollable ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
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
                      : _lineTileTrap(
                          line: s,
                          done: doneKeys.contains(_lineKey(s)),
                          selected: _selectedLine == s.lineNo,
                          onTap: () => _onTapLineTrap(s, doneKeys),
                        ),
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: SizedBox(
                  height: tileH,
                  child: (n == null)
                      ? _emptySlot()
                      : _lineTileTrap(
                          line: n,
                          done: doneKeys.contains(_lineKey(n)),
                          selected: _selectedLine == n.lineNo,
                          onTap: () => _onTapLineTrap(n, doneKeys),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onTapLineTrap(CapLine line, Set<String> doneKeys) {
    setState(() => _selectedLine = line.lineNo);

    final k = _lineKey(line);
    if (doneKeys.contains(k)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta línea ya está finalizada esta semana.')),
      );
    }
  }

  Widget _emptySlot() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1),
      ),
    );
  }

  Widget _lineTileTrap({
    required CapLine line,
    required bool done,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isGreen = line.color.toString().toUpperCase() == "GREEN";

    final baseBg = isGreen ? AppTheme.pepperGreen.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.04);
    final borderColor = isGreen ? AppTheme.pepperGreen.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.18);

    final doneBg = Colors.black.withValues(alpha: 0.03);
    final doneBorder = Colors.black.withValues(alpha: 0.18);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: done ? doneBg : (selected ? baseBg.withValues(alpha: 0.22) : baseBg),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: done ? doneBorder : (selected ? AppTheme.pepperGreen : borderColor),
              width: selected ? 1.6 : 1.1,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_activity_outlined,
                      size: 16,
                      color: done
                          ? Colors.black.withValues(alpha: 0.55)
                          : (isGreen ? AppTheme.pepperGreen : Colors.black.withValues(alpha: 0.55)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Línea ${line.lineNo}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: done
                            ? Colors.black.withValues(alpha: 0.55)
                            : (isGreen ? AppTheme.pepperGreen : Colors.black.withValues(alpha: 0.78)),
                        decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
                      ),
                    ),
                  ],
                ),
                if (done) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Finalizada',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ FIX IMPORTANTE: al volver del monitoreo => setState() para recalcular doneKeys sin tocar nada
  Future<void> _startTrapMonitoring() async {
    final map = _selectedMap;
    final cap = _selectedCapilla;
    final lineNo = _selectedLine;
    if (map == null || cap == null || lineNo == null) return;

    final lineObj = _findLineByNo(lineNo);
    if (lineObj == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró la línea seleccionada.')),
      );
      return;
    }

    final trapsEnEsaLinea = map.traps.where((t) {
      return t.cells.any((c) => c.side == lineObj.side && c.lineNo == lineObj.lineNo);
    }).toList();

    if (trapsEnEsaLinea.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay trampas registradas en esta línea.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MonitoraTrapMonitoringPage(
          map: map,
          capilla: cap,
          lineSide: lineObj.side,
          lineNo: lineNo,
          traps: trapsEnEsaLinea,
        ),
      ),
    );

    // ✅ al regresar, repinta para que aparezca "Finalizada" automáticamente
    if (!mounted) return;
    setState(() {});
  }

  // ---------------- ISO week utils (sin paquetes) ----------------

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
    final firstWeekThursday = firstThursday.add(Duration(days: 3 - ((firstThursday.weekday + 6) % 7)));
    final diff = thursday.difference(firstWeekThursday).inDays;
    return 1 + (diff ~/ 7);
  }
}

class _GreenhouseItem {
  final String id;
  final String name;
  _GreenhouseItem({required this.id, required this.name});
}

// =============================== UI Panels ===============================

class _LeftPanel extends StatelessWidget {
  final Color accent;

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
      prefixIcon: Icon(icon, color: accent),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.03),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black.withValues(alpha: 0.65)),
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
    final mapLabel = (selectedMapName == null || selectedMapName!.trim().isEmpty) ? '—' : selectedMapName!.trim();
    final capLabel = (selectedCapName == null || selectedCapName!.trim().isEmpty) ? '—' : selectedCapName!.trim();
    final lineLabel = (selectedLine == null) ? '—' : 'Línea $selectedLine';

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
                child: Icon(Icons.local_activity_outlined, color: accent),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nuevo monitoreo de trampa', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('Selecciona invernadero, capilla y línea con trampa para continuar.'),
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
              _chip(icon: Icons.yard_outlined, label: 'Invernadero', value: mapLabel),
              _chip(icon: Icons.grid_view_rounded, label: 'Capilla', value: capLabel),
              _chip(icon: Icons.local_activity_outlined, label: 'Línea', value: lineLabel),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1) Invernadero', style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
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
                items: items.map((x) => DropdownMenuItem(value: x.id, child: Text(x.name))).toList(),
                onChanged: (id) {
                  if (id == null) return;
                  onSelectMap(id);
                },
              ),
              const SizedBox(height: 16),
              Text('2) Capilla', style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
              const SizedBox(height: 10),
              DropdownButtonFormField<CapillaDef>(
                key: ValueKey('cap_${selectedCapilla?.startLineNo ?? -1}_${selectedCapilla?.endLineNo ?? -1}'),
                initialValue: selectedCapilla,
                isExpanded: true,
                decoration: _deco(
                  label: 'Selecciona capilla',
                  icon: Icons.grid_view_rounded,
                  hint: canSelectCapilla ? 'Selecciona' : 'Primero selecciona un invernadero',
                ),
                items: capillaItems,
                onChanged: canSelectCapilla ? onSelectCapilla : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Colors.black.withValues(alpha: 0.55)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Solo se muestran las líneas que tienen trampas (Sur izquierda, Norte derecha).',
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.62), fontWeight: FontWeight.w700),
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
  final GreenhouseMap? selectedMap;
  final CapillaDef? selectedCapilla;
  final Widget linesWidget;

  final bool expandBody;

  const _RightPanel({
    required this.accent,
    required this.selectedMap,
    required this.selectedCapilla,
    required this.linesWidget,
    this.expandBody = true,
  });

  @override
  Widget build(BuildContext context) {
    final ready = selectedMap != null && selectedCapilla != null;

    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: linesWidget,
    );

    return Container(
      width: double.infinity,
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
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  child: Icon(Icons.local_activity_outlined, color: accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('3) Líneas con trampas', style: TextStyle(fontWeight: FontWeight.w900, color: accent)),
                      const SizedBox(height: 2),
                      Text(
                        ready ? 'Sur (izquierda) • Norte (derecha)' : 'Primero elige invernadero y capilla.',
                        style: TextStyle(color: Colors.black.withValues(alpha: 0.62), fontWeight: FontWeight.w700),
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
