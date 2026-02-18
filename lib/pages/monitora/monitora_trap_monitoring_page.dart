import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/mapa_model.dart';
import '../../../theme/app_theme.dart';
import '../../../services/offline/offline_sync_service.dart';

/// Monitoreo de TRAMPAS (una por una) dentro de una línea (north_X / south_X)
///
/// - NO hay izquierda/derecha.
/// - Se recorre lista de trampas encontradas en esa línea.
/// - Cada trampa guarda conteo de plagas.
/// - Al final: se marca como FINISHED la "línea de trampas" (trapLine) en esa capilla.
///
/// Requiere que desde la pantalla anterior ya filtres las trampas y
/// le pases la lista `traps` (solo las que están en esa capilla y línea).
class MonitoraTrapMonitoringPage extends StatefulWidget {
  final GreenhouseMap map;
  final CapillaDef capilla;

  final NS lineSide;
  final int lineNo;

  /// Lista de trampas en esa línea (normalmente 3..8)
  final List<TrapDef> traps;

  const MonitoraTrapMonitoringPage({
    super.key,
    required this.map,
    required this.capilla,
    required this.lineSide,
    required this.lineNo,
    required this.traps,
  });

  @override
  State<MonitoraTrapMonitoringPage> createState() => _MonitoraTrapMonitoringPageState();
}

class _MonitoraTrapMonitoringPageState extends State<MonitoraTrapMonitoringPage> {
  // ✅ YA NO predefinidas. Se cargan desde Firestore.
  final _fs = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pestsSub;
  final List<String> _pestsFromDb = [];

  static const String _otherOption = 'Otra…';

  int _idx = 0;
  late DateTime _startedAt;

  /// trapId -> (pest -> qty)
  final Map<String, Map<String, int>> _countsByTrap = {};

  Timer? _draftDebounce;
  int _lastDraftFingerprint = 0;

  late final String _capName;
  late final String _lineKey; // north_7 / south_7
  late final String _sideLabel;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();

    _capName = (widget.capilla.name == null || widget.capilla.name!.trim().isEmpty)
        ? '(sin nombre)'
        : widget.capilla.name!.trim();

    _sideLabel = (widget.lineSide == NS.north) ? 'NORTE' : 'SUR';
    _lineKey = '${nsToStr(widget.lineSide).toLowerCase()}_${widget.lineNo}';

    _listenPests();
    Future.microtask(_restoreDraftIfAny);
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _pestsSub?.cancel();
    super.dispose();
  }

  // -------------------- PESTS (Firestore) --------------------

  List<String> get _pestOptions {
    // Siempre dejamos "Otra…" al final
    final base = List<String>.from(_pestsFromDb);
    base.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (!base.contains(_otherOption)) base.add(_otherOption);
    return base;
  }

  void _listenPests() {
    // plagas: { nombre, niveles, tipo }
    _pestsSub = _fs.collection('plagas').orderBy('nombre').snapshots().listen((snap) {
      final names = <String>[];
      for (final d in snap.docs) {
        final m = d.data();
        final nombre = (m['nombre'] ?? '').toString().trim();
        if (nombre.isNotEmpty) names.add(nombre);
      }

      if (!mounted) return;
      setState(() {
        _pestsFromDb
          ..clear()
          ..addAll(names);
      });
    }, onError: (_) {});
  }

  Future<String?> _createPestIfNeeded(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return null;

    // Si ya existe (case-insensitive), no duplicar
    final exists = _pestsFromDb.any((p) => p.toLowerCase() == name.toLowerCase());
    if (exists) {
      // regresa el nombre tal cual como lo escribió (o puedes normalizar)
      return _pestsFromDb.firstWhere((p) => p.toLowerCase() == name.toLowerCase(), orElse: () => name);
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;

    await _fs.collection('plagas').add({
      'nombre': name,
      'tipo': 'PLAGA',
      'niveles': <String>[],
      'createdByUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // actualiza local inmediato para que aparezca ya
    if (!_pestsFromDb.any((p) => p.toLowerCase() == name.toLowerCase())) {
      setState(() => _pestsFromDb.add(name));
    }

    return name;
  }

  // ---------------- Draft helpers ----------------

  String get _weekKey => _isoWeekKey(_startedAt);

  /// draft “normal” de captura de trampas
  String get _draftLineKey => 'trap_$_lineKey';

  /// ✅ marcador local para “línea finalizada” (sirve para pintar en la pantalla anterior)
  String get _doneMarkerLineKey => 'trap_done_$_lineKey';

  Future<void> _restoreDraftIfAny() async {
    final draft = OfflineSyncService.instance.loadDraft(
      weekKey: _weekKey,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _draftLineKey,
    );

    if (draft == null) return;

    try {
      final startedAtMs = (draft['startedAtMs'] ?? 0) as int;
      final idx = (draft['idx'] ?? 0) as int;

      final countsAny = draft['counts'];
      if (countsAny is! Map) return;
      final counts = Map<String, dynamic>.from(countsAny);

      _countsByTrap.clear();
      counts.forEach((trapId, pestsAny) {
        if (pestsAny is! Map) return;
        final m = <String, int>{};
        Map<String, dynamic>.from(pestsAny).forEach((pest, v) {
          final n = (v is int) ? v : int.tryParse(v.toString()) ?? 0;
          if (n > 0) m[pest.toString()] = n;
        });
        if (m.isNotEmpty) _countsByTrap[trapId.toString()] = m;
      });

      final restoredStartedAt = DateTime.fromMillisecondsSinceEpoch(
        startedAtMs > 0 ? startedAtMs : _startedAt.millisecondsSinceEpoch,
      );

      if (!mounted) return;
      setState(() {
        _startedAt = restoredStartedAt;
        _idx = idx.clamp(0, (widget.traps.isEmpty ? 0 : widget.traps.length - 1));
      });

      _lastDraftFingerprint = _computeDraftFingerprint(
        startedAtMs: _startedAt.millisecondsSinceEpoch,
        idx: _idx,
        countsByTrap: _countsByTrap,
      );
    } catch (_) {}
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();

    _draftDebounce = Timer(const Duration(milliseconds: 450), () {
      final fp = _computeDraftFingerprint(
        startedAtMs: _startedAt.millisecondsSinceEpoch,
        idx: _idx,
        countsByTrap: _countsByTrap,
      );

      if (fp == _lastDraftFingerprint) return;
      _lastDraftFingerprint = fp;

      final countsJson = _countsToJson();

      unawaited(Future<void>(() async {
        await OfflineSyncService.instance.saveDraft(
          weekKey: _weekKey,
          greenhouseId: widget.map.id,
          capillaId: widget.capilla.id,
          lineKey: _draftLineKey,
          startedAtMs: _startedAt.millisecondsSinceEpoch,
          rightPass: false,
          idx: _idx,
          countsJson: countsJson,
        );
      }));
    });
  }

  int _computeDraftFingerprint({
    required int startedAtMs,
    required int idx,
    required Map<String, Map<String, int>> countsByTrap,
  }) {
    var h = 17;
    h = 37 * h + startedAtMs.hashCode;
    h = 37 * h + idx;

    final trapIds = countsByTrap.keys.toList()..sort();
    for (final trapId in trapIds) {
      h = 37 * h + trapId.hashCode;
      final pests = countsByTrap[trapId] ?? {};
      final pestKeys = pests.keys.toList()..sort();
      for (final pest in pestKeys) {
        h = 37 * h + pest.hashCode;
        h = 37 * h + (pests[pest] ?? 0);
      }
    }

    return h;
  }

  Map<String, dynamic> _countsToJson() {
    final out = <String, dynamic>{};
    _countsByTrap.forEach((trapId, pests) {
      final filtered = <String, int>{};
      pests.forEach((k, v) {
        if (v > 0) filtered[k] = v;
      });
      if (filtered.isNotEmpty) out[trapId] = filtered;
    });
    return out;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    final traps = widget.traps;
    if (traps.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          title: const Text('Monitoreo de trampa'),
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
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
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.18)),
                    ),
                    child: Icon(Icons.warning_amber_rounded, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No hay trampas registradas en esta línea.\n(Revisa en el editor de mapas.)',
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.70),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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

    final currentTrap = traps[_idx];
    final trapCounts = _countsByTrap[currentTrap.id] ?? {};
    final hasPests = trapCounts.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('Monitoreo de trampa'),
        elevation: 0,
      ),
      body: RepaintBoundary(
        child: Stack(
          children: [
            Positioned.fill(child: bg),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, c) {
                  final isWide = c.maxWidth >= 900;

                  final header = _HeaderCardTrap(
                    accent: accent,
                    mapName: widget.map.name,
                    capName: _capName,
                    lineNo: widget.lineNo,
                    sideLabel: _sideLabel,
                    trapLabel: currentTrap.name.trim().isEmpty ? '(sin nombre)' : currentTrap.name.trim(),
                    indexLabel: '${_idx + 1}/${traps.length}',
                  );

                  final progress = _ProgressStrip(
                    accent: accent,
                    currentIndex: _idx,
                    total: traps.length,
                    modeLabel: 'Trampas',
                  );

                  final trapBadge = _TrapBadge(
                    accent: accent,
                    label: currentTrap.name.trim().isEmpty ? 'Trampa' : currentTrap.name.trim(),
                  );

                  final addButton = SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => _addOrEditPestDialog(trap: currentTrap),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        'Agregar plaga encontrada',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
                      ),
                    ),
                  );

                  final pestsBody = !hasPests
                      ? _EmptyState(
                          accent: accent,
                          title: 'Sin registros',
                          message: 'Aún no registras plagas en esta trampa.\nUsa “Agregar plaga encontrada”.',
                          icon: Icons.bug_report_outlined,
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: trapCounts.length,
                          itemBuilder: (context, i) {
                            final pest = trapCounts.keys.elementAt(i);
                            final qty = trapCounts[pest] ?? 0;
                            if (qty <= 0) return const SizedBox.shrink();
                            return _pestRow(trap: currentTrap, pest: pest, qty: qty);
                          },
                        );

                  final listCard = Expanded(
                    child: RepaintBoundary(
                      child: Container(
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
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: pestsBody,
                        ),
                      ),
                    ),
                  );

                  final navigation = _NavigationBar(
                    accent: accent,
                    canGoBack: _idx > 0,
                    isLast: _isLast(),
                    onBack: _goBack,
                    onNext: _goNext,
                  );

                  final finishButton = _isLast()
                      ? SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.pepperRed,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            onPressed: _finishAndSaveOfflineFirst,
                            icon: const Icon(Icons.check_circle_outline_rounded),
                            label: const Text(
                              'Finalizar monitoreo de trampa en esta línea',
                              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
                            ),
                          ),
                        )
                      : const SizedBox.shrink();

                  final leftColumn = RepaintBoundary(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header,
                        const SizedBox(height: 12),
                        progress,
                        const SizedBox(height: 14),
                        Center(child: trapBadge),
                        const SizedBox(height: 14),
                        addButton,
                        const SizedBox(height: 12),
                        navigation,
                        const SizedBox(height: 10),
                        finishButton,
                      ],
                    ),
                  );

                  final rightColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(accent: accent, title: "Plagas registradas"),
                      const SizedBox(height: 10),
                      listCard,
                    ],
                  );

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 440, child: leftColumn),
                              const SizedBox(width: 16),
                              Expanded(child: rightColumn),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              leftColumn,
                              const SizedBox(height: 14),
                              Expanded(child: rightColumn),
                            ],
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Data helpers ----------------

  bool _isLast() => _idx >= widget.traps.length - 1;

  void _setPestForTrap({required String trapId, required String pest, required int qty}) {
    if (qty <= 0) {
      final current = _countsByTrap[trapId];
      current?.remove(pest);
      if (current != null && current.isEmpty) {
        _countsByTrap.remove(trapId);
      }
      return;
    }

    _countsByTrap.putIfAbsent(trapId, () => <String, int>{});
    _countsByTrap[trapId]![pest] = qty;
  }

  // ---------------- UI rows ----------------

  Widget _pestRow({required TrapDef trap, required String pest, required int qty}) {
    final accent = AppTheme.pepperGreen;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Icon(Icons.bug_report_outlined, color: accent),
        ),
        title: Text(pest, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Cantidad: $qty',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Editar',
              icon: Icon(Icons.edit_rounded, color: accent),
              onPressed: () => _addOrEditPestDialog(
                trap: trap,
                presetPest: pest,
                presetQty: qty,
              ),
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: Icon(Icons.delete_outline_rounded, color: Colors.red.withValues(alpha: 0.90)),
              onPressed: () {
                setState(() => _setPestForTrap(trapId: trap.id, pest: pest, qty: 0));
                _scheduleDraftSave();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addOrEditPestDialog({
    required TrapDef trap,
    String? presetPest,
    int? presetQty,
  }) async {
    final accent = AppTheme.pepperGreen;

    final opts = _pestOptions;
    String selected = presetPest ?? (opts.isNotEmpty ? opts.first : _otherOption);

    final qtyCtrl = TextEditingController(text: (presetQty ?? 1).toString());
    final otherCtrl = TextEditingController();

    InputDecoration deco({
      required String label,
      String? hint,
      IconData? icon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, color: accent),
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

    final trapLabel = trap.name.trim().isEmpty ? 'Trampa' : trap.name.trim();

    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'trap_pest_dialog',
      barrierColor: Colors.black.withValues(alpha: 0.60),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, __, ___) {
        return MediaQuery.removeViewInsets(
          context: ctx,
          removeBottom: true,
          child: _KeyboardOpenSlide(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: RepaintBoundary(
                  child: Material(
                    color: Colors.transparent,
                    child: Card(
                      elevation: 18,
                      shadowColor: Colors.black.withValues(alpha: 0.30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      child: StatefulBuilder(
                        builder: (ctx, setLocal) {
                          final optionsNow = _pestOptions;
                          if (!optionsNow.contains(selected)) {
                            selected = optionsNow.isNotEmpty ? optionsNow.first : _otherOption;
                          }

                          return SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: accent.withValues(alpha: 0.18)),
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
                                          presetPest == null ? Icons.add_rounded : Icons.edit_rounded,
                                          color: accent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              presetPest == null ? 'Agregar plaga' : 'Editar plaga',
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '$trapLabel • Solo se guardan cantidades > 0',
                                              style: TextStyle(
                                                color: Colors.black.withValues(alpha: 0.62),
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

                                DropdownButtonFormField<String>(
                                  value: selected,
                                  decoration: deco(label: 'Plaga', icon: Icons.bug_report_outlined),
                                  items: optionsNow
                                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                                      .toList(),
                                  onChanged: (v) => setLocal(() => selected = v ?? selected),
                                ),

                                if (selected == _otherOption) ...[
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: otherCtrl,
                                    textInputAction: TextInputAction.next,
                                    decoration: deco(
                                      label: 'Escribe la plaga',
                                      hint: 'Ej: Trips, Minador, Oídio...',
                                      icon: Icons.edit_outlined,
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),
                                TextField(
                                  controller: qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  textInputAction: TextInputAction.done,
                                  decoration: deco(
                                    label: 'Cantidad',
                                    hint: 'Ej: 5',
                                    icon: Icons.numbers_rounded,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                        child: const Text('Cancelar'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                        icon: const Icon(Icons.check_rounded),
                                        label: const Text('Guardar'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (ok != true) return;

    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;

    // ✅ Si eligió "Otra…", creamos la plaga en BD y usamos el nombre escrito
    if (selected == _otherOption) {
      final created = await _createPestIfNeeded(otherCtrl.text);
      if (created == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe el nombre de la plaga.')));
        return;
      }
      selected = created;
    }

    setState(() => _setPestForTrap(trapId: trap.id, pest: selected, qty: qty));
    _scheduleDraftSave();
  }

  // ---------------- Navegación ----------------

  void _goBack() {
    if (_idx <= 0) return;
    setState(() => _idx--);
    _scheduleDraftSave();
  }

  void _goNext() {
    if (_isLast()) return;
    setState(() => _idx++);
    _scheduleDraftSave();
  }

  // ---------------- FINISH (OFFLINE FIRST) ----------------

  Future<void> _finishAndSaveOfflineFirst() async {
    final finishedAt = DateTime.now();

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay usuario autenticado.')));
      return;
    }

    final trapsObs = <String, dynamic>{};
    final totalsByPest = <String, int>{};

    for (final trap in widget.traps) {
      final trapId = trap.id;
      final pests = _countsByTrap[trapId] ?? {};

      final filtered = <String, int>{};
      pests.forEach((p, v) {
        if (v > 0) {
          filtered[p] = v;
          totalsByPest[p] = (totalsByPest[p] ?? 0) + v;
        }
      });

      trapsObs[trapId] = {
        'name': trap.name,
        'counts': filtered,
      };
    }

    final totalFindings = totalsByPest.values.fold<int>(0, (a, b) => a + b);

    final weekKey = _isoWeekKey(finishedAt);
    final range = _isoWeekRange(finishedAt);
    final weekStart = range.$1;
    final weekEnd = range.$2;

    final offlineTrapLinePayload = <String, dynamic>{
      'status': 'FINISHED',
      'byUid': uid,
      'startedAtMs': _startedAt.millisecondsSinceEpoch,
      'finishedAtMs': finishedAt.millisecondsSinceEpoch,
      'line': {
        'side': nsToStr(widget.lineSide),
        'lineNo': widget.lineNo,
        'lineKey': _lineKey,
      },
      'observations': {
        'traps': trapsObs,
      },
      'totalsByPest': totalsByPest,
      'totalFindings': totalFindings,
    };

    // 1) Encola el monitoreo (offline-first)
    await OfflineSyncService.instance.enqueueFinishedTrapLine(
      weekKey: weekKey,
      weekStart: weekStart,
      weekEnd: weekEnd,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _lineKey,
      offlineTrapLinePayload: offlineTrapLinePayload,
    );

    // 2) ✅ Guarda marcador local "FINALIZADA" para pintar en la pantalla anterior
    await OfflineSyncService.instance.saveDraft(
      weekKey: weekKey,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _doneMarkerLineKey, // 👈 marcador
      startedAtMs: _startedAt.millisecondsSinceEpoch,
      rightPass: false,
      idx: 0,
      countsJson: <String, dynamic>{
        'status': 'FINISHED',
        'finishedAtMs': finishedAt.millisecondsSinceEpoch,
      },
    );

    // 3) Borra el draft de captura
    await OfflineSyncService.instance.clearDraft(
      weekKey: _weekKey,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _draftLineKey,
    );

    unawaited(OfflineSyncService.instance.flush());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Monitoreo guardado en el teléfono. Se subirá automáticamente al haber internet.')),
    );
    Navigator.pop(context);
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

  (DateTime, DateTime) _isoWeekRange(DateTime dt) {
    final monday = dt.subtract(Duration(days: dt.weekday - DateTime.monday));
    final start = DateTime(monday.year, monday.month, monday.day);
    final end = start.add(const Duration(days: 6));
    return (start, end);
  }
}

// ======================== UI Components ========================

class _HeaderCardTrap extends StatelessWidget {
  final Color accent;
  final String mapName;
  final String capName;
  final int lineNo;
  final String sideLabel;

  final String trapLabel;
  final String indexLabel;

  const _HeaderCardTrap({
    required this.accent,
    required this.mapName,
    required this.capName,
    required this.lineNo,
    required this.sideLabel,
    required this.trapLabel,
    required this.indexLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
            child: Icon(Icons.yard_outlined, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mapName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.grid_view_rounded, size: 16, color: Colors.black.withValues(alpha: 0.55)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        capName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_activity_outlined, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(trapLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Línea $lineNo • $sideLabel • $indexLabel',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.black.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  final Color accent;
  final int currentIndex;
  final int total;
  final String modeLabel;

  const _ProgressStrip({
    required this.accent,
    required this.currentIndex,
    required this.total,
    required this.modeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final safeTotal = total <= 0 ? 1 : total;
    final progress = (currentIndex + 1) / safeTotal;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Icon(Icons.route_outlined, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Progreso • $modeLabel',
                  style: TextStyle(fontWeight: FontWeight.w900, color: accent),
                ),
              ),
              Text(
                '${currentIndex + 1}/$total',
                style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black.withValues(alpha: 0.70)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.black.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrapBadge extends StatelessWidget {
  final Color accent;
  final String label;

  const _TrapBadge({
    required this.accent,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_activity_outlined, color: accent),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Color accent;
  final String title;
  final String message;
  final IconData icon;

  const _EmptyState({
    required this.accent,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
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
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.70),
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

class _SectionTitle extends StatelessWidget {
  final Color accent;
  final String title;

  const _SectionTitle({
    required this.accent,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Icon(Icons.eco_outlined, size: 18, color: accent),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w900, color: accent),
        ),
      ],
    );
  }
}

class _NavigationBar extends StatelessWidget {
  final Color accent;
  final bool canGoBack;
  final bool isLast;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _NavigationBar({
    required this.accent,
    required this.canGoBack,
    required this.isLast,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canGoBack ? onBack : null,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Regresar'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            label: Text(isLast ? 'Última' : 'Avanzar'),
          ),
        ),
      ],
    );
  }
}

/// Dialog helper (igual que el de línea)
class _KeyboardOpenSlide extends StatefulWidget {
  final Widget child;
  const _KeyboardOpenSlide({required this.child});

  @override
  State<_KeyboardOpenSlide> createState() => _KeyboardOpenSlideState();
}

class _KeyboardOpenSlideState extends State<_KeyboardOpenSlide> with WidgetsBindingObserver {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _sync();

  void _sync() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;

    final v = views.first;
    final bottomInsetLogical = v.viewInsets.bottom / v.devicePixelRatio;
    final isOpenNow = bottomInsetLogical > 0;

    if (isOpenNow != _open && mounted) {
      setState(() => _open = isOpenNow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dy = _open ? -80.0 : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, dy, 0),
        child: widget.child,
      ),
    );
  }
}
