// lib/pages/admin/mapa/mapa_controller.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import './../../models/mapa_model.dart';

enum PaintTool { activate, deactivate, toggle }

class MapaController extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  GreenhouseMap? _map;
  GreenhouseMap? get map => _map;

  PaintTool _tool = PaintTool.toggle;
  PaintTool get tool => _tool;

  Timer? _notifyTimer;

  // ========================= NUEVO: ZONAS BLOQUEADAS HASTA ACTIVAR =========================
  bool _zonesEnabled = false;
  bool get zonesEnabled => _zonesEnabled;

  void setZonesEnabled(bool v) {
    if (_zonesEnabled == v) return;
    _zonesEnabled = v;
    notifyListeners();
  }

  // ========================= TRAMPAS (state) =========================

  bool _trapMode = false;
  bool get isTrapMode => _trapMode;

  final List<TrapCell> _draftTrapCells = [];
  List<TrapCell> get draftTrapCells => List.unmodifiable(_draftTrapCells);

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    super.dispose();
  }

  void setTool(PaintTool t) {
    _tool = t;
    notifyListeners();
  }

  void deleteLastCapilla() {
    if (_map == null) return;
    if (_map!.capillas.isEmpty) return;
    _map!.capillas.removeLast();
    _map!.invalidateColumnCache();
    notifyListeners();
  }

  // ========================= SEMANAS: trampas activas =========================

  /// ✅ Snapshot “histórico”: solo lo crea si NO existe.
  void _ensureWeeklyActiveTrapsSnapshotForWeek(String wk) {
    if (_map == null) return;
    _map!.weeklyActiveTraps.putIfAbsent(wk, () => _map!.activeTrapCount);
  }

  /// ✅ Semana actual SI se actualiza cuando cambias trampas (activar/desactivar/agregar/eliminar)
  /// para que al presionar “Guardar” se persista el número correcto.
  void _setCurrentWeekActiveTrapsToCurrentCount() {
    if (_map == null) return;
    final nowWk = weekKeyFromDate(DateTime.now());
    _map!.weeklyActiveTraps[nowWk] = _map!.activeTrapCount;
  }

  /// ✅ Asegura snapshots faltantes para semanas conocidas (plantas) y semana actual.
  /// - Semanas con plantas: snapshot si faltaba (NO pisa histórico)
  /// - Semana actual: si faltaba crea snapshot; si ya existe NO toca aquí (para no pisar)
  void _ensureSnapshotsForKnownWeeks() {
    if (_map == null) return;

    for (final wk in _map!.weeklyPlants.keys) {
      _ensureWeeklyActiveTrapsSnapshotForWeek(wk);
    }

    final nowWk = weekKeyFromDate(DateTime.now());
    _ensureWeeklyActiveTrapsSnapshotForWeek(nowWk);
  }

  // ========================= Plantas semanales =========================

  int? plantsForWeek(DateTime date) {
    if (_map == null) return null;
    final k = weekKeyFromDate(date);
    return _map!.weeklyPlants[k];
  }

  void setPlantsForWeek(DateTime date, int total) {
    if (_map == null) return;
    final k = weekKeyFromDate(date);
    _map!.weeklyPlants[k] = total;

    // ✅ cuando guardas plantas, guardas snapshot de trampas activas de ESA semana
    _map!.weeklyActiveTraps[k] = _map!.activeTrapCount;

    notifyListeners();
  }

  // ========================= TRAMPAS (actions) =========================

  void startTrapMode() {
    if (_map == null) return;
    _trapMode = true;
    _draftTrapCells.clear();
    notifyListeners();
  }

  void cancelTrapMode() {
    _trapMode = false;
    _draftTrapCells.clear();
    notifyListeners();
  }

  bool isDraftTrapCell(NS side, int poste, int lineNo) {
    return _draftTrapCells.any(
      (c) => c.side == side && c.poste == poste && c.lineNo == lineNo,
    );
  }

  void toggleDraftTrapCell(NS side, int poste, int lineNo) {
    if (_map == null) return;

    final exists = _cellExistsOnMap(side, poste, lineNo);
    if (!exists) return;

    final idx = _draftTrapCells.indexWhere(
      (c) => c.side == side && c.poste == poste && c.lineNo == lineNo,
    );
    if (idx >= 0) {
      _draftTrapCells.removeAt(idx);
    } else {
      _draftTrapCells.add(TrapCell(side: side, lineNo: lineNo, poste: poste));
    }
    notifyListeners();
  }

  void commitTrap(String name) {
    if (_map == null) return;
    if (_draftTrapCells.isEmpty) return;

    final id = "trap_${DateTime.now().millisecondsSinceEpoch}";
    _map!.traps.add(
      TrapDef(
        id: id,
        name: name.trim(),
        active: true,
        cells: List<TrapCell>.from(_draftTrapCells),
      ),
    );

    _map!.invalidateTrapCache();
    _trapMode = false;
    _draftTrapCells.clear();

    // ✅ histórico: no tocar semanas pasadas; solo asegurar faltantes
    _ensureSnapshotsForKnownWeeks();

    // ✅ PERO: semana actual sí debe reflejar el cambio
    _setCurrentWeekActiveTrapsToCurrentCount();

    notifyListeners();
  }

  void deleteTrap(String trapId) {
    if (_map == null) return;
    _map!.traps.removeWhere((t) => t.id == trapId);
    _map!.invalidateTrapCache();

    _ensureSnapshotsForKnownWeeks();
    _setCurrentWeekActiveTrapsToCurrentCount();

    notifyListeners();
  }

  void setTrapActive(String trapId, bool active) {
    if (_map == null) return;
    final t = _map!.trapById(trapId);
    if (t == null) return;

    if (t.active == active) return;

    t.active = active;
    _map!.invalidateTrapCache();

    _ensureSnapshotsForKnownWeeks();

    // ✅ aquí está lo que pediste: al activar/desactivar desde el panel,
    // la semana actual se actualiza (y se va a guardar al presionar Guardar).
    _setCurrentWeekActiveTrapsToCurrentCount();

    notifyListeners();
  }

  bool _cellExistsOnMap(NS side, int poste, int lineNo) {
    if (_map == null) return false;

    final maxPost = side == NS.north ? _map!.postsNorth : _map!.postsSouth;
    if (poste < 1 || poste > maxPost) return false;

    for (int col = 0; col < _map!.totalColumns; col++) {
      final info = _map!.columnInfo(col);
      final ln = side == NS.north ? info.northLineNo : info.southLineNo;
      if (ln == lineNo) return true;
    }
    return false;
  }

  // ========================= MAP BUILD / CAPILLAS =========================

  void newMap({
    required String name,
    required int postsNorth,
    required int postsSouth,
    required int firstLineNo,
    required bool stripedLines,
    required String stripedStart,
    required NS lineStartSide,
  }) {
    final tempId = "local_${DateTime.now().millisecondsSinceEpoch}";

    NS effectiveStartSide = lineStartSide;
    if (postsNorth <= 0 && postsSouth > 0) effectiveStartSide = NS.south;
    if (postsSouth <= 0 && postsNorth > 0) effectiveStartSide = NS.north;

    _map = GreenhouseMap(
      id: tempId,
      name: name.trim(),
      postsNorth: postsNorth,
      postsSouth: postsSouth,
      firstLineNo: firstLineNo,
      stripedLines: stripedLines,
      stripedStart: colorNorm(stripedStart),
      lineStartSide: effectiveStartSide,
    );

    // crea snapshot semana actual si falta
    _ensureSnapshotsForKnownWeeks();
    // y asegura valor de semana actual (por si ya hay trampas cargadas)
    _setCurrentWeekActiveTrapsToCurrentCount();

    notifyListeners();
  }

  void addCapilla({
    String? name,
    required CapSideMode mode,
    required int lineCount,
    int? overrideStartLineNo,
    bool advanced = false,
    int? bothUntilLineNo,
    CapSideMode? remainderMode,
  }) {
    if (_map == null) return;
    if (lineCount <= 0) return;

    var effMode = mode;
    var effAdvanced = advanced;

    if (_map!.postsNorth <= 0 && _map!.postsSouth > 0) {
      effMode = CapSideMode.southOnly;
      effAdvanced = false;
    }
    if (_map!.postsSouth <= 0 && _map!.postsNorth > 0) {
      effMode = CapSideMode.northOnly;
      effAdvanced = false;
    }

    final isFirst = _map!.capillas.isEmpty;
    final start = isFirst
        ? (overrideStartLineNo ?? _map!.firstLineNo)
        : (_map!.lastLineNo + 1);
    final end = start + lineCount - 1;

    List<CapSegment> segments = [];

    if (!effAdvanced || effMode != CapSideMode.bothPaired) {
      segments = [CapSegment(mode: effMode, lineCount: lineCount)];
    } else {
      final until = bothUntilLineNo ?? end;
      final safeUntil = until.clamp(start, end);

      final bothCount = safeUntil - start + 1;
      final remaining = lineCount - bothCount;

      segments.add(CapSegment(mode: CapSideMode.bothPaired, lineCount: bothCount));

      if (remaining > 0) {
        final remMode =
            (remainderMode == CapSideMode.northOnly ||
                    remainderMode == CapSideMode.southOnly)
                ? remainderMode!
                : CapSideMode.southOnly;
        segments.add(CapSegment(mode: remMode, lineCount: remaining));
      }
    }

    final id = "cap_${DateTime.now().millisecondsSinceEpoch}";
    _map!.capillas.add(
      CapillaDef(
        id: id,
        name: (name != null && name.trim().isNotEmpty) ? name.trim() : null,
        startLineNo: start,
        segments: segments,
      ),
    );

    _map!.invalidateColumnCache();
    notifyListeners();
  }

  void _scheduleNotify() {
    if (_notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 16), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  void paintCell(NS ns, int poste, int lineNo, {bool notify = true}) {
    if (_map == null) return;

    // ✅ bloqueado hasta activar "Editar zonas"
    if (!_zonesEnabled) return;

    final maxPost = ns == NS.north ? _map!.postsNorth : _map!.postsSouth;
    if (poste < 1 || poste > maxPost) return;

    final current = _map!.isActive(ns, poste, lineNo);

    bool next;
    switch (_tool) {
      case PaintTool.activate:
        next = true;
        break;
      case PaintTool.deactivate:
        next = false;
        break;
      case PaintTool.toggle:
        next = !current;
        break;
    }

    _map!.setActive(ns, poste, lineNo, next);

    if (notify) {
      notifyListeners();
    } else {
      _scheduleNotify();
    }
  }

  Future<String> saveToFirestore() async {
    if (_map == null) throw Exception("No hay mapa");

    final cleanName = _map!.name.trim();
    if (cleanName.isEmpty) {
      throw Exception("El nombre del invernadero es obligatorio.");
    }

    final q = await _db
        .collection("greenhouses_maps")
        .where("name", isEqualTo: cleanName)
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) {
      final existingId = q.docs.first.id;
      final isNew = _map!.id.startsWith("local_");
      if (isNew || existingId != _map!.id) {
        throw Exception(
          'Ya existe un invernadero con el nombre "$cleanName". Usa otro nombre.',
        );
      }
    }

    // ✅ antes de guardar:
    // - asegurar snapshots faltantes para semanas con plantas
    // - actualizar semana actual (para que lo de activar/desactivar quede persistido)
    _ensureSnapshotsForKnownWeeks();
    _setCurrentWeekActiveTrapsToCurrentCount();

    final data = _map!.toMap();

    try {
      if (_map!.id.startsWith("local_")) {
        final doc = await _db.collection("greenhouses_maps").add(data);
        _map = GreenhouseMap.fromDoc(doc.id, data);
        _map!.invalidateColumnCache();
        notifyListeners();
        return doc.id;
      } else {
        await _db
            .collection("greenhouses_maps")
            .doc(_map!.id)
            .set(data, SetOptions(merge: true));
        return _map!.id;
      }
    } on FirebaseException catch (e) {
      throw Exception("Firebase(${e.code}): ${e.message}");
    }
  }

  Future<void> deleteFromFirestore() async {
    if (_map == null) return;
    if (_map!.id.startsWith("local_")) {
      _map = null;
      notifyListeners();
      return;
    }
    await _db.collection("greenhouses_maps").doc(_map!.id).delete();
    _map = null;
    notifyListeners();
  }

  Future<void> loadFromFirestore(String docId) async {
    final snap = await _db.collection("greenhouses_maps").doc(docId).get();
    if (!snap.exists) throw Exception("No existe ese documento");
    _map = GreenhouseMap.fromDoc(snap.id, snap.data()!);

    // snapshots faltantes y semana actual consistente
    _ensureSnapshotsForKnownWeeks();
    _setCurrentWeekActiveTrapsToCurrentCount();

    _map!.invalidateColumnCache();
    notifyListeners();
  }
}