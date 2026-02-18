import 'package:cloud_firestore/cloud_firestore.dart';

class ReportService {
  final FirebaseFirestore _db;
  ReportService(this._db);

  /// Lee monitoringRecords y agrega por pestId:
  /// fields esperados:
  /// { greenhouseId, pestId, plantsChecked, plantsAffected, datetime }
  Future<Map<String, Map<String, num>>> incidenceByPest({
    required String greenhouseId,
    required DateTime from,
    required DateTime to,
  }) async {
    final qs = await _db
        .collection("monitoringRecords")
        .where("greenhouseId", isEqualTo: greenhouseId)
        .where("datetime", isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where("datetime", isLessThanOrEqualTo: Timestamp.fromDate(to))
        .get();

    final out = <String, Map<String, num>>{};
    for (final d in qs.docs) {
      final m = d.data();

      final pestId = (m["pestId"] ?? "").toString();
      if (pestId.isEmpty) continue;

      final checked = (m["plantsChecked"] as num?) ?? 0;
      final affected = (m["plantsAffected"] as num?) ?? 0;

      out.putIfAbsent(pestId, () => {"checked": 0, "affected": 0});
      out[pestId]!["checked"] = out[pestId]!["checked"]! + checked;
      out[pestId]!["affected"] = out[pestId]!["affected"]! + affected;
    }
    return out;
  }
}
