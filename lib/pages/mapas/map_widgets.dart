import 'dart:math' as math;
import 'package:flutter/material.dart';

import './../../models/mapa_model.dart';
import './mapa_controller.dart';

class MapLayoutEditor extends StatefulWidget {
  final MapaController controller;
  const MapLayoutEditor({super.key, required this.controller});

  @override
  State<MapLayoutEditor> createState() => _MapLayoutEditorState();
}

class _MapLayoutEditorState extends State<MapLayoutEditor> {
  final _tc = TransformationController();
  bool _fitDone = false;
  bool _isLongPainting = false;

  int? _activePointerId;
  bool _rangeSelecting = false;
  _HitCell? _rangeStart;
  _HitCell? _rangeEnd;
  _RangeRect? _currentRangeRect;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = widget.controller.map!;
    if (map.capillas.isEmpty) {
      return const Center(child: Text("Agrega al menos 1 capilla."));
    }

    const colW = 26.0;
    const cellH = 16.0;

    const topNumH = 26.0;
    const capBandH = 28.0;
    const bottomNumH = 26.0;
    final midHeaderH = topNumH + capBandH + bottomNumH;

    const gutterW = 54.0;
    const labelH = 18.0;
    const margin = 8.0;

    final totalCols = map.totalColumns;
    final gridW = totalCols * colW;
    final canvasW = gutterW + gridW;

    final northLabelTop = margin;
    final northGridTop = northLabelTop + labelH;
    final northGridH = map.postsNorth * cellH;

    final midHeaderTop = northGridTop + northGridH;

    final southGridTop = midHeaderTop + midHeaderH;
    final southGridH = map.postsSouth * cellH;

    final southLabelTop = southGridTop + southGridH + 2;

    final canvasH = southLabelTop + labelH + margin;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_fitDone && constraints.maxWidth > 0 && canvasW > 0) {
          _fitDone = true;

          final scale = (constraints.maxWidth - 16) / canvasW;
          final s = scale.clamp(0.2, 6.0);

          final contentW = canvasW * s;
          final tx = ((constraints.maxWidth - contentW) / 2).clamp(
            0.0,
            double.infinity,
          );

          _tc.value = Matrix4.identity()
            ..translate(tx, 8.0)
            ..scale(s);
        }

        return InteractiveViewer(
          transformationController: _tc,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(2000),
          minScale: 0.2,
          maxScale: 8.0,
          panEnabled: !_rangeSelecting,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              if (_activePointerId != null) return;

              final scene = e.localPosition;

              final hit = _hitCell(
                scene,
                map,
                colW,
                cellH,
                gutterW,
                northGridTop,
                southGridTop,
              );

              if (hit != null) {
                _activePointerId = e.pointer;
                _rangeSelecting = true;
                _rangeStart = hit;
                _rangeEnd = hit;
                _currentRangeRect = _buildRangeRect(map, hit, hit);
                setState(() {});
              }
            },
            onPointerMove: (e) {
              if (!_rangeSelecting) return;
              if (_activePointerId != e.pointer) return;

              final scene = e.localPosition;

              final hit = _hitCell(
                scene,
                map,
                colW,
                cellH,
                gutterW,
                northGridTop,
                southGridTop,
              );

              if (hit == null) return;
              if (_rangeStart != null && hit.side != _rangeStart!.side) return;

              _rangeEnd = hit;
              _currentRangeRect = _buildRangeRect(
                map,
                _rangeStart!,
                _rangeEnd!,
              );
              setState(() {});
            },
            onPointerUp: (e) {
              if (_activePointerId != e.pointer) return;
              _finishRangeSelection(map, notify: true);
            },
            onPointerCancel: (e) {
              if (_activePointerId != e.pointer) return;
              _cancelRangeSelection();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                if (_rangeSelecting) return;
                _paintOrTrapAt(
                  d.localPosition,
                  map,
                  colW,
                  cellH,
                  gutterW,
                  northGridTop,
                  southGridTop,
                  notify: true,
                );
              },
              onLongPressStart: (d) {
                if (_rangeSelecting) return;
                _isLongPainting = true;
                _paintOrTrapAt(
                  d.localPosition,
                  map,
                  colW,
                  cellH,
                  gutterW,
                  northGridTop,
                  southGridTop,
                  notify: true,
                );
              },
              onLongPressMoveUpdate: (d) {
                if (!_isLongPainting) return;
                if (_rangeSelecting) return;
                _paintOrTrapAt(
                  d.localPosition,
                  map,
                  colW,
                  cellH,
                  gutterW,
                  northGridTop,
                  southGridTop,
                  notify: false,
                );
              },
              onLongPressEnd: (_) => _isLongPainting = false,
              child: CustomPaint(
                size: Size(canvasW, canvasH),
                painter: MapLayoutPainter(
                  map: map,
                  controller: widget.controller,
                  repaint: widget.controller,
                  colW: colW,
                  cellH: cellH,
                  topNumH: topNumH,
                  capBandH: capBandH,
                  bottomNumH: bottomNumH,
                  gutterW: gutterW,
                  labelH: labelH,
                  margin: margin,
                  rangeRect: _currentRangeRect,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  _HitCell? _hitCell(
    Offset p,
    GreenhouseMap map,
    double colW,
    double cellH,
    double gutterW,
    double northGridTop,
    double southGridTop,
  ) {
    final localX = p.dx - gutterW;
    if (localX < 0) return null;

    final totalCols = map.totalColumns;
    final col = (localX / colW).floor();
    if (col < 0 || col >= totalCols) return null;

    final info = map.columnInfo(col);

    if (p.dy >= northGridTop && p.dy < northGridTop + map.postsNorth * cellH) {
      final lineNo = info.northLineNo;
      if (lineNo == null) return null;

      final row = ((p.dy - northGridTop) / cellH).floor() + 1;
      final posteReal = map.postsNorth - row + 1;

      if (posteReal < 1 || posteReal > map.postsNorth) return null;
      return _HitCell(side: NS.north, poste: posteReal, lineNo: lineNo);
    }

    if (p.dy >= southGridTop && p.dy < southGridTop + map.postsSouth * cellH) {
      final lineNo = info.southLineNo;
      if (lineNo == null) return null;

      final row = ((p.dy - southGridTop) / cellH).floor() + 1;
      final posteReal = row;

      if (posteReal < 1 || posteReal > map.postsSouth) return null;
      return _HitCell(side: NS.south, poste: posteReal, lineNo: lineNo);
    }

    return null;
  }

  _RangeRect _buildRangeRect(GreenhouseMap map, _HitCell a, _HitCell b) {
    final minPost = math.min(a.poste, b.poste);
    final maxPost = math.max(a.poste, b.poste);

    final minLine = math.min(a.lineNo, b.lineNo);
    final maxLine = math.max(a.lineNo, b.lineNo);

    return _RangeRect(
      side: a.side,
      minPost: minPost,
      maxPost: maxPost,
      minLine: minLine,
      maxLine: maxLine,
    );
  }

  void _finishRangeSelection(GreenhouseMap map, {required bool notify}) {
    final r = _currentRangeRect;
    if (r == null) {
      _cancelRangeSelection();
      return;
    }

    final controller = widget.controller;

    if (controller.isTrapMode) {
      for (int line = r.minLine; line <= r.maxLine; line++) {
        for (int post = r.minPost; post <= r.maxPost; post++) {
          final exists = _cellExistsOnMap(map, r.side, post, line);
          if (!exists) continue;
          controller.toggleDraftTrapCell(r.side, post, line);
        }
      }
      _cancelRangeSelection();
      return;
    }

    for (int line = r.minLine; line <= r.maxLine; line++) {
      for (int post = r.minPost; post <= r.maxPost; post++) {
        final exists = _cellExistsOnMap(map, r.side, post, line);
        if (!exists) continue;
        controller.paintCell(r.side, post, line, notify: false);
      }
    }

    if (notify) controller.notifyListeners();
    _cancelRangeSelection();
  }

  bool _cellExistsOnMap(GreenhouseMap map, NS side, int poste, int lineNo) {
    final maxPost = side == NS.north ? map.postsNorth : map.postsSouth;
    if (poste < 1 || poste > maxPost) return false;

    for (int col = 0; col < map.totalColumns; col++) {
      final info = map.columnInfo(col);
      final ln = side == NS.north ? info.northLineNo : info.southLineNo;
      if (ln == lineNo) return true;
    }
    return false;
  }

  void _cancelRangeSelection() {
    _activePointerId = null;
    _rangeSelecting = false;
    _rangeStart = null;
    _rangeEnd = null;
    _currentRangeRect = null;
    if (mounted) setState(() {});
  }

  void _paintOrTrapAt(
    Offset p,
    GreenhouseMap map,
    double colW,
    double cellH,
    double gutterW,
    double northGridTop,
    double southGridTop, {
    required bool notify,
  }) {
    final controller = widget.controller;

    final localX = p.dx - gutterW;
    if (localX < 0) return;

    final totalCols = map.totalColumns;
    final col = (localX / colW).floor();
    if (col < 0 || col >= totalCols) return;

    final info = map.columnInfo(col);

    if (p.dy >= northGridTop && p.dy < northGridTop + map.postsNorth * cellH) {
      final lineNo = info.northLineNo;
      if (lineNo == null) return;

      final row = ((p.dy - northGridTop) / cellH).floor() + 1;
      final posteReal = map.postsNorth - row + 1;

      if (controller.isTrapMode) {
        controller.toggleDraftTrapCell(NS.north, posteReal, lineNo);
      } else {
        controller.paintCell(NS.north, posteReal, lineNo, notify: notify);
      }
      return;
    }

    if (p.dy >= southGridTop && p.dy < southGridTop + map.postsSouth * cellH) {
      final lineNo = info.southLineNo;
      if (lineNo == null) return;

      final row = ((p.dy - southGridTop) / cellH).floor() + 1;
      final posteReal = row;

      if (controller.isTrapMode) {
        controller.toggleDraftTrapCell(NS.south, posteReal, lineNo);
      } else {
        controller.paintCell(NS.south, posteReal, lineNo, notify: notify);
      }
      return;
    }
  }
}

// ========================= PAINTER =========================

class MapLayoutPainter extends CustomPainter {
  final GreenhouseMap map;
  final MapaController controller;

  final double colW;
  final double cellH;

  final double topNumH;
  final double capBandH;
  final double bottomNumH;

  final double gutterW;
  final double labelH;
  final double margin;

  final _RangeRect? rangeRect;

  MapLayoutPainter({
    required this.map,
    required this.controller,
    Listenable? repaint,
    this.colW = 26,
    this.cellH = 16,
    this.topNumH = 26,
    this.capBandH = 28,
    this.bottomNumH = 26,
    this.gutterW = 54,
    this.labelH = 18,
    this.margin = 8,
    this.rangeRect,
  }) : super(repaint: repaint);

  double get midHeaderH => topNumH + capBandH + bottomNumH;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    if (map.capillas.isEmpty) return;

    final totalCols = map.totalColumns;
    final gridW = totalCols * colW;
    final fullW = gutterW + gridW;

    final northLabelTop = margin;
    final northGridTop = northLabelTop + labelH;
    final northGridH = map.postsNorth * cellH;

    final midHeaderTop = northGridTop + northGridH;

    final southGridTop = midHeaderTop + midHeaderH;
    final southGridH = map.postsSouth * cellH;

    final southLabelTop = southGridTop + southGridH + 2;

    _label(canvas, "NORTE", Offset(8, northLabelTop + 1));
    _label(canvas, "SUR", Offset(8, southLabelTop + 1));

    _drawPanel(
      canvas: canvas,
      ns: NS.north,
      top: northGridTop,
      posts: map.postsNorth,
      totalCols: totalCols,
      ascendingPosts: false,
      rangeRect: rangeRect,
    );

    _drawMidHeader(canvas, totalCols, top: midHeaderTop);

    _drawPanel(
      canvas: canvas,
      ns: NS.south,
      top: southGridTop,
      posts: map.postsSouth,
      totalCols: totalCols,
      ascendingPosts: true,
      rangeRect: rangeRect,
    );

    final gridLine = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..strokeWidth = 0.6;

    for (int c = 0; c <= totalCols; c++) {
      final x = gutterW + c * colW;
      canvas.drawLine(
        Offset(x, northGridTop),
        Offset(x, southGridTop + southGridH),
        gridLine,
      );
    }

    for (int r = 0; r <= map.postsNorth; r++) {
      final y = northGridTop + r * cellH;
      canvas.drawLine(Offset(gutterW, y), Offset(fullW, y), gridLine);
    }

    for (int r = 0; r <= map.postsSouth; r++) {
      final y = southGridTop + r * cellH;
      canvas.drawLine(Offset(gutterW, y), Offset(fullW, y), gridLine);
    }

    canvas.drawRect(
      Rect.fromLTWH(gutterW, midHeaderTop, gridW, 1),
      Paint()..color = Colors.black.withOpacity(0.12),
    );
    canvas.drawRect(
      Rect.fromLTWH(gutterW, midHeaderTop + midHeaderH, gridW, 1),
      Paint()..color = Colors.black.withOpacity(0.12),
    );
  }

  void _drawMidHeader(Canvas canvas, int totalCols, {required double top}) {
    final gridW = totalCols * colW;

    canvas.drawRect(
      Rect.fromLTWH(0, top, gutterW + gridW, midHeaderH),
      Paint()..color = const Color(0xFFFAFAFA),
    );

    double xCursor = gutterW;
    final capFill = Paint()..color = const Color(0xFFBBDEFB);
    final capStroke = Paint()
      ..color = const Color(0xFF1E88E5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final capY = top + topNumH;

    for (final cap in map.capillas) {
      final w = cap.columnCount * colW;
      final rect = Rect.fromLTWH(xCursor, capY, w, capBandH);
      canvas.drawRect(rect, capFill);
      canvas.drawRect(rect, capStroke);

      final title = cap.name ?? "";
      if (title.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: w - 8);

        tp.paint(
          canvas,
          Offset(
            xCursor + (w - tp.width) / 2,
            capY + (capBandH - tp.height) / 2,
          ),
        );
      }

      xCursor += w;
    }

    final numStyle = const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      color: Colors.black87,
    );

    final greenBg = Paint()..color = const Color(0xFF8BC34A);
    final whiteBg = Paint()..color = Colors.white;

    for (int c = 0; c < totalCols; c++) {
      final info = map.columnInfo(c);

      final nLine = info.northLineNo;
      final sLine = info.southLineNo;

      if (nLine != null && map.stripedLines) {
        final isGreen = map.isGreenLine(nLine);
        canvas.drawRect(
          Rect.fromLTWH(gutterW + c * colW, top, colW, topNumH),
          isGreen ? greenBg : whiteBg,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(gutterW + c * colW, top, colW, topNumH),
          Paint()..color = Colors.white,
        );
      }

      if (sLine != null && map.stripedLines) {
        final isGreen = map.isGreenLine(sLine);
        canvas.drawRect(
          Rect.fromLTWH(
            gutterW + c * colW,
            top + topNumH + capBandH,
            colW,
            bottomNumH,
          ),
          isGreen ? greenBg : whiteBg,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(
            gutterW + c * colW,
            top + topNumH + capBandH,
            colW,
            bottomNumH,
          ),
          Paint()..color = Colors.white,
        );
      }

      _rotatedNumber(
        canvas: canvas,
        text: nLine?.toString() ?? "",
        center: Offset(gutterW + c * colW + colW / 2, top + topNumH / 2),
        style: numStyle,
      );

      _rotatedNumber(
        canvas: canvas,
        text: sLine?.toString() ?? "",
        center: Offset(
          gutterW + c * colW + colW / 2,
          top + topNumH + capBandH + bottomNumH / 2,
        ),
        style: numStyle,
      );
    }
  }

  void _drawPanel({
    required Canvas canvas,
    required NS ns,
    required double top,
    required int posts,
    required int totalCols,
    required bool ascendingPosts,
    required _RangeRect? rangeRect,
  }) {
    final onPaint = Paint()
      ..color = (ns == NS.north)
          ? const Color(0xFFFFEBEE)
          : const Color(0xFFE8F5E9);
    final offPaint = Paint()..color = const Color(0xFFF3F3F3);
    final emptyPaint = Paint()..color = Colors.white;

    final bar = Paint()..color = const Color(0xFF2F62B6);
    canvas.drawRect(Rect.fromLTWH(0, top, gutterW, posts * cellH), bar);

    final postStyle = const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w900,
      color: Colors.white,
    );
    for (int r = 1; r <= posts; r++) {
      final posteNo = ascendingPosts ? r : (posts - (r - 1));
      final tp = TextPainter(
        text: TextSpan(text: "$posteNo", style: postStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(
          gutterW / 2 - tp.width / 2,
          top + (r - 1) * cellH + (cellH - tp.height) / 2,
        ),
      );
    }

    // ✅ activas azul, inactivas gris
    final trapBorderActive = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF1976D2);

    final trapBorderInactive = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withOpacity(0.35);

    final draftBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFFF57C00);

    final selFill = Paint()..color = const Color(0xFF1976D2).withOpacity(0.10);
    final selStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF1976D2).withOpacity(0.75);

    for (int visualRow = 1; visualRow <= posts; visualRow++) {
      final posteReal = ascendingPosts ? visualRow : (posts - visualRow + 1);

      for (int c = 0; c < totalCols; c++) {
        final info = map.columnInfo(c);
        final lineNo = (ns == NS.north) ? info.northLineNo : info.southLineNo;

        final rect = Rect.fromLTWH(
          gutterW + c * colW,
          top + (visualRow - 1) * cellH,
          colW,
          cellH,
        );

        if (lineNo == null) {
          canvas.drawRect(rect, emptyPaint);
          continue;
        }

        final active = map.isActive(ns, posteReal, lineNo);
        canvas.drawRect(rect, active ? onPaint : offPaint);

        if (rangeRect != null &&
            rangeRect.side == ns &&
            posteReal >= rangeRect.minPost &&
            posteReal <= rangeRect.maxPost &&
            lineNo >= rangeRect.minLine &&
            lineNo <= rangeRect.maxLine) {
          canvas.drawRect(rect, selFill);
          canvas.drawRect(rect.deflate(0.4), selStroke);
        }

        if (map.isTrapCell(ns, posteReal, lineNo)) {
          final tActive = map.isTrapCellActive(ns, posteReal, lineNo);
          canvas.drawRect(
            rect.deflate(1),
            tActive ? trapBorderActive : trapBorderInactive,
          );
        }

        if (controller.isTrapMode &&
            controller.isDraftTrapCell(ns, posteReal, lineNo)) {
          canvas.drawRect(rect.deflate(0.5), draftBorder);
        }
      }
    }
  }

  void _rotatedNumber({
    required Canvas canvas,
    required String text,
    required Offset center,
    required TextStyle style,
  }) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _label(Canvas canvas, String text, Offset pos) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant MapLayoutPainter oldDelegate) => false;
}

class _HitCell {
  final NS side;
  final int poste;
  final int lineNo;
  const _HitCell({
    required this.side,
    required this.poste,
    required this.lineNo,
  });
}

class _RangeRect {
  final NS side;
  final int minPost;
  final int maxPost;
  final int minLine;
  final int maxLine;

  const _RangeRect({
    required this.side,
    required this.minPost,
    required this.maxPost,
    required this.minLine,
    required this.maxLine,
  });
}
