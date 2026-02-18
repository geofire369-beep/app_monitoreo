import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// OfflineSyncService:
/// - Drafts (ediciones en curso)
/// - Outbox (pendiente por subir cuando haya internet)
///
/// Ya soportaba FINISHED_LINE.
/// Ahora soporta también FINISHED_TRAP_LINE (monitoreo de trampas por línea).
class OfflineSyncService {
  OfflineSyncService._();
  static final instance = OfflineSyncService._();

  static const _boxDrafts = 'drafts_box_v1';
  static const _boxOutbox = 'outbox_box_v1';

  Box<dynamic>? _drafts;
  Box<dynamic>? _outbox;

  final ValueNotifier<int> outboxListenable = ValueNotifier<int>(0);

  bool _flushing = false;

  Future<void> init() async {
    await Hive.initFlutter();

    _drafts ??= await Hive.openBox(_boxDrafts);
    _outbox ??= await Hive.openBox(_boxOutbox);

    outboxListenable.value = _outbox?.length ?? 0;
  }

  // ===================== Drafts =====================

  String _draftKey({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
    required String lineKey,
  }) =>
      '$weekKey|$greenhouseId|$capillaId|$lineKey';

  Map<String, dynamic>? loadDraft({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
    required String lineKey,
  }) {
    final k = _draftKey(
      weekKey: weekKey,
      greenhouseId: greenhouseId,
      capillaId: capillaId,
      lineKey: lineKey,
    );

    final v = _drafts?.get(k);
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  Future<void> saveDraft({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
    required String lineKey,
    required int startedAtMs,
    required bool rightPass,
    required int idx,
    required Map<String, dynamic> countsJson,
  }) async {
    final k = _draftKey(
      weekKey: weekKey,
      greenhouseId: greenhouseId,
      capillaId: capillaId,
      lineKey: lineKey,
    );

    final payload = <String, dynamic>{
      'weekKey': weekKey,
      'greenhouseId': greenhouseId,
      'capillaId': capillaId,
      'lineKey': lineKey,
      'startedAtMs': startedAtMs,
      'rightPass': rightPass,
      'idx': idx,
      'counts': countsJson,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };

    await _drafts?.put(k, payload);
  }

  Future<void> clearDraft({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
    required String lineKey,
  }) async {
    final k = _draftKey(
      weekKey: weekKey,
      greenhouseId: greenhouseId,
      capillaId: capillaId,
      lineKey: lineKey,
    );
    await _drafts?.delete(k);
  }

  // ===================== Outbox helpers =====================

  /// Regresa lineKeys pendientes para "líneas de plaga" (FINISHED_LINE)
  Set<String> pendingLineKeys({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
  }) {
    final out = <String>{};

    if (_outbox == null) return out;

    for (final k in _outbox!.keys) {
      final it = _outbox!.get(k);
      if (it is! Map) continue;
      final m = Map<String, dynamic>.from(it);

      if ((m['kind'] ?? '') != 'FINISHED_LINE') continue;
      if ((m['weekKey'] ?? '') != weekKey) continue;
      if ((m['greenhouseId'] ?? '') != greenhouseId) continue;
      if ((m['capillaId'] ?? '') != capillaId) continue;

      final lineKey = (m['lineKey'] ?? '').toString();
      if (lineKey.isNotEmpty) out.add(lineKey);
    }

    return out;
  }

  /// NUEVO: regresa lineKeys pendientes para "líneas de trampas" (FINISHED_TRAP_LINE)
  Set<String> pendingTrapLineKeys({
    required String weekKey,
    required String greenhouseId,
    required String capillaId,
  }) {
    final out = <String>{};

    if (_outbox == null) return out;

    for (final k in _outbox!.keys) {
      final it = _outbox!.get(k);
      if (it is! Map) continue;
      final m = Map<String, dynamic>.from(it);

      if ((m['kind'] ?? '') != 'FINISHED_TRAP_LINE') continue;
      if ((m['weekKey'] ?? '') != weekKey) continue;
      if ((m['greenhouseId'] ?? '') != greenhouseId) continue;
      if ((m['capillaId'] ?? '') != capillaId) continue;

      final lineKey = (m['lineKey'] ?? '').toString();
      if (lineKey.isNotEmpty) out.add(lineKey);
    }

    return out;
  }

  // ===================== Enqueue: finished line =====================

  Future<void> enqueueFinishedLine({
    required String weekKey,
    required DateTime weekStart,
    required DateTime weekEnd,
    required String greenhouseId,
    required String capillaId,
    required String lineKey,
    required Map<String, dynamic> offlineLinePayload,
  }) async {
    final id = 'line_${DateTime.now().millisecondsSinceEpoch}_$lineKey';

    final it = <String, dynamic>{
      'kind': 'FINISHED_LINE',
      'weekKey': weekKey,
      'weekStartMs': weekStart.millisecondsSinceEpoch,
      'weekEndMs': weekEnd.millisecondsSinceEpoch,
      'greenhouseId': greenhouseId,
      'capillaId': capillaId,
      'lineKey': lineKey,
      'offlineLinePayload': offlineLinePayload,
      'tryCount': 0,
      'nextTryAtMs': 0,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };

    await _outbox?.put(id, it);
    outboxListenable.value = _outbox?.length ?? 0;
  }

  // ===================== NUEVO: Enqueue finished trap-line =====================

  Future<void> enqueueFinishedTrapLine({
    required String weekKey,
    required DateTime weekStart,
    required DateTime weekEnd,
    required String greenhouseId,
    required String capillaId,
    required String lineKey,
    required Map<String, dynamic> offlineTrapLinePayload,
  }) async {
    final id = 'trapline_${DateTime.now().millisecondsSinceEpoch}_$lineKey';

    final it = <String, dynamic>{
      'kind': 'FINISHED_TRAP_LINE',
      'weekKey': weekKey,
      'weekStartMs': weekStart.millisecondsSinceEpoch,
      'weekEndMs': weekEnd.millisecondsSinceEpoch,
      'greenhouseId': greenhouseId,
      'capillaId': capillaId,
      'lineKey': lineKey,
      'offlineTrapLinePayload': offlineTrapLinePayload,
      'tryCount': 0,
      'nextTryAtMs': 0,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    };

    await _outbox?.put(id, it);
    outboxListenable.value = _outbox?.length ?? 0;
  }

  // ===================== Flush =====================

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;

    try {
      if (_outbox == null) return;

      final now = DateTime.now().millisecondsSinceEpoch;

      final keys = _outbox!.keys.toList();
      for (final id in keys) {
        final itAny = _outbox!.get(id);
        if (itAny is! Map) continue;

        final it = Map<String, dynamic>.from(itAny);

        final nextTryAtMs = (it['nextTryAtMs'] ?? 0) as int;
        if (nextTryAtMs > now) continue;

        try {
          await _uploadOne(it);

          await _outbox!.delete(id);
          outboxListenable.value = _outbox?.length ?? 0;
        } catch (e) {
          final tryCount = (it['tryCount'] ?? 0) as int;
          final updated = Map<String, dynamic>.from(it);

          final next = now + _computeBackoff(tryCount + 1).inMilliseconds;

          updated['tryCount'] = tryCount + 1;
          updated['nextTryAtMs'] = next;
          updated['lastError'] = e.toString();
          updated['lastErrorAtMs'] = DateTime.now().millisecondsSinceEpoch;

          await _outbox!.put(id, updated);
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Duration _computeBackoff(int tryCount) {
    final seconds = (5 * (1 << (tryCount.clamp(0, 10)))).clamp(5, 300);
    return Duration(seconds: seconds);
  }

  Future<void> _uploadOne(Map<String, dynamic> it) async {
    final db = FirebaseFirestore.instance;

    final kind = (it['kind'] ?? '').toString();

    final weekKey = (it['weekKey'] ?? '').toString();
    final ghId = (it['greenhouseId'] ?? '').toString();
    final capId = (it['capillaId'] ?? '').toString();
    final lineKey = (it['lineKey'] ?? '').toString();

    if (weekKey.isEmpty || ghId.isEmpty || capId.isEmpty || lineKey.isEmpty) {
      throw Exception('Outbox item inválido (faltan ids).');
    }

    final weekStartMs = (it['weekStartMs'] ?? 0) as int;
    final weekEndMs = (it['weekEndMs'] ?? 0) as int;

    final weekRef = db.collection('monitoreo_weeks').doc(weekKey);
    final ghRef = weekRef.collection('greenhouses').doc(ghId);
    final capRef = ghRef.collection('capillas').doc(capId);

    final batch = db.batch();

    // Semana
    batch.set(
      weekRef,
      {
        'weekKey': weekKey,
        'weekStart': Timestamp.fromMillisecondsSinceEpoch(weekStartMs),
        'weekEnd': Timestamp.fromMillisecondsSinceEpoch(weekEndMs),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // Invernadero
    batch.set(
      ghRef,
      {
        'greenhouseId': ghId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (kind == 'FINISHED_LINE') {
      final payloadAny = it['offlineLinePayload'];
      if (payloadAny is! Map) throw Exception('offlineLinePayload inválido');
      final offline = Map<String, dynamic>.from(payloadAny);

      final startedAtMs = (offline['startedAtMs'] ?? 0) as int;
      final finishedAtMs = (offline['finishedAtMs'] ?? 0) as int;

      final firestoreLinePayload = <String, dynamic>{
        'status': 'FINISHED',
        'byUid': (offline['byUid'] ?? '').toString(),
        'startedAt': Timestamp.fromMillisecondsSinceEpoch(startedAtMs),
        'finishedAt': Timestamp.fromMillisecondsSinceEpoch(finishedAtMs),
        'updatedAt': FieldValue.serverTimestamp(),
        'observations': offline['observations'] ?? <String, dynamic>{},
        'totalsByPest': offline['totalsByPest'] ?? <String, int>{},
        'totalFindings': offline['totalFindings'] ?? 0,
      };

      batch.set(
        capRef,
        {
          'capillaId': capId,
          'updatedAt': FieldValue.serverTimestamp(),
          'lines': {
            lineKey: firestoreLinePayload,
          },
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      return;
    }

    if (kind == 'FINISHED_TRAP_LINE') {
      final payloadAny = it['offlineTrapLinePayload'];
      if (payloadAny is! Map) throw Exception('offlineTrapLinePayload inválido');
      final offline = Map<String, dynamic>.from(payloadAny);

      final startedAtMs = (offline['startedAtMs'] ?? 0) as int;
      final finishedAtMs = (offline['finishedAtMs'] ?? 0) as int;

      final firestoreTrapLinePayload = <String, dynamic>{
        'status': 'FINISHED',
        'byUid': (offline['byUid'] ?? '').toString(),
        'startedAt': Timestamp.fromMillisecondsSinceEpoch(startedAtMs),
        'finishedAt': Timestamp.fromMillisecondsSinceEpoch(finishedAtMs),
        'updatedAt': FieldValue.serverTimestamp(),
        'line': offline['line'] ?? <String, dynamic>{},
        'observations': offline['observations'] ?? <String, dynamic>{},
        'totalsByPest': offline['totalsByPest'] ?? <String, int>{},
        'totalFindings': offline['totalFindings'] ?? 0,
      };

      // Guardamos en el doc de capilla bajo "trapLines"
      batch.set(
        capRef,
        {
          'capillaId': capId,
          'updatedAt': FieldValue.serverTimestamp(),
          'trapLines': {
            lineKey: firestoreTrapLinePayload,
          },
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      return;
    }

    throw Exception('kind no soportado: $kind');
  }
}
