// lib/models/agro_application.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Alcance de la aplicación
/// - general: todo el invernadero
/// - focus: foco/área específica (por ahora puede ser solo descripción; luego celdas/mapa)
enum ApplicationScope { general, focus }

/// Estado del registro
enum ApplicationStatus { draft, registered, approved, annulled }

class AgroApplication {
  final String id;
  final String greenhouseId;

  /// general | focus
  final ApplicationScope scope;

  /// Si scope==focus: lista de celdas seleccionadas tipo "r10c5"
  /// Si no quieres usar celdas todavía, déjalo como [] y usa focusDesc en el doc.
  final List<String> cells;

  final String productId;
  final String productNameSnapshot;

  final DateTime datetime;
  final String applicationType;

  final double? doseValue;
  final String? doseUnit;

  final String? targetPestId;
  final String responsibleUserId;

  final ApplicationStatus status;
  final String? notes;

  // Auditoría
  final DateTime createdAt;
  final String createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? changeReason;

  final DateTime? approvedAt;
  final String? approvedBy;

  final DateTime? annulledAt;
  final String? annulledBy;
  final String? annulReason;

  final List<Map<String, dynamic>> attachments; // {url, path, name, uploadedAt}

  AgroApplication({
    required this.id,
    required this.greenhouseId,
    required this.scope,
    required this.cells,
    required this.productId,
    required this.productNameSnapshot,
    required this.datetime,
    required this.applicationType,
    this.doseValue,
    this.doseUnit,
    this.targetPestId,
    required this.responsibleUserId,
    required this.status,
    this.notes,
    required this.createdAt,
    required this.createdBy,
    this.updatedAt,
    this.updatedBy,
    this.changeReason,
    this.approvedAt,
    this.approvedBy,
    this.annulledAt,
    this.annulledBy,
    this.annulReason,
    required this.attachments,
  });

  Map<String, dynamic> toMap() => {
        "greenhouseId": greenhouseId,
        "scope": scope.name,
        "cells": cells,

        "productId": productId,
        "productNameSnapshot": productNameSnapshot,

        "datetime": Timestamp.fromDate(datetime),
        "applicationType": applicationType,

        "doseValue": doseValue,
        "doseUnit": doseUnit,

        "targetPestId": targetPestId,
        "responsibleUserId": responsibleUserId,

        "status": status.name,
        "notes": notes,

        "createdAt": Timestamp.fromDate(createdAt),
        "createdBy": createdBy,
        "updatedAt": updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
        "updatedBy": updatedBy,
        "changeReason": changeReason,

        "approvedAt": approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
        "approvedBy": approvedBy,

        "annulledAt": annulledAt != null ? Timestamp.fromDate(annulledAt!) : null,
        "annulledBy": annulledBy,
        "annulReason": annulReason,

        "attachments": attachments,
      };

  factory AgroApplication.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;

    final scopeStr = (d["scope"] ?? "general").toString();
    final statusStr = (d["status"] ?? "draft").toString();

    final scope = scopeStr == "focus" ? ApplicationScope.focus : ApplicationScope.general;

    ApplicationStatus status;
    switch (statusStr) {
      case "registered":
        status = ApplicationStatus.registered;
        break;
      case "approved":
        status = ApplicationStatus.approved;
        break;
      case "annulled":
        status = ApplicationStatus.annulled;
        break;
      default:
        status = ApplicationStatus.draft;
    }

    DateTime? _dt(dynamic v) => v == null ? null : (v as Timestamp).toDate();

    return AgroApplication(
      id: doc.id,
      greenhouseId: (d["greenhouseId"] ?? "").toString(),
      scope: scope,
      cells: (d["cells"] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      productId: (d["productId"] ?? "").toString(),
      productNameSnapshot: (d["productNameSnapshot"] ?? "").toString(),
      datetime: (d["datetime"] as Timestamp).toDate(),
      applicationType: (d["applicationType"] ?? "").toString(),
      doseValue: (d["doseValue"] as num?)?.toDouble(),
      doseUnit: d["doseUnit"]?.toString(),
      targetPestId: d["targetPestId"]?.toString(),
      responsibleUserId: (d["responsibleUserId"] ?? "").toString(),
      status: status,
      notes: d["notes"]?.toString(),
      createdAt: (d["createdAt"] as Timestamp).toDate(),
      createdBy: (d["createdBy"] ?? "").toString(),
      updatedAt: _dt(d["updatedAt"]),
      updatedBy: d["updatedBy"]?.toString(),
      changeReason: d["changeReason"]?.toString(),
      approvedAt: _dt(d["approvedAt"]),
      approvedBy: d["approvedBy"]?.toString(),
      annulledAt: _dt(d["annulledAt"]),
      annulledBy: d["annulledBy"]?.toString(),
      annulReason: d["annulReason"]?.toString(),
      attachments: (d["attachments"] as List<dynamic>? ?? [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
    );
  }
}
