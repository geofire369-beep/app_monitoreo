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
    return _draftTrapCells.any((c) => c.side == side && c.poste == poste && c.lineNo == lineNo);
  }

  void toggleDraftTrapCell(NS side, int poste, int lineNo) {
    if (_map == null) return;

    // Solo permitir marcar si la celda existe en ese lado (lineNo no nulo en esa col)
    // y también si está activa (opcional, pero lo dejamos para consistencia).
    final exists = _cellExistsOnMap(side, poste, lineNo);
    if (!exists) return;

    final idx = _draftTrapCells.indexWhere((c) => c.side == side && c.poste == poste && c.lineNo == lineNo);
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
    _map!.traps.add(TrapDef(id: id, name: name.trim(), cells: List<TrapCell>.from(_draftTrapCells)));

    _map!.invalidateTrapCache();
    _trapMode = false;
    _draftTrapCells.clear();
    notifyListeners();
  }

  void deleteTrap(String trapId) {
    if (_map == null) return;
    _map!.traps.removeWhere((t) => t.id == trapId);
    _map!.invalidateTrapCache();
    notifyListeners();
  }

  bool _cellExistsOnMap(NS side, int poste, int lineNo) {
    if (_map == null) return false;

    // Validar poste
    final maxPost = side == NS.north ? _map!.postsNorth : _map!.postsSouth;
    if (poste < 1 || poste > maxPost) return false;

    // Validar que lineNo exista en el mapa (en algún columnInfo del lado correcto)
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
    required String stripedStart, // WHITE/GREEN (del lado lineStartSide)
    required NS lineStartSide, // NORTH/SOUTH (si ambos)
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

    // si el invernadero es solo N o solo S, forzar modo
    if (_map!.postsNorth <= 0 && _map!.postsSouth > 0) {
      effMode = CapSideMode.southOnly;
      effAdvanced = false;
    }
    if (_map!.postsSouth <= 0 && _map!.postsNorth > 0) {
      effMode = CapSideMode.northOnly;
      effAdvanced = false;
    }

    final isFirst = _map!.capillas.isEmpty;
    final start = isFirst ? (overrideStartLineNo ?? _map!.firstLineNo) : (_map!.lastLineNo + 1);
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
            (remainderMode == CapSideMode.northOnly || remainderMode == CapSideMode.southOnly)
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

    final q = await _db.collection("greenhouses_maps").where("name", isEqualTo: cleanName).limit(1).get();

    if (q.docs.isNotEmpty) {
      final existingId = q.docs.first.id;
      final isNew = _map!.id.startsWith("local_");
      if (isNew || existingId != _map!.id) {
        throw Exception('Ya existe un invernadero con el nombre "$cleanName". Usa otro nombre.');
      }
    }

    // toMap() guarda traps
    final data = _map!.toMap();

    try {
      if (_map!.id.startsWith("local_")) {
        final doc = await _db.collection("greenhouses_maps").add(data);
        _map = GreenhouseMap.fromDoc(doc.id, data);
        _map!.invalidateColumnCache();
        notifyListeners();
        return doc.id;
      } else {
        await _db.collection("greenhouses_maps").doc(_map!.id).set(
              data,
              SetOptions(merge: true),
            );
        return _map!.id;
      }
    } on FirebaseException catch (e) {
      throw Exception("Firebase(${e.code}): ${e.message}");
    }
  }

  Future<void> loadFromFirestore(String docId) async {
    final snap = await _db.collection("greenhouses_maps").doc(docId).get();
    if (!snap.exists) throw Exception("No existe ese documento");
    _map = GreenhouseMap.fromDoc(snap.id, snap.data()!);
    _map!.invalidateColumnCache();
    notifyListeners();
  }
}
