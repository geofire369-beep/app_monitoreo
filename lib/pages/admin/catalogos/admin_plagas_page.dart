// lib/pages/admin/plagas/admin_plagas_page.dart
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';

class AdminPlagasPage extends StatefulWidget {
  const AdminPlagasPage({super.key});

  @override
  State<AdminPlagasPage> createState() => _AdminPlagasPageState();
}

class _AdminPlagasPageState extends State<AdminPlagasPage> {
  final _fs = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _fs.collection('plagas');

  static const String _bgAsset = 'assets/images/fondos.png';

  static const String _favTrapField = 'favTrap';
  static const String _favPlagaField = 'favPlaga';

  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _searchExpanded = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _match(Map<String, dynamic> data) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;

    final nombre = (data['nombre'] ?? '').toString().toLowerCase();
    final nivelesAny = data['niveles'];
    final niveles = (nivelesAny is List)
        ? nivelesAny.map((e) => e.toString().toLowerCase()).join(' ')
        : '';
    final tipo = (data['tipo'] ?? '').toString().toLowerCase();

    return nombre.contains(q) || niveles.contains(q) || tipo.contains(q);
  }

  void _toastPro(
    String msg, {
    required Color tint,
    IconData icon = Icons.check_circle_rounded,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(milliseconds: 1800),
        content: _ToastCard(accent: tint, icon: icon, message: msg),
      ),
    );
  }

  Future<void> _toggleFavorite({
    required String docId,
    required String field,
    required bool current,
  }) async {
    try {
      await _col.doc(docId).set({field: !current}, SetOptions(merge: true));

      final isTrap = field == _favTrapField;
      final activated = !current;

      _toastPro(
        activated
            ? 'Favorito guardado en ${isTrap ? "Trampa" : "Plaga"}'
            : 'Favorito quitado de ${isTrap ? "Trampa" : "Plaga"}',
        tint: activated ? const Color(0xFF0E8A63) : const Color(0xFFB85C00),
        icon: activated ? Icons.star_rounded : Icons.star_border_rounded,
      );
    } catch (_) {
      _toastPro(
        'No se pudo actualizar favorito',
        tint: const Color(0xFFC62828),
        icon: Icons.error_rounded,
      );
      rethrow;
    }
  }

  void _toggleSearch() {
    setState(() {
      _searchExpanded = !_searchExpanded;
      if (!_searchExpanded) {
        _searchCtrl.clear();
        _q = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Plagas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _bgAsset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accent.withValues(alpha: 0.12),
                      const Color(0xFFF7F7F7),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0.88),
                    Colors.white.withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.transparent),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  _CatalogTopInfo(
                    accent: accent,
                    searching: _q.trim().isNotEmpty,
                    searchText: _q.trim(),
                    searchExpanded: _searchExpanded,
                    controller: _searchCtrl,
                    onSearchTap: _toggleSearch,
                    onSearchChanged: (v) => setState(() => _q = v),
                    onSearchClose: _toggleSearch,
                    onNewTap: () => _openEditor(context),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _col.orderBy('nombre').snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return Center(
                            child: CircularProgressIndicator(color: accent),
                          );
                        }

                        final docs = snap.data!.docs
                            .where((d) => _match(d.data()))
                            .toList();

                        if (docs.isEmpty) {
                          return _EmptyPro(
                            accent: accent,
                            title: _q.trim().isEmpty
                                ? 'Sin registros'
                                : 'Sin resultados',
                            subtitle: _q.trim().isEmpty
                                ? 'Aún no hay plagas/enfermedades en el catálogo.'
                                : 'No hay coincidencias con tu búsqueda.',
                          );
                        }

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = 1;
                            double childAspectRatio = 2.10;

                            if (constraints.maxWidth >= 1320) {
                              crossAxisCount = 4;
                              childAspectRatio = 1.62;
                            } else if (constraints.maxWidth >= 980) {
                              crossAxisCount = 3;
                              childAspectRatio = 1.56;
                            } else if (constraints.maxWidth >= 650) {
                              crossAxisCount = 2;
                              childAspectRatio = 1.72;
                            }

                            return GridView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: childAspectRatio,
                                  ),
                              itemCount: docs.length,
                              itemBuilder: (context, i) {
                                final d = docs[i];
                                final data = d.data();

                                final nombre = (data['nombre'] ?? '')
                                    .toString()
                                    .trim();
                                final tipo = (data['tipo'] ?? 'PLAGA')
                                    .toString()
                                    .trim()
                                    .toUpperCase();

                                final nivelesAny = data['niveles'];
                                final niveles = (nivelesAny is List)
                                    ? nivelesAny
                                          .map((e) => e.toString())
                                          .where((x) => x.trim().isNotEmpty)
                                          .toList()
                                    : <String>[];

                                final favTrap = (data[_favTrapField] == true);
                                final favPlaga = (data[_favPlagaField] == true);

                                return _PlagaCardCatalogCompact(
                                  accent: accent,
                                  nombre: nombre.isEmpty
                                      ? '(Sin nombre)'
                                      : nombre,
                                  tipo: tipo,
                                  niveles: niveles,
                                  favTrap: favTrap,
                                  favPlaga: favPlaga,
                                  onToggleFavTrap: () => _toggleFavorite(
                                    docId: d.id,
                                    field: _favTrapField,
                                    current: favTrap,
                                  ),
                                  onToggleFavPlaga: () => _toggleFavorite(
                                    docId: d.id,
                                    field: _favPlagaField,
                                    current: favPlaga,
                                  ),
                                  onEdit: () => _openEditor(
                                    context,
                                    docId: d.id,
                                    initial: data,
                                  ),
                                  onDelete: () => _confirmDelete(
                                    context,
                                    docId: d.id,
                                    nombre: nombre,
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context, {
    required String docId,
    required String nombre,
  }) async {
    final accent = AppTheme.pepperRed;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar'),
        content: Text(
          '¿Seguro que quieres eliminar "${nombre.isEmpty ? "este registro" : nombre}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final overlay = _SavingOverlay.show(context, text: "Eliminando registro");

    try {
      await _col.doc(docId).delete();
      overlay.done(doneText: "Eliminado");
      _toastPro(
        "Registro eliminado",
        tint: const Color(0xFFB71C1C),
        icon: Icons.delete_rounded,
      );
    } catch (_) {
      overlay.done(success: false, doneText: "No se pudo eliminar");
      rethrow;
    }
  }

  Future<void> _openEditor(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? initial,
  }) async {
    final res = await showGeneralDialog<_PlagaPayload?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'plaga_editor',
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) =>
          _PlagaEditorDialogPro(accent: AppTheme.pepperRed, initial: initial),
      transitionBuilder: (context, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (res == null) return;

    final overlay = _SavingOverlay.show(
      context,
      text: (docId == null) ? "Guardando cambios" : "Actualizando registro",
    );

    try {
      final payload = <String, dynamic>{
        'nombre': res.nombre.trim(),
        'tipo': res.tipo.trim().toUpperCase(),
        'niveles': res.niveles
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      };

      if (docId == null) {
        payload[_favTrapField] = false;
        payload[_favPlagaField] = false;
      }

      if (docId == null) {
        await _col.add(payload);
        overlay.done(doneText: "Guardado");
        _toastPro(
          "Registro guardado",
          tint: const Color(0xFF0E8A63),
          icon: Icons.check_circle_rounded,
        );
      } else {
        await _col.doc(docId).set(payload, SetOptions(merge: true));
        overlay.done(doneText: "Actualizado");
        _toastPro(
          "Registro actualizado",
          tint: const Color(0xFF1565C0),
          icon: Icons.auto_awesome_rounded,
        );
      }
    } catch (_) {
      overlay.done(success: false, doneText: "No se pudo guardar");
      rethrow;
    }
  }
}

class _CatalogTopInfo extends StatelessWidget {
  final Color accent;
  final bool searching;
  final String searchText;

  final bool searchExpanded;
  final TextEditingController controller;
  final VoidCallback onSearchTap;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClose;
  final VoidCallback onNewTap;

  const _CatalogTopInfo({
    required this.accent,
    required this.searching,
    required this.searchText,
    required this.searchExpanded,
    required this.controller,
    required this.onSearchTap,
    required this.onSearchChanged,
    required this.onSearchClose,
    required this.onNewTap,
  });

  @override
  Widget build(BuildContext context) {
    return _NeoCard(
      radius: 22,
      glowColor: accent.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _AccentIcon(
              accent: accent,
              icon: Icons.bug_report_outlined,
              size: 46,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Catálogo de plagas y enfermedades',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    searching
                        ? 'Mostrando resultados para "$searchText".'
                        : 'Vista compacta en tarjetas con favoritos y acciones rápidas.',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.62),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: searchExpanded ? 320 : 44,
              height: 44,
              child: searchExpanded
                  ? _CompactSearchInCard(
                      accent: accent,
                      controller: controller,
                      onChanged: onSearchChanged,
                      onClose: onSearchClose,
                    )
                  : Material(
                      color: Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: onSearchTap,
                        child: Icon(
                          Icons.search_rounded,
                          color: accent,
                          size: 21,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onNewTap,
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Nueva',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactSearchInCard extends StatelessWidget {
  final Color accent;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _CompactSearchInCard({
    required this.accent,
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              autofocus: true,
              cursorColor: accent,
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.82),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                hintText: 'Buscar...',
                hintStyle: TextStyle(
                  color: Colors.black.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Icon(
              Icons.close_rounded,
              color: Colors.black.withValues(alpha: 0.55),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlagaCardCatalogCompact extends StatelessWidget {
  final Color accent;
  final String nombre;
  final String tipo;
  final List<String> niveles;

  final bool favTrap;
  final bool favPlaga;
  final VoidCallback onToggleFavTrap;
  final VoidCallback onToggleFavPlaga;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PlagaCardCatalogCompact({
    required this.accent,
    required this.nombre,
    required this.tipo,
    required this.niveles,
    required this.favTrap,
    required this.favPlaga,
    required this.onToggleFavTrap,
    required this.onToggleFavPlaga,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isEnf = tipo == 'ENFERMEDAD';

    final cardTint = isEnf ? const Color(0xFFF2F5FF) : const Color(0xFFEFFBFA);

    final cardBorder = isEnf
        ? const Color(0xFFC9D4FF)
        : const Color(0xFFBFE7E3);

    final badgeColor = isEnf
        ? const Color(0xFF4057B2)
        : const Color(0xFF147D74);

    final icon = isEnf ? Icons.healing_outlined : Icons.bug_report_outlined;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorder),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cardTint,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AccentIconSmall(color: badgeColor, icon: icon),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13.6,
                              height: 1.12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _PillPro(
                                text: isEnf ? 'Enfermedad' : 'Plaga',
                                color: badgeColor,
                              ),
                              _MiniInfoChip(
                                icon: Icons.layers_outlined,
                                text: niveles.isEmpty
                                    ? '0 niveles'
                                    : '${niveles.length} niveles',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Niveles',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.black.withValues(alpha: 0.68),
                        fontSize: 11.3,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (niveles.isEmpty)
                      Text(
                        'Sin niveles registrados.',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.52),
                          fontWeight: FontWeight.w700,
                          fontSize: 11.8,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: niveles
                            .map((n) => _TagChip(text: n))
                            .toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _FavoriteBigButton(
                      accent: badgeColor,
                      icon: Icons.local_activity_outlined,
                      label: 'Trampa',
                      selected: favTrap,
                      onTap: onToggleFavTrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _FavoriteBigButton(
                      accent: badgeColor,
                      icon: Icons.bug_report_outlined,
                      label: 'Plaga',
                      selected: favPlaga,
                      onTap: onToggleFavPlaga,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ActionBtn(
                      accent: badgeColor,
                      icon: Icons.edit_outlined,
                      label: 'Editar',
                      onTap: onEdit,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionBtn(
                      accent: badgeColor,
                      icon: Icons.delete_outline,
                      label: 'Eliminar',
                      onTap: onDelete,
                      filled: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteBigButton extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FavoriteBigButton({
    required this.accent,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? accent.withValues(alpha: 0.52)
        : Colors.black.withValues(alpha: 0.08);
    final bg = selected
        ? accent.withValues(alpha: 0.13)
        : Colors.white.withValues(alpha: 0.95);
    final fg = selected ? accent : Colors.black.withValues(alpha: 0.72);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? Icons.star_rounded : icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniInfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.black.withValues(alpha: 0.62)),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.72),
              fontWeight: FontWeight.w800,
              fontSize: 11.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;

  const _TagChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.74),
          fontWeight: FontWeight.w800,
          fontSize: 11.2,
        ),
      ),
    );
  }
}

class _EmptyPro extends StatelessWidget {
  final Color accent;
  final String title;
  final String subtitle;

  const _EmptyPro({
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _NeoCard(
        radius: 24,
        glowColor: accent.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _AccentIcon(
                accent: accent,
                icon: Icons.list_alt_outlined,
                size: 56,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlagaPayload {
  final String nombre;
  final String tipo;
  final List<String> niveles;

  _PlagaPayload({
    required this.nombre,
    required this.tipo,
    required this.niveles,
  });
}

class _PlagaEditorDialogPro extends StatefulWidget {
  final Color accent;
  final Map<String, dynamic>? initial;

  const _PlagaEditorDialogPro({required this.accent, this.initial});

  @override
  State<_PlagaEditorDialogPro> createState() => _PlagaEditorDialogProState();
}

class _PlagaEditorDialogProState extends State<_PlagaEditorDialogPro> {
  late final TextEditingController _nombre;
  late final TextEditingController _nivelCtrl;

  String _tipo = 'PLAGA';
  final List<String> _niveles = [];

  @override
  void initState() {
    super.initState();
    final init = widget.initial ?? const <String, dynamic>{};

    _nombre = TextEditingController(text: (init['nombre'] ?? '').toString());
    _nivelCtrl = TextEditingController();

    _tipo = (init['tipo'] ?? 'PLAGA').toString().trim().toUpperCase();
    if (_tipo != 'PLAGA' && _tipo != 'ENFERMEDAD') _tipo = 'PLAGA';

    final nAny = init['niveles'];
    if (nAny is List) {
      _niveles.addAll(
        nAny
            .map((e) => e.toString())
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      );
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _nivelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final isEdit = widget.initial != null;

    final localTheme = Theme.of(context).copyWith(
      useMaterial3: false,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: Theme.of(
        context,
      ).colorScheme.copyWith(primary: accent, secondary: accent),
    );

    return Theme(
      data: localTheme,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accent.withValues(alpha: 0.10),
                                accent.withValues(alpha: 0.04),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Row(
                            children: [
                              _AccentIcon(
                                accent: accent,
                                icon: isEdit
                                    ? Icons.edit_rounded
                                    : Icons.add_rounded,
                                size: 52,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isEdit
                                          ? 'Editar'
                                          : 'Nueva plaga/enfermedad',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Completa los datos y guarda cambios.',
                                      style: TextStyle(
                                        color: Colors.black.withValues(
                                          alpha: 0.65,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _ProFieldRedFocus(
                          accent: accent,
                          controller: _nombre,
                          label: 'Nombre',
                          hint: 'Ej: Araña roja',
                          icon: Icons.badge_outlined,
                        ),
                        const SizedBox(height: 12),
                        _ProDropdownRedFocus(
                          accent: accent,
                          label: 'Tipo',
                          value: _tipo,
                          items: const [
                            DropdownMenuItem(
                              value: 'PLAGA',
                              child: Text('Plaga'),
                            ),
                            DropdownMenuItem(
                              value: 'ENFERMEDAD',
                              child: Text('Enfermedad'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _tipo = v ?? 'PLAGA'),
                          icon: Icons.category_outlined,
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Niveles',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.black.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _ProFieldRedFocus(
                                accent: accent,
                                controller: _nivelCtrl,
                                label: 'Agregar nivel',
                                hint: 'Ej: 1, 2, 3…',
                                icon: Icons.playlist_add_rounded,
                                onSubmitted: (_) => _addNivel(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 54,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: _addNivel,
                                icon: const Icon(Icons.add),
                                label: const Text(
                                  'Agregar',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _niveles.isEmpty
                                ? [
                                    Text(
                                      'Sin niveles',
                                      style: TextStyle(
                                        color: Colors.black.withValues(
                                          alpha: 0.60,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ]
                                : _niveles.map((n) {
                                    return InputChip(
                                      label: Text(
                                        n,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      onDeleted: () =>
                                          setState(() => _niveles.remove(n)),
                                      deleteIconColor: accent,
                                      side: BorderSide(
                                        color: Colors.black.withValues(
                                          alpha: 0.10,
                                        ),
                                      ),
                                      backgroundColor: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                    );
                                  }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accent,
                                  side: BorderSide(
                                    color: accent.withValues(alpha: 0.45),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text(
                                  'Cancelar',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: _save,
                                child: const Text(
                                  'Guardar',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
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
          ),
        ),
      ),
    );
  }

  void _addNivel() {
    final v = _nivelCtrl.text.trim();
    if (v.isEmpty) return;
    final exists = _niveles.any((e) => e.toLowerCase() == v.toLowerCase());
    if (!exists) setState(() => _niveles.add(v));
    _nivelCtrl.clear();
  }

  void _save() {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pon un nombre.')));
      return;
    }

    Navigator.pop(
      context,
      _PlagaPayload(
        nombre: nombre,
        tipo: _tipo,
        niveles: List<String>.from(_niveles),
      ),
    );
  }
}

class _ProFieldRedFocus extends StatefulWidget {
  final Color accent;
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final void Function(String)? onSubmitted;

  const _ProFieldRedFocus({
    required this.accent,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.onSubmitted,
  });

  @override
  State<_ProFieldRedFocus> createState() => _ProFieldRedFocusState();
}

class _ProFieldRedFocusState extends State<_ProFieldRedFocus> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return AnimatedBuilder(
      animation: _focus,
      builder: (_, __) {
        final focused = _focus.hasFocus;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 6),
              child: Text(
                widget.label,
                style: TextStyle(
                  color: focused
                      ? accent
                      : Colors.black.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: focused
                      ? accent.withValues(alpha: 0.90)
                      : Colors.black.withValues(alpha: 0.12),
                  width: focused ? 1.6 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: focused
                        ? accent.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    color: focused
                        ? accent
                        : Colors.black.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      focusNode: _focus,
                      controller: widget.controller,
                      onSubmitted: widget.onSubmitted,
                      cursorColor: accent,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                      autofillHints: const [],
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle: TextStyle(
                          color: Colors.black.withValues(alpha: 0.45),
                          fontWeight: FontWeight.w700,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProDropdownRedFocus extends StatefulWidget {
  final Color accent;
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  final IconData icon;

  const _ProDropdownRedFocus({
    required this.accent,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  @override
  State<_ProDropdownRedFocus> createState() => _ProDropdownRedFocusState();
}

class _ProDropdownRedFocusState extends State<_ProDropdownRedFocus> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 6),
            child: Text(
              widget.label,
              style: TextStyle(
                color: _focused ? accent : Colors.black.withValues(alpha: 0.68),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _focused
                    ? accent.withValues(alpha: 0.90)
                    : Colors.black.withValues(alpha: 0.12),
                width: _focused ? 1.6 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _focused
                      ? accent.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: _focused
                      ? accent
                      : Colors.black.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: widget.value,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      items: widget.items,
                      onChanged: widget.onChanged,
                    ),
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

class _ToastCard extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String message;

  const _ToastCard({
    required this.accent,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(alpha: 0.42),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.30)),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: accent.withValues(alpha: 0.98),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavingOverlay {
  final void Function({bool success, String? doneText}) done;

  _SavingOverlay._(this.done);

  static _SavingOverlay show(BuildContext context, {required String text}) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;

    final state = ValueNotifier<_SaveState>(_SaveState.loading(text));

    entry = OverlayEntry(
      builder: (ctx) {
        final accent = AppTheme.pepperRed;

        return Positioned.fill(
          child: Material(
            color: Colors.black.withValues(alpha: 0.18),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: 320,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: accent.withValues(alpha: 0.18)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.20),
                          blurRadius: 26,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: ValueListenableBuilder<_SaveState>(
                      valueListenable: state,
                      builder: (_, s, __) {
                        final isLoading = s.kind == _SaveKind.loading;

                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Row(
                            key: ValueKey("${s.kind}-${s.text}"),
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Center(
                                  child: isLoading
                                      ? SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.6,
                                            color: accent,
                                          ),
                                        )
                                      : Icon(
                                          Icons.check_rounded,
                                          color: accent,
                                          size: 26,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      s.text,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isLoading
                                          ? "Espera un momento…"
                                          : "Listo.",
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
        );
      },
    );

    overlay.insert(entry);

    void done({bool success = true, String? doneText}) async {
      final t = doneText ?? (success ? "Listo" : "Ocurrió un error");
      state.value = _SaveState.done(t);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      entry.remove();
    }

    return _SavingOverlay._(done);
  }
}

enum _SaveKind { loading, done }

class _SaveState {
  final _SaveKind kind;
  final String text;

  _SaveState._(this.kind, this.text);

  factory _SaveState.loading(String text) =>
      _SaveState._(_SaveKind.loading, text);
  factory _SaveState.done(String text) => _SaveState._(_SaveKind.done, text);
}

class _PillPro extends StatelessWidget {
  final String text;
  final Color color;
  const _PillPro({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _AccentIcon extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final double size;

  const _AccentIcon({
    required this.accent,
    required this.icon,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Icon(icon, color: accent),
    );
  }
}

class _AccentIconSmall extends StatelessWidget {
  final Color color;
  final IconData icon;

  const _AccentIconSmall({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _NeoCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final Color? glowColor;

  const _NeoCard({required this.child, this.radius = 18, this.glowColor});

  @override
  Widget build(BuildContext context) {
    final glow = glowColor ?? Colors.black.withValues(alpha: 0.06);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(color: glow, blurRadius: 28, offset: const Offset(0, 14)),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _ActionBtn({
    required this.accent,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return SizedBox(
        height: 38,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.3),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.3),
        ),
      ),
    );
  }
}
