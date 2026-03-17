// lib/pages/admin/agro/agro_applications_page.dart
//
// ✅ Admin Agroquímicos (Mapa) - TEMA VERDE (pepperGreen):
// - Multi-selección de semanas (como AdminMonitoreo)
// - Overlay en mapa:
//    1) Casillas con FOCO (plagas con focus=true) en semanas seleccionadas
//    2) Casillas con APLICACIÓN (agroFoco) en semanas seleccionadas
// - Hover (desktop): muestra FOCO y/o aplicaciones (por plaga) del poste en semanas seleccionadas
// - Tap/click en CUALQUIER poste activo (tenga o no FOCO): abre panel detalle:
//    - Tab "Semanas seleccionadas": FOCO + apps por semana/lado/plaga
//    - Tab "Historial": timeline escaneando semanas hacia atrás (lazy “Cargar más”)
//
// ✅ NUEVO (por pedido):
// - Botón "Aplicación general" (para TODO el invernadero)
// - Botón "Ver generales" con sheet:
//    - Tab "Semanas seleccionadas" (filtra por weekKey)
//    - Tab "Historial" (todas)
// - Se guarda en colección: agro_general_apps
//
// ✅ FIX sin tocar Firebase (sin índices compuestos):
// - Historial generales: QUITAR orderBy() del query y ordenar client-side.
// - Semanas generales: QUITAR filtro greenhouseId dentro de whereIn() y filtrar client-side.
//
// ✅ Productos para generales:
// - Los productos se cargan desde colección 'productos' y se eligen en Dropdown.
//
// ✅ Restricción de registro:
// - Bloquear registrar aplicaciones generales en semanas viejas.
//   (Si estás en semana 11, NO permite registrar semana 9).
//   => Solo permite semana actual y la inmediatamente anterior.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/mapa_model.dart';
import '../../../theme/app_theme.dart';

enum AgroViewMode { mapa }

enum AgroOverlayMode { focoVsAplicado }

class AgroApplicationsPage extends StatefulWidget {
  const AgroApplicationsPage({super.key});

  @override
  State<AgroApplicationsPage> createState() => _AgroApplicationsPageState();
}

class _AgroApplicationsPageState extends State<AgroApplicationsPage> {
  final _fs = FirebaseFirestore.instance;

  AgroViewMode _viewMode = AgroViewMode.mapa;
  AgroOverlayMode _mode = AgroOverlayMode.focoVsAplicado;

  GreenhouseMap? _selectedMap;

  // ✅ multi-week filter
  final Set<String> _weekKeys = <String>{};

  // cache de nombres por UID (tooltip/panel)
  final Map<String, String> _uidNameCache = {};

  // hover cell (desktop)
  _CellKey? _hoverCell;
  Offset? _hoverPos;

  // zoom controller
  final TransformationController _tx = TransformationController();
  bool _fittedOnce = false;

  // ✅ General apps collection
  static const String _generalAppsCol = 'agro_general_apps';

  // ✅ Productos (collection 'productos')
  List<_AgroProdOpt> _products = const [];
  bool _loadingProducts = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekKeys.add(_isoWeekKey(now));
    _weekKeys.add(_isoWeekKey(now.subtract(const Duration(days: 7))));
    _loadProducts();
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

  Future<_AgroAgg> _loadAgg(GreenhouseMap map, Set<String> weekKeys) async {
    final agg = _AgroAgg();

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
        for (final e in lines.entries) {
          final lineKey = e.key.toString();
          final payloadAny = e.value;
          if (payloadAny is! Map) continue;
          final payload = Map<String, dynamic>.from(payloadAny);

          agg.addWeekLineData(
            weekKey: wk,
            capId: capId,
            lineKey: lineKey,
            linePayload: payload,
          );
        }
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

  String _uidName(String uid) => _uidNameCache[uid] ?? uid;

  // ✅ Productos
  Future<void> _loadProducts() async {
    try {
      final snap = await _fs.collection('productos').orderBy('nombre').get();
      final out = <_AgroProdOpt>[];

      for (final d in snap.docs) {
        final m = d.data();
        final nombre = (m['nombre'] ?? '').toString().trim();
        if (nombre.isEmpty) continue;
        out.add(
          _AgroProdOpt(
            id: d.id,
            nombre: nombre,
            tipo: (m['tipo'] ?? '').toString().trim(),
          ),
        );
      }

      out.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _products = out;
        _loadingProducts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _products = const [];
        _loadingProducts = false;
      });
    }
  }

  // ---------------------- UI ----------------------

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    return Scaffold(
      backgroundColor: accent.withValues(alpha: 0.06),
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('Agroquímicos (Admin)'),
        elevation: 0,
      ),
      body: Container(
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
                  onMode: (m) => setState(() => _mode = m),
                  selectedWeeks: _weekKeys,
                  onPickWeeks: _pickWeeksDialog,

                  // ✅ NUEVO
                  onAddGeneralApp: _openAddGeneralAppDialog,
                  onOpenGeneralApps: _openGeneralAppsViewer,
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
                          _LegendBar(accent: accent, mode: _mode),
                          const SizedBox(height: 10),
                          Expanded(
                            child: FutureBuilder<_AgroAgg>(
                              future: _loadAgg(_selectedMap!, _weekKeys),
                              builder: (context, aggSnap) {
                                if (!aggSnap.hasData)
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                final agg = aggSnap.data!;

                                return _MapViewerAgro(
                                  map: _selectedMap!,
                                  agg: agg,
                                  mode: _mode,
                                  tx: _tx,
                                  fittedOnce: _fittedOnce,
                                  onFittedOnce: () => _fittedOnce = true,
                                  onHover: (cell) =>
                                      setState(() => _hoverCell = cell),
                                  onHoverPos: (pos) =>
                                      setState(() => _hoverPos = pos),
                                  hoverCell: _hoverCell,
                                  hoverPos: _hoverPos,
                                  uidName: _uidName,
                                  onTapCell: _openCellDetails,
                                  accent: accent,
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

  void _fitToViewport() {
    setState(() {
      _fittedOnce = false;
      _tx.value = Matrix4.identity();
    });
  }

  void _openCellDetails(_CellKey cell) {
    final map = _selectedMap;
    if (map == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CellDetailsSheet(
        accent: AppTheme.pepperGreen,
        map: map,
        cell: cell,
        selectedWeekKeys: Set<String>.from(_weekKeys),
        fs: _fs,
        uidName: _uidName,
      ),
    );
  }

  // ---------------------- GENERAL APPS (Admin) ----------------------

  void _openGeneralAppsViewer() {
    final map = _selectedMap;
    if (map == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GeneralAppsSheet(
        accent: AppTheme.pepperGreen,
        fs: _fs,
        map: map,
        selectedWeekKeys: Set<String>.from(_weekKeys),
      ),
    );
  }

  /// ✅ Restricción: solo permite registrar semana actual o anterior
  Set<String> _allowedRegisterWeeks() {
    final now = DateTime.now();
    final cur = _isoWeekKey(now);
    final prev = _isoWeekKey(now.subtract(const Duration(days: 7)));
    return {cur, prev};
  }

  Future<void> _openAddGeneralAppDialog() async {
    final map = _selectedMap;
    if (map == null) return;

    final accent = AppTheme.pepperGreen;

    if (_loadingProducts) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cargando productos…')));
      return;
    }
    if (_products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay productos en catálogo (colección "productos").',
          ),
        ),
      );
      return;
    }

    DateTime selectedDate = DateTime.now();
    selectedDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );

    final encargadoCtrl = TextEditingController();

    _AgroProdOpt selectedProduct = _products.first;

    const tipoOpciones = <String>[
      'Aspersión',
      'Drench',
      'Fertirriego',
      'Nebulización',
      'Otro',
    ];
    String tipo = tipoOpciones.first;

    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              InputDecoration deco({
                required String label,
                IconData? icon,
                String? hint,
              }) {
                return InputDecoration(
                  labelText: label,
                  hintText: hint,
                  prefixIcon: icon == null ? null : Icon(icon, color: accent),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.03),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: accent, width: 1.4),
                  ),
                );
              }

              final wk = _isoWeekKey(selectedDate);
              final allowed = _allowedRegisterWeeks();
              final canRegister = allowed.contains(wk);

              return Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Agregar aplicación general',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Invernadero: ${map.name}',
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
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.pop(ctx, false),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime(2023, 1, 1),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked == null) return;
                            setLocal(() {
                              selectedDate = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                              );
                            });
                          },
                          child: InputDecorator(
                            decoration: deco(
                              label: 'Fecha',
                              icon: Icons.calendar_month_rounded,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${fmt(selectedDate)}  •  ${_isoWeekKey(selectedDate)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.edit_calendar_rounded,
                                  color: Colors.black.withValues(alpha: 0.55),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        if (!canRegister)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              'Bloqueado: solo se permite registrar en la semana actual o la anterior.\n'
                              'Semana seleccionada: $wk\nPermitidas: ${allowed.join(", ")}',
                              style: TextStyle(
                                color: Colors.red.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),

                        const SizedBox(height: 12),

                        TextField(
                          controller: encargadoCtrl,
                          decoration: deco(
                            label: 'Nombre del encargado',
                            icon: Icons.person_outline_rounded,
                            hint: 'Ej: Juan Pérez',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<_AgroProdOpt>(
                          value: selectedProduct,
                          decoration: deco(
                            label: 'Producto aplicado',
                            icon: Icons.science_outlined,
                          ),
                          items: _products
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    p.tipo.isEmpty
                                        ? p.nombre
                                        : '${p.nombre} (${p.tipo})',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(
                            () => selectedProduct = v ?? selectedProduct,
                          ),
                        ),

                        const SizedBox(height: 12),

                        DropdownButtonFormField<String>(
                          value: tipo,
                          decoration: deco(
                            label: 'Tipo de aplicación',
                            icon: Icons.category_outlined,
                          ),
                          items: tipoOpciones
                              .map(
                                (x) =>
                                    DropdownMenuItem(value: x, child: Text(x)),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(() => tipo = v ?? tipo),
                        ),

                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: canRegister
                                    ? () => Navigator.pop(ctx, true)
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Guardar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (ok != true) return;

    final encargado = encargadoCtrl.text.trim();
    if (encargado.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa el nombre del encargado.')),
      );
      return;
    }

    final wk = _isoWeekKey(selectedDate);
    final allowed = _allowedRegisterWeeks();
    if (!allowed.contains(wk)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bloqueado: no se puede registrar en $wk. Solo: ${allowed.join(", ")}',
          ),
        ),
      );
      return;
    }

    final appliedAtMs = selectedDate.millisecondsSinceEpoch;

    try {
      await _fs.collection(_generalAppsCol).add({
        'greenhouseId': map.id,
        'greenhouseName': map.name.trim(),
        'weekKey': wk,
        'appliedAtMs': appliedAtMs,
        'encargadoName': encargado,
        'producto': selectedProduct.nombre,
        'productoId': selectedProduct.id,
        'productoTipo': selectedProduct.tipo,
        'tipoAplicacion': tipo,
        'createdByUid': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aplicación general guardada ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
    }
  }

  // ---------------------- Weeks multi-select dialog ----------------------

  Future<void> _pickWeeksDialog() async {
    final accent = AppTheme.pepperGreen;
    final now = DateTime.now();

    final options = List.generate(
      20,
      (i) => _isoWeekKey(now.subtract(Duration(days: 7 * i))),
    );
    final temp = Set<String>.from(_weekKeys);

    String prettyWeek(String key) {
      final parts = key.split('-W');
      if (parts.length != 2) return key;
      return 'Semana ${int.tryParse(parts[1]) ?? parts[1]} • ${parts[0]}';
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

        _hoverCell = null;
        _hoverPos = null;
      });
    }
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
}

// ========================= TOP UI =========================

class _TopBar extends StatelessWidget {
  final AgroViewMode viewMode;
  final ValueChanged<AgroViewMode> onViewMode;

  final Color accent;
  final AgroOverlayMode mode;
  final ValueChanged<AgroOverlayMode> onMode;

  final Set<String> selectedWeeks;
  final VoidCallback onPickWeeks;

  final VoidCallback onAddGeneralApp;
  final VoidCallback onOpenGeneralApps;

  const _TopBar({
    required this.viewMode,
    required this.onViewMode,
    required this.accent,
    required this.mode,
    required this.onMode,
    required this.selectedWeeks,
    required this.onPickWeeks,
    required this.onAddGeneralApp,
    required this.onOpenGeneralApps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
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
          SegmentedButton<AgroViewMode>(
            segments: const [
              ButtonSegment(
                value: AgroViewMode.mapa,
                label: Text('Mapa'),
                icon: Icon(Icons.map_outlined),
              ),
            ],
            selected: {viewMode},
            onSelectionChanged: (s) => onViewMode(s.first),
          ),
          OutlinedButton.icon(
            onPressed: onPickWeeks,
            icon: const Icon(Icons.date_range_outlined),
            label: Text('Semanas (${selectedWeeks.length})'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(color: accent.withValues(alpha: 0.26)),
              foregroundColor: accent,
            ),
          ),
          FilledButton.icon(
            onPressed: onAddGeneralApp,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Aplicación general'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onOpenGeneralApps,
            icon: const Icon(Icons.history_rounded),
            label: const Text('Ver generales'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(color: accent.withValues(alpha: 0.26)),
              foregroundColor: accent,
            ),
          ),
          SegmentedButton<AgroOverlayMode>(
            segments: const [
              ButtonSegment(
                value: AgroOverlayMode.focoVsAplicado,
                label: Text('FOCO vs Aplicado'),
                icon: Icon(Icons.layers_outlined),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onMode(s.first),
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
        border: Border.all(color: accent.withValues(alpha: 0.16)),
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
              value: selectedId,
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
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendBar extends StatelessWidget {
  final Color accent;
  final AgroOverlayMode mode;

  const _LegendBar({required this.accent, required this.mode});

  @override
  Widget build(BuildContext context) {
    final focoC = const Color(0xFFFB8C00);
    final aplicadoC = const Color(0xFF43A047);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _Dot(color: focoC.withValues(alpha: 0.85)),
          const SizedBox(width: 8),
          const Text('FOCO', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 16),
          _Dot(color: aplicadoC.withValues(alpha: 0.85)),
          const SizedBox(width: 8),
          const Text('Aplicado', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 16),
          _Dot(color: Colors.black.withValues(alpha: 0.18)),
          const SizedBox(width: 8),
          const Text(
            'Sin datos',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Text(
            'Hover / click para detalles',
            style: TextStyle(color: Colors.black.withValues(alpha: 0.6)),
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
          border: Border.all(color: accent.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.10),
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

class _MapViewerAgro extends StatefulWidget {
  final GreenhouseMap map;
  final _AgroAgg agg;
  final AgroOverlayMode mode;

  final TransformationController tx;
  final bool fittedOnce;
  final VoidCallback onFittedOnce;

  final ValueChanged<_CellKey?> onHover;
  final ValueChanged<Offset?> onHoverPos;
  final _CellKey? hoverCell;
  final Offset? hoverPos;

  final String Function(String uid) uidName;
  final ValueChanged<_CellKey> onTapCell;

  final Color accent;

  const _MapViewerAgro({
    required this.map,
    required this.agg,
    required this.mode,
    required this.tx,
    required this.fittedOnce,
    required this.onFittedOnce,
    required this.onHover,
    required this.onHoverPos,
    required this.hoverCell,
    required this.hoverPos,
    required this.uidName,
    required this.onTapCell,
    required this.accent,
  });

  @override
  State<_MapViewerAgro> createState() => _MapViewerAgroState();
}

class _MapViewerAgroState extends State<_MapViewerAgro> {
  bool _dragging = false;
  bool _overCell = false;

  static const double _minScale = 0.08;
  static const double _maxScale = 10.0;

  Offset? _lastTapPos;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
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
                        onTapUp: (d) {
                          final scene = widget.tx.toScene(d.localPosition);
                          final cell = _hitTestCell(
                            canvasLocal: scene,
                            map: widget.map,
                          );
                          if (cell != null) widget.onTapCell(cell);
                        },
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
                              painter: _AgroMapPainter(
                                map: widget.map,
                                agg: widget.agg,
                                mode: widget.mode,
                                hoverCell: widget.hoverCell,
                                accent: accent,
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
                    child: _HoverInfoAgro(
                      accent: accent,
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
              border: Border.all(color: accent.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.12),
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

class _HoverInfoAgro extends StatelessWidget {
  final Color accent;
  final _AgroAgg agg;
  final _CellKey? hover;
  final String Function(String uid) uidName;

  const _HoverInfoAgro({
    required this.accent,
    required this.agg,
    required this.hover,
    required this.uidName,
  });

  @override
  Widget build(BuildContext context) {
    if (hover == null) {
      return _pill(
        'Hover sobre una casilla (click para detalle)',
        Icons.mouse_outlined,
      );
    }

    final key = _AggKey(
      capId: hover!.capillaId,
      lineKey: hover!.lineKey,
      post: hover!.post,
    );
    final cell = agg.cells[key];

    final title =
        '${hover!.ns == NS.north ? "NORTE" : "SUR"} • Línea ${hover!.lineNo} • Poste ${hover!.post}';
    final hasFoco = cell?.focusPests.isNotEmpty == true;
    final hasApps = cell?.appsByPest.isNotEmpty == true;

    final status = hasApps
        ? 'Aplicación registrada'
        : (hasFoco ? 'FOCO (sin aplicación)' : 'Sin FOCO / sin aplicación');

    final focoKeys = (cell?.focusPests ?? const <String>{}).toList()..sort();

    final appEntries = <String, _AgroAppRec>{};
    final appsByPest = cell?.appsByPest ?? const <String, List<_AgroAppRec>>{};
    for (final e in appsByPest.entries) {
      final list = [...e.value]
        ..sort((a, b) => b.appliedAtMs.compareTo(a.appliedAtMs));
      if (list.isNotEmpty) appEntries[e.key] = list.first;
    }
    final appKeys = appEntries.keys.toList()..sort();

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
              status,
              style: TextStyle(
                color: hasApps
                    ? Colors.greenAccent
                    : (hasFoco ? Colors.orangeAccent : Colors.white70),
              ),
            ),
            const SizedBox(height: 8),
            if (hasFoco) ...[
              Text(
                'FOCO:',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              if (focoKeys.isEmpty)
                const Text('—', style: TextStyle(color: Colors.white70))
              else
                ...focoKeys
                    .take(6)
                    .map(
                      (k) => Text(
                        '• ${_pestPretty(k)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
              if (focoKeys.length > 6)
                Text(
                  '+ ${focoKeys.length - 6} más...',
                  style: const TextStyle(color: Colors.white70),
                ),
              const SizedBox(height: 8),
            ],
            if (hasApps) ...[
              Text(
                'Aplicaciones (última por plaga):',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              ...appKeys.take(5).map((pestKey) {
                final a = appEntries[pestKey]!;
                final dt = DateTime.fromMillisecondsSinceEpoch(a.appliedAtMs);
                final when =
                    '${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")} '
                    '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
                final who = a.appliedByName.isNotEmpty
                    ? a.appliedByName
                    : uidName(a.appliedByUid);
                final qty = a.qtyText.isNotEmpty
                    ? a.qtyText
                    : (a.qtyNum > 0 ? '${a.qtyNum}' : '—');
                final prod = a.productTipo.isEmpty
                    ? a.productName
                    : '${a.productName} (${a.productTipo})';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${_pestPretty(pestKey)}\n  $prod • $qty • ${a.tipoAplicacion}\n  $who • $when',
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }),
              if (appKeys.length > 5)
                Text(
                  '+ ${appKeys.length - 5} más...',
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
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
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
}

// ========================= PAINTER =========================

class _AgroMapPainter extends CustomPainter {
  final GreenhouseMap map;
  final _AgroAgg agg;
  final AgroOverlayMode mode;
  final _CellKey? hoverCell;
  final Color accent;

  _AgroMapPainter({
    required this.map,
    required this.agg,
    required this.mode,
    required this.hoverCell,
    required this.accent,
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
          ..color = accent.withValues(alpha: 0.95);
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
    final rows = (ns == NS.north) ? map.postsNorth : map.postsSouth;

    final focoC = const Color(0xFFFB8C00);
    final aplicadoC = const Color(0xFF43A047);
    final emptyC = Colors.black.withValues(alpha: 0.05);

    for (int post = 1; post <= rows; post++) {
      if (!map.isActive(ns, post, lineNo)) continue;

      final key = _AggKey(capId: ci.capilla.id, lineKey: lineKey, post: post);
      final cell = agg.cells[key];

      final hasFoco = cell?.focusPests.isNotEmpty == true;
      final hasApps = cell?.appsByPest.isNotEmpty == true;

      Color fill;
      if (hasApps) {
        fill = aplicadoC.withValues(alpha: 0.72);
      } else if (hasFoco) {
        fill = focoC.withValues(alpha: 0.72);
      } else {
        fill = emptyC;
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

      if (hasApps && hasFoco) {
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = focoC.withValues(alpha: 0.85);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          p,
        );
      }
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

  @override
  bool shouldRepaint(covariant _AgroMapPainter old) {
    return old.map != map ||
        old.agg != agg ||
        old.mode != mode ||
        old.hoverCell != hoverCell ||
        old.accent != accent;
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

// ========================= AGG DATA MODELS =========================

class _AgroAgg {
  final Map<_AggKey, _AgroCell> cells = {};
  final Set<String> uids = {};

  void addWeekLineData({
    required String weekKey,
    required String capId,
    required String lineKey,
    required Map<String, dynamic> linePayload,
  }) {
    final focus = _readFocusFromLinePayload(linePayload);
    final apps = _readAgroFocoApps(linePayload);

    final posts = <int>{};
    posts.addAll(focus['L']!.keys);
    posts.addAll(focus['R']!.keys);
    posts.addAll(apps['L']!.keys);
    posts.addAll(apps['R']!.keys);

    for (final post in posts) {
      final k = _AggKey(capId: capId, lineKey: lineKey, post: post);
      final prev = cells[k] ?? _AgroCell.empty();

      final focusPests = <String>{...prev.focusPests};
      focusPests.addAll(focus['L']?[post] ?? const <String>{});
      focusPests.addAll(focus['R']?[post] ?? const <String>{});

      final mergedApps = <String, List<_AgroAppRec>>{};
      mergedApps.addAll(prev.appsByPest.map((k, v) => MapEntry(k, [...v])));

      void mergeSide(String side) {
        final postMap = apps[side]?[post];
        if (postMap == null) return;

        for (final e in postMap.entries) {
          final pestKey = e.key;
          final list = e.value;
          if (list.isEmpty) continue;

          mergedApps.putIfAbsent(pestKey, () => <_AgroAppRec>[]);
          mergedApps[pestKey]!.addAll(list);

          for (final a in list) {
            if (a.appliedByUid.isNotEmpty) uids.add(a.appliedByUid);
          }
        }
      }

      mergeSide('L');
      mergeSide('R');

      cells[k] = _AgroCell(focusPests: focusPests, appsByPest: mergedApps);
    }
  }
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
  bool operator ==(Object other) =>
      other is _AggKey &&
      other.capId == capId &&
      other.lineKey == lineKey &&
      other.post == post;

  @override
  int get hashCode => Object.hash(capId, lineKey, post);
}

class _AgroCell {
  final Set<String> focusPests;
  final Map<String, List<_AgroAppRec>> appsByPest;

  const _AgroCell({required this.focusPests, required this.appsByPest});

  factory _AgroCell.empty() => const _AgroCell(
    focusPests: <String>{},
    appsByPest: <String, List<_AgroAppRec>>{},
  );
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

// ========================= PARSERS (FOCO + APPS) =========================

Map<String, Map<int, Set<String>>> _readFocusFromLinePayload(
  Map<String, dynamic> line,
) {
  final out = <String, Map<int, Set<String>>>{
    'L': <int, Set<String>>{},
    'R': <int, Set<String>>{},
  };

  final obsAny = line['observations'];
  if (obsAny is! Map) return out;
  final obs = Map<String, dynamic>.from(obsAny);

  final focusAny = obs['focus'];
  if (focusAny is! Map) return out;
  final focus = Map<String, dynamic>.from(focusAny);

  Map<int, Set<String>> parseSide(Object? sideAny) {
    final sideOut = <int, Set<String>>{};
    if (sideAny is! Map) return sideOut;
    final sideMap = Map<String, dynamic>.from(sideAny as Map);

    sideMap.forEach((postStr, pestsAny) {
      final post = int.tryParse(postStr.toString()) ?? 0;
      if (post <= 0) return;
      if (pestsAny is! Map) return;
      final pests = Map<String, dynamic>.from(pestsAny as Map);

      final keys = <String>{};
      pests.forEach((pestKey, v) {
        final isTrue = (v is bool && v) || (v?.toString() == 'true');
        if (isTrue) keys.add(pestKey.toString());
      });

      if (keys.isNotEmpty) sideOut[post] = keys;
    });

    return sideOut;
  }

  out['L']!.addAll(parseSide(focus['left']));
  out['R']!.addAll(parseSide(focus['right']));
  return out;
}

Map<String, Map<int, Map<String, List<_AgroAppRec>>>> _readAgroFocoApps(
  Map<String, dynamic> line,
) {
  final out = <String, Map<int, Map<String, List<_AgroAppRec>>>>{
    'L': <int, Map<String, List<_AgroAppRec>>>{},
    'R': <int, Map<String, List<_AgroAppRec>>>{},
  };

  final agroAny = line['agroFoco'];
  if (agroAny is! Map) return out;
  final agro = Map<String, dynamic>.from(agroAny);

  final focusAny = agro['focus'];
  if (focusAny is! Map) return out;
  final focus = Map<String, dynamic>.from(focusAny);

  void readSide(String sideKey) {
    final sideAny = focus[sideKey];
    if (sideAny is! Map) return;

    final postsMap = Map<String, dynamic>.from(sideAny as Map);
    for (final e in postsMap.entries) {
      final post = int.tryParse(e.key.toString()) ?? 0;
      if (post <= 0) continue;

      final pestsAny = e.value;
      if (pestsAny is! Map) continue;

      final pestsMap = Map<String, dynamic>.from(pestsAny as Map);
      final outPests = <String, List<_AgroAppRec>>{};

      for (final p in pestsMap.entries) {
        final pestKey = p.key.toString();
        final listAny = p.value;

        if (listAny is List) {
          final list = <_AgroAppRec>[];
          for (final item in listAny) {
            if (item is! Map) continue;
            list.add(_AgroAppRec.fromJson(Map<String, dynamic>.from(item)));
          }
          if (list.isNotEmpty) outPests[pestKey] = list;
        } else if (listAny is Map) {
          final m = Map<String, dynamic>.from(listAny as Map);
          final list = <_AgroAppRec>[];
          for (final v in m.values) {
            if (v is! Map) continue;
            list.add(_AgroAppRec.fromJson(Map<String, dynamic>.from(v)));
          }
          if (list.isNotEmpty) outPests[pestKey] = list;
        }
      }

      if (outPests.isNotEmpty) {
        out[sideKey]![post] = outPests;
      }
    }
  }

  readSide('L');
  readSide('R');
  return out;
}

String _pestPretty(String pestKey) {
  final raw = pestKey.trim();
  final idx = raw.lastIndexOf('|');
  if (idx <= 0) return raw;
  final name = raw.substring(0, idx).trim();
  final level = raw.substring(idx + 1).trim();
  if (name.isEmpty || level.isEmpty) return raw;
  return '$name - $level';
}

// ========================= APP RECORD =========================

class _AgroAppRec {
  final String id;
  final String productId;
  final String productName;
  final String productTipo;

  final String qtyText;
  final double qtyNum;

  final String tipoAplicacion;
  final int appliedAtMs;
  final String appliedByUid;
  final String appliedByName;

  const _AgroAppRec({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productTipo,
    required this.qtyText,
    required this.qtyNum,
    required this.tipoAplicacion,
    required this.appliedAtMs,
    required this.appliedByUid,
    required this.appliedByName,
  });

  static _AgroAppRec fromJson(Map<String, dynamic> m) {
    final qtyText = (m['qtyText'] ?? '').toString().trim();
    final qtyNum = (m['qty'] is num)
        ? (m['qty'] as num).toDouble()
        : double.tryParse('${m['qty']}') ?? 0.0;

    return _AgroAppRec(
      id: (m['id'] ?? '').toString(),
      productId: (m['productId'] ?? '').toString(),
      productName: (m['productName'] ?? '').toString(),
      productTipo: (m['productTipo'] ?? '').toString(),
      qtyText: qtyText,
      qtyNum: qtyNum,
      tipoAplicacion: (m['tipoAplicacion'] ?? '').toString(),
      appliedAtMs: (m['appliedAtMs'] is int)
          ? (m['appliedAtMs'] as int)
          : int.tryParse('${m['appliedAtMs']}') ?? 0,
      appliedByUid: (m['appliedByUid'] ?? '').toString(),
      appliedByName: (m['appliedByName'] ?? '').toString(),
    );
  }
}

// ========================= DETAILS SHEET (CLICK) =========================

class _CellDetailsSheet extends StatefulWidget {
  final Color accent;
  final GreenhouseMap map;
  final _CellKey cell;
  final Set<String> selectedWeekKeys;
  final FirebaseFirestore fs;
  final String Function(String uid) uidName;

  const _CellDetailsSheet({
    required this.accent,
    required this.map,
    required this.cell,
    required this.selectedWeekKeys,
    required this.fs,
    required this.uidName,
  });

  @override
  State<_CellDetailsSheet> createState() => _CellDetailsSheetState();
}

class _CellDetailsSheetState extends State<_CellDetailsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  bool _loadingHistory = false;
  int _weeksToScan = 16;
  final List<_HistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final title =
        '${widget.cell.ns == NS.north ? "NORTE" : "SUR"} • Línea ${widget.cell.lineNo} • Poste ${widget.cell.post}';

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 22,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(Icons.science_outlined, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: 0.14)),
                  ),
                  child: TabBar(
                    controller: _tab,
                    labelColor: accent,
                    unselectedLabelColor: Colors.black.withValues(alpha: 0.65),
                    indicatorColor: accent,
                    tabs: const [
                      Tab(text: 'Semanas seleccionadas'),
                      Tab(text: 'Historial'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _SelectedWeeksView(
                      accent: accent,
                      fs: widget.fs,
                      mapId: widget.map.id,
                      capId: widget.cell.capillaId,
                      lineKey: widget.cell.lineKey,
                      post: widget.cell.post,
                      weekKeys: widget.selectedWeekKeys,
                      uidName: widget.uidName,
                      scrollCtrl: scrollCtrl,
                    ),
                    _HistoryView(
                      accent: accent,
                      loading: _loadingHistory,
                      history: _history,
                      onLoadMore: () async {
                        setState(() => _weeksToScan += 12);
                        await _loadHistory();
                      },
                      uidName: widget.uidName,
                      scrollCtrl: scrollCtrl,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadHistory() async {
    if (_loadingHistory) return;
    setState(() => _loadingHistory = true);

    try {
      final now = DateTime.now();
      final keys = <String>[];
      for (int i = 0; i < _weeksToScan; i++) {
        keys.add(_isoWeekKey(now.subtract(Duration(days: 7 * i))));
      }

      final out = <_HistoryItem>[];

      for (final wk in keys) {
        final capRef = widget.fs
            .collection('monitoreo_weeks')
            .doc(wk)
            .collection('greenhouses')
            .doc(widget.map.id)
            .collection('capillas')
            .doc(widget.cell.capillaId);

        final capSnap = await capRef.get();
        final capDoc = capSnap.data();
        if (capDoc == null) continue;

        final line = _readLinePayload(capDoc, widget.cell.lineKey);
        if (line == null) continue;

        final apps = _readAgroFocoApps(line);

        for (final side in const ['L', 'R']) {
          final postMap =
              apps[side]?[widget.cell.post] ??
              const <String, List<_AgroAppRec>>{};
          for (final e in postMap.entries) {
            final pestKey = e.key;
            for (final a in e.value) {
              if (a.appliedAtMs <= 0) continue;
              out.add(
                _HistoryItem(weekKey: wk, side: side, pestKey: pestKey, app: a),
              );
            }
          }
        }
      }

      out.sort((a, b) => b.app.appliedAtMs.compareTo(a.app.appliedAtMs));

      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(out);
      });
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Map<String, dynamic>? _readLinePayload(
    Map<String, dynamic> capDoc,
    String lineKey,
  ) {
    final linesAny = capDoc['lines'];
    if (linesAny is! Map) return null;
    final lines = Map<String, dynamic>.from(linesAny);
    final lineAny = lines[lineKey];
    if (lineAny is! Map) return null;
    return Map<String, dynamic>.from(lineAny);
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

class _SelectedWeeksView extends StatelessWidget {
  final Color accent;
  final FirebaseFirestore fs;
  final String mapId;
  final String capId;
  final String lineKey;
  final int post;
  final Set<String> weekKeys;
  final String Function(String uid) uidName;
  final ScrollController scrollCtrl;

  const _SelectedWeeksView({
    required this.accent,
    required this.fs,
    required this.mapId,
    required this.capId,
    required this.lineKey,
    required this.post,
    required this.weekKeys,
    required this.uidName,
    required this.scrollCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final keys = weekKeys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final wk = keys[i];
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: fs
              .collection('monitoreo_weeks')
              .doc(wk)
              .collection('greenhouses')
              .doc(mapId)
              .collection('capillas')
              .doc(capId)
              .get(),
          builder: (context, snap) {
            final capDoc = snap.data?.data();
            if (capDoc == null) return _weekCard(wk, 'Sin datos', const []);

            final line = _readLinePayload(capDoc, lineKey);
            if (line == null) return _weekCard(wk, 'Sin línea', const []);

            final foco = _readFocusFromLinePayload(line);
            final focoL = foco['L']?[post] ?? <String>{};
            final focoR = foco['R']?[post] ?? <String>{};

            final apps = _readAgroFocoApps(line);
            final appsL =
                apps['L']?[post] ?? const <String, List<_AgroAppRec>>{};
            final appsR =
                apps['R']?[post] ?? const <String, List<_AgroAppRec>>{};

            final children = <Widget>[
              _sideBlock('Izquierda (L)', focoL, appsL, uidName),
              const SizedBox(height: 10),
              _sideBlock('Derecha (R)', focoR, appsR, uidName),
            ];

            final hasFoco = focoL.isNotEmpty || focoR.isNotEmpty;
            return _weekCard(
              wk,
              hasFoco ? 'FOCO detectado' : 'Sin FOCO',
              children,
            );
          },
        );
      },
    );
  }

  Map<String, dynamic>? _readLinePayload(
    Map<String, dynamic> capDoc,
    String lineKey,
  ) {
    final linesAny = capDoc['lines'];
    if (linesAny is! Map) return null;
    final lines = Map<String, dynamic>.from(linesAny);
    final lineAny = lines[lineKey];
    if (lineAny is! Map) return null;
    return Map<String, dynamic>.from(lineAny);
  }

  Widget _weekCard(String wk, String subtitle, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            wk,
            style: TextStyle(fontWeight: FontWeight.w900, color: accent),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _sideBlock(
    String label,
    Set<String> focoPests,
    Map<String, List<_AgroAppRec>> appsByPest,
    String Function(String uid) uidName,
  ) {
    final keys = focoPests.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        if (keys.isEmpty)
          Text(
            'Sin plagas FOCO.',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.65),
              fontWeight: FontWeight.w700,
            ),
          )
        else
          ...keys.map((pestKey) {
            final list = appsByPest[pestKey] ?? const <_AgroAppRec>[];
            final sorted = [...list]
              ..sort((a, b) => b.appliedAtMs.compareTo(a.appliedAtMs));

            final pestPretty = _pestPretty(pestKey);

            if (sorted.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '• $pestPretty — (sin aplicación)',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.70),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            final last = sorted.first;
            final who = last.appliedByName.isNotEmpty
                ? last.appliedByName
                : uidName(last.appliedByUid);
            final dt = DateTime.fromMillisecondsSinceEpoch(last.appliedAtMs);
            final when =
                '${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")} ${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
            final qty = last.qtyText.isNotEmpty
                ? last.qtyText
                : (last.qtyNum > 0 ? '${last.qtyNum}' : '—');
            final prod = last.productTipo.isEmpty
                ? last.productName
                : '${last.productName} (${last.productTipo})';

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '• $pestPretty\n   $prod\n   Cant: $qty • ${last.tipoAplicacion}\n   Por: $who • $when',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _HistoryView extends StatelessWidget {
  final Color accent;
  final bool loading;
  final List<_HistoryItem> history;
  final VoidCallback onLoadMore;
  final String Function(String uid) uidName;
  final ScrollController scrollCtrl;

  const _HistoryView({
    required this.accent,
    required this.loading,
    required this.history,
    required this.onLoadMore,
    required this.uidName,
    required this.scrollCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Historial (más reciente primero)',
                style: TextStyle(fontWeight: FontWeight.w900, color: accent),
              ),
            ),
            TextButton.icon(
              onPressed: loading ? null : onLoadMore,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Cargar más'),
              style: TextButton.styleFrom(foregroundColor: accent),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (loading && history.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(),
            ),
          )
        else if (history.isEmpty)
          Text(
            'Sin aplicaciones encontradas en el rango cargado.',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.65),
              fontWeight: FontWeight.w700,
            ),
          )
        else
          ...history.map((h) => _historyTile(h)),
      ],
    );
  }

  Widget _historyTile(_HistoryItem h) {
    final dt = DateTime.fromMillisecondsSinceEpoch(h.app.appliedAtMs);
    final when =
        '${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")} ${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';

    final prod = h.app.productTipo.isEmpty
        ? h.app.productName
        : '${h.app.productName} (${h.app.productTipo})';
    final qty = h.app.qtyText.isNotEmpty
        ? h.app.qtyText
        : (h.app.qtyNum > 0 ? '${h.app.qtyNum}' : '—');
    final who = h.app.appliedByName.isNotEmpty
        ? h.app.appliedByName
        : uidName(h.app.appliedByUid);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${h.weekKey} • ${h.side == "L" ? "Izq (L)" : "Der (R)"}',
            style: TextStyle(fontWeight: FontWeight.w900, color: accent),
          ),
          const SizedBox(height: 6),
          Text(
            _pestPretty(h.pestKey),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            prod,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Cant: $qty • ${h.app.tipoAplicacion}',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.68),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Fecha: $when • Por: $who',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.62),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem {
  final String weekKey;
  final String side; // L/R
  final String pestKey;
  final _AgroAppRec app;
  const _HistoryItem({
    required this.weekKey,
    required this.side,
    required this.pestKey,
    required this.app,
  });
}

// ========================= GENERAL APPLICATIONS (ADMIN) =========================

class _GeneralAgroApp {
  final String id;
  final String greenhouseId;
  final String greenhouseName;
  final String weekKey;
  final int appliedAtMs;

  final String encargadoName;
  final String producto;
  final String tipoAplicacion;

  final String createdByUid;
  final int createdAtMs;

  const _GeneralAgroApp({
    required this.id,
    required this.greenhouseId,
    required this.greenhouseName,
    required this.weekKey,
    required this.appliedAtMs,
    required this.encargadoName,
    required this.producto,
    required this.tipoAplicacion,
    required this.createdByUid,
    required this.createdAtMs,
  });

  static _GeneralAgroApp fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? <String, dynamic>{};

    int tsToMs(dynamic v) {
      if (v is Timestamp) return v.millisecondsSinceEpoch;
      if (v is int) return v;
      return int.tryParse('$v') ?? 0;
    }

    return _GeneralAgroApp(
      id: d.id,
      greenhouseId: (m['greenhouseId'] ?? '').toString(),
      greenhouseName: (m['greenhouseName'] ?? '').toString(),
      weekKey: (m['weekKey'] ?? '').toString(),
      appliedAtMs: (m['appliedAtMs'] is int)
          ? (m['appliedAtMs'] as int)
          : int.tryParse('${m['appliedAtMs']}') ?? 0,
      encargadoName: (m['encargadoName'] ?? '').toString(),
      producto: (m['producto'] ?? '').toString(),
      tipoAplicacion: (m['tipoAplicacion'] ?? '').toString(),
      createdByUid: (m['createdByUid'] ?? '').toString(),
      createdAtMs: tsToMs(m['createdAt']),
    );
  }
}

class _GeneralAppsSheet extends StatefulWidget {
  final Color accent;
  final FirebaseFirestore fs;
  final GreenhouseMap map;
  final Set<String> selectedWeekKeys;

  const _GeneralAppsSheet({
    required this.accent,
    required this.fs,
    required this.map,
    required this.selectedWeekKeys,
  });

  @override
  State<_GeneralAppsSheet> createState() => _GeneralAppsSheetState();
}

class _GeneralAppsSheetState extends State<_GeneralAppsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 22,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(Icons.history_rounded, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Aplicaciones generales • ${widget.map.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: 0.14)),
                  ),
                  child: TabBar(
                    controller: _tab,
                    labelColor: accent,
                    unselectedLabelColor: Colors.black.withValues(alpha: 0.65),
                    indicatorColor: accent,
                    tabs: [
                      Tab(text: 'Semanas (${widget.selectedWeekKeys.length})'),
                      const Tab(text: 'Historial'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _GeneralAppsSelectedWeeksList(
                      accent: accent,
                      fs: widget.fs,
                      mapId: widget.map.id,
                      weekKeys: widget.selectedWeekKeys,
                      scrollCtrl: scrollCtrl,
                    ),
                    _GeneralAppsHistoryList(
                      accent: accent,
                      fs: widget.fs,
                      mapId: widget.map.id,
                      scrollCtrl: scrollCtrl,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GeneralAppsSelectedWeeksList extends StatelessWidget {
  final Color accent;
  final FirebaseFirestore fs;
  final String mapId;
  final Set<String> weekKeys;
  final ScrollController scrollCtrl;

  const _GeneralAppsSelectedWeeksList({
    required this.accent,
    required this.fs,
    required this.mapId,
    required this.weekKeys,
    required this.scrollCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final keys = weekKeys.toList()..sort((a, b) => b.compareTo(a));
    if (keys.isEmpty) {
      return ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            'No hay semanas seleccionadas.',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return FutureBuilder<List<_GeneralAgroApp>>(
      future: _fetchByWeeks(fs: fs, mapId: mapId, weekKeys: keys),
      builder: (context, snap) {
        if (snap.hasError) {
          return ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                'Error: ${snap.error}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          );
        }
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());

        final items = snap.data!;
        if (items.isEmpty) {
          return ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                'Sin aplicaciones generales en semanas seleccionadas.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }

        return ListView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          itemCount: items.length,
          itemBuilder: (_, i) => _generalAppTile(accent, items[i]),
        );
      },
    );
  }

  /// ✅ FIX sin índice:
  /// Query solo por weekKey(whereIn) y filtrar greenhouseId en memoria.
  static Future<List<_GeneralAgroApp>> _fetchByWeeks({
    required FirebaseFirestore fs,
    required String mapId,
    required List<String> weekKeys,
  }) async {
    const col = 'agro_general_apps';
    const chunkSize = 10;

    final out = <_GeneralAgroApp>[];

    for (int i = 0; i < weekKeys.length; i += chunkSize) {
      final chunk = weekKeys.sublist(
        i,
        math.min(i + chunkSize, weekKeys.length),
      );
      final qs = await fs
          .collection(col)
          .where('weekKey', whereIn: chunk)
          .get();

      for (final d in qs.docs) {
        final app = _GeneralAgroApp.fromDoc(d);
        if (app.greenhouseId == mapId) out.add(app);
      }
    }

    out.sort((a, b) => b.appliedAtMs.compareTo(a.appliedAtMs));
    return out;
  }

  static Widget _generalAppTile(Color accent, _GeneralAgroApp a) {
    final dt = DateTime.fromMillisecondsSinceEpoch(a.appliedAtMs);
    final date =
        '${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${a.weekKey} • $date',
            style: TextStyle(fontWeight: FontWeight.w900, color: accent),
          ),
          const SizedBox(height: 6),
          Text(a.producto, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            'Tipo: ${a.tipoAplicacion}',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.70),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Encargado: ${a.encargadoName}',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.62),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralAppsHistoryList extends StatelessWidget {
  final Color accent;
  final FirebaseFirestore fs;
  final String mapId;
  final ScrollController scrollCtrl;

  const _GeneralAppsHistoryList({
    required this.accent,
    required this.fs,
    required this.mapId,
    required this.scrollCtrl,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ FIX sin índice: NO orderBy (se ordena client-side)
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: fs
          .collection('agro_general_apps')
          .where('greenhouseId', isEqualTo: mapId)
          .limit(250)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                'Error: ${snap.error}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          );
        }
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs;
        final items = docs.map((d) => _GeneralAgroApp.fromDoc(d)).toList()
          ..sort(
            (a, b) => b.appliedAtMs.compareTo(a.appliedAtMs),
          ); // ✅ orden client-side

        if (items.isEmpty) {
          return ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                'Sin historial de aplicaciones generales.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }

        return ListView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          itemCount: items.length,
          itemBuilder: (_, i) =>
              _GeneralAppsSelectedWeeksList._generalAppTile(accent, items[i]),
        );
      },
    );
  }
}

// ========================= PRODUCT OPTION MODEL =========================

class _AgroProdOpt {
  final String id;
  final String nombre;
  final String tipo;
  const _AgroProdOpt({
    required this.id,
    required this.nombre,
    required this.tipo,
  });
}
