// lib/pages/monitora/monitora_line_monitoring_page.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/mapa_model.dart';
import '../../../theme/app_theme.dart';
import '../../../services/offline/offline_sync_service.dart';

class MonitoraLineMonitoringPage extends StatefulWidget {
  final GreenhouseMap map;
  final CapillaDef capilla;
  final CapLine line;

  const MonitoraLineMonitoringPage({
    super.key,
    required this.map,
    required this.capilla,
    required this.line,
  });

  @override
  State<MonitoraLineMonitoringPage> createState() =>
      _MonitoraLineMonitoringPageState();
}

class _MonitoraLineMonitoringPageState
    extends State<MonitoraLineMonitoringPage> {
  final _fs = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pestsSub;

  // ✅ favoritos para MONITOREO DE PLAGA
  static const String _favPlagaField = 'favPlaga';

  final List<String> _pestsFavPlaga = [];
  final List<String> _pestsNonFav = [];
  final Map<String, List<String>> _pestLevelsByName = {};

  static const String _otherOption = 'Otra…';

  // ✅ Conteos por lado/poste/pestKey
  final Map<String, Map<int, Map<String, int>>> _counts = {
    'L': <int, Map<String, int>>{},
    'R': <int, Map<String, int>>{},
  };

  // ✅ FOCO por lado/poste: SOLO guardamos las plagas con FOCO = true
  final Map<String, Map<int, Set<String>>> _focus = {
    'L': <int, Set<String>>{},
    'R': <int, Set<String>>{},
  };

  List<String> _levelsForPest(String pestName) {
    final levels = _pestLevelsByName[pestName] ?? const <String>[];
    final cleaned = levels
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    cleaned.sort((a, b) {
      final ai = int.tryParse(a);
      final bi = int.tryParse(b);
      if (ai != null && bi != null) return ai.compareTo(bi);
      return a.compareTo(b);
    });
    return cleaned;
  }

  /// Clave interna: "Nombre|Nivel" (si no hay nivel, solo "Nombre")
  String _composePestKey(String name, String? level) {
    final n = name.trim();
    final l = (level ?? '').trim();
    if (l.isEmpty) return n;
    return '$n|$l';
  }

  ({String name, String? level}) _parsePestKey(String key) {
    final raw = key.trim();
    final idx = raw.lastIndexOf('|');
    if (idx <= 0) return (name: raw, level: null);
    final name = raw.substring(0, idx).trim();
    final level = raw.substring(idx + 1).trim();
    if (name.isEmpty || level.isEmpty) return (name: raw, level: null);
    return (name: name, level: level);
  }

  void _listenPests() {
    _pestsSub = _fs.collection('plagas').orderBy('nombre').snapshots().listen((
      snap,
    ) {
      final fav = <String>[];
      final non = <String>[];
      final levelsMap = <String, List<String>>{};

      for (final d in snap.docs) {
        final m = d.data();
        final nombre = (m['nombre'] ?? '').toString().trim();
        if (nombre.isEmpty) continue;

        final isFavPlaga = (m[_favPlagaField] == true);
        if (isFavPlaga) {
          fav.add(nombre);
        } else {
          non.add(nombre);
        }

        final nivelesAny = m['niveles'];
        if (nivelesAny is List) {
          levelsMap[nombre] = nivelesAny
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        } else {
          levelsMap[nombre] = <String>[];
        }
      }

      if (!mounted) return;
      setState(() {
        _pestsFavPlaga
          ..clear()
          ..addAll(fav);
        _pestsNonFav
          ..clear()
          ..addAll(non);
        _pestLevelsByName
          ..clear()
          ..addAll(levelsMap);
      });
    }, onError: (_) {});
  }

  Future<String?> _createPestIfNeeded(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return null;

    final existsFav = _pestsFavPlaga.any(
      (p) => p.toLowerCase() == name.toLowerCase(),
    );
    final existsNon = _pestsNonFav.any(
      (p) => p.toLowerCase() == name.toLowerCase(),
    );

    if (existsFav || existsNon) {
      final inFav = _pestsFavPlaga.firstWhere(
        (p) => p.toLowerCase() == name.toLowerCase(),
        orElse: () => '',
      );
      if (inFav.trim().isNotEmpty) return inFav;

      final inNon = _pestsNonFav.firstWhere(
        (p) => p.toLowerCase() == name.toLowerCase(),
        orElse: () => name,
      );
      return inNon;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;

    await _fs.collection('plagas').add({
      'nombre': name,
      'tipo': 'PLAGA',
      'niveles': <String>[],
      'favPlaga': false,
      'favTrap': false,
      'createdByUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      setState(() {
        _pestsNonFav.add(name);
        _pestLevelsByName[name] = <String>[];
      });
    }

    return name;
  }

  bool _rightPass = false;
  int _idx = 0;

  late DateTime _startedAt;

  late final List<int> _leftPosts;
  late final List<int> _rightPosts;

  Timer? _draftDebounce;
  int _lastDraftFingerprint = 0;

  late final String _lineKey;
  late final String _capName;
  late final String _sideLabel;

  @override
  void initState() {
    super.initState();

    _startedAt = DateTime.now();
    _lineKey =
        '${nsToStr(widget.line.side).toLowerCase()}_${widget.line.lineNo}';

    _capName =
        (widget.capilla.name == null || widget.capilla.name!.trim().isEmpty)
        ? '(sin nombre)'
        : widget.capilla.name!.trim();

    _sideLabel = (widget.line.side == NS.north) ? 'NORTE' : 'SUR';

    final postsCount = (widget.line.side == NS.north)
        ? widget.map.postsNorth
        : widget.map.postsSouth;

    final active = <int>[];
    for (int p = 1; p <= postsCount; p++) {
      if (widget.map.isActive(widget.line.side, p, widget.line.lineNo)) {
        active.add(p);
      }
    }

    _leftPosts = active;
    _rightPosts = [...active].reversed.toList();

    _listenPests();
    Future.microtask(_restoreDraftIfAny);
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _pestsSub?.cancel();
    super.dispose();
  }

  // ---------------- Draft helpers ----------------

  String get _weekKey => _isoWeekKey(_startedAt);
  String get _sideKey => _rightPass ? 'R' : 'L';
  List<int> get _currentPosts => _rightPass ? _rightPosts : _leftPosts;

  Future<void> _restoreDraftIfAny() async {
    final draft = OfflineSyncService.instance.loadDraft(
      weekKey: _weekKey,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _lineKey,
    );

    if (draft == null) return;

    try {
      final startedAtMs = (draft['startedAtMs'] ?? 0) as int;
      final rightPass = (draft['rightPass'] ?? false) as bool;
      final idx = (draft['idx'] ?? 0) as int;

      final countsAny = draft['counts'];
      if (countsAny is! Map) return;
      final counts = Map<String, dynamic>.from(countsAny);

      _counts['L']!.clear();
      _counts['R']!.clear();

      void applySideCounts(String side) {
        final sideAny = counts[side];
        if (sideAny is! Map) return;
        final postsMap = Map<String, dynamic>.from(sideAny);

        postsMap.forEach((postStr, pestsAny) {
          final post = int.tryParse(postStr.toString()) ?? 0;
          if (post <= 0) return;

          if (pestsAny is! Map) return;
          final pestsMap = Map<String, dynamic>.from(pestsAny);

          final out = <String, int>{};
          pestsMap.forEach((pest, v) {
            final n = (v is int) ? v : int.tryParse(v.toString()) ?? 0;
            if (n > 0) out[pest.toString()] = n;
          });

          if (out.isNotEmpty) _counts[side]![post] = out;
        });
      }

      applySideCounts('L');
      applySideCounts('R');

      _focus['L']!.clear();
      _focus['R']!.clear();

      final focoAny = counts['FOCO'];
      if (focoAny is Map) {
        final foco = Map<String, dynamic>.from(focoAny);

        void readSide(String side) {
          final sideAny = foco[side];
          if (sideAny is! Map) return;

          final postsMap = Map<String, dynamic>.from(sideAny);
          postsMap.forEach((postStr, listAny) {
            final post = int.tryParse(postStr.toString()) ?? 0;
            if (post <= 0) return;

            if (listAny is! List) return;
            final keys = listAny
                .map((e) => e.toString())
                .where((e) => e.trim().isNotEmpty)
                .toSet();
            if (keys.isNotEmpty) {
              _focus[side]![post] = keys;
            }
          });
        }

        readSide('L');
        readSide('R');
      }

      final restoredStartedAt = DateTime.fromMillisecondsSinceEpoch(
        startedAtMs > 0 ? startedAtMs : _startedAt.millisecondsSinceEpoch,
      );

      if (!mounted) return;
      setState(() {
        _startedAt = restoredStartedAt;
        _rightPass = rightPass;
        _idx = idx.clamp(
          0,
          (_currentPosts.isEmpty ? 0 : _currentPosts.length - 1),
        );
      });

      _lastDraftFingerprint = _computeDraftFingerprint(
        startedAtMs: _startedAt.millisecondsSinceEpoch,
        rightPass: _rightPass,
        idx: _idx,
        counts: _counts,
        focus: _focus,
      );
    } catch (_) {}
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();

    _draftDebounce = Timer(const Duration(milliseconds: 500), () {
      final fp = _computeDraftFingerprint(
        startedAtMs: _startedAt.millisecondsSinceEpoch,
        rightPass: _rightPass,
        idx: _idx,
        counts: _counts,
        focus: _focus,
      );

      if (fp == _lastDraftFingerprint) return;
      _lastDraftFingerprint = fp;

      final countsJson = _countsToJson();

      unawaited(
        Future<void>(() async {
          await OfflineSyncService.instance.saveDraft(
            weekKey: _weekKey,
            greenhouseId: widget.map.id,
            capillaId: widget.capilla.id,
            lineKey: _lineKey,
            startedAtMs: _startedAt.millisecondsSinceEpoch,
            rightPass: _rightPass,
            idx: _idx,
            countsJson: countsJson,
          );
        }),
      );
    });
  }

  int _computeDraftFingerprint({
    required int startedAtMs,
    required bool rightPass,
    required int idx,
    required Map<String, Map<int, Map<String, int>>> counts,
    required Map<String, Map<int, Set<String>>> focus,
  }) {
    var h = 17;
    h = 37 * h + startedAtMs.hashCode;
    h = 37 * h + (rightPass ? 1 : 0);
    h = 37 * h + idx;

    for (final side in const ['L', 'R']) {
      final posts = counts[side]!;
      final postKeys = posts.keys.toList()..sort();
      for (final post in postKeys) {
        h = 37 * h + post;
        final pests = posts[post]!;
        final pestKeys = pests.keys.toList()..sort();
        for (final pest in pestKeys) {
          final v = pests[pest] ?? 0;
          h = 37 * h + pest.hashCode;
          h = 37 * h + v;
        }
      }
    }

    for (final side in const ['L', 'R']) {
      final posts = focus[side]!;
      final postKeys = posts.keys.toList()..sort();
      for (final post in postKeys) {
        h = 37 * h + 99991;
        h = 37 * h + post;
        final keys = posts[post]!.toList()..sort();
        for (final k in keys) {
          h = 37 * h + 99997;
          h = 37 * h + k.hashCode;
        }
      }
    }

    return h;
  }

  Map<String, dynamic> _countsToJson() {
    final out = <String, dynamic>{};

    for (final side in const ['L', 'R']) {
      final sideMap = <String, dynamic>{};
      _counts[side]!.forEach((post, pests) {
        if (pests.isEmpty) return;

        final pestsOut = <String, int>{};
        pests.forEach((p, v) {
          if (v > 0) pestsOut[p] = v;
        });

        if (pestsOut.isNotEmpty) sideMap[post.toString()] = pestsOut;
      });
      out[side] = sideMap;
    }

    final focoOut = <String, dynamic>{};
    for (final side in const ['L', 'R']) {
      final sideOut = <String, dynamic>{};
      _focus[side]!.forEach((post, keys) {
        if (keys.isEmpty) return;
        sideOut[post.toString()] = (keys.toList()..sort());
      });
      focoOut[side] = sideOut;
    }
    out['FOCO'] = focoOut;

    return out;
  }

  // ---------------- FOCO per plaga ----------------

  bool _isFocusOn({required int post, required String pestKey}) {
    return _focus[_sideKey]?[post]?.contains(pestKey) ?? false;
  }

  void _setFocus({
    required int post,
    required String pestKey,
    required bool on,
  }) {
    final side = _sideKey;

    if (!on) {
      final set = _focus[side]?[post];
      set?.remove(pestKey);
      if (set != null && set.isEmpty) {
        _focus[side]!.remove(post);
      }
      return;
    }

    _focus[side]!.putIfAbsent(post, () => <String>{});
    _focus[side]![post]!.add(pestKey);
  }

  // ---------------- Navigation ----------------

  bool _canGoBack() => !(!_rightPass && _idx == 0);
  bool _isLastOfThisPass() => _idx >= _currentPosts.length - 1;
  bool _isLastOfLastPass() => _rightPass && _isLastOfThisPass();

  void _goBack() {
    if (_idx > 0) {
      setState(() => _idx--);
      _scheduleDraftSave();
      return;
    }

    if (_rightPass) {
      setState(() {
        _rightPass = false;
        _idx = _leftPosts.isEmpty ? 0 : (_leftPosts.length - 1);
      });
      _scheduleDraftSave();
    }
  }

  Future<void> _goNextOrTurn() async {
    final accent = AppTheme.pepperGreen;

    if (!_isLastOfThisPass()) {
      setState(() => _idx++);
      _scheduleDraftSave();
      return;
    }

    if (!_rightPass) {
      final ok = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'turn_dialog',
        barrierColor: Colors.black.withValues(alpha: 0.60),
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Material(
                color: Colors.transparent,
                child: Card(
                  elevation: 18,
                  shadowColor: Colors.black.withValues(alpha: 0.30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Padding(
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
                            border: Border.all(
                              color: accent.withValues(alpha: 0.18),
                            ),
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
                                child: Icon(Icons.sync_rounded, color: accent),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Dar vuelta',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Terminaste el lado izquierdo. Continúa por la derecha.',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context, false),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text('Continuar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      );

      if (ok == true) {
        setState(() {
          _rightPass = true;
          _idx = 0;
        });
        _scheduleDraftSave();
      }
    }
  }

  // ---------------- Data helpers ----------------

  void _setPestForPost({
    required int post,
    required String pestKey,
    required int qty,
  }) {
    if (qty <= 0) {
      final current = _counts[_sideKey]![post];
      current?.remove(pestKey);
      if (current != null && current.isEmpty) {
        _counts[_sideKey]!.remove(post);
      }

      _setFocus(post: post, pestKey: pestKey, on: false);
      return;
    }

    _counts[_sideKey]!.putIfAbsent(post, () => <String, int>{});
    _counts[_sideKey]![post]![pestKey] = qty;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperGreen;

    final passLabel = _rightPass ? "Derecha" : "Izquierda";
    final posts = _rightPass ? _rightPosts : _leftPosts;

    final bg = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.10), Colors.white, Colors.white],
        ),
      ),
    );

    if (posts.isEmpty) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          title: const Text('Monitoreo'),
          elevation: 0,
        ),
        body: RepaintBoundary(
          child: Stack(
            children: [
              Positioned.fill(child: bg),
              SafeArea(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 560),
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
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
                            border: Border.all(
                              color: accent.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No hay postes activos para esta línea.\n(Revisa casillas desactivadas en el mapa.)',
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
            ],
          ),
        ),
      );
    }

    final currentPost = posts[_idx];
    final currentPests = _counts[_sideKey]?[currentPost];
    final hasPests = currentPests != null && currentPests.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('Monitoreo'),
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

                  final header = _HeaderCard(
                    accent: accent,
                    mapName: widget.map.name,
                    capName: _capName,
                    lineNo: widget.line.lineNo,
                    sideLabel: _sideLabel,
                    passLabel: passLabel,
                  );

                  final progress = _ProgressStrip(
                    accent: accent,
                    currentIndex: _idx,
                    total: posts.length,
                    modeLabel: passLabel,
                  );

                  final postBadge = _PostBadge(
                    accent: accent,
                    postNo: currentPost,
                  );

                  final addButton = SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => _addOrEditPestDialog(post: currentPost),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        'Agregar plaga encontrada',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  );

                  final pestsBody = !hasPests
                      ? _EmptyState(
                          accent: accent,
                          title: 'Sin registros',
                          message:
                              'Aún no registras plagas en este poste.\nUsa “Agregar plaga encontrada”.',
                          icon: Icons.bug_report_outlined,
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: currentPests!.length,
                          itemBuilder: (context, i) {
                            final key = currentPests.keys.elementAt(i);
                            final qty = currentPests[key] ?? 0;
                            if (qty <= 0) return const SizedBox.shrink();
                            return _pestRow(
                              post: currentPost,
                              pestKey: key,
                              qty: qty,
                            );
                          },
                        );

                  final listCard = Expanded(
                    child: RepaintBoundary(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
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
                    canGoBack: _canGoBack(),
                    isLast: _isLastOfLastPass(),
                    onBack: _goBack,
                    onNext: _goNextOrTurn,
                  );

                  final finishButton = _isLastOfLastPass()
                      ? SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.pepperRed,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            onPressed: _finishAndSaveOfflineFirst,
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                            ),
                            label: const Text(
                              'Marcar línea como finalizada',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
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
                        Center(child: postBadge),
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
                      _SectionTitle(
                        accent: accent,
                        title: "Plagas registradas",
                      ),
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

  Widget _pestRow({
    required int post,
    required String pestKey,
    required int qty,
  }) {
    final accent = AppTheme.pepperGreen;
    final parsed = _parsePestKey(pestKey);
    final isFoco = _isFocusOn(post: post, pestKey: pestKey);

    final focoColor = AppTheme.pepperRed;
    final focoBg = isFoco
        ? focoColor.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.03);
    final focoBorder = isFoco
        ? focoColor.withValues(alpha: 0.35)
        : Colors.black.withValues(alpha: 0.12);

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
        title: Text(
          parsed.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            parsed.level == null || parsed.level!.isEmpty
                ? 'Cantidad: $qty'
                : 'Nivel: ${parsed.level} • Cantidad: $qty',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: isFoco ? 'FOCO: sí' : 'FOCO: no',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(
                    () => _setFocus(post: post, pestKey: pestKey, on: !isFoco),
                  );
                  _scheduleDraftSave();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: focoBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: focoBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.flash_on_rounded,
                        size: 18,
                        color: isFoco ? focoColor : Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'FOCO',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: isFoco ? focoColor : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Editar',
              icon: Icon(Icons.edit_rounded, color: accent),
              onPressed: () => _addOrEditPestDialog(
                post: post,
                presetPestKey: pestKey,
                presetQty: qty,
                presetFoco: isFoco,
              ),
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: Icon(
                Icons.delete_outline_rounded,
                color: Colors.red.withValues(alpha: 0.90),
              ),
              onPressed: () {
                setState(
                  () => _setPestForPost(post: post, pestKey: pestKey, qty: 0),
                );
                _scheduleDraftSave();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ✅ MODIFICADO COMO PEDISTE AHORA:
  // - UN SOLO APARTADO de selección (una sola lista)
  // - Siempre primero FAVORITAS
  // - Botón "Otras" habilita mostrar NO favoritas debajo (sin quitar favoritas)
  // - Buscador SIEMPRE activo (filtra favoritas y no favoritas)
  // - La opción "Otra…" solo aparece al FINAL cuando "Otras" está abierto
  Future<void> _addOrEditPestDialog({
    required int post,
    String? presetPestKey,
    int? presetQty,
    bool? presetFoco,
  }) async {
    final accent = AppTheme.pepperGreen;

    final presetParsed = (presetPestKey == null)
        ? null
        : _parsePestKey(presetPestKey);

    String selectedName =
        presetParsed?.name ??
        (_pestsFavPlaga.isNotEmpty
            ? _pestsFavPlaga.first
            : (_pestsNonFav.isNotEmpty ? _pestsNonFav.first : _otherOption));
    String? selectedLevel = presetParsed?.level;

    bool othersOpen = false;
    if (presetParsed != null) {
      final nlc = presetParsed.name.trim().toLowerCase();
      final inFav = _pestsFavPlaga.any((p) => p.trim().toLowerCase() == nlc);
      final inNon = _pestsNonFav.any((p) => p.trim().toLowerCase() == nlc);
      if (!inFav && inNon) othersOpen = true;
    }

    final qtyCtrl = TextEditingController(text: (presetQty ?? 1).toString());
    final otherCtrl = TextEditingController();
    bool foco = presetFoco ?? false;

    final searchCtrl = TextEditingController();
    String query = '';

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

    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'pest_dialog',
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: StatefulBuilder(
                        builder: (ctx, setLocal) {
                          final fav = List<String>.from(_pestsFavPlaga)
                            ..sort(
                              (a, b) =>
                                  a.toLowerCase().compareTo(b.toLowerCase()),
                            );
                          final non = List<String>.from(_pestsNonFav)
                            ..sort(
                              (a, b) =>
                                  a.toLowerCase().compareTo(b.toLowerCase()),
                            );

                          final q = query.trim().toLowerCase();

                          final favFiltered = fav.where((p) {
                            if (q.isEmpty) return true;
                            return p.toLowerCase().contains(q);
                          }).toList();

                          final nonFiltered = non.where((p) {
                            if (q.isEmpty) return true;
                            return p.toLowerCase().contains(q);
                          }).toList();

                          // ✅ lista final: favoritas + (si otrasOpen) no favoritas + (si otrasOpen) Otra…
                          final items = <String>[
                            ...favFiltered,
                            if (othersOpen) ...nonFiltered,
                            if (othersOpen) _otherOption,
                          ];

                          // si lo seleccionado ya no existe en items, clamp a lo primero disponible
                          final selectedOk = selectedName == _otherOption
                              ? items.contains(_otherOption)
                              : items.any(
                                  (x) =>
                                      x.toLowerCase() ==
                                      selectedName.toLowerCase(),
                                );

                          if (!selectedOk) {
                            if (items.isNotEmpty) {
                              selectedName = items.first;
                            } else {
                              selectedName = _otherOption;
                              othersOpen = true; // para permitir escribir
                            }
                            selectedLevel = null;
                          }

                          final levels = (selectedName == _otherOption)
                              ? <String>[]
                              : _levelsForPest(selectedName);

                          if (levels.isNotEmpty) {
                            if (selectedLevel == null ||
                                !levels.contains(selectedLevel)) {
                              selectedLevel = levels.first;
                            }
                          } else {
                            selectedLevel = null;
                          }

                          final lvInt = int.tryParse(
                            (selectedLevel ?? '').trim(),
                          );
                          if (lvInt != null && lvInt >= 3) foco = true;

                          Widget itemTile(String label) {
                            final sel =
                                selectedName.toLowerCase() ==
                                label.toLowerCase();
                            final isOther = label == _otherOption;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: sel
                                    ? accent.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: sel
                                      ? accent.withValues(alpha: 0.25)
                                      : Colors.black.withValues(alpha: 0.10),
                                ),
                              ),
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  isOther
                                      ? Icons.edit_outlined
                                      : Icons.bug_report_outlined,
                                  color: sel
                                      ? accent
                                      : Colors.black.withValues(alpha: 0.55),
                                ),
                                title: Text(
                                  label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: sel
                                        ? accent
                                        : Colors.black.withValues(alpha: 0.85),
                                  ),
                                ),
                                trailing: sel
                                    ? Icon(Icons.check_rounded, color: accent)
                                    : null,
                                onTap: () => setLocal(() {
                                  selectedName = label;
                                  selectedLevel = null;
                                }),
                              ),
                            );
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
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: Icon(
                                          presetPestKey == null
                                              ? Icons.add_rounded
                                              : Icons.edit_rounded,
                                          color: accent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              presetPestKey == null
                                                  ? 'Agregar plaga'
                                                  : 'Editar plaga',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Poste $post • Favoritas primero',
                                              style: TextStyle(
                                                color: Colors.black.withValues(
                                                  alpha: 0.62,
                                                ),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Cerrar',
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // ✅ buscador SIEMPRE filtra TODO (fav y non)
                                TextField(
                                  controller: searchCtrl,
                                  onChanged: (v) => setLocal(() => query = v),
                                  decoration: deco(
                                    label: 'Buscar plaga',
                                    hint: 'Escribe el nombre…',
                                    icon: Icons.search_rounded,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // ✅ lista única (favoritas primero; otras solo si othersOpen)
                                SizedBox(
                                  height: 280,
                                  child: Scrollbar(
                                    thumbVisibility: true,
                                    child: ListView(
                                      children: [
                                        for (final it in items) itemTile(it),
                                        if (items.isEmpty)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.02,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: Colors.black.withValues(
                                                  alpha: 0.10,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              'Sin resultados.',
                                              style: TextStyle(
                                                color: Colors.black.withValues(
                                                  alpha: 0.65,
                                                ),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 10),

                                // ✅ botón Otras (solo abre/cierra, no quita favoritas)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => setLocal(
                                      () => othersOpen = !othersOpen,
                                    ),
                                    icon: Icon(
                                      Icons.layers_outlined,
                                      color: Colors.black.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                    label: Text(
                                      othersOpen ? 'Ocultar otras' : 'Otras',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black.withValues(
                                          alpha: 0.75,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                if (selectedName == _otherOption) ...[
                                  const SizedBox(height: 8),
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

                                if (selectedName != _otherOption &&
                                    levels.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    value: selectedLevel,
                                    decoration: deco(
                                      label: 'Nivel',
                                      icon: Icons.stairs_rounded,
                                    ),
                                    items: levels
                                        .map(
                                          (l) => DropdownMenuItem(
                                            value: l,
                                            child: Text(l),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      setLocal(() {
                                        selectedLevel = v;
                                        final lvInt = int.tryParse(
                                          (selectedLevel ?? '').trim(),
                                        );
                                        if (lvInt != null && lvInt >= 3)
                                          foco = true;
                                      });
                                    },
                                  ),
                                ],

                                const SizedBox(height: 12),
                                TextField(
                                  controller: qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  textInputAction: TextInputAction.done,
                                  decoration: deco(
                                    label: 'Cantidad',
                                    hint: 'Ej: 5',
                                    icon: Icons.numbers_rounded,
                                  ),
                                ),

                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (foco
                                        ? AppTheme.pepperRed.withValues(
                                            alpha: 0.08,
                                          )
                                        : Colors.black.withValues(alpha: 0.02)),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: (foco
                                          ? AppTheme.pepperRed.withValues(
                                              alpha: 0.30,
                                            )
                                          : Colors.black.withValues(
                                              alpha: 0.12,
                                            )),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.flash_on_rounded,
                                        color: foco
                                            ? AppTheme.pepperRed
                                            : Colors.black54,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '¿Requiere FOCO?',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: foco
                                                ? AppTheme.pepperRed
                                                : Colors.black.withValues(
                                                    alpha: 0.70,
                                                  ),
                                          ),
                                        ),
                                      ),
                                      Transform.scale(
                                        scale: 0.90,
                                        child: Switch.adaptive(
                                          value: foco,
                                          onChanged: (v) =>
                                              setLocal(() => foco = v),
                                          activeColor: AppTheme.pepperRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                        ),
                                        child: const Text('Cancelar'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
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
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );

    searchCtrl.dispose();

    if (ok != true) return;

    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;

    if (selectedName == _otherOption) {
      final created = await _createPestIfNeeded(otherCtrl.text);
      if (created == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escribe el nombre de la plaga.')),
        );
        return;
      }
      selectedName = created;
      selectedLevel = null;
    }

    final pestKey = _composePestKey(selectedName, selectedLevel);

    final lvInt = int.tryParse((selectedLevel ?? '').trim());
    final autoFoco = (lvInt != null && lvInt >= 3);

    setState(() {
      if (presetPestKey != null && presetPestKey != pestKey) {
        final hadFoco = _isFocusOn(post: post, pestKey: presetPestKey);
        _setPestForPost(post: post, pestKey: presetPestKey, qty: 0);
        if (hadFoco) _setFocus(post: post, pestKey: pestKey, on: true);
      }

      _setPestForPost(post: post, pestKey: pestKey, qty: qty);

      final finalFoco = (qty > 0) && (autoFoco || foco);
      _setFocus(post: post, pestKey: pestKey, on: finalFoco);
    });

    _scheduleDraftSave();
  }

  // ---------------- FINISH (OFFLINE FIRST) ----------------
  Future<void> _finishAndSaveOfflineFirst() async {
    final finishedAt = DateTime.now();

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay usuario autenticado.')),
      );
      return;
    }

    Map<String, dynamic> compactSideCounts(Map<int, Map<String, int>> src) {
      final out = <String, dynamic>{};
      src.forEach((poste, pests) {
        if (pests.isEmpty) return;

        final filtered = <String, int>{};
        pests.forEach((k, v) {
          if (v > 0) filtered[k] = v;
        });
        if (filtered.isNotEmpty) out[poste.toString()] = filtered;
      });
      return out;
    }

    Map<String, dynamic> compactSideFocus(Map<int, Set<String>> src) {
      final out = <String, dynamic>{};
      src.forEach((poste, keys) {
        if (keys.isEmpty) return;
        final m = <String, bool>{};
        for (final k in keys) {
          if (k.trim().isNotEmpty) m[k] = true;
        }
        if (m.isNotEmpty) out[poste.toString()] = m;
      });
      return out;
    }

    final left = compactSideCounts(_counts['L']!);
    final right = compactSideCounts(_counts['R']!);

    final totalsByPest = <String, int>{};

    void acc(Map<String, dynamic> side) {
      side.forEach((_, pestsAny) {
        final pests = Map<String, dynamic>.from(pestsAny as Map);
        pests.forEach((pest, v) {
          final n = (v is int) ? v : int.tryParse(v.toString()) ?? 0;
          if (n > 0) totalsByPest[pest] = (totalsByPest[pest] ?? 0) + n;
        });
      });
    }

    acc(left);
    acc(right);

    final totalFindings = totalsByPest.values.fold<int>(0, (a, b) => a + b);

    final weekKey = _isoWeekKey(finishedAt);
    final range = _isoWeekRange(finishedAt);
    final weekStart = range.$1;
    final weekEnd = range.$2;

    final offlineLinePayload = <String, dynamic>{
      'status': 'FINISHED',
      'byUid': uid,
      'startedAtMs': _startedAt.millisecondsSinceEpoch,
      'finishedAtMs': finishedAt.millisecondsSinceEpoch,
      'observations': {'left': left, 'right': right},
      'totalsByPest': totalsByPest,
      'totalFindings': totalFindings,
    };

    final focoLeft = compactSideFocus(_focus['L']!);
    final focoRight = compactSideFocus(_focus['R']!);

    if (focoLeft.isNotEmpty || focoRight.isNotEmpty) {
      final obs = Map<String, dynamic>.from(
        offlineLinePayload['observations'] as Map,
      );
      obs['focus'] = {
        if (focoLeft.isNotEmpty) 'left': focoLeft,
        if (focoRight.isNotEmpty) 'right': focoRight,
      };
      offlineLinePayload['observations'] = obs;
    }

    await OfflineSyncService.instance.enqueueFinishedLine(
      weekKey: weekKey,
      weekStart: weekStart,
      weekEnd: weekEnd,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _lineKey,
      offlineLinePayload: offlineLinePayload,
    );

    await OfflineSyncService.instance.clearDraft(
      weekKey: _weekKey,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _lineKey,
    );

    unawaited(OfflineSyncService.instance.flush());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Monitoreo guardado en el teléfono. Se subirá automáticamente al haber internet.',
        ),
      ),
    );
    Navigator.pop(context);
  }

  // ---------------- ISO week utils ----------------
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
    final firstWeekThursday = firstThursday.add(
      Duration(days: 3 - ((firstThursday.weekday + 6) % 7)),
    );
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

// ======================== UI Components (sin cambios) ========================

class _HeaderCard extends StatelessWidget {
  final Color accent;
  final String mapName;
  final String capName;
  final int lineNo;
  final String sideLabel;
  final String passLabel;

  const _HeaderCard({
    required this.accent,
    required this.mapName,
    required this.capName,
    required this.lineNo,
    required this.sideLabel,
    required this.passLabel,
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
                    Icon(
                      Icons.grid_view_rounded,
                      size: 16,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
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
                    Icon(Icons.view_week_outlined, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      'Línea $lineNo',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$sideLabel • $passLabel',
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
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.black.withValues(alpha: 0.70),
                ),
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

class _PostBadge extends StatelessWidget {
  final Color accent;
  final int postNo;

  const _PostBadge({required this.accent, required this.postNo});

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
          Icon(Icons.sensor_occupied_outlined, color: accent),
          const SizedBox(width: 10),
          Text(
            'Poste $postNo',
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
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
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

  const _SectionTitle({required this.accent, required this.title});

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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            label: Text(isLast ? 'Finalizar' : 'Avanzar'),
          ),
        ),
      ],
    );
  }
}

class _KeyboardOpenSlide extends StatefulWidget {
  final Widget child;
  const _KeyboardOpenSlide({required this.child});

  @override
  State<_KeyboardOpenSlide> createState() => _KeyboardOpenSlideState();
}

class _KeyboardOpenSlideState extends State<_KeyboardOpenSlide>
    with WidgetsBindingObserver {
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
