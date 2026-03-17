import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

class AgroProductosPage extends StatefulWidget {
  const AgroProductosPage({super.key});

  @override
  State<AgroProductosPage> createState() => _AgroProductosPageState();
}

class _AgroProductosPageState extends State<AgroProductosPage> {
  static const String _bgAsset = 'assets/images/fondos.png';

  final _db = FirebaseFirestore.instance;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  String _q = "";
  String _tipoFilter = 'Todos';
  String _sort = 'Recientes'; // Recientes | Nombre A-Z | Nombre Z-A | Tipo A-Z

  static const List<String> _tipos = <String>[
    "Insecticida",
    "Fungicida",
    "Fertilizante",
    "Herbicida",
    "Acaricida",
    "Nematicida",
    "Coadyuvante",
    "Otro",
  ];

  static const List<String> _tiposFilter = <String>["Todos", ..._tipos];

  static const List<String> _sortOptions = <String>[
    "Recientes",
    "Nombre A-Z",
    "Nombre Z-A",
    "Tipo A-Z",
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('productos').withConverter<Map<String, dynamic>>(
            fromFirestore: (s, _) => s.data() ?? <String, dynamic>{},
            toFirestore: (m, _) => m,
          );

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
      ),
    );
  }

  void _focusSearch() => FocusScope.of(context).requestFocus(_searchFocus);

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _q = "");
    FocusScope.of(context).unfocus();
  }

  Future<void> _openForm({String? docId, Map<String, dynamic>? existing}) async {
    final res = await showDialog<_ProductoFormResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ProductoDialog(initial: existing),
    );

    if (res == null) return;

    final now = FieldValue.serverTimestamp();

    if (docId == null) {
      await _col.add({
        "nombre": res.nombre.trim(),
        "ingredientesActivos": res.ingredientesActivos.trim(),
        "tipo": res.tipo.trim(),
        "fabricante": res.fabricante.trim(),
        "descripcion": res.descripcion.trim(),
        "createdAt": now,
        "updatedAt": now,
      });
      _toast("Producto guardado ✅");
    } else {
      await _col.doc(docId).set({
        "nombre": res.nombre.trim(),
        "ingredientesActivos": res.ingredientesActivos.trim(),
        "tipo": res.tipo.trim(),
        "fabricante": res.fabricante.trim(),
        "descripcion": res.descripcion.trim(),
        "updatedAt": now,
      }, SetOptions(merge: true));
      _toast("Producto actualizado ✅");
    }
  }

  Future<void> _deleteProducto(String docId, String nombre) async {
    final accent = AppTheme.pepperRed;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: accent),
            const SizedBox(width: 8),
            const Text("Eliminar producto"),
          ],
        ),
        content: Text('¿Seguro que quieres eliminar "$nombre"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _col.doc(docId).delete();
    _toast("Producto eliminado 🗑️");
  }

  bool _matchesQuery(Map<String, dynamic> data) {
    if (_q.trim().isEmpty) return true;
    final query = _q.trim().toLowerCase();

    final nombre = (data["nombre"] ?? "").toString().toLowerCase();
    final tipo = (data["tipo"] ?? "").toString().toLowerCase();
    final fabricante = (data["fabricante"] ?? "").toString().toLowerCase();
    final ing = (data["ingredientesActivos"] ?? "").toString().toLowerCase();

    return nombre.contains(query) || tipo.contains(query) || fabricante.contains(query) || ing.contains(query);
  }

  bool _matchesTipo(Map<String, dynamic> data) {
    if (_tipoFilter == 'Todos') return true;
    final tipo = (data["tipo"] ?? "").toString().trim().toLowerCase();
    return tipo == _tipoFilter.toLowerCase();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applySort(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    int cmpString(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    final copy = [...docs];

    switch (_sort) {
      case "Nombre A-Z":
        copy.sort((a, b) => cmpString((a.data()["nombre"] ?? "").toString(), (b.data()["nombre"] ?? "").toString()));
        break;
      case "Nombre Z-A":
        copy.sort((a, b) => -cmpString((a.data()["nombre"] ?? "").toString(), (b.data()["nombre"] ?? "").toString()));
        break;
      case "Tipo A-Z":
        copy.sort((a, b) {
          final c = cmpString((a.data()["tipo"] ?? "").toString(), (b.data()["tipo"] ?? "").toString());
          if (c != 0) return c;
          return cmpString((a.data()["nombre"] ?? "").toString(), (b.data()["nombre"] ?? "").toString());
        });
        break;
      case "Recientes":
      default:
        break;
    }

    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Productos Agroquímicos"),
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        // ✅ sin lupa ni +
        actions: const [],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text("Nuevo"),
      ),
      body: Stack(
        children: [
          // Fondo tipo Catálogos
          Positioned.fill(
            child: Image.asset(
              _bgAsset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [accent.withValues(alpha: 0.14), const Color(0xFFF7F7F7)],
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
                    accent.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.82),
                    Colors.white.withValues(alpha: 0.92),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final isWide = w >= 980;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: _HeaderSearchFilterCardPro(
                        accent: accent,
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        value: _q,
                        tipoValue: _tipoFilter,
                        sortValue: _sort,
                        tipos: _tiposFilter,
                        sorts: _sortOptions,
                        onChanged: (v) => setState(() => _q = v),
                        onClear: _clearSearch,
                        onSearchTap: _focusSearch,
                        onTipoChanged: (v) => setState(() => _tipoFilter = v ?? 'Todos'),
                        onSortChanged: (v) => setState(() => _sort = v ?? 'Recientes'),
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _col.orderBy("updatedAt", descending: true).snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return _EmptyState(
                              title: "Ocurrió un error",
                              subtitle: "${snap.error}",
                              icon: Icons.error_outline_rounded,
                              accent: accent,
                              actionLabel: "Reintentar",
                              onAction: () => setState(() {}),
                            );
                          }
                          if (!snap.hasData) {
                            return Center(child: CircularProgressIndicator(color: accent));
                          }

                          final allDocs = snap.data!.docs;
                          final filtered = allDocs.where((d) => _matchesTipo(d.data())).where((d) => _matchesQuery(d.data())).toList();
                          final docs = _applySort(filtered);

                          if (docs.isEmpty) {
                            final emptyBySearch = _q.trim().isNotEmpty || _tipoFilter != 'Todos';
                            return _EmptyState(
                              title: emptyBySearch ? "Sin resultados" : "Sin productos aún",
                              subtitle: emptyBySearch
                                  ? "Prueba con otro término, cambia el tipo o limpia filtros."
                                  : "Presiona “Nuevo” para registrar tu primer producto.",
                              icon: emptyBySearch ? Icons.search_off_rounded : Icons.inventory_2_outlined,
                              accent: accent,
                              actionLabel: emptyBySearch ? "Limpiar filtros" : "Crear producto",
                              onAction: emptyBySearch
                                  ? () {
                                      setState(() {
                                        _tipoFilter = 'Todos';
                                        _sort = 'Recientes';
                                        _q = '';
                                      });
                                      _searchCtrl.clear();
                                    }
                                  : () => _openForm(),
                            );
                          }

                          if (isWide) {
                            final cols = w >= 1320 ? 3 : 2;
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.55,
                              ),
                              itemCount: docs.length,
                              itemBuilder: (_, i) {
                                final doc = docs[i];
                                final data = doc.data();
                                return _ProductoCardPro(
                                  data: data,
                                  onEdit: () => _openForm(docId: doc.id, existing: data),
                                  onDelete: () => _deleteProducto(doc.id, (data["nombre"] ?? "—").toString()),
                                );
                              },
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                            itemCount: docs.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final doc = docs[i];
                              final data = doc.data();
                              return _ProductoCardPro(
                                data: data,
                                onEdit: () => _openForm(docId: doc.id, existing: data),
                                onDelete: () => _deleteProducto(doc.id, (data["nombre"] ?? "—").toString()),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ========================= HEADER PRO =========================

class _HeaderSearchFilterCardPro extends StatelessWidget {
  final Color accent;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String value;
  final String tipoValue;
  final String sortValue;
  final List<String> tipos;
  final List<String> sorts;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onSearchTap;
  final ValueChanged<String?> onTipoChanged;
  final ValueChanged<String?> onSortChanged;

  const _HeaderSearchFilterCardPro({
    required this.accent,
    required this.controller,
    required this.focusNode,
    required this.value,
    required this.tipoValue,
    required this.sortValue,
    required this.tipos,
    required this.sorts,
    required this.onChanged,
    required this.onClear,
    required this.onSearchTap,
    required this.onTipoChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final border = Colors.black.withValues(alpha: 0.08);

    final baseInput = InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.90),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accent.withValues(alpha: 0.60), width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.72), fontWeight: FontWeight.w800),
      floatingLabelStyle: TextStyle(color: accent.withValues(alpha: 0.92), fontWeight: FontWeight.w900),
    );

    return _NeoGlassCard(
      radius: 22,
      borderColor: accent.withValues(alpha: 0.14),
      glowColor: accent.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Theme(
          data: Theme.of(context).copyWith(inputDecorationTheme: baseInput),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AccentSquareIcon(accent: accent, icon: Icons.science_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Catálogo de productos",
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 3),
                        Text("Busca por texto, filtra por tipo y ordena.",
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.64),
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            )),
                      ],
                    ),
                  ),
                  _Badge(text: "Admin", color: accent),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 620;

                  final searchField = TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: "Buscar por nombre, tipo, fabricante…",
                      prefixIcon: Icon(Icons.search_rounded, color: accent),
                      suffixIcon: value.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: "Limpiar",
                              onPressed: onClear,
                              icon: Icon(Icons.close_rounded, color: Colors.black.withValues(alpha: 0.60)),
                            ),
                    ),
                  );

                  final searchBtn = SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: onSearchTap,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text("Buscar"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accent,
                        side: BorderSide(color: accent.withValues(alpha: 0.55)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                    ),
                  );

                  if (wide) {
                    return Row(
                      children: [Expanded(child: searchField), const SizedBox(width: 10), searchBtn],
                    );
                  }
                  return Column(
                    children: [searchField, const SizedBox(height: 10), SizedBox(width: double.infinity, child: searchBtn)],
                  );
                },
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 620;

                  final tipo = DropdownButtonFormField<String>(
                    value: tipoValue,
                    dropdownColor: Colors.white,
                    items: tipos.map((t) => DropdownMenuItem<String>(value: t, child: Text(t))).toList(),
                    onChanged: onTipoChanged,
                    decoration: InputDecoration(
                      labelText: "Tipo",
                      prefixIcon: Icon(Icons.category_outlined, color: accent),
                    ),
                  );

                  final sort = DropdownButtonFormField<String>(
                    value: sortValue,
                    dropdownColor: Colors.white,
                    items: sorts.map((t) => DropdownMenuItem<String>(value: t, child: Text(t))).toList(),
                    onChanged: onSortChanged,
                    decoration: InputDecoration(
                      labelText: "Orden",
                      prefixIcon: Icon(Icons.sort_rounded, color: accent),
                    ),
                  );

                  if (wide) {
                    return Row(children: [Expanded(child: tipo), const SizedBox(width: 10), Expanded(child: sort)]);
                  }
                  return Column(children: [tipo, const SizedBox(height: 10), sort]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================= EMPTY STATE =========================

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _NeoGlassCard(
            radius: 22,
            borderColor: accent.withValues(alpha: 0.14),
            glowColor: accent.withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.10),
                      border: Border.all(color: accent.withValues(alpha: 0.20)),
                    ),
                    child: Icon(icon, color: accent, size: 44),
                  ),
                  const SizedBox(height: 12),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.70), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: onAction,
                      child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ========================= PRODUCT CARD PRO (DESCRIPCIÓN JUSTIFICADA) =========================

class _ProductoCardPro extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductoCardPro({
    required this.data,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ProductoCardPro> createState() => _ProductoCardProState();
}

class _ProductoCardProState extends State<_ProductoCardPro> {
  bool _hover = false;
  bool get _canHover => kIsWeb;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;

    final nombre = (widget.data["nombre"] ?? "—").toString();
    final tipo = (widget.data["tipo"] ?? "—").toString();
    final fabricante = (widget.data["fabricante"] ?? "—").toString();
    final ing = (widget.data["ingredientesActivos"] ?? "—").toString();
    final desc = (widget.data["descripcion"] ?? "").toString();

    final border = _hover ? accent.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.08);
    final glow = _hover ? accent.withValues(alpha: 0.16) : accent.withValues(alpha: 0.10);

    return MouseRegion(
      onEnter: (_) => _canHover ? setState(() => _hover = true) : null,
      onExit: (_) => _canHover ? setState(() => _hover = false) : null,
      child: _NeoGlassCard(
        radius: 22,
        borderColor: border,
        glowColor: glow,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: widget.onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AccentSquareIcon(accent: accent, icon: Icons.inventory_2_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _TypeChipRed(tipo: tipo),
                              _MiniChipRed(text: fabricante, icon: Icons.factory_outlined),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoLine(icon: Icons.science_outlined, label: "Ingredientes activos", value: ing),
                if (desc.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InfoLine(
                    icon: Icons.notes_outlined,
                    label: "Descripción",
                    value: desc,
                    justify: true, // ✅
                  ),
                ],
                const Spacer(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text("Editar"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(color: accent.withValues(alpha: 0.60)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w900),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: widget.onDelete,
                        icon: const Icon(Icons.delete_rounded, size: 18),
                        label: const Text("Eliminar"),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w900),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool justify;

  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.justify = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;
    final v = value.trim().isEmpty ? "—" : value.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
          ),
          child: Icon(icon, color: accent.withValues(alpha: 0.90), size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Colors.black.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                v,
                textAlign: justify ? TextAlign.justify : TextAlign.start,
                style: const TextStyle(fontWeight: FontWeight.w800, height: 1.15),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ========================= DIALOG PRO BLANCO REAL (SIN TINTES) =========================

class _ProductoDialog extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _ProductoDialog({this.initial});

  @override
  State<_ProductoDialog> createState() => _ProductoDialogState();
}

class _ProductoDialogState extends State<_ProductoDialog> {
  static const _tipos = <String>[
    "Insecticida",
    "Fungicida",
    "Fertilizante",
    "Herbicida",
    "Acaricida",
    "Nematicida",
    "Coadyuvante",
    "Otro",
  ];

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nombreCtrl;
  late final TextEditingController _ingCtrl;
  late final TextEditingController _fabCtrl;
  late final TextEditingController _descCtrl;

  String _tipo = _tipos.first;
  final _tipoOtherCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.initial ?? {};

    _nombreCtrl = TextEditingController(text: (i["nombre"] ?? "").toString());
    _ingCtrl = TextEditingController(text: (i["ingredientesActivos"] ?? "").toString());
    _fabCtrl = TextEditingController(text: (i["fabricante"] ?? "").toString());
    _descCtrl = TextEditingController(text: (i["descripcion"] ?? "").toString());

    final rawTipo = (i["tipo"] ?? "").toString().trim();
    final match = _tipos.where((t) => t.toLowerCase() == rawTipo.toLowerCase()).toList();
    if (match.isNotEmpty) {
      _tipo = match.first;
    } else if (rawTipo.isNotEmpty) {
      _tipo = "Otro";
      _tipoOtherCtrl.text = rawTipo;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _ingCtrl.dispose();
    _fabCtrl.dispose();
    _descCtrl.dispose();
    _tipoOtherCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final finalTipo = (_tipo == "Otro") ? _tipoOtherCtrl.text.trim() : _tipo.trim();

    Navigator.pop(
      context,
      _ProductoFormResult(
        nombre: _nombreCtrl.text,
        ingredientesActivos: _ingCtrl.text,
        tipo: finalTipo,
        fabricante: _fabCtrl.text,
        descripcion: _descCtrl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;
    final isEdit = widget.initial != null;

    // ✅ FORZAMOS Material 2 SOLO AQUÍ (elimina surfaceTint/overlays verdosos de M3)
    final dialogTheme = Theme.of(context).copyWith(
      useMaterial3: false,
      dialogBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      cardColor: Colors.white,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: Theme.of(context).colorScheme.copyWith(primary: accent, secondary: accent),
    );

    return Theme(
      data: dialogTheme,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.white, // ✅ blanco real
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NeoGlassCard(
                  radius: 20,
                  borderColor: accent.withValues(alpha: 0.18),
                  glowColor: accent.withValues(alpha: 0.10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        _AccentSquareIcon(
                          accent: accent,
                          icon: isEdit ? Icons.edit_rounded : Icons.add_rounded,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isEdit ? "Editar producto" : "Nuevo producto",
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                              const SizedBox(height: 2),
                              Text("Completa los datos y guarda cambios.",
                                  style: TextStyle(color: Colors.black.withValues(alpha: 0.65), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: "Cerrar",
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Flexible(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _ProFieldShell(
                            accent: accent,
                            child: TextFormField(
                              controller: _nombreCtrl,
                              decoration: const InputDecoration(
                                labelText: "Nombre",
                                hintText: "Ej: Imidacloprid 350",
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? "Nombre obligatorio" : null,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ProFieldShell(
                            accent: accent,
                            child: DropdownButtonFormField<String>(
                              value: _tipo,
                              dropdownColor: Colors.white,
                              items: _tipos.map((t) => DropdownMenuItem<String>(value: t, child: Text(t))).toList(),
                              onChanged: (v) => setState(() => _tipo = v ?? _tipos.first),
                              decoration: const InputDecoration(
                                labelText: "Tipo",
                                prefixIcon: Icon(Icons.category_outlined),
                              ),
                            ),
                          ),
                          if (_tipo == "Otro") ...[
                            const SizedBox(height: 10),
                            _ProFieldShell(
                              accent: accent,
                              child: TextFormField(
                                controller: _tipoOtherCtrl,
                                decoration: const InputDecoration(
                                  labelText: "Especifica el tipo",
                                  hintText: "Ej: Regulador / Biológico / etc.",
                                  prefixIcon: Icon(Icons.edit_outlined),
                                ),
                                validator: (v) {
                                  if (_tipo != "Otro") return null;
                                  if (v == null || v.trim().isEmpty) return "Especifica el tipo";
                                  return null;
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          _ProFieldShell(
                            accent: accent,
                            child: TextFormField(
                              controller: _ingCtrl,
                              decoration: const InputDecoration(
                                labelText: "Ingredientes activos",
                                hintText: "Ej: Imidacloprid 35% + ...",
                                prefixIcon: Icon(Icons.science_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ProFieldShell(
                            accent: accent,
                            child: TextFormField(
                              controller: _fabCtrl,
                              decoration: const InputDecoration(
                                labelText: "Fabricante",
                                hintText: "Ej: Bayer",
                                prefixIcon: Icon(Icons.factory_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ProFieldShell(
                            accent: accent,
                            child: TextFormField(
                              controller: _descCtrl,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: "Descripción general",
                                hintText: "Notas importantes del producto...",
                                prefixIcon: Icon(Icons.notes_outlined),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(color: accent.withValues(alpha: 0.55)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        child: const Text("Cancelar"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        onPressed: _submit,
                        child: const Text("Guardar"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ Campo pro BLANCO: sin verde, sin overlay, borde y sombra elegante.
class _ProFieldShell extends StatelessWidget {
  final Color accent;
  final Widget child;

  const _ProFieldShell({required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    final border = Colors.black.withValues(alpha: 0.10);

    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white, // ✅ blanco real
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: accent.withValues(alpha: 0.75), width: 1.6),
          ),
          labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.72), fontWeight: FontWeight.w800),
          floatingLabelStyle: TextStyle(color: accent.withValues(alpha: 0.95), fontWeight: FontWeight.w900),
          prefixIconColor: Colors.black.withValues(alpha: 0.62),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

// ========================= CHIPS / UI BASE =========================

class _TypeChipRed extends StatelessWidget {
  final String tipo;
  const _TypeChipRed({required this.tipo});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;
    final t = tipo.trim().isEmpty ? "—" : tipo.trim();
    final w = _weightByTipo(t);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06 + (w * 0.06)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.18 + (w * 0.12))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_florist_outlined, size: 16, color: accent.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(fontWeight: FontWeight.w900, color: accent.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  double _weightByTipo(String tipo) {
    final s = tipo.toLowerCase();
    if (s.contains('insect')) return 1.00;
    if (s.contains('fung')) return 0.86;
    if (s.contains('herb')) return 0.74;
    if (s.contains('fert')) return 0.62;
    if (s.contains('acar')) return 0.55;
    if (s.contains('nemat')) return 0.48;
    if (s.contains('coady')) return 0.40;
    return 0.32;
  }
}

class _MiniChipRed extends StatelessWidget {
  final String text;
  final IconData icon;
  const _MiniChipRed({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.pepperRed;
    final t = text.trim().isEmpty ? "—" : text.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11.5)),
    );
  }
}

class _AccentSquareIcon extends StatelessWidget {
  final Color accent;
  final IconData icon;
  const _AccentSquareIcon({required this.accent, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Icon(icon, color: accent),
    );
  }
}

class _NeoGlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final Color? borderColor;
  final Color? glowColor;

  const _NeoGlassCard({
    required this.child,
    this.radius = 18,
    this.borderColor,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? Colors.black.withValues(alpha: 0.08);
    final glow = glowColor ?? Colors.black.withValues(alpha: 0.06);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(color: glow, blurRadius: 28, offset: const Offset(0, 14)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

class _ProductoFormResult {
  final String nombre;
  final String ingredientesActivos;
  final String tipo;
  final String fabricante;
  final String descripcion;

  const _ProductoFormResult({
    required this.nombre,
    required this.ingredientesActivos,
    required this.tipo,
    required this.fabricante,
    required this.descripcion,
  });
}
