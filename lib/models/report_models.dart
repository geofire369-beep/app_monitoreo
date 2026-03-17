class ReportPayload {
  final String greenhouseName;
  final DateTime from;
  final DateTime to;
  final List<ReportRow> rows;

  const ReportPayload({
    required this.greenhouseName,
    required this.from,
    required this.to,
    required this.rows,
  });
}

class ReportRow {
  final String pestName;
  final int plantsChecked;
  final int plantsAffected;
  final double incidencePercent;
  final double? threshold;
  final String status;

  const ReportRow({
    required this.pestName,
    required this.plantsChecked,
    required this.plantsAffected,
    required this.incidencePercent,
    this.threshold,
    required this.status,
  });
}
