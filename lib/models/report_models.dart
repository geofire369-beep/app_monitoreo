class IncidenceRow {
  final String pestName;
  final int plantsChecked;
  final int plantsAffected;
  final double incidencePercent;
  final double? threshold;
  final String status;

  IncidenceRow({
    required this.pestName,
    required this.plantsChecked,
    required this.plantsAffected,
    required this.incidencePercent,
    this.threshold,
    required this.status,
  });
}

class ReportPayload {
  final String greenhouseId;
  final String greenhouseName;
  final DateTime from;
  final DateTime to;
  final List<IncidenceRow> rows;

  ReportPayload({
    required this.greenhouseId,
    required this.greenhouseName,
    required this.from,
    required this.to,
    required this.rows,
  });
}
