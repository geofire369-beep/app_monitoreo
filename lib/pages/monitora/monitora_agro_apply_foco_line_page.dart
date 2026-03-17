import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/mapa_model.dart';
import '../../../services/offline/offline_sync_service.dart';

const Color kAgroAccent = Color(0xFFF55000);
const Color kAgroAccentDark = Color(0xFFB63A00);

// ✅ Nuevo ámbar para etiquetas y textos secundarios
const Color kAgroAmber = Color(0xFFC47A00);
const Color kAgroAmberDark = Color(0xFF8F5600);

class MonitoraAgroApplyFocoLinePage extends StatefulWidget {
  final GreenhouseMap map;
  final CapillaDef capilla;
  final CapLine line;

  const MonitoraAgroApplyFocoLinePage({
    super.key,
    required this.map,
    required this.capilla,
    required this.line,
  });

  @override
  State<MonitoraAgroApplyFocoLinePage> createState() =>
      _MonitoraAgroApplyFocoLinePageState();
}

class _MonitoraAgroApplyFocoLinePageState
    extends State<MonitoraAgroApplyFocoLinePage> {
  static const Color _agroAccent = kAgroAccent;
  static const Color _agroAccentDark = kAgroAccentDark;
  static const Color _agroAmber = kAgroAmber;
  static const Color _agroAmberDark = kAgroAmberDark;

  final _fs = FirebaseFirestore.instance;

  late DateTime _startedAt;
  late final String _lineKey;
  late final String _capName;
  late final String _sideLabel;

  String _uid = '';
  String _userLabel = '';

  List<_AgroProdOpt> _products = const [];
  bool _loadingProducts = true;

  final Map<String, Map<int, Set<String>>> _foco = {
    'L': <int, Set<String>>{},
    'R': <int, Set<String>>{},
  };

  bool _rightPass = false;
  int _idx = 0;

  List<int> _leftTargets = const [];
  List<int> _rightTargets = const [];

  Timer? _draftDebounce;
  int _lastDraftFingerprint = 0;

  final Map<String, Map<int, Map<String, List<_AgroApp>>>> _apps = {
    'L': <int, Map<String, List<_AgroApp>>>{},
    'R': <int, Map<String, List<_AgroApp>>>{},
  };

  String get _weekKey => _isoWeekKey(DateTime.now());

  DocumentReference<Map<String, dynamic>> get _capDocRef => _fs
      .collection('monitoreo_weeks')
      .doc(_weekKey)
      .collection('greenhouses')
      .doc(widget.map.id)
      .collection('capillas')
      .doc(widget.capilla.id);

  String get _draftLineKey => 'AGRO_FOCO|$_lineKey';

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

    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _userLabel = _uid;

    _loadUserLabel();
    _loadProducts();
    Future.microtask(_restoreDraftIfAny);
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    super.dispose();
  }

  InputDecoration _dialogFieldDecoration({
    required String label,
    String? hint,
    required Color accent,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFFFF9F4),
      labelStyle: const TextStyle(
        color: _agroAmber,
        fontWeight: FontWeight.w800,
      ),
      floatingLabelStyle: const TextStyle(
        color: _agroAmberDark,
        fontWeight: FontWeight.w900,
      ),
      hintStyle: TextStyle(
        color: Colors.black.withValues(alpha: 0.42),
        fontWeight: FontWeight.w600,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.28)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      isDense: true,
    );
  }

  Future<void> _loadUserLabel() async {
    if (_uid.isEmpty) return;
    try {
      final d = await _fs.collection('app_users').doc(_uid).get();
      final m = d.data() ?? {};
      final fullName = (m['fullName'] ?? '').toString().trim();
      final first = (m['firstName'] ?? '').toString().trim();
      final last = (m['lastName'] ?? '').toString().trim();

      String name;
      if (fullName.isNotEmpty) {
        name = fullName;
      } else if (first.isNotEmpty || last.isNotEmpty) {
        name = ('$first $last').trim();
      } else {
        name = (m['name'] ?? m['displayName'] ?? m['email'] ?? _uid)
            .toString()
            .trim();
      }

      if (!mounted) return;
      setState(() => _userLabel = name.isEmpty ? _uid : name);
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final snap = await _fs.collection('productos').orderBy('nombre').get();
      final out = <_AgroProdOpt>[];

      for (final d in snap.docs) {
        final m = d.data();
        final nombre = (m['nombre'] ?? '').toString().trim();
        if (nombre.isEmpty) continue;
        out.add(
          _AgroProdOpt(
            id: d.id,
            nombre: nombre,
            tipo: (m['tipo'] ?? '').toString().trim(),
          ),
        );
      }

      out.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _products = out;
        _loadingProducts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _products = const [];
        _loadingProducts = false;
      });
    }
  }

  String get _sideKey => _rightPass ? 'R' : 'L';
  List<int> get _currentTargets => _rightPass ? _rightTargets : _leftTargets;

  bool _canGoBack() => !(!_rightPass && _idx == 0);
  bool _isLastOfThisPass() => _idx >= _currentTargets.length - 1;
  bool _hasRightTargets() => _rightTargets.isNotEmpty;
  bool _hasLeftTargets() => _leftTargets.isNotEmpty;

  bool _isLastOfLastPass() {
    if (_hasLeftTargets() && _hasRightTargets()) {
      return _rightPass && _isLastOfThisPass();
    }
    return _isLastOfThisPass();
  }

  void _goBack() {
    if (_idx > 0) {
      setState(() => _idx--);
      _scheduleDraftSave();
      return;
    }
    if (_rightPass && _hasLeftTargets()) {
      setState(() {
        _rightPass = false;
        _idx = _leftTargets.isEmpty ? 0 : (_leftTargets.length - 1);
      });
      _scheduleDraftSave();
    }
  }

  Future<void> _goNextOrTurn() async {
    if (!_isLastOfThisPass()) {
      setState(() => _idx++);
      _scheduleDraftSave();
      return;
    }

    if (!_rightPass && _hasLeftTargets() && _hasRightTargets()) {
      final ok = await _turnDialog();
      if (ok == true) {
        setState(() {
          _rightPass = true;
          _idx = 0;
        });
        _scheduleDraftSave();
      }
      return;
    }
  }

  Future<bool?> _turnDialog() async {
    final accent = _agroAccent;

    return showGeneralDialog<bool>(
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
                shadowColor: accent.withValues(alpha: 0.30),
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
                                foregroundColor: _agroAccentDark,
                                side: BorderSide(
                                  color: accent.withValues(alpha: 0.35),
                                ),
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
      transitionBuilder: (_, anim, _, child) {
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
  }

  Future<void> _restoreDraftIfAny() async {
    final draft = OfflineSyncService.instance.loadDraft(
      weekKey: _weekKey,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _draftLineKey,
    );
    if (draft == null) return;

    try {
      final startedAtMs = (draft['startedAtMs'] ?? 0) as int;
      final rightPass = (draft['rightPass'] ?? false) as bool;
      final idx = (draft['idx'] ?? 0) as int;

      final countsAny = draft['counts'];
      if (countsAny is Map) {
        final counts = Map<String, dynamic>.from(countsAny);

        _apps['L']!.clear();
        _apps['R']!.clear();

        final appsAny = counts['APPS'];
        if (appsAny is Map) {
          final apps = Map<String, dynamic>.from(appsAny);

          void readSide(String side) {
            final sideAny = apps[side];
            if (sideAny is! Map) return;
            final posts = Map<String, dynamic>.from(sideAny);

            posts.forEach((postStr, pestsAny) {
              final post = int.tryParse(postStr.toString()) ?? 0;
              if (post <= 0) return;
              if (pestsAny is! Map) return;
              final pests = Map<String, dynamic>.from(pestsAny);

              final outPests = <String, List<_AgroApp>>{};
              pests.forEach((pestKey, listAny) {
                if (listAny is! List) return;
                final list = <_AgroApp>[];
                for (final item in listAny) {
                  if (item is! Map) continue;
                  final m = Map<String, dynamic>.from(item);
                  list.add(_AgroApp.fromJson(m));
                }
                if (list.isNotEmpty) outPests[pestKey.toString()] = list;
              });

              if (outPests.isNotEmpty) _apps[side]![post] = outPests;
            });
          }

          readSide('L');
          readSide('R');
        }

        _foco['L']!.clear();
        _foco['R']!.clear();
        final focoAny = counts['FOCO'];
        if (focoAny is Map) {
          final foco = Map<String, dynamic>.from(focoAny);

          void readF(String side) {
            final sideAny = foco[side];
            if (sideAny is! Map) return;
            final posts = Map<String, dynamic>.from(sideAny);
            posts.forEach((postStr, listAny) {
              final post = int.tryParse(postStr.toString()) ?? 0;
              if (post <= 0) return;
              if (listAny is! List) return;
              final set = listAny
                  .map((e) => e.toString())
                  .where((e) => e.trim().isNotEmpty)
                  .toSet();
              if (set.isNotEmpty) _foco[side]![post] = set;
            });
          }

          readF('L');
          readF('R');
        }

        final restoredStartedAt = DateTime.fromMillisecondsSinceEpoch(
          startedAtMs > 0 ? startedAtMs : _startedAt.millisecondsSinceEpoch,
        );

        if (!mounted) return;
        setState(() {
          _startedAt = restoredStartedAt;
          _rightPass = rightPass;
          _idx = idx;
        });

        _recomputeTargets();
      }

      _lastDraftFingerprint = _computeDraftFingerprint();
    } catch (_) {}
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 500), () async {
      final fp = _computeDraftFingerprint();
      if (fp == _lastDraftFingerprint) return;
      _lastDraftFingerprint = fp;

      final countsJson = _draftToJson();
      await OfflineSyncService.instance.saveDraft(
        weekKey: _weekKey,
        greenhouseId: widget.map.id,
        capillaId: widget.capilla.id,
        lineKey: _draftLineKey,
        startedAtMs: _startedAt.millisecondsSinceEpoch,
        rightPass: _rightPass,
        idx: _idx,
        countsJson: countsJson,
      );
    });
  }

  int _computeDraftFingerprint() {
    var h = 17;
    h = 37 * h + _startedAt.millisecondsSinceEpoch.hashCode;
    h = 37 * h + (_rightPass ? 1 : 0);
    h = 37 * h + _idx;

    for (final side in const ['L', 'R']) {
      final posts = _foco[side]!;
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

    for (final side in const ['L', 'R']) {
      final posts = _apps[side]!;
      final postKeys = posts.keys.toList()..sort();
      for (final post in postKeys) {
        h = 37 * h + 77777;
        h = 37 * h + post;
        final pests = posts[post]!;
        final pestKeys = pests.keys.toList()..sort();
        for (final pest in pestKeys) {
          h = 37 * h + 77783;
          h = 37 * h + pest.hashCode;
          final list = pests[pest]!;
          h = 37 * h + list.length;
          for (final a in list) {
            h = 37 * h + a.hashFingerprint();
          }
        }
      }
    }

    return h;
  }

  Map<String, dynamic> _draftToJson() {
    final out = <String, dynamic>{};

    final focoOut = <String, dynamic>{};
    for (final side in const ['L', 'R']) {
      final sideOut = <String, dynamic>{};
      _foco[side]!.forEach((post, keys) {
        if (keys.isEmpty) return;
        sideOut[post.toString()] = (keys.toList()..sort());
      });
      focoOut[side] = sideOut;
    }
    out['FOCO'] = focoOut;

    final appsOut = <String, dynamic>{};
    for (final side in const ['L', 'R']) {
      final sideOut = <String, dynamic>{};
      _apps[side]!.forEach((post, pests) {
        final pestsOut = <String, dynamic>{};
        pests.forEach((pestKey, list) {
          if (list.isEmpty) return;
          pestsOut[pestKey] = list.map((e) => e.toJson()).toList();
        });
        if (pestsOut.isNotEmpty) sideOut[post.toString()] = pestsOut;
      });
      appsOut[side] = sideOut;
    }
    out['APPS'] = appsOut;

    return out;
  }

  void _recomputeTargets() {
    final leftPosts = _foco['L']!.keys.toList()..sort();
    final rightPosts = _foco['R']!.keys.toList()..sort();

    _leftTargets = leftPosts;
    _rightTargets = rightPosts.reversed.toList();

    if (_leftTargets.isEmpty && _rightTargets.isNotEmpty) {
      _rightPass = true;
    }
    if (_rightTargets.isEmpty && _leftTargets.isNotEmpty) {
      _rightPass = false;
    }

    final cur = _currentTargets;
    if (cur.isEmpty) {
      _idx = 0;
    } else {
      _idx = _idx.clamp(0, cur.length - 1);
    }
  }

  void _addLocalApp({
    required String side,
    required int post,
    required String pestKey,
    required _AgroProdOpt product,
    required String qtyText,
    required String tipoAplicacion,
  }) {
    final app = _AgroApp(
      id: _localId(),
      productId: product.id,
      productName: product.nombre,
      productTipo: product.tipo,
      qtyText: qtyText,
      tipoAplicacion: tipoAplicacion,
      appliedAtMs: DateTime.now().millisecondsSinceEpoch,
      appliedByUid: _uid,
      appliedByName: _userLabel,
    );

    _apps[side]!.putIfAbsent(post, () => <String, List<_AgroApp>>{});
    _apps[side]![post]!.putIfAbsent(pestKey, () => <_AgroApp>[]);
    _apps[side]![post]![pestKey]!.add(app);
  }

  // ========================= NUEVO (solo para Apps registradas): editar/eliminar =========================

  Future<void> _editAppDialog({
    required String side,
    required int post,
    required String pestKey,
    required _AgroApp app,
  }) async {
    final accent = _agroAccent;

    if (_loadingProducts) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cargando productos…')),
      );
      return;
    }
    if (_products.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos en catálogo.')),
      );
      return;
    }

    // intentar preseleccionar producto actual
    _AgroProdOpt selectedProduct = _products.first;
    final match = _products.where((p) => p.id == app.productId).toList();
    if (match.isNotEmpty) selectedProduct = match.first;

    final qtyCtrl = TextEditingController(text: app.qtyText);
    String tipoAplicacion = app.tipoAplicacion.trim().isEmpty
        ? 'Aspersión'
        : app.tipoAplicacion.trim();

    const tipoOptions = <String>[
      'Aspersión',
      'Drench',
      'Fertirriego',
      'Nebulización',
      'Otro',
    ];
    if (!tipoOptions.contains(tipoAplicacion)) tipoAplicacion = 'Otro';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFCFA),
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Icon(Icons.edit_rounded, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Editar aplicación',
                style: const TextStyle(
                  color: _agroAccentDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: StatefulBuilder(
          builder: (ctx, setLocal) {
            return SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _miniInfo(
                      accent: accent,
                      capName: _capName,
                      lineNo: widget.line.lineNo,
                      sideLabel: _sideLabel,
                      post: post,
                      passSideLabel: side == "L"
                          ? "Izquierda (L)"
                          : "Derecha (R)",
                      pestLabel: _pestPretty(pestKey),
                      userLabel: _userLabel.isEmpty ? _uid : _userLabel,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<_AgroProdOpt>(
                      initialValue: selectedProduct,
                      iconEnabledColor: _agroAmberDark,
                      dropdownColor: Colors.white,
                      decoration: _dialogFieldDecoration(
                        label: 'Producto aplicado',
                        accent: accent,
                      ),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      items: _products
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                p.tipo.isEmpty
                                    ? p.nombre
                                    : '${p.nombre} (${p.tipo})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(
                        () => selectedProduct = v ?? selectedProduct,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      decoration: _dialogFieldDecoration(
                        label: 'Cantidad aplicada',
                        hint: 'Ej: 50 ml, 2 L, 1.5 lt',
                        accent: accent,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: tipoAplicacion,
                      iconEnabledColor: _agroAmberDark,
                      dropdownColor: Colors.white,
                      decoration: _dialogFieldDecoration(
                        label: 'Tipo de aplicación',
                        accent: accent,
                      ),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      items: tipoOptions
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setLocal(() => tipoAplicacion = v ?? tipoAplicacion),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TextStyle(
                color: _agroAccentDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Guardar',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final qtyText = qtyCtrl.text.trim();
    if (qtyText.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad obligatoria.')),
      );
      return;
    }

    setState(() {
      final list = _apps[side]?[post]?[pestKey];
      if (list == null) return;

      final idx = list.indexWhere((x) => x.id == app.id);
      if (idx < 0) return;

      list[idx] = app.copyWith(
        productId: selectedProduct.id,
        productName: selectedProduct.nombre,
        productTipo: selectedProduct.tipo,
        qtyText: qtyText,
        tipoAplicacion: tipoAplicacion,
      );
    });

    _scheduleDraftSave();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _agroAccentDark,
        content: const Text('Aplicación actualizada ✅'),
      ),
    );
  }

  Future<void> _deleteAppConfirm({
    required String side,
    required int post,
    required String pestKey,
    required _AgroApp app,
  }) async {
    final accent = _agroAccent;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFCFA),
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.withValues(alpha: 0.18)),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Eliminar aplicación',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '¿Seguro que quieres eliminar esta aplicación?\n\n'
          '${_pestPretty(pestKey)}\n'
          '${app.productTipo.trim().isEmpty ? app.productName : '${app.productName} (${app.productTipo})'}\n'
          'Cant: ${app.qtyText} • ${app.tipoAplicacion}',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.72),
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TextStyle(
                color: _agroAccentDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      final postMap = _apps[side]?[post];
      if (postMap == null) return;

      final list = postMap[pestKey];
      if (list == null) return;

      list.removeWhere((x) => x.id == app.id);

      if (list.isEmpty) {
        postMap.remove(pestKey);
      }
      if (postMap.isEmpty) {
        _apps[side]!.remove(post);
      }
    });

    _scheduleDraftSave();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: accent,
        content: const Text('Aplicación eliminada ✅'),
      ),
    );
  }

  // ========================= FIN NUEVO =========================

  String _localId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _pestPretty(String pestKey) {
    final raw = pestKey.trim();
    final idx = raw.lastIndexOf('|');
    if (idx <= 0) return raw;
    final name = raw.substring(0, idx).trim();
    final level = raw.substring(idx + 1).trim();
    if (name.isEmpty || level.isEmpty) return raw;
    return '$name - $level';
  }

  Future<void> _addApplicationDialog({
    required int post,
    required String side,
    required Set<String> pestKeys,
  }) async {
    final accent = _agroAccent;

    if (_loadingProducts) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cargando productos…')));
      return;
    }
    if (_products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos en catálogo.')),
      );
      return;
    }
    if (pestKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este punto no tiene plagas FOCO.')),
      );
      return;
    }

    String selectedPestKey = (pestKeys.toList()..sort()).first;
    _AgroProdOpt selectedProduct = _products.first;
    final qtyCtrl = TextEditingController(text: '50 ml');

    String tipoAplicacion = 'Aspersión';
    const tipoOptions = <String>[
      'Aspersión',
      'Drench',
      'Fertirriego',
      'Nebulización',
      'Otro',
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFCFA),
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Icon(Icons.edit_note_rounded, color: accent),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Registrar aplicación (FOCO)',
                style: TextStyle(
                  color: _agroAccentDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: StatefulBuilder(
          builder: (ctx, setLocal) {
            return SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _miniInfo(
                      accent: accent,
                      capName: _capName,
                      lineNo: widget.line.lineNo,
                      sideLabel: _sideLabel,
                      post: post,
                      passSideLabel:
                          side == "L" ? "Izquierda (L)" : "Derecha (R)",
                      pestLabel: _pestPretty(selectedPestKey),
                      userLabel: _userLabel.isEmpty ? _uid : _userLabel,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPestKey,
                      iconEnabledColor: _agroAmberDark,
                      dropdownColor: Colors.white,
                      decoration: _dialogFieldDecoration(
                        label: 'Plaga (FOCO)',
                        accent: accent,
                      ),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      items: (pestKeys.toList()..sort()).map((k) {
                        return DropdownMenuItem(
                          value: k,
                          child: Text(_pestPretty(k)),
                        );
                      }).toList(),
                      onChanged: (v) =>
                          setLocal(() => selectedPestKey = v ?? selectedPestKey),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<_AgroProdOpt>(
                      initialValue: selectedProduct,
                      iconEnabledColor: _agroAmberDark,
                      dropdownColor: Colors.white,
                      decoration: _dialogFieldDecoration(
                        label: 'Producto aplicado',
                        accent: accent,
                      ),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      items: _products
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                p.tipo.isEmpty
                                    ? p.nombre
                                    : '${p.nombre} (${p.tipo})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(
                        () => selectedProduct = v ?? selectedProduct,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      decoration: _dialogFieldDecoration(
                        label: 'Cantidad aplicada',
                        hint: 'Ej: 50 ml, 2 L, 1.5 lt',
                        accent: accent,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: tipoAplicacion,
                      iconEnabledColor: _agroAmberDark,
                      dropdownColor: Colors.white,
                      decoration: _dialogFieldDecoration(
                        label: 'Tipo de aplicación',
                        accent: accent,
                      ),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                      items: tipoOptions
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(
                        () => tipoAplicacion = v ?? tipoAplicacion,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7EF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.cloud_done_outlined,
                            size: 18,
                            color: _agroAmberDark,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Se guarda offline primero. Al finalizar, se sube automáticamente cuando haya internet.',
                              style: TextStyle(
                                color: Colors.black.withValues(alpha: 0.72),
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: TextStyle(
                color: _agroAccentDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Guardar',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final qtyText = qtyCtrl.text.trim();
    if (qtyText.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad obligatoria.')),
      );
      return;
    }

    setState(() {
      _addLocalApp(
        side: side,
        post: post,
        pestKey: selectedPestKey,
        product: selectedProduct,
        qtyText: qtyText,
        tipoAplicacion: tipoAplicacion,
      );
    });

    _scheduleDraftSave();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _agroAccentDark,
        content: const Text('Aplicación guardada en el teléfono ✅'),
      ),
    );
  }

  Widget _miniInfo({
    required Color accent,
    required String capName,
    required int lineNo,
    required String sideLabel,
    required int post,
    required String passSideLabel,
    required String pestLabel,
    required String userLabel,
  }) {
    Widget infoRow({
      required IconData icon,
      required String label,
      required String value,
      bool emphasize = false,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.85),
                  fontSize: 14.5,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                      color: _agroAmberDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontWeight: emphasize ? FontWeight.w900 : FontWeight.w800,
                      color: Colors.black.withValues(alpha: 0.80),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFFFFF7F1), const Color(0xFFFFF1E7)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Icon(Icons.fact_check_outlined, color: accent),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Resumen del registro',
                  style: TextStyle(
                    color: _agroAccentDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 16.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          infoRow(
            icon: Icons.grid_view_rounded,
            label: 'Ubicación',
            value: '$capName • Línea $lineNo ($sideLabel)',
          ),
          const SizedBox(height: 10),
          infoRow(
            icon: Icons.place_outlined,
            label: 'Punto',
            value: 'Poste $post • Lado $passSideLabel',
          ),
          const SizedBox(height: 10),
          infoRow(
            icon: Icons.bug_report_outlined,
            label: 'Aplicará a',
            value: pestLabel,
            emphasize: true,
          ),
          const SizedBox(height: 10),
          infoRow(
            icon: Icons.person_outline_rounded,
            label: 'Responsable',
            value: userLabel,
          ),
          const SizedBox(height: 10),
          infoRow(icon: Icons.today_outlined, label: 'Fecha', value: 'Hoy'),
        ],
      ),
    );
  }

  Future<void> _finishAndEnqueueOffline() async {
    final finishedAt = DateTime.now();

    if (_uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay usuario autenticado.')),
      );
      return;
    }

    Map<String, dynamic> appsToJsonSide(
      Map<int, Map<String, List<_AgroApp>>> src,
    ) {
      final out = <String, dynamic>{};
      src.forEach((post, pests) {
        final pestsOut = <String, dynamic>{};
        pests.forEach((pestKey, list) {
          if (list.isEmpty) return;
          pestsOut[pestKey] = list.map((e) => e.toJson()).toList();
        });
        if (pestsOut.isNotEmpty) out[post.toString()] = pestsOut;
      });
      return out;
    }

    final offline = <String, dynamic>{
      'status': 'FINISHED',
      'byUid': _uid,
      'byName': _userLabel,
      'startedAtMs': _startedAt.millisecondsSinceEpoch,
      'finishedAtMs': finishedAt.millisecondsSinceEpoch,
      'updatedAtMs': finishedAt.millisecondsSinceEpoch,
      'agroFoco': {
        'focus': {
          'L': appsToJsonSide(_apps['L']!),
          'R': appsToJsonSide(_apps['R']!),
        },
      },
    };

    final wk = _isoWeekKey(finishedAt);
    final range = _isoWeekRange(finishedAt);
    final weekStart = range.$1;
    final weekEnd = range.$2;

    await OfflineSyncService.instance.enqueueFinishedAgroFocoLine(
      weekKey: wk,
      weekStart: weekStart,
      weekEnd: weekEnd,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _lineKey,
      offlineAgroFocoLinePayload: offline,
    );

    await OfflineSyncService.instance.clearDraft(
      weekKey: _weekKey,
      greenhouseId: widget.map.id,
      capillaId: widget.capilla.id,
      lineKey: _draftLineKey,
    );

    unawaited(OfflineSyncService.instance.flush());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _agroAccentDark,
        content: const Text(
          'Aplicación guardada en el teléfono. Se subirá al haber internet.',
        ),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _agroAccent;

    final bg = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.14),
            const Color(0xFFFFF7F2),
            Colors.white,
          ],
        ),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('Aplicación a FOCO'),
        elevation: 0,
      ),
      body: RepaintBoundary(
        child: Stack(
          children: [
            Positioned.fill(child: bg),
            SafeArea(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _capDocRef.snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: accent),
                    );
                  }

                  final capDoc = snap.data!.data() ?? {};
                  _readFocoFromCapDoc(capDoc);

                  _recomputeTargets();

                  if (_currentTargets.isEmpty) {
                    return Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 560),
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFCFA),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.14),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.08),
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
                                Icons.flash_on_rounded,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No hay puntos con FOCO en esta línea.\n(Verifica observations.focus en esta semana.)',
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.70),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (_idx >= _currentTargets.length) {
                    _idx = _currentTargets.length - 1;
                  }

                  final passLabel = _rightPass ? 'Derecha' : 'Izquierda';
                  final currentPost = _currentTargets[_idx];
                  final pestKeys = _foco[_sideKey]?[currentPost] ?? <String>{};

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
                    total: _currentTargets.length,
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
                      onPressed: () => _addApplicationDialog(
                        post: currentPost,
                        side: _sideKey,
                        pestKeys: pestKeys,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        'Registrar aplicación',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
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
                              backgroundColor: _agroAccentDark,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            onPressed: _finishAndEnqueueOffline,
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                            ),
                            label: const Text(
                              'Finalizar aplicación',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink();

                  final listCard = Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFCFA),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.08),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _AppsListForPoint(
                          accent: accent,
                          post: currentPost,
                          side: _sideKey,
                          pestKeys: pestKeys,
                          apps: _apps[_sideKey]?[currentPost] ??
                              const <String, List<_AgroApp>>{},
                          pestPretty: _pestPretty,

                          // ✅✅✅ SOLO CAMBIO PEDIDO: botones Editar/Eliminar en cada app
                          onEdit: (pestKey, app) => _editAppDialog(
                            side: _sideKey,
                            post: currentPost,
                            pestKey: pestKey,
                            app: app,
                          ),
                          onDelete: (pestKey, app) => _deleteAppConfirm(
                            side: _sideKey,
                            post: currentPost,
                            pestKey: pestKey,
                            app: app,
                          ),
                        ),
                      ),
                    ),
                  );

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final isWide = c.maxWidth >= 900;

                        final leftColumn = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            header,
                            const SizedBox(height: 12),
                            progress,
                            const SizedBox(height: 14),
                            Center(child: postBadge),
                            const SizedBox(height: 12),
                            _FocoPestsCard(
                              accent: accent,
                              sideLabel:
                                  _sideKey == 'L' ? 'Izquierda (L)' : 'Derecha (R)',
                              pestKeys: pestKeys,
                              pestPretty: _pestPretty,
                            ),
                            const SizedBox(height: 12),
                            addButton,
                            const SizedBox(height: 12),
                            navigation,
                            const SizedBox(height: 10),
                            finishButton,
                          ],
                        );

                        final rightColumn = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionTitle(
                              accent: accent,
                              title: 'Aplicaciones registradas',
                            ),
                            const SizedBox(height: 10),
                            listCard,
                          ],
                        );

                        return isWide
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
                              );
                      },
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

  void _readFocoFromCapDoc(Map<String, dynamic> capDoc) {
    _foco['L']!.clear();
    _foco['R']!.clear();

    final linesAny = capDoc['lines'];
    if (linesAny is! Map) return;
    final lines = Map<String, dynamic>.from(linesAny);

    final lineAny = lines[_lineKey];
    if (lineAny is! Map) return;
    final line = Map<String, dynamic>.from(lineAny);

    final obsAny = line['observations'];
    if (obsAny is! Map) return;
    final obs = Map<String, dynamic>.from(obsAny);

    final focusAny = obs['focus'];
    if (focusAny is! Map) return;
    final focus = Map<String, dynamic>.from(focusAny);

    Map<int, Set<String>> parseSide(Object? sideAny) {
      final out = <int, Set<String>>{};
      if (sideAny is! Map) return out;

      final sideMap = Map<String, dynamic>.from(sideAny);
      sideMap.forEach((postStr, pestsAny) {
        final post = int.tryParse(postStr.toString()) ?? 0;
        if (post <= 0) return;
        if (pestsAny is! Map) return;

        final pests = Map<String, dynamic>.from(pestsAny);
        final keys = <String>{};
        pests.forEach((pestKey, v) {
          final isTrue = (v is bool && v) || (v?.toString() == 'true');
          if (isTrue) keys.add(pestKey.toString());
        });
        if (keys.isNotEmpty) out[post] = keys;
      });

      return out;
    }

    final left = parseSide(focus['left']);
    final right = parseSide(focus['right']);

    _foco['L']!.addAll(left);
    _foco['R']!.addAll(right);
  }

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

class _AgroProdOpt {
  final String id;
  final String nombre;
  final String tipo;

  const _AgroProdOpt({
    required this.id,
    required this.nombre,
    required this.tipo,
  });
}

class _AgroApp {
  final String id;
  final String productId;
  final String productName;
  final String productTipo;
  final String qtyText;
  final String tipoAplicacion;
  final int appliedAtMs;
  final String appliedByUid;
  final String appliedByName;

  const _AgroApp({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productTipo,
    required this.qtyText,
    required this.tipoAplicacion,
    required this.appliedAtMs,
    required this.appliedByUid,
    required this.appliedByName,
  });

  _AgroApp copyWith({
    String? productId,
    String? productName,
    String? productTipo,
    String? qtyText,
    String? tipoAplicacion,
  }) {
    return _AgroApp(
      id: id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productTipo: productTipo ?? this.productTipo,
      qtyText: qtyText ?? this.qtyText,
      tipoAplicacion: tipoAplicacion ?? this.tipoAplicacion,
      appliedAtMs: appliedAtMs,
      appliedByUid: appliedByUid,
      appliedByName: appliedByName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'productName': productName,
        'productTipo': productTipo,
        'qtyText': qtyText,
        'tipoAplicacion': tipoAplicacion,
        'appliedAtMs': appliedAtMs,
        'appliedByUid': appliedByUid,
        'appliedByName': appliedByName,
      };

  static _AgroApp fromJson(Map<String, dynamic> m) {
    return _AgroApp(
      id: (m['id'] ?? '').toString(),
      productId: (m['productId'] ?? '').toString(),
      productName: (m['productName'] ?? '').toString(),
      productTipo: (m['productTipo'] ?? '').toString(),
      qtyText: (m['qtyText'] ?? m['qty'] ?? '').toString(),
      tipoAplicacion: (m['tipoAplicacion'] ?? '').toString(),
      appliedAtMs: (m['appliedAtMs'] is int)
          ? (m['appliedAtMs'] as int)
          : int.tryParse('${m['appliedAtMs']}') ?? 0,
      appliedByUid: (m['appliedByUid'] ?? '').toString(),
      appliedByName: (m['appliedByName'] ?? '').toString(),
    );
  }

  int hashFingerprint() {
    var h = 17;
    h = 37 * h + id.hashCode;
    h = 37 * h + productId.hashCode;
    h = 37 * h + productName.hashCode;
    h = 37 * h + qtyText.hashCode;
    h = 37 * h + tipoAplicacion.hashCode;
    h = 37 * h + appliedAtMs.hashCode;
    return h;
  }
}

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
        color: const Color(0xFFFFFCFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
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
            child: Icon(Icons.local_pharmacy_outlined, color: accent),
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
                        '$capName • Línea $lineNo',
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
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.20)),
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
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: kAgroAccentDark,
                      ),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: kAgroAccentDark,
                  ),
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
              color: kAgroAccentDark,
            ),
          ),
        ],
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
          style: TextStyle(fontWeight: FontWeight.w900, color: kAgroAccentDark),
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
              foregroundColor: kAgroAccentDark,
              side: BorderSide(color: accent.withValues(alpha: 0.32)),
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

class _FocoPestsCard extends StatelessWidget {
  final Color accent;
  final String sideLabel;
  final Set<String> pestKeys;
  final String Function(String) pestPretty;

  const _FocoPestsCard({
    required this.accent,
    required this.sideLabel,
    required this.pestKeys,
    required this.pestPretty,
  });

  @override
  Widget build(BuildContext context) {
    final keys = pestKeys.toList()..sort();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FOCO • $sideLabel',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: kAgroAccentDark,
            ),
          ),
          const SizedBox(height: 8),
          if (keys.isEmpty)
            Text(
              'Sin plagas con FOCO.',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.70),
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in keys)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flash_on_rounded, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          pestPretty(k),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AppsListForPoint extends StatelessWidget {
  final Color accent;
  final int post;
  final String side;
  final Set<String> pestKeys;
  final Map<String, List<_AgroApp>> apps;
  final String Function(String) pestPretty;

  // ✅ NUEVO: callbacks para editar/eliminar (solo UI de apps registradas)
  final void Function(String pestKey, _AgroApp app)? onEdit;
  final void Function(String pestKey, _AgroApp app)? onDelete;

  const _AppsListForPoint({
    required this.accent,
    required this.post,
    required this.side,
    required this.pestKeys,
    required this.apps,
    required this.pestPretty,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final keys = pestKeys.toList()..sort();

    final anyApps = keys.any((k) => (apps[k] ?? const <_AgroApp>[]).isNotEmpty);
    if (!anyApps) {
      return Center(
        child: Text(
          'Sin aplicaciones registradas aquí.',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.65),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final pestKey = keys[i];
        final list = apps[pestKey] ?? const <_AgroApp>[];
        if (list.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F4),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kAgroAccent.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pestPretty(pestKey),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: kAgroAccentDark,
                  ),
                ),
                const SizedBox(height: 10),
                for (final a in list) ...[
                  _AppTile(
                    accent: accent,
                    app: a,

                    // ✅ botones edit/delete a la derecha
                    onEdit: onEdit == null ? null : () => onEdit!(pestKey, a),
                    onDelete:
                        onDelete == null ? null : () => onDelete!(pestKey, a),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppTile extends StatelessWidget {
  final Color accent;
  final _AgroApp app;

  // ✅ NUEVO: acciones a la derecha
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _AppTile({
    required this.accent,
    required this.app,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dt = (app.appliedAtMs > 0)
        ? DateTime.fromMillisecondsSinceEpoch(app.appliedAtMs)
        : null;
    final dateText = (dt == null)
        ? '—'
        : '${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")} '
            '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';

    final prod = app.productTipo.trim().isEmpty
        ? app.productName
        : '${app.productName} (${app.productTipo})';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kAgroAccent.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.science_outlined, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prod, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  'Cant: ${app.qtyText} • ${app.tipoAplicacion}',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fecha: $dateText • Por: ${app.appliedByName.isEmpty ? app.appliedByUid : app.appliedByName}',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // ✅✅✅ SOLO LO PEDIDO: botones a la derecha para corregir errores
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Editar',
                onPressed: onEdit,
                icon: Icon(Icons.edit_rounded, color: accent),
              ),
              IconButton(
                tooltip: 'Eliminar',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}