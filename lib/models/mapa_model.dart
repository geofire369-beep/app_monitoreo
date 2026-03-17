import 'dart:convert';

enum NS { north, south }

NS nsOpposite(NS v) => v == NS.north ? NS.south : NS.north;

String nsToStr(NS v) => v == NS.north ? "NORTH" : "SOUTH";

NS nsFromStr(String s) {
  final v = s.trim().toUpperCase();
  return v == "SOUTH" ? NS.south : NS.north;
}

enum CapSideMode { bothPaired, northOnly, southOnly }

String capModeToStr(CapSideMode m) {
  switch (m) {
    case CapSideMode.bothPaired:
      return "BOTH_PAIRED";
    case CapSideMode.northOnly:
      return "N_ONLY";
    case CapSideMode.southOnly:
      return "S_ONLY";
  }
}

CapSideMode capModeFromStr(String s) {
  switch (s) {
    case "N_ONLY":
      return CapSideMode.northOnly;
    case "S_ONLY":
      return CapSideMode.southOnly;
    default:
      return CapSideMode.bothPaired;
  }
}

String colorNorm(String v) {
  final t = v.toString().trim().toUpperCase();
  return (t == "GREEN") ? "GREEN" : "WHITE";
}

String colorOpposite(String v) => colorNorm(v) == "GREEN" ? "WHITE" : "GREEN";

/// Línea explícita en BD con lado (N/S) + color (WHITE/GREEN)
class CapLine {
  final int lineNo;
  final NS side;

  /// "WHITE" | "GREEN"
  final String color;

  const CapLine({
    required this.lineNo,
    required this.side,
    required this.color,
  });

  bool get isGreen => colorNorm(color) == "GREEN";

  Map<String, dynamic> toMap() => {
    "lineNo": lineNo,
    "side": nsToStr(side),
    "color": colorNorm(color),
  };

  static CapLine fromMap(Map<String, dynamic> m) => CapLine(
    lineNo: (m["lineNo"] ?? 0) as int,
    side: nsFromStr((m["side"] ?? "NORTH").toString()),
    color: colorNorm((m["color"] ?? "WHITE").toString()),
  );
}

// ========================= PLANTAS POR SEMANA =========================
String weekKeyFromDate(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  final weekday = date.weekday; // Mon=1..Sun=7
  final thursday = date.add(Duration(days: (4 - weekday)));
  final firstThursday = DateTime(thursday.year, 1, 4);
  final firstThursdayWeekday = firstThursday.weekday;
  final firstIsoThursday = firstThursday.add(
    Duration(days: (4 - firstThursdayWeekday)),
  );

  final weekNumber = 1 + ((thursday.difference(firstIsoThursday).inDays) ~/ 7);
  final weekYear = thursday.year;

  final ww = weekNumber.toString().padLeft(2, '0');
  return "$weekYear-W$ww";
}

int? weeklyPlantsValue(Map<String, int> weeklyPlants, DateTime date) {
  final k = weekKeyFromDate(date);
  return weeklyPlants[k];
}

// ========================= TRAMPAS =========================

String trapCellKey(NS side, int lineNo, int poste) =>
    '${nsToStr(side)}_${lineNo}_${poste}';

class TrapCell {
  final NS side;
  final int lineNo;
  final int poste;

  const TrapCell({
    required this.side,
    required this.lineNo,
    required this.poste,
  });

  String get key => trapCellKey(side, lineNo, poste);

  Map<String, dynamic> toMap() => {
    "side": nsToStr(side),
    "lineNo": lineNo,
    "poste": poste,
  };

  static TrapCell fromMap(Map<String, dynamic> m) => TrapCell(
    side: nsFromStr((m["side"] ?? "NORTH").toString()),
    lineNo: (m["lineNo"] ?? 0) as int,
    poste: (m["poste"] ?? 0) as int,
  );
}

class TrapDef {
  final String id;
  String name;

  /// ✅ NUEVO: activa / inactiva
  bool active;

  List<TrapCell> cells;

  TrapDef({
    required this.id,
    required this.name,
    this.active = true,
    required this.cells,
  });

  Map<String, dynamic> toMap() => {
    "id": id,
    "name": name.trim(),
    "active": active,
    "cells": cells.map((c) => c.toMap()).toList(),
  };

  static TrapDef fromMap(Map<String, dynamic> m) => TrapDef(
    id: (m["id"] ?? "").toString(),
    name: (m["name"] ?? "").toString(),
    active: (m["active"] ?? true) == true,
    cells: ((m["cells"] ?? const []) as List)
        .map((e) => TrapCell.fromMap(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

/// Segmento dentro de una capilla (compatibilidad / UI).
class CapSegment {
  CapSideMode mode;
  int lineCount;

  CapSegment({required this.mode, required this.lineCount});

  int get columnCount {
    if (mode == CapSideMode.bothPaired) {
      return (lineCount + 1) ~/ 2; // ceil
    }
    return lineCount;
  }

  Map<String, dynamic> toMap() => {
    "mode": capModeToStr(mode),
    "lineCount": lineCount,
  };

  static CapSegment fromMap(Map<String, dynamic> m) => CapSegment(
    mode: capModeFromStr((m["mode"] ?? "BOTH_PAIRED").toString()),
    lineCount: (m["lineCount"] ?? 0) as int,
  );
}

class CapillaDef {
  final String id;
  String? name;

  int startLineNo;
  List<CapSegment> segments;

  List<CapLine> lines;

  CapillaDef({
    required this.id,
    required this.startLineNo,
    required this.segments,
    this.name,
    List<CapLine>? lines,
  }) : lines = lines ?? <CapLine>[];

  int get totalLineCount => segments.fold<int>(0, (a, s) => a + s.lineCount);

  int get endLineNo => startLineNo + totalLineCount - 1;

  int get endLineNoResolved {
    if (lines.isNotEmpty) {
      final maxLine = lines
          .map((e) => e.lineNo)
          .fold<int>(startLineNo, (a, b) => b > a ? b : a);
      return maxLine;
    }
    return endLineNo;
  }

  int get columnCount {
    if (lines.isEmpty) {
      return segments.fold<int>(0, (a, s) => a + s.columnCount);
    }

    final sorted = [...lines]..sort((a, b) => a.lineNo.compareTo(b.lineNo));
    int cols = 0;
    int i = 0;
    while (i < sorted.length) {
      if (i + 1 < sorted.length && sorted[i + 1].side != sorted[i].side) {
        cols += 1;
        i += 2;
      } else {
        cols += 1;
        i += 1;
      }
    }
    return cols;
  }

  Map<String, dynamic> toMapWithContext(GreenhouseMap ctx) => {
    "id": id,
    "name": name,
    "startLineNo": startLineNo,
    "segments": segments.map((s) => s.toMap()).toList(),
    "lines": ctx.capLinesWithColor(this).map((l) => l.toMap()).toList(),
  };

  static CapillaDef fromMap(Map<String, dynamic> m) {
    final id = (m["id"] ?? "").toString();
    final name = m["name"] as String?;
    final start = (m["startLineNo"] ?? 1) as int;

    final segs = <CapSegment>[];
    if (m.containsKey("segments")) {
      segs.addAll(
        ((m["segments"] ?? const []) as List)
            .map((e) => CapSegment.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
    } else {
      final oldMode = capModeFromStr((m["mode"] ?? "BOTH_PAIRED").toString());
      final oldCount = (m["lineCount"] ?? 0) as int;
      segs.add(CapSegment(mode: oldMode, lineCount: oldCount));
    }

    final ls = <CapLine>[];
    if (m.containsKey("lines")) {
      ls.addAll(
        ((m["lines"] ?? const []) as List)
            .map((e) => CapLine.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }

    return CapillaDef(
      id: id,
      name: name,
      startLineNo: start,
      segments: segs,
      lines: ls,
    );
  }

  List<_SideLine> resolvedSideLines(GreenhouseMap ctx) {
    if (lines.isNotEmpty) {
      final sorted = [...lines]..sort((a, b) => a.lineNo.compareTo(b.lineNo));
      return sorted
          .map((e) => _SideLine(lineNo: e.lineNo, side: e.side))
          .toList();
    }

    int cursor = startLineNo;
    final out = <_SideLine>[];

    for (final seg in segments) {
      for (int i = 0; i < seg.lineCount; i++) {
        final lineNo = cursor + i;

        final NS side;
        if (seg.mode == CapSideMode.northOnly) {
          side = NS.north;
        } else if (seg.mode == CapSideMode.southOnly) {
          side = NS.south;
        } else {
          side = ctx.sideForLine(lineNo);
        }

        out.add(_SideLine(lineNo: lineNo, side: side));
      }
      cursor += seg.lineCount;
    }

    return out;
  }

  List<_CapColumn> buildColumns(GreenhouseMap ctx) {
    final ls = resolvedSideLines(ctx);
    final sorted = [...ls]..sort((a, b) => a.lineNo.compareTo(b.lineNo));

    final cols = <_CapColumn>[];
    int i = 0;

    while (i < sorted.length) {
      final cur = sorted[i];

      if (i + 1 < sorted.length && sorted[i + 1].side != cur.side) {
        final nxt = sorted[i + 1];
        final northLine = cur.side == NS.north ? cur.lineNo : nxt.lineNo;
        final southLine = cur.side == NS.south ? cur.lineNo : nxt.lineNo;
        cols.add(_CapColumn(northLineNo: northLine, southLineNo: southLine));
        i += 2;
      } else {
        cols.add(
          _CapColumn(
            northLineNo: cur.side == NS.north ? cur.lineNo : null,
            southLineNo: cur.side == NS.south ? cur.lineNo : null,
          ),
        );
        i += 1;
      }
    }

    return cols;
  }
}

class _SideLine {
  final int lineNo;
  final NS side;
  const _SideLine({required this.lineNo, required this.side});
}

class _CapColumn {
  final int? northLineNo;
  final int? southLineNo;
  const _CapColumn({required this.northLineNo, required this.southLineNo});
}

class GreenhouseMap {
  String id;
  String name;

  int postsNorth;
  int postsSouth;

  int firstLineNo;

  NS lineStartSide;

  bool stripedLines;

  String stripedStart;

  List<CapillaDef> capillas;

  Set<String> inactiveN;
  Set<String> inactiveS;

  List<TrapDef> traps;

  List<_GlobalColumn>? _colCache;
  Map<int, _LineMeta>? _lineMetaCache;
  Map<String, _TrapIndexEntry>? _trapIndexCache;

  /// total de plantas por semana
  Map<String, int> weeklyPlants;

  /// ✅ NUEVO: total trampas activas por semana (weekKey -> count)
  Map<String, int> weeklyActiveTraps;

  Map<int, NS>? _sideCache;
  Map<int, bool>? _pairedLineCache;

  GreenhouseMap({
    required this.id,
    required this.name,
    required this.postsNorth,
    required this.postsSouth,
    required this.firstLineNo,
    this.lineStartSide = NS.north,
    this.stripedLines = true,
    this.stripedStart = "WHITE",
    List<CapillaDef>? capillas,
    Set<String>? inactiveN,
    Set<String>? inactiveS,
    List<TrapDef>? traps,
    Map<String, int>? weeklyPlants,
    Map<String, int>? weeklyActiveTraps,
  }) : capillas = capillas ?? <CapillaDef>[],
       inactiveN = inactiveN ?? <String>{},
       inactiveS = inactiveS ?? <String>{},
       traps = traps ?? <TrapDef>[],
       weeklyPlants = weeklyPlants ?? <String, int>{},
       weeklyActiveTraps = weeklyActiveTraps ?? <String, int>{};

  // ✅ count traps active (por definición)
  int get activeTrapCount => traps.where((t) => t.active).length;

  void invalidateTrapCache() {
    _trapIndexCache = null;
  }

  void invalidateColumnCache() {
    _colCache = null;
    _lineMetaCache = null;
    _trapIndexCache = null;
    _sideCache = null;
    _pairedLineCache = null;
  }

  static String cellKey(int poste, int lineNo) => "${poste}_$lineNo";

  bool isActive(NS ns, int poste, int lineNo) {
    final k = cellKey(poste, lineNo);
    final set = ns == NS.north ? inactiveN : inactiveS;
    return !set.contains(k);
  }

  void setActive(NS ns, int poste, int lineNo, bool active) {
    final k = cellKey(poste, lineNo);
    final set = ns == NS.north ? inactiveN : inactiveS;
    if (active) {
      set.remove(k);
    } else {
      set.add(k);
    }
  }

  int get totalColumns {
    _ensureColCache();
    return _colCache!.length;
  }

  int get lastLineNo {
    if (capillas.isEmpty) return firstLineNo - 1;
    return capillas.last.endLineNoResolved;
  }

  NS sideForLine(int lineNo) {
    if (postsNorth <= 0 && postsSouth > 0) return NS.south;
    if (postsSouth <= 0 && postsNorth > 0) return NS.north;

    _ensureSideAndKindCache();
    final cached = _sideCache?[lineNo];
    if (cached != null) return cached;

    final off = lineNo - firstLineNo;
    if (off % 2 == 0) return lineStartSide;
    return nsOpposite(lineStartSide);
  }

  bool isPairedLine(int lineNo) {
    _ensureSideAndKindCache();
    return _pairedLineCache?[lineNo] == true;
  }

  void _ensureSideAndKindCache() {
    if (_sideCache != null && _pairedLineCache != null) return;

    final sideMap = <int, NS>{};
    final pairedMap = <int, bool>{};

    int bothCounter = 0;

    for (final cap in capillas) {
      int cursor = cap.startLineNo;

      for (final seg in cap.segments) {
        for (int i = 0; i < seg.lineCount; i++) {
          final ln = cursor + i;

          if (seg.mode == CapSideMode.northOnly) {
            sideMap[ln] = NS.north;
            pairedMap[ln] = false;
          } else if (seg.mode == CapSideMode.southOnly) {
            sideMap[ln] = NS.south;
            pairedMap[ln] = false;
          } else {
            sideMap[ln] = (bothCounter % 2 == 0)
                ? lineStartSide
                : nsOpposite(lineStartSide);
            pairedMap[ln] = true;
            bothCounter++;
          }
        }
        cursor += seg.lineCount;
      }
    }

    _sideCache = sideMap;
    _pairedLineCache = pairedMap;
  }

  void _ensureColCache() {
    if (_colCache != null) return;

    final cols = <_GlobalColumn>[];
    for (final cap in capillas) {
      final local = cap.buildColumns(this);
      for (final c in local) {
        cols.add(
          _GlobalColumn(
            capilla: cap,
            northLineNo: c.northLineNo,
            southLineNo: c.southLineNo,
          ),
        );
      }
    }
    _colCache = cols;
  }

  ColumnInfo columnInfo(int colIndex) {
    _ensureColCache();
    if (colIndex < 0 || colIndex >= _colCache!.length) {
      throw RangeError("colIndex fuera de rango");
    }
    final c = _colCache![colIndex];
    return ColumnInfo(
      capilla: c.capilla,
      colIndex: colIndex,
      northLineNo: c.northLineNo,
      southLineNo: c.southLineNo,
    );
  }

  // ========================= TRAMPAS (helpers) =========================

  void _ensureTrapIndex() {
    if (_trapIndexCache != null) return;

    final idx = <String, _TrapIndexEntry>{};
    for (final t in traps) {
      for (final c in t.cells) {
        idx[c.key] = _TrapIndexEntry(
          trapId: t.id,
          trapName: t.name,
          active: t.active,
        );
      }
    }
    _trapIndexCache = idx;
  }

  String? trapNameAt(NS ns, int poste, int lineNo) {
    _ensureTrapIndex();
    return _trapIndexCache?[trapCellKey(ns, lineNo, poste)]?.trapName;
  }

  String? trapIdAt(NS ns, int poste, int lineNo) {
    _ensureTrapIndex();
    return _trapIndexCache?[trapCellKey(ns, lineNo, poste)]?.trapId;
  }

  bool isTrapCell(NS ns, int poste, int lineNo) =>
      trapIdAt(ns, poste, lineNo) != null;

  bool isTrapCellActive(NS ns, int poste, int lineNo) {
    _ensureTrapIndex();
    final e = _trapIndexCache?[trapCellKey(ns, lineNo, poste)];
    return e != null && e.active;
  }

  TrapDef? trapById(String trapId) {
    for (final t in traps) {
      if (t.id == trapId) return t;
    }
    return null;
  }

  // ========================= COLORES (FIX) =========================

  void _ensureLineMeta() {
    if (_lineMetaCache != null) return;

    final meta = <int, _LineMeta>{};

    if (!stripedLines) {
      final all = <_SideLine>[];
      for (final cap in capillas) {
        all.addAll(cap.resolvedSideLines(this));
      }
      all.sort((a, b) => a.lineNo.compareTo(b.lineNo));
      for (final l in all) {
        meta[l.lineNo] = _LineMeta(side: l.side, color: "WHITE");
      }
      _lineMetaCache = meta;
      return;
    }

    final startColor = colorNorm(stripedStart);

    final all = <_SideLine>[];
    for (final cap in capillas) {
      all.addAll(cap.resolvedSideLines(this));
    }
    all.sort((a, b) => a.lineNo.compareTo(b.lineNo));

    bool nSeen = false;
    bool sSeen = false;

    String? lastNorthColor;
    String? lastSouthColor;

    int nCount = 0;
    int sCount = 0;

    String colorByCount(int count, String start) {
      return (count % 2 == 0) ? start : colorOpposite(start);
    }

    String? northStart;
    String? southStart;

    for (final l in all) {
      if (l.side == NS.north) {
        if (!nSeen) {
          nSeen = true;

          if (lineStartSide == NS.north) {
            northStart = startColor;
          } else {
            final base = lastSouthColor ?? startColor;
            northStart = colorOpposite(base);
          }
        }

        final c = colorByCount(nCount, northStart!);
        meta[l.lineNo] = _LineMeta(side: NS.north, color: c);
        lastNorthColor = c;
        nCount++;
      } else {
        if (!sSeen) {
          sSeen = true;

          if (lineStartSide == NS.south) {
            southStart = startColor;
          } else {
            final base = lastNorthColor ?? startColor;
            southStart = colorOpposite(base);
          }
        }

        final c = colorByCount(sCount, southStart!);
        meta[l.lineNo] = _LineMeta(side: NS.south, color: c);
        lastSouthColor = c;
        sCount++;
      }
    }

    _lineMetaCache = meta;
  }

  bool isGreenLine(int lineNo) {
    _ensureLineMeta();
    return _lineMetaCache?[lineNo]?.color == "GREEN";
  }

  String lineColor(int lineNo) {
    _ensureLineMeta();
    return _lineMetaCache?[lineNo]?.color ?? "WHITE";
  }

  NS lineSide(int lineNo) {
    _ensureLineMeta();
    return _lineMetaCache?[lineNo]?.side ?? NS.north;
  }

  List<CapLine> capLinesWithColor(CapillaDef cap) {
    _ensureLineMeta();
    final sideLines = cap.resolvedSideLines(this);
    final sorted = [...sideLines]..sort((a, b) => a.lineNo.compareTo(b.lineNo));

    return sorted
        .map(
          (l) => CapLine(
            lineNo: l.lineNo,
            side: l.side,
            color: lineColor(l.lineNo),
          ),
        )
        .toList();
  }

  Map<String, dynamic> toMap() => {
    "name": name.trim(),
    "postsNorth": postsNorth,
    "postsSouth": postsSouth,
    "firstLineNo": firstLineNo,
    "lineStartSide": nsToStr(lineStartSide),
    "stripedLines": stripedLines,
    "stripedStart": colorNorm(stripedStart),
    "capillas": capillas.map((c) => c.toMapWithContext(this)).toList(),
    "inactiveN": inactiveN.toList(),
    "inactiveS": inactiveS.toList(),
    "traps": traps.map((t) => t.toMap()).toList(),
    "weeklyPlants": weeklyPlants,
    "weeklyActiveTraps": weeklyActiveTraps,
    "updatedAt": DateTime.now().toIso8601String(),
  };

  static GreenhouseMap fromDoc(String id, Map<String, dynamic> m) {
    final pn = (m["postsNorth"] ?? 0) as int;
    final ps = (m["postsSouth"] ?? 0) as int;

    NS startSide = NS.north;
    if (m.containsKey("lineStartSide")) {
      startSide = nsFromStr((m["lineStartSide"] ?? "NORTH").toString());
    }

    if (pn <= 0 && ps > 0) startSide = NS.south;
    if (ps <= 0 && pn > 0) startSide = NS.north;

    final map = GreenhouseMap(
      id: id,
      name: (m["name"] ?? "") as String,
      postsNorth: pn,
      postsSouth: ps,
      firstLineNo: (m["firstLineNo"] ?? 1) as int,
      lineStartSide: startSide,
      stripedLines: (m["stripedLines"] ?? true) == true,
      stripedStart: colorNorm((m["stripedStart"] ?? "WHITE").toString()),
      weeklyPlants: (m["weeklyPlants"] is Map)
          ? Map<String, int>.from(
              (m["weeklyPlants"] as Map).map(
                (k, v) => MapEntry(k.toString(), (v ?? 0) as int),
              ),
            )
          : <String, int>{},
      weeklyActiveTraps: (m["weeklyActiveTraps"] is Map)
          ? Map<String, int>.from(
              (m["weeklyActiveTraps"] as Map).map(
                (k, v) => MapEntry(k.toString(), (v ?? 0) as int),
              ),
            )
          : <String, int>{},
      capillas: ((m["capillas"] ?? const []) as List)
          .map((e) => CapillaDef.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      inactiveN: Set<String>.from((m["inactiveN"] ?? const []) as List),
      inactiveS: Set<String>.from((m["inactiveS"] ?? const []) as List),
      traps: ((m["traps"] ?? const []) as List)
          .map((e) => TrapDef.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );

    return map;
  }

  String toJson() => jsonEncode(toMap());
}

class _LineMeta {
  final NS side;
  final String color;
  const _LineMeta({required this.side, required this.color});
}

class _GlobalColumn {
  final CapillaDef capilla;
  final int? northLineNo;
  final int? southLineNo;

  const _GlobalColumn({
    required this.capilla,
    required this.northLineNo,
    required this.southLineNo,
  });
}

class ColumnInfo {
  final CapillaDef capilla;
  final int colIndex;
  final int? northLineNo;
  final int? southLineNo;

  ColumnInfo({
    required this.capilla,
    required this.colIndex,
    required this.northLineNo,
    required this.southLineNo,
  });
}

class _TrapIndexEntry {
  final String trapId;
  final String trapName;
  final bool active;
  const _TrapIndexEntry({
    required this.trapId,
    required this.trapName,
    required this.active,
  });
}
